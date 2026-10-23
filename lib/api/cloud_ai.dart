import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app/env.dart';
import 'api_error.dart';

const String _system = 'You are VIGIL, a terse tactical personal-ops assistant. Lead with the number, then the risk, '
    'then one recommendation. 24h times, rupees with Indian grouping. No exclamation marks, no praise, no emoji. '
    'Use only facts from the SITREP JSON; if data is missing say "No data for X." Reply in at most 3 sentences.';

/// Free-tier Gemini models tried, in order, when the chosen one is refused. Never a paid model.
const List<String> kGeminiFreeFallbacks = <String>['gemini-flash-latest', 'gemini-2.5-flash', 'gemini-2.5-flash-lite'];

/// HTTP statuses after which another free Gemini model is worth trying: payment required, model not found,
/// rate limited, overloaded.
const Set<int> _retryStatuses = <int>{402, 404, 429, 503};

/// One earlier turn of the conversation, sent so the model can follow what was said before.
class ChatTurn {
  const ChatTurn(this.fromUser, this.text);

  final bool fromUser;
  final String text;
}

/// Result of a cloud call: the reply text, or why there is none.
class CloudReply {
  const CloudReply.ok(String this.text, {this.model, this.note}) : error = null;
  const CloudReply.fail(String this.error) : text = null, model = null, note = null;

  final String? text;
  final String? error;

  /// The model that answered.
  final String? model;

  /// Set when the chosen model failed and another one answered.
  final String? note;
}

/// Optional cloud assist for hard requests. Returns null if no key is set or
/// the call fails, so the caller falls back to the on-device rules.
Future<String?> askCloud(String question, String sitrep, {http.Client? client}) async =>
    (await askCloudDetailed(question, sitrep, client: client)).text;

/// Same call, but says what went wrong. Providers (CLOUD_AI_PROVIDER):
///  - `gemini`:    Google Gemini API, free tier available (default)
///  - `openai`:    any OpenAI-compatible endpoint: Groq, OpenRouter, Ollama, OpenAI
///  - `anthropic`: Anthropic Claude API (paid)
/// Provider, model, base URL and key all come from Env (the app's API keys screen or .env).
///
/// [system] replaces the default instructions, [history] gives earlier turns, and [json] asks Gemini for a JSON
/// reply. With Gemini, a refused model (402, 404, 429, 503) is retried on the free fallbacks, and the reply says so.
Future<CloudReply> askCloudDetailed(
  String question,
  String sitrep, {
  http.Client? client,
  String? system,
  List<ChatTurn> history = const <ChatTurn>[],
  bool json = false,
}) async {
  if (!Env.hasCloudAi) return const CloudReply.fail('No API key set.');
  final http.Client c = client ?? http.Client();
  try {
    final String provider = Env.cloudAiProvider;
    final String base = Env.cloudAiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final String chosen = Env.cloudAiModel;
    final bool canFallBack = provider == 'gemini' && base == 'https://generativelanguage.googleapis.com';
    final List<String> models = <String>[chosen, if (canFallBack) ...kGeminiFreeFallbacks.where((String m) => m != chosen)];
    final List<(String, String)> turns = _alternate(history, 'SITREP: $sitrep\n\nQUESTION: $question');
    final String sys = system ?? _system;

    String? firstFailure;
    final List<String> tried = <String>[];
    for (final String model in models) {
      tried.add(model);
      final http.Response r = await _post(c, provider, base, model, sys, turns, json);
      if (r.statusCode == 200) {
        final String? text = _extractText(provider, r.body);
        if (text == null || text.isEmpty) {
          firstFailure ??= 'The model returned no text.';
          break;
        }
        return CloudReply.ok(text, model: model, note: model == chosen ? null : '$chosen was refused ($firstFailure). Answered by $model.');
      }
      firstFailure ??= _explain(provider, model, r.statusCode, apiErrorMessage(r.body));
      if (!_retryStatuses.contains(r.statusCode)) break;
    }
    return CloudReply.fail(tried.length > 1 ? '$firstFailure Also tried ${tried.skip(1).join(', ')}.' : firstFailure ?? 'The model returned no text.');
  } on TimeoutException {
    return const CloudReply.fail('Timed out after 25 seconds.');
  } catch (e) {
    return CloudReply.fail('Could not reach the service: ${e.toString().split('\n').first}');
  } finally {
    if (client == null) c.close();
  }
}

/// Turns the history plus the new message into strictly alternating user/assistant turns that start with the user,
/// which Anthropic requires and the others accept.
List<(String, String)> _alternate(List<ChatTurn> history, String latestUser) {
  final List<(String, String)> out = <(String, String)>[];
  void add(String role, String text) {
    if (out.isEmpty && role != 'user') return;
    if (out.isNotEmpty && out.last.$1 == role) {
      out[out.length - 1] = (role, '${out.last.$2}\n$text');
    } else {
      out.add((role, text));
    }
  }

  for (final ChatTurn t in history) {
    if (t.text.trim().isNotEmpty) add(t.fromUser ? 'user' : 'assistant', t.text.trim());
  }
  add('user', latestUser);
  return out;
}

Future<http.Response> _post(http.Client c, String provider, String base, String model, String system, List<(String, String)> turns, bool json) {
  late final Uri uri;
  late final Map<String, String> headers;
  late final Object body;
  switch (provider) {
    case 'gemini':
      uri = Uri.parse('$base/v1beta/models/$model:generateContent');
      headers = <String, String>{'content-type': 'application/json', 'x-goog-api-key': Env.cloudAiKey};
      body = <String, dynamic>{
        'systemInstruction': <String, dynamic>{
          'parts': <Map<String, String>>[<String, String>{'text': system}],
        },
        'contents': <Map<String, dynamic>>[
          for (final (String, String) t in turns)
            <String, dynamic>{
              'role': t.$1 == 'user' ? 'user' : 'model',
              'parts': <Map<String, String>>[<String, String>{'text': t.$2}],
            },
        ],
        // Generous, because thinking models spend part of the budget before answering.
        'generationConfig': <String, dynamic>{'maxOutputTokens': 2048, 'temperature': 0.3, if (json) 'responseMimeType': 'application/json'},
      };
    case 'openai':
      uri = Uri.parse('$base/v1/chat/completions');
      headers = <String, String>{'content-type': 'application/json', 'authorization': 'Bearer ${Env.cloudAiKey}'};
      body = <String, dynamic>{
        'model': model,
        'messages': <Map<String, String>>[
          <String, String>{'role': 'system', 'content': system},
          for (final (String, String) t in turns) <String, String>{'role': t.$1, 'content': t.$2},
        ],
      };
    default: // anthropic
      uri = Uri.parse('$base/v1/messages');
      headers = <String, String>{'content-type': 'application/json', 'x-api-key': Env.cloudAiKey, 'anthropic-version': '2023-06-01'};
      body = <String, dynamic>{
        'model': model,
        'max_tokens': 1024,
        'system': system,
        'messages': <Map<String, String>>[
          for (final (String, String) t in turns) <String, String>{'role': t.$1, 'content': t.$2},
        ],
      };
  }
  return c.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 25));
}

/// "HTTP 402: ..." plus what it means and what to do, for the statuses people actually hit.
String _explain(String provider, String model, int status, String message) {
  final String head = 'HTTP $status: $message';
  final String? hint = switch (status) {
    402 => provider == 'gemini'
        ? 'Google refused $model because the project behind this key has prepaid billing with no credits. Free-tier models still work: use gemini-flash-latest, or a key from a project without billing.'
        : '$model needs credit on this account.',
    429 => 'Rate or daily limit reached. Wait a minute, or choose another model.',
    404 => '$model was not found for this key. Pick one from the model list.',
    401 || 403 => provider == 'gemini' ? 'The key was refused. Use a Gemini key from aistudio.google.com.' : 'The key was refused. Check it belongs to this service.',
    _ => null,
  };
  return hint == null ? head : '$head $hint';
}

/// Pulls the reply text out of a successful response; null if the shape is unexpected.
String? _extractText(String provider, String body) {
  try {
    final Map<String, dynamic> j = jsonDecode(body) as Map<String, dynamic>;
    switch (provider) {
      case 'gemini':
        final List<dynamic>? cands = j['candidates'] as List<dynamic>?;
        if (cands == null || cands.isEmpty) return null; // e.g. blocked by a safety filter
        final List<dynamic> parts = ((cands.first as Map<String, dynamic>)['content'] as Map<String, dynamic>?)?['parts'] as List<dynamic>? ?? <dynamic>[];
        return parts.whereType<Map<String, dynamic>>().where((Map<String, dynamic> p) => p['thought'] != true && p['text'] is String).map((Map<String, dynamic> p) => p['text'] as String).join().trim();
      case 'openai':
        return ((((j['choices'] as List<dynamic>).first as Map<String, dynamic>)['message'] as Map<String, dynamic>)['content'] as String?)?.trim();
      default:
        final dynamic block = (j['content'] as List<dynamic>).firstWhere((dynamic b) => b['type'] == 'text', orElse: () => null);
        return block == null ? null : (block['text'] as String).trim();
    }
  } catch (_) {
    return null;
  }
}
