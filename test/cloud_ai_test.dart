import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vigil/api/cloud_ai.dart';
import 'package:vigil/app/env.dart';

void config(String lines) => dotenv.testLoad(fileInput: lines);

http.Response json(int code, Object body) => http.Response(jsonEncode(body), code, headers: <String, String>{'content-type': 'application/json'});

void main() {
  group('Gemini', () {
    test('builds the generateContent request and reads the reply', () async {
      config('CLOUD_AI_PROVIDER=gemini\nCLOUD_AI_API_KEY=test-key\n');
      late http.Request seen;
      final MockClient client = MockClient((http.Request r) async {
        seen = r;
        return json(200, <String, dynamic>{
          'candidates': <Map<String, dynamic>>[
            <String, dynamic>{
              'content': <String, dynamic>{
                'parts': <Map<String, dynamic>>[
                  <String, dynamic>{'text': 'Thinking…', 'thought': true},
                  <String, dynamic>{'text': 'Hydration 1.2 of 3.0 L. '},
                  <String, dynamic>{'text': 'Recommend 500 ml now.'},
                ],
              },
            },
          ],
        });
      });
      final CloudReply r = await askCloudDetailed('water?', '{"water_ml":1200}', client: client);
      expect(r.text, 'Hydration 1.2 of 3.0 L. Recommend 500 ml now.');
      expect(seen.url.toString(), 'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent');
      expect(seen.headers['x-goog-api-key'], 'test-key');
      expect(seen.url.queryParameters.containsKey('key'), isFalse, reason: 'the key must not appear in the URL');
      final Map<String, dynamic> body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['systemInstruction']['parts'][0]['text'], contains('You are K'));
      expect(body['contents'][0]['role'], 'user');
      expect(body['contents'][0]['parts'][0]['text'], allOf(contains('SITREP'), contains('water?')));
    });

    test('a custom model and base URL are used', () async {
      config('CLOUD_AI_PROVIDER=gemini\nCLOUD_AI_API_KEY=k\nCLOUD_AI_MODEL=gemini-3-flash-preview\nCLOUD_AI_BASE_URL=https://example.test/\n');
      late Uri url;
      final MockClient client = MockClient((http.Request r) async {
        url = r.url;
        return json(200, <String, dynamic>{'candidates': <dynamic>[]});
      });
      await askCloudDetailed('q', '{}', client: client);
      expect(url.toString(), 'https://example.test/v1beta/models/gemini-3-flash-preview:generateContent');
    });

    test('explains an API error instead of failing silently', () async {
      config('CLOUD_AI_PROVIDER=gemini\nCLOUD_AI_API_KEY=bad\n');
      final MockClient client = MockClient((http.Request r) async => json(400, <String, dynamic>{
            'error': <String, dynamic>{'code': 400, 'message': 'API key not valid. Please pass a valid API key.', 'status': 'INVALID_ARGUMENT'},
          }));
      final CloudReply r = await askCloudDetailed('q', '{}', client: client);
      expect(r.text, isNull);
      expect(r.error, 'HTTP 400: API key not valid. Please pass a valid API key.');
    });

    test('a blocked or empty answer is reported', () async {
      config('CLOUD_AI_PROVIDER=gemini\nCLOUD_AI_API_KEY=k\n');
      final MockClient client = MockClient((http.Request r) async => json(200, <String, dynamic>{
            'promptFeedback': <String, dynamic>{'blockReason': 'SAFETY'},
          }));
      expect((await askCloudDetailed('q', '{}', client: client)).error, 'The model returned no text.');
    });
  });

  group('OpenAI-compatible (Groq, OpenRouter, Ollama)', () {
    test('posts to /v1/chat/completions on the given base URL', () async {
      config('CLOUD_AI_PROVIDER=openai\nCLOUD_AI_API_KEY=gsk_x\nCLOUD_AI_MODEL=llama-test\nCLOUD_AI_BASE_URL=https://api.groq.com/openai\n');
      late http.Request seen;
      final MockClient client = MockClient((http.Request r) async {
        seen = r;
        return json(200, <String, dynamic>{
          'choices': <Map<String, dynamic>>[
            <String, dynamic>{'message': <String, dynamic>{'content': ' Ready. '}},
          ],
        });
      });
      final CloudReply r = await askCloudDetailed('q', '{}', client: client);
      expect(r.text, 'Ready.');
      expect(seen.url.toString(), 'https://api.groq.com/openai/v1/chat/completions');
      expect(seen.headers['authorization'], 'Bearer gsk_x');
      expect((jsonDecode(seen.body) as Map<String, dynamic>)['model'], 'llama-test');
    });
  });

  group('Anthropic', () {
    test('posts to /v1/messages and reads the first text block', () async {
      config('CLOUD_AI_PROVIDER=anthropic\nCLOUD_AI_API_KEY=ak\n');
      late http.Request seen;
      final MockClient client = MockClient((http.Request r) async {
        seen = r;
        return json(200, <String, dynamic>{
          'content': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'thinking', 'thinking': 'x'},
            <String, dynamic>{'type': 'text', 'text': 'Done.'},
          ],
        });
      });
      expect((await askCloudDetailed('q', '{}', client: client)).text, 'Done.');
      expect(seen.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(seen.headers['x-api-key'], 'ak');
    });
  });

  group('shared behaviour', () {
    test('no key means no request', () async {
      config('CLOUD_AI_PROVIDER=gemini\n');
      bool called = false;
      final MockClient client = MockClient((http.Request r) async {
        called = true;
        return json(200, <String, dynamic>{});
      });
      final CloudReply r = await askCloudDetailed('q', '{}', client: client);
      expect(called, isFalse);
      expect(r.error, 'No API key set.');
      expect(Env.hasCloudAi, isFalse);
    });

    test('a network failure becomes a message, not an exception', () async {
      config('CLOUD_AI_PROVIDER=gemini\nCLOUD_AI_API_KEY=k\n');
      final MockClient client = MockClient((http.Request r) async => throw http.ClientException('offline'));
      final CloudReply r = await askCloudDetailed('q', '{}', client: client);
      expect(r.text, isNull);
      expect(r.error, startsWith('Could not reach the service'));
    });

    test('askCloud returns null on failure and the text on success', () async {
      config('CLOUD_AI_PROVIDER=openai\nCLOUD_AI_API_KEY=k\n');
      expect(await askCloud('q', '{}', client: MockClient((http.Request r) async => json(500, <String, dynamic>{}))), isNull);
      expect(
        await askCloud('q', '{}', client: MockClient((http.Request r) async => json(200, <String, dynamic>{'choices': <dynamic>[<String, dynamic>{'message': <String, dynamic>{'content': 'ok'}}]}))),
        'ok',
      );
    });

    test('defaults: gemini is the default provider, and its model is the free-tier alias', () {
      config('CLOUD_AI_API_KEY=k\n');
      expect(Env.cloudAiProvider, 'gemini');
      expect(Env.cloudAiModel, 'gemini-flash-latest');
      expect(Env.cloudAiBaseUrl, 'https://generativelanguage.googleapis.com');
    });
  });
}
