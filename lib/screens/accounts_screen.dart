import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/common.dart';
import '../app/providers.dart';
import '../services/calendar_sync.dart';
import '../services/google_accounts.dart';
import '../vigil/vigil.dart';

/// Link up to two Google accounts. Their calendars merge into the Timeline, and events made in VIGIL
/// can be added to either one.
class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  final Map<int, String> _msg = <int, String>{};
  int? _busySlot;
  bool _syncing = false;
  String? _syncMsg;
  bool? _available;
  String? _sha1;

  @override
  void initState() {
    super.initState();
    final GoogleAccounts g = GoogleAccounts.instance;
    g.isAvailable().then((bool v) => mounted ? setState(() => _available = v) : null);
    g.signingSha1().then((String? v) => mounted ? setState(() => _sha1 = v) : null);
  }

  Future<void> _link(int slot) async {
    setState(() {
      _busySlot = slot;
      _msg.remove(slot);
    });
    final GoogleAccounts g = ref.read(googleAccountsProvider);
    final String? err = await g.link(slot);
    if (!mounted) return;
    setState(() {
      _busySlot = null;
      if (err != null) _msg[slot] = err;
    });
    if (err == null) await _syncNow();
  }

  Future<void> _unlink(int slot) async {
    final GoogleAccounts g = ref.read(googleAccountsProvider);
    final GoogleAccount? a = g.bySlot(slot);
    if (a == null) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('UNLINK ACCOUNT?'),
        content: Text('${a.email} is removed from K and its calendar access is revoked. Events already in Google stay where they are.'),
        actions: <Widget>[
          VigilButton(label: 'Keep', variant: VigilButtonVariant.secondary, onPressed: () => Navigator.pop(ctx, false)),
          VigilButton(label: 'Unlink', variant: VigilButtonVariant.critical, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok != true) return;
    await g.unlink(slot);
    if (!mounted) return;
    setState(() => _msg.remove(slot));
    await _syncNow();
  }

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _syncMsg = null;
    });
    final CalendarSyncResult r = await syncCalendars(ref.read(storeProvider));
    if (mounted) {
      setState(() {
        _syncing = false;
        _syncMsg = r.summary;
      });
    }
  }

  Future<void> _copy(String label, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showVigilSnack(context, '$label copied');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final GoogleAccounts g = ref.watch(googleAccountsProvider);
    return VigilScaffold(
      title: 'Google accounts',
      subtitle: 'UP TO TWO · CALENDAR',
      leading: VigilIconButton(icon: VigilIcons.chevronLeft, semanticLabel: 'Back', onPressed: () => context.pop()),
      body: ListView(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 28),
        children: <Widget>[
          VigilCard(
            child: Text(
              'Both calendars merge into the Timeline, and a meeting that is in both shows once. Events you make in K can be added to either account. '
              'K asks Google only for calendar events. No password and no key are stored: your phone holds the approval.',
              style: t.caption.copyWith(color: c.textMuted),
            ),
          ),
          const SizedBox(height: 14),
          if (_available == false) ...<Widget>[
            VigilCard(
              borderColor: c.critical,
              child: Text('Google Play services is not available on this phone, so Google accounts cannot be linked here.', style: t.caption.copyWith(color: c.critical)),
            ),
            const SizedBox(height: 14),
          ],
          for (int slot = 0; slot < GoogleAccounts.slots; slot++) ...<Widget>[_slotCard(context, g, slot), const SizedBox(height: 14)],
          if (g.hasAny)
            Align(
              alignment: Alignment.centerLeft,
              child: VigilButton(label: _syncing ? 'Syncing…' : 'Sync now', variant: VigilButtonVariant.accent, onPressed: _syncing ? null : _syncNow),
            ),
          if (_syncMsg != null) ...<Widget>[
            const SizedBox(height: 8),
            Semantics(liveRegion: true, child: Text(_syncMsg!, style: t.meta.copyWith(color: c.textMuted, fontSize: 12))),
          ],
          const SizedBox(height: 18),
          _setupCard(context),
        ],
      ),
    );
  }

  Widget _slotCard(BuildContext context, GoogleAccounts g, int slot) {
    final c = context.vigil;
    final t = context.vtype;
    final GoogleAccount? a = g.bySlot(slot);
    final bool busy = _busySlot == slot;
    final String? note = a == null ? null : g.noteOf(a);
    final String? msg = _msg[slot];
    return VigilCard(
      padding: const EdgeInsets.all(16),
      borderColor: note != null ? c.critical : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text(GoogleAccounts.defaultLabels[slot], style: t.label.copyWith(color: c.text))),
          StatusChip(a == null ? 'NOT LINKED' : (note == null ? 'LINKED' : 'ATTENTION'), on: a != null && note == null, color: note != null ? c.critical : null),
        ]),
        const SizedBox(height: 8),
        if (a != null) ...<Widget>[
          Text(a.email, style: t.body),
          if (note != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(note, style: t.caption.copyWith(color: c.critical)),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            VigilButton(label: busy ? 'Working…' : (note != null ? 'Approve again' : 'Link again'), variant: VigilButtonVariant.secondary, onPressed: busy ? null : () => _link(slot)),
            VigilButton(label: 'Unlink', variant: VigilButtonVariant.secondary, onPressed: busy ? null : () => _unlink(slot)),
          ]),
        ] else ...<Widget>[
          Text('Choose a Google account on this phone and approve calendar access.', style: t.caption.copyWith(color: c.textMuted)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: VigilButton(label: busy ? 'Working…' : 'Link account', onPressed: busy || _available == false ? null : () => _link(slot)),
          ),
        ],
        if (msg != null) ...<Widget>[
          const SizedBox(height: 10),
          Semantics(liveRegion: true, child: Text(msg, style: t.meta.copyWith(color: c.critical, fontSize: 12))),
        ],
      ]),
    );
  }

  Widget _setupCard(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    Widget step(String n, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            SizedBox(width: 22, child: Text(n, style: t.label.copyWith(color: c.signal))),
            Expanded(child: Text(text, style: t.caption.copyWith(color: c.textMuted))),
          ]),
        );
    return VigilCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text('ONE-TIME SETUP · FREE', style: t.label.copyWith(color: c.text)),
        const SizedBox(height: 8),
        Text('Google only lets an app use calendars once its owner registers it. This takes about five minutes and costs nothing.', style: t.caption.copyWith(color: c.textMuted)),
        const SizedBox(height: 12),
        step('1', 'Open console.cloud.google.com and create a project.'),
        step('2', 'APIs & Services, Library: enable Google Calendar API, and Google Drive API if you want backup.'),
        step('3', 'OAuth consent screen: user type External. Add both Gmail addresses under Test users.'),
        step('4', 'Credentials, Create credentials, OAuth client ID, type Android. Use the package name and SHA-1 below.'),
        step('5', 'Come back here and link each account.'),
        const SizedBox(height: 4),
        Text('PACKAGE NAME', style: t.micro.copyWith(color: c.textFaint, fontSize: 10)),
        const SizedBox(height: 4),
        Row(children: <Widget>[
          Expanded(child: SelectableText(kAppPackage, style: t.meta.copyWith(color: c.text))),
          VigilButton(label: 'Copy', variant: VigilButtonVariant.secondary, onPressed: () => _copy('Package name', kAppPackage)),
        ]),
        const SizedBox(height: 10),
        Text('SHA-1 OF THIS APP', style: t.micro.copyWith(color: c.textFaint, fontSize: 10)),
        const SizedBox(height: 4),
        Row(children: <Widget>[
          Expanded(child: SelectableText(_sha1 ?? 'Not available', style: t.meta.copyWith(color: c.text, fontSize: 11))),
          if (_sha1 != null) VigilButton(label: 'Copy', variant: VigilButtonVariant.secondary, onPressed: () => _copy('SHA-1', _sha1!)),
        ]),
        const SizedBox(height: 12),
        Text(
          'While the consent screen is in Testing, Google asks you to approve again every 7 days. To stop that, set the publishing status to In production. '
          'Google then shows an "unverified app" screen once, which is fine for your own use (limit 100 users). A different build or signing key has a different SHA-1: add it to the same client.',
          style: t.caption.copyWith(color: c.textFaint),
        ),
      ]),
    );
  }
}
