import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app/env.dart';

const String _system = 'You are VIGIL, a terse tactical personal-ops assistant. Lead with the number, then the risk, '
    'then one recommendation. 24h times, rupees with Indian grouping. No exclamation marks, no praise, no emoji. '
    'Use only facts from the SITREP JSON; if data is missing say "No data for X." Reply in at most 3 sentences.';

/// Optional cloud assist for hard requests. Returns null if no key is set or
/// the call fails, so the caller falls back to the on-device rules.
/// Provider/model/base URL/key all come from `.env`.
Future<String?> askCloud(String question, String sitrep) async {
  if (!Env.hasCloudAi) return null;
  try {
    final bool openai = Env.cloudAiProvider == 'openai';
    final Uri uri = Uri.parse(openai ? '${Env.cloudAiBaseUrl}/v1/chat/completions' : '${Env.cloudAiBaseUrl}/v1/messages');
    final Map<String, String> headers = <String, String>{
      'content-type': 'application/json',
      if (openai) 'authorization': 'Bearer ${Env.cloudAiKey}' else ...<String, String>{'x-api-key': Env.cloudAiKey, 'anthropic-version': '2023-06-01'},
    };
    final String user = 'SITREP: $sitrep\n\nQUESTION: $question';
    final Object body = openai
        ? <String, dynamic>{
            'model': Env.cloudAiModel,
            'messages': <Map<String, String>>[
              <String, String>{'role': 'system', 'content': _system},
              <String, String>{'role': 'user', 'content': user},
            ],
          }
        : <String, dynamic>{
            'model': Env.cloudAiModel,
            'max_tokens': 1024,
            'system': _system,
            'messages': <Map<String, String>>[
              <String, String>{'role': 'user', 'content': user},
            ],
          };
    final http.Response r = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) return null;
    final Map<String, dynamic> j = jsonDecode(r.body) as Map<String, dynamic>;
    if (openai) return (j['choices'][0]['message']['content'] as String).trim();
    final dynamic block = (j['content'] as List<dynamic>).firstWhere((dynamic b) => b['type'] == 'text', orElse: () => null);
    return block == null ? null : (block['text'] as String).trim();
  } catch (_) {
    return null;
  }
}
