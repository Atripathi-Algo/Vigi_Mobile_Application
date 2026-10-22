import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_error.dart';

/// How a model is billed, from the user's side. Colour in the UI: green for [free] and [cheap],
/// amber for [paid], red for [premium], grey for [unrated].
enum ModelTier {
  free('FREE'),
  cheap('CHEAP'),
  paid('PAID'),
  premium('PREMIUM'),
  unrated('UNRATED');

  const ModelTier(this.label);
  final String label;

  bool get isGreen => this == free || this == cheap;

  /// Anything but a free tier can bill the account behind the key.
  bool get costsMoney => this != free;
}

/// Output price per 1M tokens (USD) up to which a paid model counts as CHEAP / PAID. Above is PREMIUM.
const double kCheapMaxOut = 1.5;
const double kPaidMaxOut = 10;

/// Tier for a model that has no free tier, from its output price per 1M tokens.
ModelTier tierForOutputPrice(double? outPerM) {
  if (outPerM == null || outPerM < 0) return ModelTier.unrated;
  if (outPerM <= kCheapMaxOut) return ModelTier.cheap;
  if (outPerM <= kPaidMaxOut) return ModelTier.paid;
  return ModelTier.premium;
}

/// The services behind the three API styles (`gemini`, `openai`, `anthropic`).
/// Groq, OpenRouter and OpenAI all speak the OpenAI style and differ only in base URL.
enum AiService {
  gemini('Gemini', 'gemini', 'https://generativelanguage.googleapis.com'),
  groq('Groq', 'openai', 'https://api.groq.com/openai'),
  openrouter('OpenRouter', 'openai', 'https://openrouter.ai/api'),
  openai('OpenAI', 'openai', 'https://api.openai.com'),
  anthropic('Anthropic', 'anthropic', 'https://api.anthropic.com');

  const AiService(this.label, this.provider, this.baseUrl);
  final String label;

  /// Value for CLOUD_AI_PROVIDER.
  final String provider;

  /// Value for CLOUD_AI_BASE_URL (what the service itself uses).
  final String baseUrl;

  String get host => Uri.parse(baseUrl).host;

  /// The service a provider and base URL point at; null for a custom endpoint such as Ollama.
  static AiService? detect(String provider, String baseUrl) {
    final String b = baseUrl.trim().toLowerCase();
    if (b.isEmpty) {
      return switch (provider) {
        'gemini' => gemini,
        'anthropic' => anthropic,
        _ => openai,
      };
    }
    for (final AiService s in values) {
      if (b.contains(s.host)) return s;
    }
    return null;
  }
}

/// One model with how it is billed. Prices are USD per 1M tokens and approximate.
class AiModel {
  const AiModel(this.service, this.id, this.label, {this.freeTier = false, this.inPerM, this.outPerM, this.note = ''});

  final AiService service;
  final String id;
  final String label;

  /// True when the service offers it without charge (rate limited, no card needed).
  final bool freeTier;
  final double? inPerM;
  final double? outPerM;
  final String note;

  ModelTier get tier => freeTier ? ModelTier.free : tierForOutputPrice(outPerM);

  /// Price line for the list: "$0.10 in / $0.40 out per 1M", with a free-tier prefix where it applies.
  String get price {
    final String paid = (inPerM != null && outPerM != null) ? '${_usd(inPerM!)} in / ${_usd(outPerM!)} out per 1M' : 'price not known';
    if (!freeTier) return paid;
    return (inPerM != null && outPerM != null) ? 'Free tier. If billed: $paid' : 'Free tier, rate limited';
  }
}

String _usd(double v) => '\$${v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';

/// Curated list, prices as published around October 2026. Anthropic figures are from Anthropic's own
/// price list; Google, OpenAI and Groq change often, so the screen tells the user to check the provider.
/// A model missing here is still usable: type its id, or load the live list.
const List<AiModel> kAiModels = <AiModel>[
  // Gemini: the free tier is rate limited and Google may use free-tier prompts to improve its products.
  AiModel(AiService.gemini, 'gemini-flash-latest', 'Gemini Flash (latest)', freeTier: true, note: 'Alias for the current Flash. App default.'),
  AiModel(AiService.gemini, 'gemini-flash-lite-latest', 'Gemini Flash-Lite (latest)', freeTier: true, note: 'Alias for the current Flash-Lite. Fastest.'),
  AiModel(AiService.gemini, 'gemini-2.5-flash', 'Gemini 2.5 Flash', freeTier: true, inPerM: 0.30, outPerM: 2.50),
  AiModel(AiService.gemini, 'gemini-2.5-flash-lite', 'Gemini 2.5 Flash-Lite', freeTier: true, inPerM: 0.10, outPerM: 0.40),
  AiModel(AiService.gemini, 'gemini-2.5-pro', 'Gemini 2.5 Pro', inPerM: 1.25, outPerM: 10, note: 'Free tier may not include Pro.'),
  // Groq: free plan without a card, per-model request limits.
  AiModel(AiService.groq, 'llama-3.1-8b-instant', 'Llama 3.1 8B Instant', freeTier: true, note: 'Highest free daily allowance.'),
  AiModel(AiService.groq, 'llama-3.3-70b-versatile', 'Llama 3.3 70B', freeTier: true),
  AiModel(AiService.groq, 'openai/gpt-oss-20b', 'GPT-OSS 20B', freeTier: true),
  AiModel(AiService.groq, 'openai/gpt-oss-120b', 'GPT-OSS 120B', freeTier: true),
  // OpenAI: no free API tier.
  AiModel(AiService.openai, 'gpt-5.4-nano', 'GPT-5.4 nano', inPerM: 0.20, outPerM: 1.25),
  AiModel(AiService.openai, 'gpt-5.4-mini', 'GPT-5.4 mini', inPerM: 0.75, outPerM: 4.50),
  AiModel(AiService.openai, 'gpt-5.4', 'GPT-5.4', inPerM: 2.50, outPerM: 15),
  // Anthropic: no free API tier.
  AiModel(AiService.anthropic, 'claude-haiku-5-5', 'Claude Haiku 5.5', inPerM: 0.10, outPerM: 0.50, note: 'Cheapest Claude.'),
  AiModel(AiService.anthropic, 'claude-haiku-4-5', 'Claude Haiku 4.5', inPerM: 1, outPerM: 5),
  AiModel(AiService.anthropic, 'claude-sonnet-5-5', 'Claude Sonnet 5.5', inPerM: 2, outPerM: 10),
  AiModel(AiService.anthropic, 'claude-opus-5-5', 'Claude Opus 5.5', inPerM: 4, outPerM: 20),
  AiModel(AiService.anthropic, 'claude-fable-5-1', 'Claude Fable 5.1', inPerM: 10, outPerM: 50, note: 'Most capable. Highest price.'),
];

/// The listed models for [service], in catalog order.
List<AiModel> modelsFor(AiService service) => kAiModels.where((AiModel m) => m.service == service).toList();

/// The catalog entry for [id] on [service], or null.
AiModel? catalogModel(AiService? service, String id) {
  for (final AiModel m in kAiModels) {
    if (m.service == service && m.id == id) return m;
  }
  return null;
}

/// How [id] is billed on [service]. Models outside the catalog are rated from their id where the
/// service marks it (OpenRouter `:free`), otherwise [ModelTier.unrated]. A custom endpoint (null service)
/// is unrated: it may be a local Ollama (free) or a paid gateway, and the app cannot tell.
ModelTier rateModel(AiService? service, String id) {
  final AiModel? m = catalogModel(service, id);
  if (m != null) return m.tier;
  if (service == AiService.openrouter && id.endsWith(':free')) return ModelTier.free;
  return ModelTier.unrated;
}

/// The model Env falls back to for a provider when the model field is blank.
String defaultModelFor(String provider) => switch (provider) {
      'openai' => 'gpt-4o-mini',
      'gemini' => 'gemini-flash-latest',
      _ => 'claude-haiku-5-5',
    };

const String _notChat = r'whisper|tts|embed|dall-e|moderation|guard|image|audio|transcribe|realtime|orpheus|rerank|robotics|computer-use|aqa|live';

int _tierRank(ModelTier t) => t.index;

/// Result of asking a service which models the key can use.
class LiveModels {
  const LiveModels.ok(this.models) : error = null;
  const LiveModels.fail(String this.error) : models = const <AiModel>[];

  final List<AiModel> models;
  final String? error;
}

/// Turns a model-list response into rated models. Pure, so it is tested with canned bodies.
/// Catalog entries win over what the list says; OpenRouter lists real prices, which are used for the rest.
List<AiModel> parseLiveModels(AiService service, String body) {
  final dynamic j = jsonDecode(body);
  final List<AiModel> out = <AiModel>[];
  final RegExp skip = RegExp(_notChat, caseSensitive: false);

  void add(String id, String label, {bool free = false, double? inPerM, double? outPerM}) {
    if (id.isEmpty || skip.hasMatch(id)) return;
    out.add(catalogModel(service, id) ?? AiModel(service, id, label, freeTier: free || (service == AiService.openrouter && id.endsWith(':free')), inPerM: inPerM, outPerM: outPerM));
  }

  switch (service) {
    case AiService.gemini:
      for (final dynamic m in (j['models'] as List<dynamic>? ?? <dynamic>[])) {
        final Map<String, dynamic> e = m as Map<String, dynamic>;
        final List<dynamic> methods = e['supportedGenerationMethods'] as List<dynamic>? ?? <dynamic>[];
        final String id = ((e['name'] as String?) ?? '').replaceFirst('models/', '');
        if (!methods.contains('generateContent') || !(id.startsWith('gemini') || id.startsWith('gemma'))) continue;
        add(id, (e['displayName'] as String?) ?? id);
      }
    case AiService.anthropic:
      for (final dynamic m in (j['data'] as List<dynamic>? ?? <dynamic>[])) {
        final Map<String, dynamic> e = m as Map<String, dynamic>;
        final String id = (e['id'] as String?) ?? '';
        add(id, (e['display_name'] as String?) ?? id);
      }
    case AiService.groq || AiService.openai || AiService.openrouter:
      for (final dynamic m in (j['data'] as List<dynamic>? ?? <dynamic>[])) {
        final Map<String, dynamic> e = m as Map<String, dynamic>;
        final String id = (e['id'] as String?) ?? '';
        final dynamic modalities = (e['architecture'] as Map<String, dynamic>?)?['output_modalities'];
        if (modalities is List && !modalities.contains('text')) continue;
        double? perM(dynamic v) {
          final double? d = double.tryParse('${v ?? ''}');
          return (d == null || d < 0) ? null : d * 1e6;
        }

        final Map<String, dynamic>? pricing = e['pricing'] as Map<String, dynamic>?;
        final double? pin = perM(pricing?['prompt']);
        final double? pout = perM(pricing?['completion']);
        add(id, (e['name'] as String?) ?? id, free: pin == 0 && pout == 0, inPerM: pin, outPerM: pout);
      }
  }
  // Free first, then by price tier; the same id can appear twice on a few services.
  final Map<String, AiModel> unique = <String, AiModel>{for (final AiModel m in out) m.id: m};
  final List<AiModel> sorted = unique.values.toList()
    ..sort((AiModel a, AiModel b) {
      final int byTier = _tierRank(a.tier).compareTo(_tierRank(b.tier));
      return byTier != 0 ? byTier : a.id.compareTo(b.id);
    });
  return sorted;
}

/// Asks [service] which models [apiKey] can use. Needs the key, except for OpenRouter (public list).
Future<LiveModels> fetchLiveModels(AiService service, {required String apiKey, http.Client? client}) async {
  final String key = apiKey.trim();
  if (key.isEmpty && service != AiService.openrouter) return const LiveModels.fail('Add the API key first.');
  late final Uri uri;
  late final Map<String, String> headers;
  switch (service) {
    case AiService.gemini:
      uri = Uri.parse('${service.baseUrl}/v1beta/models?pageSize=200');
      headers = <String, String>{'x-goog-api-key': key};
    case AiService.anthropic:
      uri = Uri.parse('${service.baseUrl}/v1/models?limit=100');
      headers = <String, String>{'x-api-key': key, 'anthropic-version': '2023-06-01'};
    case AiService.openrouter:
      uri = Uri.parse('${service.baseUrl}/v1/models');
      headers = <String, String>{};
    case AiService.groq || AiService.openai:
      uri = Uri.parse('${service.baseUrl}/v1/models');
      headers = <String, String>{'authorization': 'Bearer $key'};
  }
  final http.Client c = client ?? http.Client();
  try {
    final http.Response r = await c.get(uri, headers: headers).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return LiveModels.fail('HTTP ${r.statusCode}: ${apiErrorMessage(r.body)}');
    final List<AiModel> models = parseLiveModels(service, r.body);
    return models.isEmpty ? const LiveModels.fail('The service listed no usable models.') : LiveModels.ok(models);
  } on TimeoutException {
    return const LiveModels.fail('Timed out after 20 seconds.');
  } catch (e) {
    return LiveModels.fail('Could not reach the service: ${e.toString().split('\n').first}');
  } finally {
    if (client == null) c.close();
  }
}
