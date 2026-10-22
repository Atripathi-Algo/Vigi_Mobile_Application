import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vigil/api/ai_models.dart';

http.Response json(int code, Object body) => http.Response(jsonEncode(body), code, headers: <String, String>{'content-type': 'application/json'});

void main() {
  group('tiers', () {
    test('output price decides the tier for models without a free tier', () {
      expect(tierForOutputPrice(0.40), ModelTier.cheap);
      expect(tierForOutputPrice(1.5), ModelTier.cheap);
      expect(tierForOutputPrice(1.51), ModelTier.paid);
      expect(tierForOutputPrice(10), ModelTier.paid);
      expect(tierForOutputPrice(10.01), ModelTier.premium);
      expect(tierForOutputPrice(null), ModelTier.unrated);
      expect(tierForOutputPrice(-1), ModelTier.unrated);
    });

    test('green is free or cheap; only free costs nothing', () {
      expect(<ModelTier>[for (final ModelTier t in ModelTier.values) if (t.isGreen) t], <ModelTier>[ModelTier.free, ModelTier.cheap]);
      expect(ModelTier.free.costsMoney, isFalse);
      for (final ModelTier t in <ModelTier>[ModelTier.cheap, ModelTier.paid, ModelTier.premium, ModelTier.unrated]) {
        expect(t.costsMoney, isTrue, reason: t.label);
      }
    });
  });

  group('catalog', () {
    AiModel pick(AiService s, String id) => catalogModel(s, id)!;

    test('ids are unique per service', () {
      final Set<String> seen = <String>{};
      for (final AiModel m in kAiModels) {
        expect(seen.add('${m.service.name}/${m.id}'), isTrue, reason: m.id);
      }
    });

    test('ratings the user sees', () {
      expect(pick(AiService.gemini, 'gemini-flash-latest').tier, ModelTier.free);
      expect(pick(AiService.gemini, 'gemini-2.5-flash-lite').tier, ModelTier.free);
      expect(pick(AiService.gemini, 'gemini-2.5-pro').tier, ModelTier.paid, reason: '\$10 out is the top of PAID');
      expect(pick(AiService.groq, 'llama-3.3-70b-versatile').tier, ModelTier.free);
      expect(pick(AiService.openai, 'gpt-5.4-nano').tier, ModelTier.cheap);
      expect(pick(AiService.openai, 'gpt-5.4').tier, ModelTier.premium);
      expect(pick(AiService.anthropic, 'claude-haiku-5-5').tier, ModelTier.cheap);
      expect(pick(AiService.anthropic, 'claude-sonnet-5-5').tier, ModelTier.paid);
      expect(pick(AiService.anthropic, 'claude-opus-5-5').tier, ModelTier.premium);
      expect(pick(AiService.anthropic, 'claude-fable-5-1').tier, ModelTier.premium);
    });

    test('every Gemini and Groq model without a price is on the free tier, and every paid one has a price', () {
      for (final AiModel m in kAiModels) {
        if (m.outPerM == null) expect(m.freeTier, isTrue, reason: m.id);
        if (!m.freeTier) expect(m.tier, isNot(ModelTier.unrated), reason: m.id);
      }
    });

    test('the default model for each provider is rated', () {
      expect(rateModel(AiService.gemini, defaultModelFor('gemini')), ModelTier.free);
      expect(rateModel(AiService.anthropic, defaultModelFor('anthropic')), ModelTier.cheap);
    });

    test('price lines read well', () {
      expect(pick(AiService.gemini, 'gemini-2.5-flash-lite').price, 'Free tier. If billed: \$0.10 in / \$0.40 out per 1M');
      expect(pick(AiService.gemini, 'gemini-flash-latest').price, 'Free tier, rate limited');
      expect(pick(AiService.anthropic, 'claude-opus-5-5').price, '\$4 in / \$20 out per 1M');
    });
  });

  group('services', () {
    test('detects the service from provider and base URL', () {
      expect(AiService.detect('gemini', ''), AiService.gemini);
      expect(AiService.detect('anthropic', ''), AiService.anthropic);
      expect(AiService.detect('openai', ''), AiService.openai);
      expect(AiService.detect('openai', 'https://api.groq.com/openai'), AiService.groq);
      expect(AiService.detect('openai', 'https://openrouter.ai/api/'), AiService.openrouter);
      expect(AiService.detect('openai', 'http://192.168.1.20:11434'), isNull);
    });

    test('a model outside the catalog is unrated, except an OpenRouter :free one', () {
      expect(rateModel(AiService.openrouter, 'meta-llama/some-model:free'), ModelTier.free);
      expect(rateModel(AiService.openrouter, 'meta-llama/some-model'), ModelTier.unrated);
      expect(rateModel(AiService.gemini, 'gemini-9-ultra'), ModelTier.unrated);
      expect(rateModel(null, 'llama3'), ModelTier.unrated, reason: 'a custom endpoint may be local or paid');
    });
  });

  group('live lists', () {
    test('Gemini: only models that can generate text', () {
      final List<AiModel> r = parseLiveModels(
        AiService.gemini,
        jsonEncode(<String, dynamic>{
          'models': <Map<String, dynamic>>[
            <String, dynamic>{'name': 'models/gemini-2.5-flash', 'displayName': 'Gemini 2.5 Flash', 'supportedGenerationMethods': <String>['generateContent', 'countTokens']},
            <String, dynamic>{'name': 'models/gemini-embedding-001', 'supportedGenerationMethods': <String>['embedContent']},
            <String, dynamic>{'name': 'models/imagen-4', 'supportedGenerationMethods': <String>['predict']},
            <String, dynamic>{'name': 'models/gemini-9-new', 'displayName': 'Gemini 9', 'supportedGenerationMethods': <String>['generateContent']},
            <String, dynamic>{'name': 'models/gemini-2.5-flash-preview-tts', 'supportedGenerationMethods': <String>['generateContent']},
          ],
        }),
      );
      expect(r.map((AiModel m) => m.id), <String>['gemini-2.5-flash', 'gemini-9-new']);
      expect(r.first.tier, ModelTier.free, reason: 'the catalog entry wins');
      expect(r.last.tier, ModelTier.unrated);
      expect(r.last.label, 'Gemini 9');
    });

    test('OpenRouter: real prices decide the tier, and free comes first', () {
      final List<AiModel> r = parseLiveModels(
        AiService.openrouter,
        jsonEncode(<String, dynamic>{
          'data': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'big/model', 'name': 'Big', 'pricing': <String, String>{'prompt': '0.000005', 'completion': '0.000025'}},
            <String, dynamic>{'id': 'small/model', 'name': 'Small', 'pricing': <String, String>{'prompt': '0.0000001', 'completion': '0.0000004'}},
            <String, dynamic>{'id': 'free/model', 'name': 'Free', 'pricing': <String, String>{'prompt': '0', 'completion': '0'}},
            <String, dynamic>{'id': 'router/auto', 'name': 'Auto', 'pricing': <String, String>{'prompt': '-1', 'completion': '-1'}},
            <String, dynamic>{'id': 'pic/model', 'name': 'Pic', 'architecture': <String, dynamic>{'output_modalities': <String>['image']}, 'pricing': <String, String>{'prompt': '0', 'completion': '0'}},
          ],
        }),
      );
      expect(r.map((AiModel m) => '${m.id}:${m.tier.label}'), <String>['free/model:FREE', 'small/model:CHEAP', 'big/model:PREMIUM', 'router/auto:UNRATED']);
      expect(r[2].outPerM, closeTo(25, 1e-9));
    });

    test('Groq and OpenAI: non-chat models are left out', () {
      final List<AiModel> r = parseLiveModels(
        AiService.groq,
        jsonEncode(<String, dynamic>{
          'data': <Map<String, String>>[
            <String, String>{'id': 'llama-3.1-8b-instant'},
            <String, String>{'id': 'whisper-large-v3'},
            <String, String>{'id': 'meta-llama/llama-guard-4-12b'},
            <String, String>{'id': 'openai/gpt-oss-20b'},
          ],
        }),
      );
      expect(r.map((AiModel m) => m.id).toSet(), <String>{'llama-3.1-8b-instant', 'openai/gpt-oss-20b'});
      expect(r.every((AiModel m) => m.tier == ModelTier.free), isTrue);
    });

    test('Anthropic: ids and display names', () {
      final List<AiModel> r = parseLiveModels(
        AiService.anthropic,
        jsonEncode(<String, dynamic>{
          'data': <Map<String, String>>[
            <String, String>{'id': 'claude-opus-5-5', 'display_name': 'Claude Opus 5.5'},
            <String, String>{'id': 'claude-future-9', 'display_name': 'Claude Future 9'},
          ],
        }),
      );
      expect(r.map((AiModel m) => '${m.id}:${m.tier.label}'), <String>['claude-opus-5-5:PREMIUM', 'claude-future-9:UNRATED']);
    });
  });

  group('fetchLiveModels', () {
    test('needs a key, except OpenRouter', () async {
      int calls = 0;
      final MockClient client = MockClient((http.Request r) async {
        calls++;
        return json(200, <String, dynamic>{'data': <dynamic>[]});
      });
      final LiveModels r = await fetchLiveModels(AiService.gemini, apiKey: ' ', client: client);
      expect(r.error, 'Add the API key first.');
      expect(calls, 0);
    });

    test('each service gets its own URL and auth header', () async {
      final Map<AiService, http.Request> seen = <AiService, http.Request>{};
      for (final AiService s in AiService.values) {
        final MockClient client = MockClient((http.Request r) async {
          seen[s] = r;
          return json(200, <String, dynamic>{
            'models': <Map<String, dynamic>>[
              <String, dynamic>{'name': 'models/gemini-x', 'supportedGenerationMethods': <String>['generateContent']},
            ],
            'data': <Map<String, String>>[
              <String, String>{'id': 'some-model'},
            ],
          });
        });
        final LiveModels r = await fetchLiveModels(s, apiKey: 'K', client: client);
        expect(r.error, isNull, reason: s.name);
        expect(r.models, isNotEmpty);
      }
      expect(seen[AiService.gemini]!.url.toString(), startsWith('https://generativelanguage.googleapis.com/v1beta/models'));
      expect(seen[AiService.gemini]!.headers['x-goog-api-key'], 'K');
      expect(seen[AiService.gemini]!.url.queryParameters.containsKey('key'), isFalse, reason: 'the key must not appear in the URL');
      expect(seen[AiService.groq]!.url.toString(), 'https://api.groq.com/openai/v1/models');
      expect(seen[AiService.groq]!.headers['authorization'], 'Bearer K');
      expect(seen[AiService.openai]!.url.toString(), 'https://api.openai.com/v1/models');
      expect(seen[AiService.anthropic]!.url.path, '/v1/models');
      expect(seen[AiService.anthropic]!.headers['x-api-key'], 'K');
      expect(seen[AiService.anthropic]!.headers['anthropic-version'], '2023-06-01');
      expect(seen[AiService.openrouter]!.url.toString(), 'https://openrouter.ai/api/v1/models');
      expect(seen[AiService.openrouter]!.headers.containsKey('authorization'), isFalse, reason: 'the public list needs no key, and none is sent to a service it does not belong to');
    });

    test('says what went wrong', () async {
      final MockClient bad = MockClient((http.Request r) async => json(401, <String, dynamic>{
            'error': <String, dynamic>{'message': 'Invalid API Key'},
          }));
      expect((await fetchLiveModels(AiService.groq, apiKey: 'x', client: bad)).error, 'HTTP 401: Invalid API Key');

      final MockClient off = MockClient((http.Request r) async => throw http.ClientException('offline'));
      expect((await fetchLiveModels(AiService.groq, apiKey: 'x', client: off)).error, startsWith('Could not reach the service'));

      final MockClient empty = MockClient((http.Request r) async => json(200, <String, dynamic>{'data': <dynamic>[]}));
      expect((await fetchLiveModels(AiService.groq, apiKey: 'x', client: empty)).error, 'The service listed no usable models.');
    });
  });
}
