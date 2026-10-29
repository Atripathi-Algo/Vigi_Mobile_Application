import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/brand.dart';
import '../app/common.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/assistant.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/drive_backup.dart';
import '../services/drive_sync.dart';
import '../services/google_accounts.dart';
import '../services/haptics.dart';
import '../services/notifications.dart';
import '../services/sfx.dart';
import '../vigil/vigil.dart';
import 'rationale_sheet.dart';

/// First-run setup guide, four steps: your name, what K should help with, one guided command, done. Everything
/// else (microphone, notifications, Health Connect, the AI model) is asked for the first time a feature needs it, with a
/// short "Before Android asks" sheet. Restoring from Google Drive is a side path from step 1.
///
/// Shown on the first launch after a fresh install, and again from Settings, "Run K setup again" (then it only
/// changes the name and the modules, never wipes anything).
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

enum _Step { welcome, google, restore, modules, tryit, ready }

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final TextEditingController _nick = TextEditingController();
  final TextEditingController _cmd = TextEditingController();
  _Step _step = _Step.welcome;
  bool _working = false;
  String? _error;
  DriveFile? _backup;
  String? _driveNote;
  late Set<String> _modules;
  ChatMsg? _result;
  bool _notifAsked = false;
  bool _notifOn = false;

  static const List<String> _examples = <String>['remind me to call Mom at 6 pm', 'log 250 ml water', 'spent 200 on lunch'];

  @override
  void initState() {
    super.initState();
    final VigilStore s = ref.read(storeProvider);
    _nick.text = s.callsign;
    _modules = <String>{...s.modules};
    _nick.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nick.dispose();
    _cmd.dispose();
    super.dispose();
  }

  int get _number => switch (_step) {
        _Step.welcome || _Step.google || _Step.restore => 1,
        _Step.modules => 2,
        _Step.tryit => 3,
        _Step.ready => 4,
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
      case _Step.google:
        _go(_Step.welcome);
      case _Step.restore:
        _go(_Step.google);
      case _Step.modules:
        _go(_Step.welcome);
      case _Step.tryit:
        _go(_Step.modules);
      case _Step.ready:
        _go(_Step.tryit);
    }
  }

  // ---------------------------------------------------------------- Google and Drive (side path from step 1)

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
    if (mounted) _go(_Step.modules);
  }

  Future<void> _startFresh() async {
    final DriveFile? f = _backup;
    if (f != null) await DriveSync.instance.startFreshOver(f);
    if (mounted) _go(_Step.modules);
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
      _nick.text = s.callsign;
      _modules = <String>{...s.modules};
      _go(_Step.modules);
    }
  }

  // ---------------------------------------------------------------- step 3: one guided command

  Future<void> _tryCommand(String text) async {
    final String q = text.trim();
    if (q.isEmpty || _working) return;
    setState(() => _working = true);
    final VigilStore s = ref.read(storeProvider);
    final ChatMsg m = await Assistant(s).reply(q);
    if (!mounted) return;
    Haptics.strike();
    SfxService.play(m.diff != null ? Sfx.clear : Sfx.deny);
    setState(() {
      _result = m;
      _working = false;
    });
  }

  Future<void> _askNotifications() async {
    final bool ok = await showRationaleSheet(
      context,
      title: 'Let K nudge you',
      why: 'K can remind you when a task is due, send a short morning briefing and warn you when a habit streak is at risk.',
      note: 'Only on this phone. Nothing is sent anywhere.',
      icon: VigilIcons.alert,
      allowLabel: 'Allow notifications',
    );
    if (!ok || !mounted) {
      if (mounted) setState(() => _notifAsked = true);
      return;
    }
    final bool granted = await NotificationService.requestPermission();
    ref.read(storeProvider).setLink('Notifications', granted ? 'OK' : 'DENIED');
    if (mounted) {
      setState(() {
        _notifAsked = true;
        _notifOn = granted;
      });
    }
  }

  // ---------------------------------------------------------------- finish

  void _finish() {
    final VigilStore s = ref.read(storeProvider);
    Haptics.tap();
    SfxService.play(Sfx.boot);
    if (s.booted) {
      s.setProfile(fullName: s.fullName, nickname: _nick.text);
      s.setModules(_modules);
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    } else {
      s.completeBoot(name: s.fullName, call: _nick.text, wake: s.wakeMin, bed: s.bedMin, armed: _modules);
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
      body: SafeArea(
        child: Column(children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: <Widget>[
              if (!first || context.canPop())
                InkWell(
                  onTap: _back,
                  customBorder: const CircleBorder(),
                  child: SizedBox(width: VigilSize.touch, height: VigilSize.touch, child: Center(child: VigilIcon(VigilIcons.chevronLeft, size: 20, color: c.textMuted))),
                )
              else
                const SizedBox(width: 8),
              Expanded(child: Text('Step $_number of 4', style: t.label.copyWith(color: c.textMuted))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(children: <Widget>[
              for (int i = 1; i <= 4; i++) ...<Widget>[
                if (i > 1) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(gradient: i <= _number ? KGradients.primary : null, color: i <= _number ? null : c.surfaceHigh, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ],
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
              child: switch (_step) {
                _Step.welcome => _welcome(context),
                _Step.google => _google(context),
                _Step.restore => _restoreStep(context),
                _Step.modules => _modulesStep(context),
                _Step.tryit => _tryStep(context),
                _Step.ready => _ready(context),
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _errorBox(String message) {
    final c = context.vigil;
    final t = context.vtype;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: c.critical), color: c.critical.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(KRadius.field)),
      child: Semantics(liveRegion: true, child: Text(message, style: t.caption.copyWith(color: c.critical))),
    );
  }

  Widget _tag(String text) {
    final c = context.vigil;
    final t = context.vtype;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(border: Border.all(color: c.lineStrong), borderRadius: BorderRadius.circular(KRadius.pill), color: c.surface),
      child: Text(text, style: t.meta.copyWith(color: c.textMuted)),
    );
  }

  // 1 -------------------------------------------------------------------
  Widget _welcome(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final bool ok = _nick.text.trim().isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      const SizedBox(height: 8),
      const Center(child: KBadge(size: 84)),
      const SizedBox(height: 20),
      Text('Welcome to $kAssistantName.', style: t.h1, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text('Your day, handled. I run on this phone: free, offline, private.', style: t.body.copyWith(color: c.textMuted), textAlign: TextAlign.center),
      const SizedBox(height: 14),
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: <Widget>[_tag('On this phone'), _tag('No account needed'), _tag('Private')]),
      const SizedBox(height: 28),
      VigilField(controller: _nick, label: 'What should I call you?', hint: 'A nickname is fine', autofocus: false, onSubmitted: (_) => ok ? _go(_Step.modules) : null),
      const SizedBox(height: 18),
      VigilButton(
        label: ok ? 'Continue' : 'Add a name',
        size: VigilButtonSize.large,
        expand: true,
        onPressed: ok ? () => _go(_Step.modules) : null,
      ),
      const SizedBox(height: 6),
      Center(child: VigilButton(label: 'Restore from Google Drive', variant: VigilButtonVariant.ghost, onPressed: () => _go(_Step.google))),
    ]);
  }

  Widget _google(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    const List<String> stored = <String>['Tasks', 'Notes', 'Habits', 'Water', 'Expenses', 'Bills', 'Budget', 'Garage', 'Settings', 'Chat log'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('Optional', style: t.label.copyWith(color: c.violet)),
      const SizedBox(height: 4),
      Text('Back up to your own Google Drive', style: t.h2),
      const SizedBox(height: 8),
      Text('$kAssistantName keeps a copy in a hidden app folder in your Drive. Reinstall, or move to a new phone, and everything comes back. No server of ours sits in between. If a backup already exists, you can restore it.', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 16),
      Text('What is backed up', style: t.label.copyWith(color: c.textMuted)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: <Widget>[for (final String x in stored) _tag(x)]),
      const SizedBox(height: 14),
      Text('Not backed up: API keys and Google sign-in tokens. They never leave this phone. Re-enter keys after a restore.', style: t.caption.copyWith(color: c.textMuted)),
      if (_error != null) _errorBox('Google sign-in did not finish. $_error'),
      const SizedBox(height: 24),
      VigilButton(
        label: _working ? 'Working…' : (_error != null ? 'Try again' : 'Continue with Google'),
        size: VigilButtonSize.large,
        expand: true,
        onPressed: _working ? null : _continueWithGoogle,
      ),
      const SizedBox(height: 6),
      Center(child: VigilButton(label: 'Not now, keep data on this phone only', variant: VigilButtonVariant.ghost, onPressed: _working ? null : () => _go(_Step.welcome))),
    ]);
  }

  Widget _restoreStep(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final DriveFile? f = _backup;
    final String account = GoogleAccounts.instance.hasAny ? GoogleAccounts.instance.accounts.first.email : '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('Signed in as $account', style: t.label.copyWith(color: c.violet)),
      const SizedBox(height: 4),
      Text('Restore your data?', style: t.h2),
      const SizedBox(height: 8),
      Text('We found a $kAssistantName backup in this account\'s Drive. Bring it onto this phone, or start with a clean slate.', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 16),
      VigilCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('Backup found', style: t.label.copyWith(color: c.textMuted)),
          const SizedBox(height: 6),
          Text(f == null ? '' : '${Fmt.dayStamp(f.modified)} · ${Fmt.time(f.modified)}', style: t.title),
          const SizedBox(height: 6),
          Text('Includes your tasks, notes, habits, water, expenses, bills, budget, garage, settings and the $kAssistantName chat log. API keys are never in a backup.', style: t.caption.copyWith(color: c.textMuted)),
        ]),
      ),
      const SizedBox(height: 10),
      Text('Start fresh replaces this backup with the data on this phone at the first sync.', style: t.caption.copyWith(color: c.textFaint)),
      if (_error != null) _errorBox(_error!),
      const SizedBox(height: 24),
      Row(children: <Widget>[
        Expanded(child: VigilButton(label: 'Start fresh', variant: VigilButtonVariant.secondary, size: VigilButtonSize.large, expand: true, onPressed: _working ? null : _startFresh)),
        const SizedBox(width: 12),
        Expanded(child: VigilButton(label: _working ? 'Restoring…' : 'Restore', size: VigilButtonSize.large, expand: true, onPressed: _working ? null : _restore)),
      ]),
    ]);
  }

  // 2 -------------------------------------------------------------------
  Widget _modulesStep(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    Widget row(KTile tile, VigilIcons icon, String title, String sub, {String? module, bool locked = false}) {
      final bool on = locked || _modules.contains(module);
      return SizedBox(
        height: 68,
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 6),
          child: Row(children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(gradient: tile.gradient, borderRadius: BorderRadius.circular(KRadius.iconTile)),
              child: Center(child: VigilIcon(icon, size: 20, color: Colors.white)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text(title, style: t.rowTitle), Text(sub, style: t.caption.copyWith(color: c.textFaint), maxLines: 1, overflow: TextOverflow.ellipsis)])),
            VigilSwitch(
              value: on,
              semanticLabel: title,
              onChanged: locked ? null : (bool v) => setState(() => v ? _modules.add(module!) : _modules.remove(module)),
            ),
          ]),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('What should $kAssistantName help with?', style: t.h2),
      const SizedBox(height: 8),
      Text('Tasks, habits and money are always here. Turn off what you do not need; you can bring it back any time in Settings.', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 18),
      RowList(children: <Widget>[
        row(KTile.blue, VigilIcons.ops, 'Tasks and calendar', 'Always on', locked: true),
        row(KTile.cyan, VigilIcons.protocols, 'Habits', 'Always on', locked: true),
        row(KTile.orange, VigilIcons.vault, 'Money', 'Budget and spending. Always on', locked: true),
        row(KTile.green, VigilIcons.sleep, 'Health and sleep', 'Steps, sleep, weight, screen time', module: kModuleHealth),
        row(KTile.violet, VigilIcons.deepOps, 'Bike garage', 'Fuel, mileage, service reminders', module: kModuleGarage),
      ]),
      const SizedBox(height: 26),
      VigilButton(label: 'Continue', size: VigilButtonSize.large, expand: true, onPressed: () => _go(_Step.tryit)),
    ]);
  }

  // 3 -------------------------------------------------------------------
  Widget _tryStep(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final ChatMsg? m = _result;
    final bool done = m?.diff != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('Try it', style: t.label.copyWith(color: c.violet)),
      const SizedBox(height: 4),
      Text('Tell $kAssistantName something', style: t.h2),
      const SizedBox(height: 8),
      Text('Type a command and watch it happen. Every change comes with Undo.', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 0, children: <Widget>[
        for (final String e in _examples) VigilFilterChip(label: e, selected: _cmd.text == e, onTap: () => setState(() => _cmd.text = e)),
      ]),
      const SizedBox(height: 8),
      VigilField(controller: _cmd, label: 'Your command', hint: _examples.first, onChanged: (_) => setState(() {}), onSubmitted: _tryCommand),
      const SizedBox(height: 14),
      VigilButton(label: _working ? 'Working…' : 'Send', variant: done ? VigilButtonVariant.secondary : VigilButtonVariant.primary, onPressed: _working || _cmd.text.trim().isEmpty ? null : () => _tryCommand(_cmd.text)),
      if (m != null) ...<Widget>[
        const SizedBox(height: 16),
        VigilCard(
          brackets: done,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              Text(kAssistantName, style: t.label.copyWith(color: m.alert ? c.critical : c.violet)),
              const SizedBox(width: 8),
              if (m.source == ReplySource.instant) Text('Done instantly · ${m.ms ?? 0} ms', style: t.meta.copyWith(color: c.success)),
            ]),
            const SizedBox(height: 6),
            Text(m.text, style: t.body),
            if (m.diff != null) ...<Widget>[
              const SizedBox(height: 10),
              for (final (String, String) r in m.diff!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    SizedBox(width: 84, child: Text(r.$1, style: t.label.copyWith(color: c.violet))),
                    Expanded(child: Text(r.$2, style: t.meta.copyWith(color: c.text))),
                  ]),
                ),
              if (m.undoable)
                Align(
                  alignment: Alignment.centerRight,
                  child: VigilButton(
                    label: 'Undo',
                    size: VigilButtonSize.small,
                    variant: VigilButtonVariant.secondary,
                    onPressed: () {
                      m.onUndo?.call();
                      setState(() => _result = null);
                    },
                  ),
                ),
            ] else
              Padding(padding: const EdgeInsets.only(top: 6), child: Text('That did not change anything. Try one of the examples above.', style: t.caption.copyWith(color: c.textFaint))),
          ]),
        ),
        if (done) ...<Widget>[
          const SizedBox(height: 12),
          if (!_notifAsked)
            VigilCard(
              onTap: _askNotifications,
              child: Row(children: <Widget>[
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text('Get a nudge when it is due?', style: t.rowTitle), Text('Optional. Notifications stay on this phone.', style: t.caption.copyWith(color: c.textFaint))])),
                VigilIcon(VigilIcons.chevronRight, size: 18, color: c.textMuted),
              ]),
            )
          else
            Text(_notifOn ? 'Notifications are on.' : 'Notifications are off. You can turn them on in Settings.', style: t.caption.copyWith(color: c.textMuted)),
        ],
      ],
      const SizedBox(height: 24),
      VigilButton(label: done ? 'Continue' : 'Skip for now', size: VigilButtonSize.large, variant: done ? VigilButtonVariant.primary : VigilButtonVariant.secondary, expand: true, onPressed: () => _go(_Step.ready)),
    ]);
  }

  // 4 -------------------------------------------------------------------
  Widget _ready(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final GoogleAccounts g = GoogleAccounts.instance;
    final List<(String, String, bool)> rows = <(String, String, bool)>[
      ('Name', _nick.text.trim(), true),
      ('Health and sleep', _modules.contains(kModuleHealth) ? 'On' : 'Off', _modules.contains(kModuleHealth)),
      ('Bike garage', _modules.contains(kModuleGarage) ? 'On' : 'Off', _modules.contains(kModuleGarage)),
      ('Drive backup', g.hasAny ? g.accounts.first.label : 'Later, in Settings', g.hasAny),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      const SizedBox(height: 8),
      const Center(child: KBadge(size: 64)),
      const SizedBox(height: 16),
      Text(_nick.text.trim().isEmpty ? '${Fmt.greeting(DateTime.now())}.' : '${Fmt.greeting(DateTime.now())}, ${_nick.text.trim()}.', style: t.h1, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text('You are set. $kAssistantName will ask for the microphone, Health Connect and its AI model only when you first use them.', style: t.body.copyWith(color: c.textMuted), textAlign: TextAlign.center),
      const SizedBox(height: 18),
      RowList(children: <Widget>[
        for (final (String, String, bool) r in rows)
          SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: <Widget>[
                Expanded(child: Text(r.$1, style: t.rowTitle)),
                Text(r.$2, style: t.meta.copyWith(color: r.$3 ? c.success : c.textFaint)),
              ]),
            ),
          ),
      ]),
      if (_driveNote != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_driveNote!, style: t.caption.copyWith(color: c.textMuted))),
      const SizedBox(height: 22),
      VigilButton(label: 'Open $kAssistantName', size: VigilButtonSize.large, expand: true, icon: VigilIcons.arrowRight, onPressed: _finish),
      const SizedBox(height: 10),
      Center(child: Text('Run this guide again any time: Settings, Run $kAssistantName setup again.', style: t.caption.copyWith(color: c.textFaint), textAlign: TextAlign.center)),
    ]);
  }
}
