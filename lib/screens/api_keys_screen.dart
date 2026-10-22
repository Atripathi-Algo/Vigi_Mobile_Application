import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/cloud_ai.dart';
import '../api/weather_api.dart';
import '../app/common.dart';
import '../app/env.dart';
import '../app/providers.dart';
import '../data/store.dart';
import '../services/calendar_sync.dart';
import '../services/push.dart';
import '../services/output_sync.dart';
import '../vigil/vigil.dart';

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
    'Lets Uplink answer open-ended questions. Used only when Cloud AI is switched on in Loadout. Sends your SITREP (objectives, sleep, spending totals) and the question to the provider.',
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
    'Reads today\'s events into the Timeline. An API key works for public calendars only. Use the full calendar id, for example you@gmail.com.',
    <_KeyField>[
      _KeyField('GOOGLE_CALENDAR_API_KEY', 'API key', secret: true),
      _KeyField('GOOGLE_CALENDAR_ID', 'Calendar id', hint: 'you@gmail.com'),
      _KeyField('GOOGLE_CLIENT_ID', 'OAuth client id', hint: 'for future sign-in'),
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
    'VIGIL backend',
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

  @override
  void initState() {
    super.initState();
    for (final _Group g in _groups) {
      for (final _KeyField f in g.fields) {
        _ctl[f.key] = TextEditingController(text: Env.value(f.key));
      }
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> _values(_Group g) => <String, String>{
        for (final _KeyField f in g.fields) f.key: _ctl[f.key]!.text.trim(),
        if (g.id == 'ai') 'CLOUD_AI_PROVIDER': _provider,
      };

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
    await Env.save(<String, String>{for (final _KeyField f in g.fields) f.key: '', if (g.id == 'ai') 'CLOUD_AI_PROVIDER': ''});
    if (!mounted) return;
    setState(() {
      for (final _KeyField f in g.fields) {
        _ctl[f.key]!.text = Env.value(f.key);
      }
      if (g.id == 'ai') _provider = Env.cloudAiProvider;
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
            final CloudReply a = await askCloudDetailed('Reply with the single word: ready.', s.sitrep(DateTime.now()));
            final String? text = a.text;
            out = text == null ? 'Failed. ${a.error}' : 'OK. Reply: ${text.length > 80 ? '${text.substring(0, 80)}…' : text}';
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
            'LINKED' => 'Connected. Copy the device token from Loadout.',
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
      subtitle: 'SAVED ON THIS PHONE · ENCRYPTED',
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
          Expanded(child: Text(g.title.toUpperCase(), style: t.label.copyWith(color: c.text))),
          StatusChip(g.required.isEmpty ? (src == 'NONE' ? 'DEFAULT' : 'SET · $src') : (ready ? 'READY · $src' : 'NOT SET'), on: ready || (g.required.isEmpty && src != 'NONE')),
        ]),
        const SizedBox(height: 6),
        Text(g.blurb, style: t.caption.copyWith(color: c.textMuted)),
        const SizedBox(height: 12),
        if (g.id == 'ai') ...<Widget>[
          Text('PROVIDER', style: t.label.copyWith(color: c.textFaint)),
          const SizedBox(height: 6),
          VigilSegmented<String>(
            segments: const <(String, String)>[('gemini', 'GEMINI'), ('openai', 'OPENAI API'), ('anthropic', 'ANTHROPIC')],
            selected: _provider,
            onSelected: (String v) => setState(() => _provider = v),
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
            suffix: f.secret
                ? IconButton(
                    tooltip: _shown.contains(f.key) ? 'Hide' : 'Show',
                    icon: Icon(_shown.contains(f.key) ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: c.textMuted),
                    onPressed: () => setState(() => _shown.contains(f.key) ? _shown.remove(f.key) : _shown.add(f.key)),
                  )
                : null,
          ),
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
