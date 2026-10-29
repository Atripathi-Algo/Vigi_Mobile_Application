import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/ai_models.dart';
import '../api/cloud_ai.dart';
import '../api/weather_api.dart';
import '../app/common.dart';
import '../app/env.dart';
import '../app/providers.dart';
import '../data/store.dart';
import '../services/calendar_sync.dart';
import '../services/push.dart';
import '../vigil/vigil.dart';
import 'model_picker.dart';

class _KeyField {
  const _KeyField(this.key, this.label, {this.hint = '', this.secret = false, this.number = false});

  final String key;
  final String label;
  final String hint;
  final bool secret;
  final bool number;
}

class _Group {
  const _Group(this.id, this.title, this.blurb, this.fields, {this.required = const <String>[], this.testLabel});

  final String id;
  final String title;
  final String blurb;
  final List<_KeyField> fields;

  /// Keys that must be set for the feature to switch on.
  final List<String> required;
  final String? testLabel;
}

const List<_Group> _groups = <_Group>[
  _Group(
    'ai',
    'Cloud AI',
    'Lets K answer open-ended questions. Used only when Cloud AI is switched on in Settings. Sends only your question, and earlier cloud answers, to the provider. Your tasks, sleep and spending are never sent.',
    <_KeyField>[
      _KeyField('CLOUD_AI_API_KEY', 'API key', hint: 'paste your key', secret: true),
      _KeyField('CLOUD_AI_MODEL', 'Model', hint: 'blank = provider default'),
      _KeyField('CLOUD_AI_BASE_URL', 'Base URL', hint: 'blank = provider default'),
    ],
    required: <String>['CLOUD_AI_API_KEY'],
    testLabel: 'Test',
  ),
  _Group(
    'cal',
    'Google Calendar',
    'A public calendar only: an API key cannot read a private one. For private calendars link your Google accounts in Settings instead. Use the full calendar id, for example you@gmail.com.',
    <_KeyField>[
      _KeyField('GOOGLE_CALENDAR_API_KEY', 'API key', secret: true),
      _KeyField('GOOGLE_CALENDAR_ID', 'Calendar id', hint: 'you@gmail.com'),
    ],
    required: <String>['GOOGLE_CALENDAR_API_KEY', 'GOOGLE_CALENDAR_ID'],
    testLabel: 'Sync now',
  ),
  _Group(
    'wx',
    'Weather',
    'Shown in the Dawn Briefing. Open-Meteo needs no key; set your coordinates.',
    <_KeyField>[
      _KeyField('WEATHER_API_BASE_URL', 'Base URL', hint: 'https://api.open-meteo.com/v1/forecast'),
      _KeyField('WEATHER_LATITUDE', 'Latitude', hint: '28.6139', number: true),
      _KeyField('WEATHER_LONGITUDE', 'Longitude', hint: '77.2090', number: true),
    ],
    testLabel: 'Test',
  ),
  _Group(
    'fcm',
    'Firebase push',
    'Firebase console > Project settings > Your apps > Android (package com.algoanalytics.vigil). A changed project applies after the next app start.',
    <_KeyField>[
      _KeyField('FIREBASE_API_KEY', 'API key', secret: true),
      _KeyField('FIREBASE_APP_ID', 'App id', hint: '1:1234567890:android:abc…'),
      _KeyField('FIREBASE_MESSAGING_SENDER_ID', 'Sender id', hint: 'project number'),
      _KeyField('FIREBASE_PROJECT_ID', 'Project id'),
      _KeyField('FIREBASE_STORAGE_BUCKET', 'Storage bucket', hint: 'optional'),
    ],
    required: <String>['FIREBASE_API_KEY', 'FIREBASE_APP_ID', 'FIREBASE_MESSAGING_SENDER_ID', 'FIREBASE_PROJECT_ID'],
    testLabel: 'Connect',
  ),
  _Group(
    'be',
    'K backend',
    'Reserved for your own server. Nothing calls it yet; the values are stored for when you add endpoints.',
    <_KeyField>[
      _KeyField('VIGIL_API_BASE_URL', 'Base URL', hint: 'https://api.example.com'),
      _KeyField('VIGIL_API_KEY', 'API key', secret: true),
    ],
    required: <String>['VIGIL_API_BASE_URL'],
  ),
];

/// Settings > API keys. Values are saved in encrypted storage on this phone and
/// override the bundled `.env`, so no rebuild is needed.
class ApiKeysScreen extends ConsumerStatefulWidget {
  const ApiKeysScreen({super.key});

  @override
  ConsumerState<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends ConsumerState<ApiKeysScreen> {
  final Map<String, TextEditingController> _ctl = <String, TextEditingController>{};
  final Set<String> _shown = <String>{};
  final Map<String, String> _result = <String, String>{};
  final Set<String> _busy = <String>{};
  String _provider = Env.cloudAiProvider;

  /// Cloud AI keys are kept per service, so switching service never sends one company's key to another.
  final Map<AiService, String> _svcKeys = <AiService, String>{};

  static String _svcKeyName(AiService s) => 'CLOUD_AI_KEY_${s.name.toUpperCase()}';

  @override
  void initState() {
    super.initState();
    for (final _Group g in _groups) {
      for (final _KeyField f in g.fields) {
        _ctl[f.key] = TextEditingController(text: Env.value(f.key));
      }
    }
    for (final AiService s in AiService.values) {
      _svcKeys[s] = Env.value(_svcKeyName(s));
    }
    // A key saved before per-service keys existed belongs to the service in use.
    final AiService? cur = _service;
    if (cur != null && (_svcKeys[cur] ?? '').isEmpty) _svcKeys[cur] = Env.value('CLOUD_AI_API_KEY');
  }

  AiService? get _service => AiService.detect(_provider, _ctl['CLOUD_AI_BASE_URL']!.text);

  /// The model in effect on screen: the field, or the provider's default when it is blank.
  String get _modelId {
    final String v = _ctl['CLOUD_AI_MODEL']!.text.trim();
    return v.isEmpty ? defaultModelFor(_provider) : v;
  }

  void _stashKey() {
    final AiService? s = _service;
    if (s != null) _svcKeys[s] = _ctl['CLOUD_AI_API_KEY']!.text.trim();
  }

  /// Points the Cloud AI fields at [s]: provider, base URL, model and that service's own key.
  void _useService(AiService s, {String model = ''}) {
    _stashKey();
    _provider = s.provider;
    _ctl['CLOUD_AI_MODEL']!.text = model;
    _ctl['CLOUD_AI_BASE_URL']!.text = (s == AiService.groq || s == AiService.openrouter) ? s.baseUrl : '';
    _ctl['CLOUD_AI_API_KEY']!.text = _svcKeys[s] ?? '';
  }

  Future<void> _pickModel() async {
    final AiService? before = _service;
    final AiModel? m = await showModelPicker(context, service: before, apiKey: _ctl['CLOUD_AI_API_KEY']!.text, selectedId: _modelId);
    if (m == null || !mounted) return;
    if (m.tier.costsMoney && !await _confirmPaid(m)) return;
    if (!mounted) return;
    setState(() {
      if (m.service == before) {
        _ctl['CLOUD_AI_MODEL']!.text = m.id;
      } else {
        _useService(m.service, model: m.id);
      }
    });
    if (m.service != before && (_svcKeys[m.service] ?? '').isEmpty) showVigilSnack(context, 'Paste your ${m.service.label} key, then Save');
  }

  /// Anything off a free tier can bill the account behind the key, so it is never picked silently.
  Future<bool> _confirmPaid(AiModel m) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(m.tier == ModelTier.unrated ? 'Price unknown' : 'Paid model'),
        content: Text('${m.label} is not on a free tier (${m.price}). Calls are billed to the account behind your ${m.service.label} key. Use it?'),
        actions: <Widget>[
          VigilButton(label: 'Keep current', variant: VigilButtonVariant.secondary, onPressed: () => Navigator.pop(ctx, false)),
          VigilButton(label: 'Use it', onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    return ok ?? false;
  }

  Widget _modelRating(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final AiService? svc = _service;
    final String id = _modelId;
    final String line = catalogModel(svc, id)?.price ??
        (svc == null ? 'Custom endpoint: cost depends on what runs there' : 'Not in the list: check the provider\'s price');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: <Widget>[
        ModelTierBadge(rateModel(svc, id)),
        const SizedBox(width: 8),
        Expanded(
          child: Text('${_ctl['CLOUD_AI_MODEL']!.text.trim().isEmpty ? 'Default · ' : ''}$id · $line', style: t.micro.copyWith(color: c.textFaint, fontSize: 10)),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    for (final TextEditingController c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> _values(_Group g) {
    if (g.id == 'ai') _stashKey();
    return <String, String>{
      for (final _KeyField f in g.fields) f.key: _ctl[f.key]!.text.trim(),
      if (g.id == 'ai') ...<String, String>{
        'CLOUD_AI_PROVIDER': _provider,
        for (final MapEntry<AiService, String> e in _svcKeys.entries) _svcKeyName(e.key): e.value,
      },
    };
  }

  bool _ready(_Group g) => g.required.isNotEmpty && g.required.every((String k) => Env.value(k).isNotEmpty);

  String _source(_Group g) {
    final Set<String> s = g.fields.map((_KeyField f) => Env.source(f.key)).toSet();
    if (s.contains('APP')) return 'APP';
    if (s.contains('.ENV')) return '.ENV';
    return 'NONE';
  }

  Future<void> _save(_Group g) async {
    await Env.save(_values(g));
    if (!mounted) return;
    setState(() => _result[g.id] = 'Saved on this phone.');
    showVigilSnack(context, '${g.title} saved');
    final VigilStore s = ref.read(storeProvider);
    if (g.id == 'cal' && Env.hasCalendar) await pullCalendar(s);
    if (g.id == 'fcm') await PushService.init();
    if (g.id == 'wx' || g.id == 'cal') await ref.read(outputSyncProvider)?.run();
  }

  Future<void> _clear(_Group g) async {
    await Env.save(<String, String>{
      for (final _KeyField f in g.fields) f.key: '',
      if (g.id == 'ai') ...<String, String>{'CLOUD_AI_PROVIDER': '', for (final AiService s in AiService.values) _svcKeyName(s): ''},
    });
    if (!mounted) return;
    setState(() {
      for (final _KeyField f in g.fields) {
        _ctl[f.key]!.text = Env.value(f.key);
      }
      if (g.id == 'ai') {
        _provider = Env.cloudAiProvider;
        _svcKeys.updateAll((AiService _, String __) => '');
        _stashKey();
      }
      _result[g.id] = 'App values cleared. Using .env where set.';
    });
  }

  Future<void> _test(_Group g) async {
    // Test what is on screen, so save first.
    await Env.save(_values(g));
    setState(() {
      _busy.add(g.id);
      _result.remove(g.id);
    });
    final VigilStore s = ref.read(storeProvider);
    String out;
    try {
      switch (g.id) {
        case 'ai':
          if (!Env.hasCloudAi) {
            out = 'No API key set.';
          } else {
            final CloudReply a = await askCloudDetailed('Reply with the single word: ready.', '');
            final String? text = a.text;
            out = text == null ? 'Failed. ${a.error}' : 'OK. Reply: ${text.length > 80 ? '${text.substring(0, 80)}…' : text}${a.note == null ? '' : ' Note: ${a.note}'}';
          }
        case 'cal':
          out = !Env.hasCalendar ? 'Needs an API key and a calendar id.' : (await pullCalendar(s) ? 'OK. Events merged into the Timeline.' : 'Failed. The calendar must be public and the id exact.');
        case 'wx':
          final Weather? w = await fetchWeather();
          out = w == null ? 'Failed. Check the base URL and coordinates.' : 'OK. ${w.tempC.round()}°C ${w.summary}.';
        case 'fcm':
          await PushService.init();
          final String st = PushService.status.value;
          out = switch (st) {
            'LINKED' => 'Connected. Copy the device token from Settings.',
            'RESTART' => 'Saved. Restart the app to switch Firebase projects.',
            'OFF' => 'Fill in API key, app id, sender id and project id.',
            _ => 'Status: $st. Check the values against the Firebase console.',
          };
        default:
          out = 'Nothing to test.';
      }
    } catch (e) {
      out = 'Error: $e';
    }
    if (mounted) {
      setState(() {
        _busy.remove(g.id);
        _result[g.id] = out;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    return VigilScaffold(
      title: 'API keys',
      subtitle: 'Saved on this phone · Encrypted',
      leading: VigilIconButton(icon: VigilIcons.chevronLeft, semanticLabel: 'Back', onPressed: () => context.pop()),
      body: ListView(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 28),
        children: <Widget>[
          VigilCard(
            child: Text(
              'Values saved here override the bundled .env file and take effect without a rebuild. They live in Android\'s encrypted storage and are not part of exports. Leave a field blank to fall back to .env.',
              style: t.caption.copyWith(color: c.textMuted),
            ),
          ),
          const SizedBox(height: 14),
          for (final _Group g in _groups) ...<Widget>[_groupCard(context, g), const SizedBox(height: 14)],
        ],
      ),
    );
  }

  Widget _groupCard(BuildContext context, _Group g) {
    final c = context.vigil;
    final t = context.vtype;
    final bool ready = _ready(g);
    final String src = _source(g);
    final bool busy = _busy.contains(g.id);
    return VigilCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text(g.title, style: t.label.copyWith(color: c.text))),
          StatusChip(g.required.isEmpty ? (src == 'NONE' ? 'DEFAULT' : 'SET · $src') : (ready ? 'READY · $src' : 'NOT SET'), on: ready || (g.required.isEmpty && src != 'NONE')),
        ]),
        const SizedBox(height: 6),
        Text(g.blurb, style: t.caption.copyWith(color: c.textMuted)),
        const SizedBox(height: 12),
        if (g.id == 'ai') ...<Widget>[
          Text('Provider', style: t.label.copyWith(color: c.textFaint)),
          const SizedBox(height: 6),
          VigilSegmented<String>(
            segments: const <(String, String)>[('gemini', 'Gemini'), ('openai', 'OpenAI API'), ('anthropic', 'Anthropic')],
            selected: _provider,
            onSelected: (String v) {
              if (v == _provider) return;
              setState(() => _useService(switch (v) {
                    'gemini' => AiService.gemini,
                    'anthropic' => AiService.anthropic,
                    _ => AiService.openai,
                  }));
            },
          ),
          const SizedBox(height: 6),
          Text(
            switch (_provider) {
              'gemini' => 'FREE TIER · GOOGLE MAY USE WHAT YOU SEND TO IMPROVE ITS PRODUCTS',
              'openai' => 'GROQ, OPENROUTER, OLLAMA OR OPENAI · SET THE MODEL AND BASE URL',
              _ => 'PAID API · BILLED BY ANTHROPIC',
            },
            style: t.micro.copyWith(color: _provider == 'anthropic' ? c.critical : c.textFaint, fontSize: 9),
          ),
          const SizedBox(height: 12),
        ],
        for (final _KeyField f in g.fields) ...<Widget>[
          VigilField(
            controller: _ctl[f.key]!,
            label: f.label,
            hint: f.hint,
            obscure: f.secret && !_shown.contains(f.key),
            keyboardType: f.number ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
            onChanged: g.id == 'ai' ? (_) => setState(() {}) : null,
            suffix: f.key == 'CLOUD_AI_MODEL'
                ? IconButton(
                    tooltip: 'Choose a model',
                    icon: Icon(Icons.arrow_drop_down_rounded, size: 30, color: c.signal),
                    onPressed: _pickModel,
                  )
                : f.secret
                    ? IconButton(
                        tooltip: _shown.contains(f.key) ? 'Hide' : 'Show',
                        icon: Icon(_shown.contains(f.key) ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: c.textMuted),
                        onPressed: () => setState(() => _shown.contains(f.key) ? _shown.remove(f.key) : _shown.add(f.key)),
                      )
                    : null,
          ),
          if (f.key == 'CLOUD_AI_MODEL') _modelRating(context),
          Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 10),
            child: Text(f.key, style: t.micro.copyWith(color: c.textFaint, fontSize: 9)),
          ),
        ],
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          VigilButton(label: 'Save', onPressed: busy ? null : () => _save(g)),
          if (g.testLabel != null) VigilButton(label: busy ? 'Working…' : g.testLabel!, variant: VigilButtonVariant.accent, onPressed: busy ? null : () => _test(g)),
          VigilButton(label: 'Clear', variant: VigilButtonVariant.secondary, onPressed: busy ? null : () => _clear(g)),
        ]),
        if (_result[g.id] != null) ...<Widget>[
          const SizedBox(height: 10),
          Semantics(liveRegion: true, child: Text(_result[g.id]!, style: t.meta.copyWith(color: _result[g.id]!.startsWith('OK') || _result[g.id]!.startsWith('Saved') || _result[g.id]!.startsWith('Connected') ? c.signal : c.textMuted, fontSize: 12))),
        ],
      ]),
    );
  }
}
