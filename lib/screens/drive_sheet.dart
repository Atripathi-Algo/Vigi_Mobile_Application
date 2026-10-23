import 'package:flutter/material.dart';

import '../app/fmt.dart';
import '../data/store.dart';
import '../services/drive_backup.dart';
import '../services/google_accounts.dart';
import '../vigil/vigil.dart';

/// Back up to, or restore from, the private app folder on a linked Google account's Drive.
Future<void> showDriveSheet(BuildContext context, VigilStore store) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (BuildContext ctx) => _DriveSheet(store: store),
    );

class _DriveSheet extends StatefulWidget {
  const _DriveSheet({required this.store});

  final VigilStore store;

  @override
  State<_DriveSheet> createState() => _DriveSheetState();
}

class _DriveSheetState extends State<_DriveSheet> {
  String? _busy; // email of the account being worked on
  String? _message;
  bool _isError = false;

  String _when(DateTime d) => '${Fmt.dayStamp(d)} ${Fmt.time(d)}';

  Future<void> _run(GoogleAccount a, Future<String> Function() job) async {
    setState(() {
      _busy = a.email;
      _message = null;
    });
    String msg;
    bool err = false;
    try {
      msg = await job();
    } on DriveException catch (e) {
      msg = e.message;
      err = true;
    }
    if (!mounted) return;
    setState(() {
      _busy = null;
      _message = msg;
      _isError = err;
    });
  }

  Future<void> _backup(GoogleAccount a) => _run(a, () async {
        final DriveFile f = await backupToDrive(widget.store, GoogleAccounts.instance, a);
        return 'Backed up to ${a.label} Drive at ${_when(f.modified)}.';
      });

  Future<void> _restore(GoogleAccount a) => _run(a, () async {
        final DriveFile? f = await latestBackup(GoogleAccounts.instance, a);
        if (f == null) return 'No backup found on ${a.label} Drive yet.';
        if (!mounted) return '';
        final bool? ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('RESTORE BACKUP?'),
            content: Text('Replaces everything on this phone with the backup from ${_when(f.modified)}. This cannot be undone.'),
            actions: <Widget>[
              VigilButton(label: 'Keep mine', variant: VigilButtonVariant.secondary, onPressed: () => Navigator.pop(ctx, false)),
              VigilButton(label: 'Restore', variant: VigilButtonVariant.critical, onPressed: () => Navigator.pop(ctx, true)),
            ],
          ),
        );
        if (ok != true) return 'Restore cancelled. Nothing changed.';
        await restoreFromDrive(widget.store, GoogleAccounts.instance, a, f);
        return 'Restored from ${a.label} Drive (${_when(f.modified)}).';
      });

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final List<GoogleAccount> accounts = GoogleAccounts.instance.accounts;
    final int? last = widget.store.prefs.getInt('driveBackupAt');
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.paddingOf(context).bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text('GOOGLE DRIVE BACKUP', style: t.h2),
        const SizedBox(height: 6),
        Text(
          'One file in a private app folder: you will not see it in Drive, and no other app can. It holds your objectives, protocols, ledger, notes, sleep and settings. Google asks you to approve this once.',
          style: t.caption.copyWith(color: c.textMuted),
        ),
        if (last != null) ...<Widget>[
          const SizedBox(height: 6),
          Text('LAST BACKUP FROM THIS PHONE ${_when(DateTime.fromMillisecondsSinceEpoch(last)).toUpperCase()}', style: t.micro.copyWith(color: c.textFaint, fontSize: 10)),
        ],
        const SizedBox(height: 14),
        if (accounts.isEmpty)
          Text('Link a Google account first (Loadout, Google accounts).', style: t.caption.copyWith(color: c.critical)),
        for (final GoogleAccount a in accounts) ...<Widget>[
          Text('${a.label} · ${a.email}', style: t.rowTitle),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            VigilButton(label: _busy == a.email ? 'Working…' : 'Back up now', onPressed: _busy != null ? null : () => _backup(a)),
            VigilButton(label: 'Restore', variant: VigilButtonVariant.secondary, onPressed: _busy != null ? null : () => _restore(a)),
          ]),
          const SizedBox(height: 14),
        ],
        if (_message != null)
          Semantics(liveRegion: true, child: Text(_message!, style: t.meta.copyWith(color: _isError ? c.critical : c.signal, fontSize: 12))),
      ]),
    );
  }
}
