import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app/brand.dart';
import '../app/common.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/store.dart';
import '../services/drive_backup.dart';
import '../services/drive_sync.dart';
import '../services/google_accounts.dart';
import '../services/health.dart';
import '../services/local_brain.dart';
import '../services/notifications.dart';
import '../services/sfx.dart';
import '../services/steps.dart';
import '../services/voice.dart';
import '../vigil/vigil.dart';
import '../services/haptics.dart';

/// First-run setup guide: seven steps, each one idea. Shown on the first launch after a fresh install, and again
/// from Loadout, "Run K setup again" (then it only changes the profile and settings, never wipes anything).
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

enum _Step { welcome, profile, google, restore, brain, permissions, voice, ready }

class _Perm {
  const _Perm(this.key, this.title, this.reason, {this.optional = false});

  final String key;
  final String title;
  final String reason;
  final bool optional;
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  static const List<_Perm> _perms = <_Perm>[
    _Perm('mic', 'Microphone', 'So you can talk to K. Speech is turned into text on this phone (offline speech pack).'),
    _Perm('notif', 'Notifications', 'Reminders, briefings and streak nudges. Critical alerts ring even in Do Not Disturb only if you allow it.'),
    _Perm('steps', 'Steps & activity', 'Counts your steps with the phone\'s own sensor. Nothing leaves the phone.'),
    _Perm('health', 'Health Connect', 'Sleep, weight and resting heart rate, read only. K never writes to it.', optional: true),
    _Perm('battery', 'Background & battery', 'Lets reminders arrive on time. In Android settings, allow auto-start and choose "No restrictions".'),
  ];

  final TextEditingController _nick = TextEditingController();
  final TextEditingController _full = TextEditingController();
  final Map<String, String> _permState = <String, String>{}; // key -> OK / DENIED / SKIPPED
  _Step _step = _Step.welcome;
  int _permIndex = 0;
  bool _working = false;
  String? _error;
  DriveFile? _backup;
  String? _driveNote;
  String? _brainError;

  @override
  void initState() {
    super.initState();
    final VigilStore s = ref.read(storeProvider);
    _nick.text = s.callsign;
    _full.text = s.fullName;
    _nick.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nick.dispose();
    _full.dispose();
    super.dispose();
  }

  int get _number => switch (_step) {
        _Step.welcome => 1,
        _Step.profile => 2,
        _Step.google || _Step.restore => 3,
        _Step.brain => 4,
        _Step.permissions => 5,
        _Step.voice => 6,
        _Step.ready => 7,
      };

  void _go(_Step s) => setState(() {
        _step = s;
        _error = null;
        _working = false;
      });

  void _back() {
    switch (_step) {
      case _Step.welcome:
        if (context.canPop()) context.pop();
      case _Step.profile:
        _go(_Step.welcome);
      case _Step.google:
        _go(_Step.profile);
      case _Step.restore:
        _go(_Step.google);
      case _Step.brain:
        _go(_Step.google);
      case _Step.permissions:
        if (_permIndex > 0) {
          setState(() => _permIndex--);
        } else {
          _go(_Step.brain);
        }
      case _Step.voice:
        _go(_Step.permissions);
      case _Step.ready:
        _go(_Step.voice);
    }
  }

  // ---------------------------------------------------------------- step 3: Google and Drive

  Future<void> _continueWithGoogle() async {
    setState(() {
      _working = true;
      _error = null;
    });
    final GoogleAccounts g = GoogleAccounts.instance;
    final String? err = g.hasAny ? null : await g.link(0);
    if (!mounted) return;
    DriveSync.instance.attach(ref.read(storeProvider));
    if (err != null) {
      setState(() {
        _working = false;
        _error = err;
      });
      return;
    }
    try {
      final DriveSync sync = DriveSync.instance;
      await sync.choose(g.accounts.first);
      final DriveFile? f = await latestBackup(g, g.accounts.first);
      if (!mounted) return;
      if (f == null) await sync.enable(g.accounts.first);
      if (!mounted) return;
      if (f != null) {
        setState(() {
          _backup = f;
          _step = _Step.restore;
          _working = false;
        });
        return;
      }
    } on DriveException catch (e) {
      _driveNote = e.message;
    }
    if (mounted) _go(_Step.brain);
  }

  Future<void> _startFresh() async {
    final DriveFile? f = _backup;
    if (f != null) await DriveSync.instance.startFreshOver(f);
    if (mounted) _go(_Step.brain);
  }

  Future<void> _restore() async {
    final DriveFile? f = _backup;
    final GoogleAccounts g = GoogleAccounts.instance;
    if (f == null || !g.hasAny) return;
    setState(() {
      _working = true;
      _error = null;
    });
    final VigilStore s = ref.read(storeProvider);
    try {
      await DriveSync.instance.restoreNow();
    } on DriveException catch (e) {
      if (mounted) {
        setState(() {
          _working = false;
          _error = e.message;
        });
      }
      return;
    }
    if (!mounted) return;
    if (s.booted) {
      context.go('/');
    } else {
      _go(_Step.brain);
    }
  }

  // ---------------------------------------------------------------- step 4: K's brain

  Future<void> _downloadBrain() async {
    setState(() => _brainError = null);
    final String? err = await ref.read(brainProvider).download();
    if (mounted && err != null) setState(() => _brainError = err);
  }

  // ---------------------------------------------------------------- step 5: permissions

  Future<void> _allow(_Perm p) async {
    final VigilStore s = ref.read(storeProvider);
    setState(() => _working = true);
    bool ok = false;
    switch (p.key) {
      case 'mic':
        ok = (await Permission.microphone.request()).isGranted;
        s.setLink('Voice uplink', ok ? 'OK' : 'DENIED');
      case 'notif':
        ok = await NotificationService.requestPermission();
        s.setLink('Notifications', ok ? 'OK' : 'DENIED');
      case 'steps':
        ok = await StepService.start(s, request: true);
        s.setLink('Step sensor', ok ? 'OK' : 'DENIED');
      case 'health':
        ok = await HealthService.connect(s);
      case 'battery':
        await openAppSettings();
        ok = true; // Android does not say whether the user changed it
    }
    if (!mounted) return;
    setState(() {
      _working = false;
      _permState[p.key] = ok ? 'OK' : 'DENIED';
    });
    if (ok) _nextPermission();
  }

  void _skipPermission(_Perm p) {
    _permState.putIfAbsent(p.key, () => 'SKIPPED');
    _nextPermission();
  }

  void _nextPermission() {
    if (_permIndex < _perms.length - 1) {
      setState(() => _permIndex++);
    } else {
      _go(_Step.voice);
    }
  }

  // ---------------------------------------------------------------- finish

  void _finish() {
    final VigilStore s = ref.read(storeProvider);
    Haptics.tap();
    SfxService.play(Sfx.boot);
    if (s.booted) {
      s.setProfile(fullName: _full.text, nickname: _nick.text);
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    } else {
      s.completeBoot(name: _full.text, call: _nick.text, wake: s.wakeMin, bed: s.bedMin, armed: s.modules);
      context.go('/');
    }
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final bool first = _step == _Step.welcome;
    return Scaffold(
      backgroundColor: c.ground,
      body: GridBackground(
        child: SafeArea(
          child: Column(children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(children: <Widget>[
                if (!first || context.canPop())
                  InkWell(
                    onTap: _back,
                    child: SizedBox(width: VigilSize.touch, height: VigilSize.touch, child: Center(child: VigilIcon(VigilIcons.chevronLeft, size: 20, color: c.textMuted))),
                  ),
                Expanded(child: Text('SETUP · STEP $_number OF 7', style: t.micro.copyWith(color: c.textFaint))),
                if (_step == _Step.google || _step == _Step.brain || _step == _Step.voice) TextButton(onPressed: _skip, child: Text('SKIP', style: t.button.copyWith(fontSize: 11, color: c.textMuted))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(children: <Widget>[
                for (int i = 1; i <= 7; i++) ...<Widget>[
                  if (i > 1) const SizedBox(width: 4),
                  Expanded(child: Container(height: 3, color: i <= _number ? c.signal : c.line)),
                ],
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: switch (_step) {
                  _Step.welcome => _welcome(context),
                  _Step.profile => _profile(context),
                  _Step.google => _google(context),
                  _Step.restore => _restoreStep(context),
                  _Step.brain => _brain(context),
                  _Step.permissions => _permissions(context),
                  _Step.voice => _voice(context),
                  _Step.ready => _ready(context),
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _skip() {
    switch (_step) {
      case _Step.google:
        _go(_Step.brain);
      case _Step.brain:
        _go(_Step.permissions);
      case _Step.voice:
        _go(_Step.ready);
      default:
        break;
    }
  }

  Widget _chip(String text) {
    final c = context.vigil;
    final t = context.vtype;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(border: Border.all(color: c.lineStrong)),
      child: Text(text.toUpperCase(), style: t.micro.copyWith(color: c.textMuted)),
    );
  }

  Widget _errorBox(String message) {
    final c = context.vigil;
    final t = context.vtype;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: c.critical), color: c.critical.withValues(alpha: 0.06)),
      child: Semantics(liveRegion: true, child: Text(message, style: t.caption.copyWith(color: c.critical))),
    );
  }

  // 1 -------------------------------------------------------------------
  Widget _welcome(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      const SizedBox(height: 12),
      Center(child: SizedBox(width: 132, height: 132, child: CornerBrackets(allCorners: true, length: 18, child: const Center(child: VigilEmblem(size: 84))))),
      const SizedBox(height: 22),
      Center(child: Text('I AM $kAssistantName', style: t.micro.copyWith(color: c.signal))),
      const SizedBox(height: 8),
      Text('Welcome to $kAssistantName.', style: t.h1, textAlign: TextAlign.center),
      const SizedBox(height: 10),
      Text('Personal ops, under your command. I run on this phone: free, offline, private.', style: t.body.copyWith(color: c.textMuted), textAlign: TextAlign.center),
      const SizedBox(height: 18),
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: <Widget>[_chip('On-device'), _chip('No server'), _chip('Private')]),
      const SizedBox(height: 32),
      VigilButton(label: 'Begin setup', size: VigilButtonSize.large, expand: true, icon: VigilIcons.arrowRight, onPressed: () => _go(_Step.profile)),
      const SizedBox(height: 8),
      Center(child: Text('Takes about 3 minutes', style: t.micro.copyWith(color: c.textFaint))),
    ]);
  }

  // 2 -------------------------------------------------------------------
  Widget _profile(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final VigilStore s = ref.watch(storeProvider);
    final bool ok = _nick.text.trim().isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('PROFILE', style: t.label.copyWith(color: c.signal)),
      const SizedBox(height: 6),
      Text('What should $kAssistantName call you?', style: t.h2),
      const SizedBox(height: 8),
      Text('Your nickname is for greetings and briefings; your full name is for formal moments. Both stay on this phone and in your own backup.', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 18),
      VigilField(controller: _nick, label: 'Nickname', hint: 'Shown as "Evening, nickname."'),
      const SizedBox(height: 12),
      VigilField(controller: _full, label: 'Full name', hint: 'Used by the Butler persona and on exports'),
      const SizedBox(height: 18),
      Text('CLOCK', style: t.micro.copyWith(color: c.textFaint)),
      const SizedBox(height: 6),
      VigilSegmented<bool>(
        segments: const <(bool, String)>[(true, '24 H · 19:42'), (false, '12 H · 7:42 PM')],
        selected: s.clock24,
        onSelected: s.setClock24,
      ),
      const SizedBox(height: 18),
      Text('CURRENCY', style: t.micro.copyWith(color: c.textFaint)),
      const SizedBox(height: 6),
      Container(
        height: VigilSize.input,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.lineStrong)),
        child: Row(children: <Widget>[
          Expanded(child: Text('₹ INR · Indian grouping ₹1,24,500', style: t.body)),
          Text('FIXED', style: t.micro.copyWith(color: c.textFaint)),
        ]),
      ),
      const SizedBox(height: 28),
      VigilButton(
        label: ok ? 'Next' : 'Add a nickname',
        size: VigilButtonSize.large,
        expand: true,
        onPressed: ok ? () => _go(_Step.google) : null,
      ),
    ]);
  }

  // 3 -------------------------------------------------------------------
  Widget _google(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    const List<String> stored = <String>['Objectives', 'Notes', 'Protocols', 'Water', 'Expenses', 'Bills', 'Budget', 'Settings', 'Chat log'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('RECOMMENDED', style: t.label.copyWith(color: c.signal)),
      const SizedBox(height: 6),
      Text('Back up to your own Google Drive', style: t.h2),
      const SizedBox(height: 8),
      Text('$kAssistantName keeps a copy in a hidden app folder in your Drive. Reinstall, or move to a new phone, and everything comes back. No server of ours sits in between.', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 16),
      Text('WHAT IS BACKED UP', style: t.micro.copyWith(color: c.textFaint)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: <Widget>[for (final String x in stored) _chip(x)]),
      const SizedBox(height: 14),
      Text('Not backed up: API keys and Google sign-in tokens. They never leave this phone. Re-enter keys after a restore.', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 8),
      Text('Stored in your own Drive, visible only to $kAssistantName.', style: t.micro.copyWith(color: c.textFaint)),
      if (_error != null) _errorBox('Google sign-in did not finish. $_error'),
      const SizedBox(height: 24),
      VigilButton(
        label: _working ? 'Working…' : (_error != null ? 'Try again' : 'Continue with Google'),
        size: VigilButtonSize.large,
        expand: true,
        onPressed: _working ? null : _continueWithGoogle,
      ),
      const SizedBox(height: 8),
      Center(child: VigilButton(label: 'Skip, keep data on this phone only', variant: VigilButtonVariant.ghost, onPressed: _working ? null : () => _go(_Step.brain))),
    ]);
  }

  Widget _restoreStep(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final DriveFile? f = _backup;
    final String account = GoogleAccounts.instance.hasAny ? GoogleAccounts.instance.accounts.first.email : '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('SIGNED IN · $account'.toUpperCase(), style: t.micro.copyWith(color: c.signal)),
      const SizedBox(height: 6),
      Text('Restore your data?', style: t.h2),
      const SizedBox(height: 8),
      Text('We found a $kAssistantName backup in this account\'s Drive. Bring it onto this phone, or start with a clean slate.', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 16),
      VigilCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('BACKUP FOUND', style: t.micro.copyWith(color: c.textFaint)),
          const SizedBox(height: 6),
          Text(f == null ? '' : '${Fmt.dayStamp(f.modified)} · ${Fmt.time(f.modified)}', style: t.title),
          const SizedBox(height: 6),
          Text('Includes your objectives, notes, protocols, water, expenses, bills, budget, settings and the $kAssistantName chat log. API keys are never in a backup.', style: t.caption.copyWith(color: c.textMuted)),
        ]),
      ),
      const SizedBox(height: 10),
      Text('Start fresh replaces this backup with the data on this phone at the first sync.', style: t.micro.copyWith(color: c.textFaint)),
      if (_error != null) _errorBox(_error!),
      const SizedBox(height: 24),
      Row(children: <Widget>[
        Expanded(child: VigilButton(label: 'Start fresh', variant: VigilButtonVariant.secondary, size: VigilButtonSize.large, expand: true, onPressed: _working ? null : _startFresh)),
        const SizedBox(width: 12),
        Expanded(child: VigilButton(label: _working ? 'Restoring…' : 'Restore', size: VigilButtonSize.large, expand: true, onPressed: _working ? null : _restore)),
      ]),
    ]);
  }

  // 4 -------------------------------------------------------------------
  Widget _brain(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final LocalBrain brain = ref.watch(brainProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('$kAssistantName\'S BRAIN', style: t.label.copyWith(color: c.signal)),
      const SizedBox(height: 6),
      Text('Download $kAssistantName\'s brain', style: t.h2),
      const SizedBox(height: 8),
      Text('A one-time ${brain.variant.sizeText} download. After this, $kAssistantName thinks on this phone: free, offline, private.', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 16),
      AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[brain, brain.progress]),
        builder: (BuildContext ctx, Widget? _) {
          final BrainStatus st = brain.status;
          return VigilCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('MINICPM5-1B · ${brain.variant.label}', style: t.micro.copyWith(color: c.textFaint)),
              const SizedBox(height: 8),
              if (st == BrainStatus.downloading) ...<Widget>[
                Text('Downloading ${(brain.progress.value * 100).round()} %', style: t.title),
                const SizedBox(height: 10),
                LinearProgressIndicator(value: brain.progress.value, minHeight: 4),
                const SizedBox(height: 10),
                Text('Keep Wi-Fi on. If it is interrupted, it resumes where it stopped.', style: t.caption.copyWith(color: c.textMuted)),
                const SizedBox(height: 12),
                VigilButton(label: 'Pause', variant: VigilButtonVariant.secondary, onPressed: brain.cancelDownload),
              ] else if (st == BrainStatus.notInstalled) ...<Widget>[
                Text('On Wi-Fi advised', style: t.title),
                const SizedBox(height: 12),
                VigilButton(label: _brainError != null ? 'Retry download' : 'Download', onPressed: _downloadBrain),
              ] else ...<Widget>[
                Text('Installed. Ready when you ask.', style: t.title.copyWith(color: c.signal)),
              ],
            ]),
          );
        },
      ),
      if (_brainError != null) _errorBox('The download stopped: $_brainError. Check the connection and retry; it resumes where it stopped.'),
      const SizedBox(height: 14),
      Text('$kAssistantName still answers instant commands and questions about your data without it.', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 24),
      VigilButton(label: 'Next', size: VigilButtonSize.large, expand: true, onPressed: () => _go(_Step.permissions)),
    ]);
  }

  // 5 -------------------------------------------------------------------
  Widget _permissions(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final _Perm p = _perms[_permIndex];
    final String? st = _permState[p.key];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('PERMISSION ${_permIndex + 1} OF ${_perms.length}${p.optional ? ' · OPTIONAL' : ''}', style: t.label.copyWith(color: c.signal)),
      const SizedBox(height: 6),
      Text(p.title, style: t.h2),
      const SizedBox(height: 8),
      Text(p.reason, style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 16),
      RowList(children: <Widget>[
        for (int i = 0; i < _perms.length; i++)
          SizedBox(
            height: 46,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: <Widget>[
                Expanded(child: Text(_perms[i].title.toUpperCase(), style: t.button.copyWith(fontWeight: FontWeight.w400, color: i == _permIndex ? c.text : c.textMuted))),
                Text(
                  switch (_permState[_perms[i].key]) { 'OK' => 'ON', 'DENIED' => 'DENIED', 'SKIPPED' => 'LATER', _ => i == _permIndex ? 'NOW' : '' },
                  style: t.meta.copyWith(color: _permState[_perms[i].key] == 'OK' ? c.signal : c.textFaint),
                ),
              ]),
            ),
          ),
      ]),
      if (st == 'DENIED') _errorBox('${p.title} is off. You can turn it on in Android settings, or carry on without it.'),
      const SizedBox(height: 24),
      VigilButton(
        label: _working ? 'Waiting…' : (st == 'DENIED' ? 'Try again' : 'Allow ${p.title.toLowerCase()}'),
        size: VigilButtonSize.large,
        expand: true,
        onPressed: _working ? null : () => _allow(p),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
        if (st == 'DENIED') VigilButton(label: 'Open settings', variant: VigilButtonVariant.ghost, onPressed: openAppSettings),
        VigilButton(label: st == 'DENIED' ? 'Continue' : 'Not now', variant: VigilButtonVariant.ghost, onPressed: _working ? null : () => _skipPermission(p)),
      ]),
    ]);
  }

  // 6 -------------------------------------------------------------------
  Widget _voice(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final VigilStore s = ref.watch(storeProvider);
    final String sample = switch (s.persona) {
      Persona.tactical => 'Water logged. 2,000 of 3,000. Keep moving.',
      Persona.butler => 'Two litres so far, which is rather good. Shall we make it three?',
      Persona.quiet => '2.0 / 3.0 L',
    };
    final bool sfxOn = s.toggles['sfx'] ?? true;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('VOICE & SOUND', style: t.label.copyWith(color: c.signal)),
      const SizedBox(height: 6),
      Text('How should $kAssistantName sound?', style: t.h2),
      const SizedBox(height: 18),
      Text('PERSONA', style: t.micro.copyWith(color: c.textFaint)),
      const SizedBox(height: 6),
      VigilSegmented<Persona>(segments: const <(Persona, String)>[(Persona.tactical, 'TACTICAL'), (Persona.butler, 'BUTLER'), (Persona.quiet, 'QUIET')], selected: s.persona, onSelected: s.setPersona),
      const SizedBox(height: 10),
      Text('"$sample"', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 10),
      VigilButton(label: 'Test $kAssistantName\'s voice', variant: VigilButtonVariant.secondary, onPressed: () => VoiceService.instance.speak(sample)),
      const SizedBox(height: 18),
      RowList(children: <Widget>[
        SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.only(left: 14, right: 8),
            child: Row(children: <Widget>[
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text('Spoken replies', style: t.rowTitle), Text('READS ANSWERS ALOUD', style: t.micro.copyWith(color: c.textFaint), maxLines: 1, overflow: TextOverflow.ellipsis)])),
              VigilSwitch(value: s.toggles['spoken'] ?? false, onChanged: (bool v) => s.setToggle('spoken', v), semanticLabel: 'Spoken replies'),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      RowList(children: <Widget>[
        SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.only(left: 14, right: 8),
            child: Row(children: <Widget>[
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text('Haptics', style: t.rowTitle), Text('TICKS AND TAPS THAT MIRROR THE SOUNDS', style: t.micro.copyWith(color: c.textFaint), maxLines: 1, overflow: TextOverflow.ellipsis)])),
              VigilSwitch(value: s.toggles['haptics'] ?? true, onChanged: (bool v) => s.setToggle('haptics', v), semanticLabel: 'Haptics'),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 18),
      Text('SOUND EFFECTS', style: t.micro.copyWith(color: c.textFaint)),
      const SizedBox(height: 6),
      VigilSegmented<int>(
        segments: const <(int, String)>[(-1, 'OFF'), (0, 'LOW'), (1, 'MEDIUM'), (2, 'HIGH')],
        selected: sfxOn ? s.sfxLevel : -1,
        onSelected: (int v) {
          if (v < 0) {
            s.setToggle('sfx', false);
          } else {
            s.setToggle('sfx', true);
            s.setSfxLevel(v);
          }
          SfxService.configure(on: v >= 0, level: v < 0 ? s.sfxLevel : v);
          if (v >= 0) SfxService.play(Sfx.tick);
        },
      ),
      const SizedBox(height: 6),
      Text('Effects follow media volume; alerts follow notification volume.', style: t.micro.copyWith(color: c.textFaint)),
      const SizedBox(height: 24),
      VigilButton(label: 'Next', size: VigilButtonSize.large, expand: true, onPressed: () => _go(_Step.ready)),
    ]);
  }

  // 7 -------------------------------------------------------------------
  Widget _ready(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final VigilStore s = ref.watch(storeProvider);
    final LocalBrain brain = ref.watch(brainProvider);
    final GoogleAccounts g = GoogleAccounts.instance;
    String perm(String key) => switch (_permState[key]) { 'OK' => 'ON', _ => 'SET UP LATER' };
    final List<(String, String)> rows = <(String, String)>[
      ('Name & ${s.clock24 ? '24 h' : '12 h'} clock', 'ON'),
      (g.hasAny ? 'Drive backup · ${g.accounts.first.label.toLowerCase()}' : 'Drive backup', g.hasAny ? 'ON' : 'SET UP LATER'),
      ('$kAssistantName\'s brain', brain.status == BrainStatus.downloading ? '${(brain.progress.value * 100).round()} %' : (brain.status == BrainStatus.notInstalled ? 'SET UP LATER' : 'ON')),
      ('Microphone', perm('mic')),
      ('Notifications', perm('notif')),
      ('Steps & activity', perm('steps')),
      ('Health Connect', perm('health')),
      ('Background & battery', perm('battery')),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('READY', style: t.label.copyWith(color: c.signal)),
      const SizedBox(height: 6),
      Text(_nick.text.trim().isEmpty ? '${Fmt.greeting(DateTime.now())}.' : '${Fmt.greeting(DateTime.now())}, ${_nick.text.trim()}.', style: t.h1),
      const SizedBox(height: 14),
      RowList(children: <Widget>[
        for (final (String, String) r in rows)
          SizedBox(
            height: 46,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: <Widget>[
                Expanded(child: Text(r.$1.toUpperCase(), style: t.button.copyWith(fontWeight: FontWeight.w400, color: c.text))),
                Text(r.$2, style: t.meta.copyWith(color: r.$2 == 'SET UP LATER' ? c.textFaint : c.signal)),
              ]),
            ),
          ),
      ]),
      if (_driveNote != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_driveNote!, style: t.caption.copyWith(color: c.textMuted))),
      const SizedBox(height: 22),
      VigilButton(label: 'Open $kAssistantName', size: VigilButtonSize.large, expand: true, icon: VigilIcons.arrowRight, onPressed: _finish),
      const SizedBox(height: 10),
      Center(child: Text('Re-open this guide any time: Loadout › Run $kAssistantName setup again.', style: t.micro.copyWith(color: c.textFaint), textAlign: TextAlign.center)),
    ]);
  }
}
