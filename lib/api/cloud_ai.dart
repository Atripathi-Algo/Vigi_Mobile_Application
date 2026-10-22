import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app/env.dart';

const String _system = 'You are VIGIL, a terse tactical personal-ops assistant. Lead with the number, then the risk, '
    'then one recommendation. 24h times, rupees with Indian grouping. No exclamation marks, no praise, no emoji. '
    'Use only facts from the SITREP JSON; if data is missing say "No data for X." Reply in at most 3 sentences.';

/// Result of a cloud call: the reply text, or why there is none.
class CloudReply {
  const CloudReply.ok(String this.text) : error = null;
  const CloudReply.fail(String this.error) : text = null;

  final String? text;
  final String? error;
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
Future<CloudReply> askCloudDetailed(String question, String sitrep, {http.Client? client}) async {
  if (!Env.hasCloudAi) return const CloudReply.fail('No API key set.');
  final http.Client c = client ?? http.Client();
  try {
    final String provider = Env.cloudAiProvider;
    final String base = Env.cloudAiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final String user = 'SITREP: $sitrep\n\nQUESTION: $question';
    late final Uri uri;
    late final Map<String, String> headers;
    late final Object body;
    switch (provider) {
      case 'gemini':
        uri = Uri.parse('$base/v1beta/models/${Env.cloudAiModel}:generateContent');
        headers = <String, String>{'content-type': 'application/json', 'x-goog-api-key': Env.cloudAiKey};
        body = <String, dynamic>{
          'systemInstruction': <String, dynamic>{
            'parts': <Map<String, String>>[<String, String>{'text': _system}],
          },
          'contents': <Map<String, dynamic>>[
            <String, dynamic>{
              'role': 'user',
              'parts': <Map<String, String>>[<String, String>{'text': user}],
            },
          ],
          // Generous, because thinking models spend part of the budget before answering.
          'generationConfig': <String, dynamic>{'maxOutputTokens': 2048, 'temperature': 0.3},
        };
      case 'openai':
        uri = Uri.parse('$base/v1/chat/completions');
        headers = <String, String>{'content-type': 'application/json', 'authorization': 'Bearer ${Env.cloudAiKey}'};
        body = <String, dynamic>{
          'model': Env.cloudAiModel,
          'messages': <Map<String, String>>[
            <String, String>{'role': 'system', 'content': _system},
            <String, String>{'role': 'user', 'content': user},
          ],
        };
      default: // anthropic
        uri = Uri.parse('$base/v1/messages');
        headers = <String, String>{'content-type': 'application/json', 'x-api-key': Env.cloudAiKey, 'anthropic-version': '2023-06-01'};
        body = <String, dynamic>{
          'model': Env.cloudAiModel,
          'max_tokens': 1024,
          'system': _system,
          'messages': <Map<String, String>>[
            <String, String>{'role': 'user', 'content': user},
          ],
        };
    }
    final http.Response r = await c.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) return CloudReply.fail('HTTP ${r.statusCode}: ${_apiMessage(r.body)}');
    final String? text = _extractText(provider, r.body);
    if (text == null || text.isEmpty) return const CloudReply.fail('The model returned no text.');
    return CloudReply.ok(text);
  } on TimeoutException {
    return const CloudReply.fail('Timed out after 25 seconds.');
  } catch (e) {
    return CloudReply.fail('Could not reach the service: ${e.toString().split('\n').first}');
  } finally {
    if (client == null) c.close();
  }
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

/// The provider's own error message, shortened, or the start of the body.
String _apiMessage(String body) {
  String msg = body;
  try {
    final dynamic j = jsonDecode(body);
    final dynamic err = j is Map ? j['error'] : null;
    if (err is Map && err['message'] is String) {
      msg = err['message'] as String;
    } else if (err is String) {
      msg = err;
    }
  } catch (_) {}
  msg = msg.replaceAll(RegExp(r'\s+'), ' ').trim();
  return msg.length > 160 ? '${msg.substring(0, 160)}…' : msg;
}
