import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/brand.dart';
import '../app/common.dart';
import '../app/fmt.dart';
import '../data/store.dart';
import '../services/drive_backup.dart';
import '../services/drive_sync.dart';
import '../services/google_accounts.dart';
import '../vigil/vigil.dart';

/// The colour of a sync state: green when in step, amber when waiting, red when it failed.
Color syncColor(BuildContext context, SyncState s) => switch (s) {
      SyncState.synced => VigilPalette.success,
      SyncState.syncing => context.vigil.signal,
      SyncState.offline || SyncState.conflict => VigilPalette.warning,
      SyncState.failed => context.vigil.critical,
      SyncState.off || SyncState.signIn => context.vigil.textMuted,
    };

/// Opens what the sync status asks for: the conflict question, a retry, or the Drive screen.
Future<void> openSyncStatus(BuildContext context, VigilStore store) async {
  final DriveSync sync = DriveSync.instance;
  if (sync.state == SyncState.conflict) return showDriveConflict(context, sync);
  if (sync.state == SyncState.failed && sync.configured) {
    sync.syncNow(manual: true);
    return;
  }
  return showDriveSheet(context, store);
}

/// Back up to, or restore from, the private app folder on a linked Google account's Drive, and the sync settings.
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
  final DriveSync _sync = DriveSync.instance;
  String? _message;
  bool _isError = false;

  String _when(DateTime d) {
    final DateTime n = DateTime.now();
    final bool today = d.year == n.year && d.month == n.month && d.day == n.day;
    return today ? 'today ${Fmt.time(d)}' : '${Fmt.dayStamp(d)} ${Fmt.time(d)}';
  }

  String _size(int? bytes) {
    if (bytes == null) return '';
    return bytes < 1024 * 1024 ? '${(bytes / 1024).toStringAsFixed(0)} KB' : '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  Future<void> _run(Future<String> Function() job) async {
    setState(() {
      _message = null;
      _isError = false;
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
      _message = msg;
      _isError = err;
    });
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          VigilButton(label: 'Keep', variant: VigilButtonVariant.secondary, onPressed: () => Navigator.pop(ctx, false)),
          VigilButton(label: action, variant: VigilButtonVariant.critical, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_sync, GoogleAccounts.instance]),
      builder: (BuildContext ctx, Widget? _) {
        final List<GoogleAccount> accounts = GoogleAccounts.instance.accounts;
        final GoogleAccount? chosen = _sync.account;
        final DateTime? last = _sync.lastSync;
        final bool busy = _sync.state == SyncState.syncing;
        const List<String> stored = <String>['Objectives', 'Notes', 'Protocols', 'Water', 'Expenses', 'Bills', 'Budget', 'Settings', 'Chat log'];
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.paddingOf(context).bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text('DRIVE BACKUP', style: t.h2),
            const SizedBox(height: 6),
            Text('Your data is saved on this phone first, then copied to a hidden folder in your own Google Drive. $kAssistantName has no server.', style: t.caption.copyWith(color: c.textMuted)),
            const SizedBox(height: 14),
            if (accounts.isEmpty) ...<Widget>[
              Text('Link a Google account first (Settings, Google accounts).', style: t.caption.copyWith(color: c.critical)),
            ] else if (chosen == null) ...<Widget>[
              Text('CHOOSE THE ACCOUNT FOR THE BACKUP', style: t.micro.copyWith(color: c.textFaint)),
              const SizedBox(height: 8),
              for (final GoogleAccount a in accounts) ...<Widget>[
                VigilButton(label: '${a.label} · ${a.email}', variant: VigilButtonVariant.secondary, expand: true, onPressed: () => _run(() async {
                      await _sync.enable(a);
                      return _sync.state == SyncState.failed ? (_sync.error ?? 'Could not reach Drive.') : 'Backing up to ${a.email}.';
                    })),
                const SizedBox(height: 8),
              ],
            ] else ...<Widget>[
              Row(children: <Widget>[
                Expanded(child: Text('BACKING UP TO', style: t.micro.copyWith(color: c.textFaint))),
                if (accounts.length > 1)
                  TextButton(
                    onPressed: () => _run(() async {
                      final GoogleAccount other = accounts.firstWhere((GoogleAccount a) => a.email != chosen.email);
                      await _sync.disconnect();
                      await _sync.enable(other);
                      return 'Now backing up to ${other.email}.';
                    }),
                    child: Text('CHANGE', style: t.button.copyWith(fontSize: 11, color: c.signal)),
                  ),
              ]),
              Text('${chosen.label} · ${chosen.email}', style: t.rowTitle),
              const SizedBox(height: 12),
              VigilCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('STATUS', style: t.micro.copyWith(color: c.textFaint)),
                  const SizedBox(height: 4),
                  Row(children: <Widget>[
                    Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: syncColor(context, _sync.state))),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_sync.statusText(), style: t.title)),
                  ]),
                  if (last != null) ...<Widget>[
                    const SizedBox(height: 6),
                    Text('Last backup ${_when(last)}${_sync.sizeBytes == null ? '' : ' · ${_size(_sync.sizeBytes)}'} · hidden app folder', style: t.caption.copyWith(color: c.textMuted)),
                  ],
                  if (_sync.error != null && (_sync.state == SyncState.failed || _sync.state == SyncState.offline || _sync.state == SyncState.signIn)) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(_sync.error!, style: t.caption.copyWith(color: _sync.state == SyncState.offline ? c.textMuted : c.critical)),
                  ],
                  if (_sync.state == SyncState.conflict) ...<Widget>[
                    const SizedBox(height: 8),
                    VigilButton(label: 'Settle the conflict', onPressed: () => showDriveConflict(context, _sync)),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: <Widget>[
                Expanded(child: VigilButton(label: busy ? 'Working…' : 'Back up now', expand: true, onPressed: busy ? null : () => _run(() async {
                      await _sync.backupNow();
                      return _sync.state == SyncState.synced ? 'Backed up.' : (_sync.error ?? _sync.statusText());
                    }))),
                const SizedBox(width: 10),
                Expanded(child: VigilButton(label: 'Restore', variant: VigilButtonVariant.secondary, expand: true, onPressed: busy ? null : () async {
                      if (!await _confirm('RESTORE BACKUP?', 'Replaces everything on this phone with the backup in Drive. This cannot be undone.', 'Restore')) return;
                      await _run(() async {
                        await _sync.restoreNow();
                        return 'Restored from Drive.';
                      });
                    })),
              ]),
              const SizedBox(height: 14),
              RowList(children: <Widget>[
                _switchRow(context, 'Auto-sync', 'Backs up a few seconds after each change', _sync.autoSync, _sync.setAutoSync),
                _switchRow(context, 'Wi-Fi only', 'Never uses mobile data; waits for Wi-Fi', _sync.wifiOnly, _sync.setWifiOnly),
              ]),
              const SizedBox(height: 14),
              Text('WHAT IS STORED', style: t.micro.copyWith(color: c.textFaint)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                for (final String x in stored)
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(border: Border.all(color: c.lineStrong)), child: Text(x.toUpperCase(), style: t.micro.copyWith(color: c.textMuted, fontSize: 9.5))),
              ]),
              const SizedBox(height: 10),
              Text('Not backed up: API keys and Google sign-in tokens. Re-enter them on a new phone. They never leave this one.', style: t.caption.copyWith(color: c.textMuted)),
              const SizedBox(height: 6),
              Text('Stored in your own Drive, visible only to $kAssistantName.', style: t.micro.copyWith(color: c.textFaint)),
              const SizedBox(height: 14),
              Row(children: <Widget>[
                VigilButton(label: 'Disconnect', variant: VigilButtonVariant.ghost, onPressed: () => _run(() async {
                      await _sync.disconnect();
                      return 'Disconnected. Your backup stays in Drive.';
                    })),
                const Spacer(),
                VigilButton(label: 'Delete my Drive backup', variant: VigilButtonVariant.ghost, onPressed: () async {
                  if (!await _confirm('DELETE THE BACKUP?', 'Removes the backup file from your Drive. Your data on this phone is not touched, and auto-sync is switched off.', 'Delete')) return;
                  await _run(() async {
                    await _sync.deleteBackup();
                    return 'The backup was deleted from Drive.';
                  });
                }),
              ]),
            ],
            if (_message != null) ...<Widget>[
              const SizedBox(height: 10),
              Semantics(liveRegion: true, child: Text(_message!, style: t.meta.copyWith(color: _isError ? c.critical : c.signal, fontSize: 12))),
            ],
          ]),
        );
      },
    );
  }

  Widget _switchRow(BuildContext context, String title, String sub, bool value, Future<void> Function(bool) onChanged) {
    final c = context.vigil;
    final t = context.vtype;
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 8),
        child: Row(children: <Widget>[
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text(title, style: t.rowTitle), Text(sub.toUpperCase(), style: t.micro.copyWith(color: c.textFaint), maxLines: 1, overflow: TextOverflow.ellipsis)])),
          VigilSwitch(value: value, onChanged: (bool v) => onChanged(v), semanticLabel: title),
        ]),
      ),
    );
  }
}

/// "Two versions of your data": what differs, and three ways to settle it. Nothing is deleted until the user chooses.
Future<void> showDriveConflict(BuildContext context, DriveSync sync) => showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (BuildContext ctx) => _ConflictDialog(sync: sync),
    );

class _ConflictDialog extends StatefulWidget {
  const _ConflictDialog({required this.sync});

  final DriveSync sync;

  @override
  State<_ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends State<_ConflictDialog> {
  late final Future<ConflictPreview?> _preview = widget.sync.conflictPreview();
  bool _working = false;
  String? _error;

  Future<void> _choose(ConflictChoice choice) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.sync.resolve(choice);
      if (mounted) Navigator.pop(context);
    } on DriveException catch (e) {
      if (mounted) {
        setState(() {
          _working = false;
          _error = e.message;
        });
      }
    }
  }

  static String _count(Map<String, Object> v, String key) {
    final Object? x = v[key];
    if (x is int) return '$x';
    if (x is String) {
      try {
        final dynamic d = jsonDecode(x);
        if (d is List) return '${d.length}';
      } catch (_) {}
    }
    return '0';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    return AlertDialog(
      title: const Text('TWO VERSIONS OF YOUR DATA'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('This phone and your Drive backup both changed since the last sync.', style: t.caption.copyWith(color: c.textMuted)),
          const SizedBox(height: 12),
          FutureBuilder<ConflictPreview?>(
            future: _preview,
            builder: (BuildContext ctx, AsyncSnapshot<ConflictPreview?> snap) {
              final ConflictPreview? p = snap.data;
              if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator(minHeight: 2);
              if (p == null) return Text('Could not read the backup to compare. You can still choose.', style: t.caption.copyWith(color: c.textMuted));
              Widget row(String label, String a, String b) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: <Widget>[
                      Expanded(child: Text(label.toUpperCase(), style: t.micro.copyWith(color: c.textFaint))),
                      SizedBox(width: 64, child: Text(a, style: t.meta, textAlign: TextAlign.right)),
                      SizedBox(width: 64, child: Text(b, style: t.meta, textAlign: TextAlign.right)),
                    ]),
                  );
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                row('Item', 'PHONE', 'DRIVE'),
                row('Edited', p.phoneEdited == null ? '—' : Fmt.time(p.phoneEdited!), Fmt.time(p.driveModified)),
                row('Objectives', _count(p.phone, 'objectives'), _count(p.drive, 'objectives')),
                row('Notes', _count(p.phone, 'notes'), _count(p.drive, 'notes')),
                row('Protocols', _count(p.phone, 'protocols'), _count(p.drive, 'protocols')),
                row('Expenses', _count(p.phone, 'txns'), _count(p.drive, 'txns')),
                row('Water ml', _count(p.phone, 'water'), _count(p.drive, 'water')),
              ]);
            },
          ),
          const SizedBox(height: 12),
          Text('Merge keeps both: records from both are joined, and the newest edit wins where they clash.', style: t.caption.copyWith(color: c.textMuted)),
          const SizedBox(height: 4),
          Text('Nothing is deleted until you choose.', style: t.micro.copyWith(color: c.textFaint)),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(_error!, style: t.caption.copyWith(color: c.critical)),
          ],
        ]),
      ),
      actions: <Widget>[
        VigilButton(label: 'Keep this phone', variant: VigilButtonVariant.secondary, onPressed: _working ? null : () => _choose(ConflictChoice.keepPhone)),
        VigilButton(label: 'Use Drive', variant: VigilButtonVariant.secondary, onPressed: _working ? null : () => _choose(ConflictChoice.useDrive)),
        VigilButton(label: _working ? 'Working…' : 'Merge', onPressed: _working ? null : () => _choose(ConflictChoice.merge)),
      ],
    );
  }
}
