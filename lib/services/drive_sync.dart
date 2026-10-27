import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/store.dart';
import 'drive_backup.dart';
import 'google_accounts.dart';

/// What the sync is doing, shown as a small chip.
enum SyncState { off, signIn, synced, syncing, offline, failed, conflict }

/// How to settle a conflict, when this phone and the Drive backup both changed.
enum ConflictChoice { keepPhone, useDrive, merge }

/// This phone's data next to the backup's, for the conflict question.
class ConflictPreview {
  const ConflictPreview(this.phone, this.drive, this.phoneEdited, this.driveModified);

  final Map<String, Object> phone;
  final Map<String, Object> drive;
  final DateTime? phoneEdited;
  final DateTime driveModified;
}

/// Whether the phone is online, and on Wi-Fi. A seam so tests do not need a network.
abstract class NetworkProbe {
  Future<bool> online();
  Future<bool> onWifi();
}

class DeviceNetwork implements NetworkProbe {
  final Connectivity _c = Connectivity();

  @override
  Future<bool> online() async => (await _c.checkConnectivity()).any((ConnectivityResult r) => r != ConnectivityResult.none);

  @override
  Future<bool> onWifi() async => (await _c.checkConnectivity()).any((ConnectivityResult r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet);
}

/// Keeps the app's data and the user's own Drive backup in step, with no server of ours.
///
/// Phone first: every change is saved on the phone at once. A few seconds later (and never more often than
/// [minGap]) a snapshot goes to the hidden app folder in Drive, if anything really changed. When the app opens, it
/// looks at Drive once: newer data from another phone is taken if this phone has no changes of its own, and if both
/// changed, nothing is overwritten and the user chooses ([resolve]).
class DriveSync extends ChangeNotifier {
  DriveSync({
    GoogleAccounts? accounts,
    NetworkProbe? network,
    this.client,
    this.debounce = const Duration(seconds: 8),
    this.minGap = const Duration(seconds: 60),
  })  : accounts = accounts ?? GoogleAccounts.instance,
        network = network ?? DeviceNetwork();

  static final DriveSync instance = DriveSync();

  final GoogleAccounts accounts;
  final NetworkProbe network;
  final http.Client? client;
  final Duration debounce;
  final Duration minGap;

  VigilStore? _store;
  Timer? _timer;
  bool _busy = false;
  bool _again = false;
  bool _applying = false;
  DateTime? _lastUpload;
  DriveFile? _conflict;

  SyncState state = SyncState.off;

  /// Why the last sync failed, or a note such as "Waiting for Wi-Fi".
  String? error;

  bool get attached => _store != null;
  SharedPreferences get _prefs => _store!.prefs;

  /// The Google account whose Drive holds the backup, or null when none is chosen.
  String? get accountEmail => attached ? _prefs.getString('driveAccount') : null;

  GoogleAccount? get account {
    final String? email = accountEmail;
    if (email == null) return null;
    for (final GoogleAccount a in accounts.accounts) {
      if (a.email.toLowerCase() == email.toLowerCase()) return a;
    }
    return null;
  }

  bool get configured => account != null;
  bool get autoSync => attached ? (_prefs.getBool('driveAutoSync') ?? true) : true;
  bool get wifiOnly => attached ? (_prefs.getBool('driveWifiOnly') ?? true) : true;
  int? get sizeBytes => attached ? _prefs.getInt('driveSize') : null;
  DriveFile? get conflict => _conflict;

  DateTime? get lastSync {
    final int? ms = attached ? _prefs.getInt('driveBackupAt') : null;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Starts watching [store]. Safe to call more than once.
  void attach(VigilStore store) {
    if (_store != null) return;
    _store = store;
    store.addListener(_onStore);
    _settle();
  }

  void _settle() {
    if (!configured) {
      state = accounts.hasAny ? SyncState.off : SyncState.signIn;
    } else if (_conflict != null) {
      state = SyncState.conflict;
    } else if (state == SyncState.off || state == SyncState.signIn) {
      state = autoSync ? SyncState.synced : SyncState.off;
    }
  }

  void _onStore() {
    if (_applying || !configured) return;
    _prefs.setInt('driveDirtyAt', DateTime.now().millisecondsSinceEpoch);
    if (!autoSync || state == SyncState.conflict) return;
    _schedule();
  }

  void _schedule() {
    Duration delay = debounce;
    final DateTime? last = _lastUpload;
    if (last != null) {
      final Duration wait = last.add(minGap).difference(DateTime.now());
      if (wait > delay) delay = wait;
    }
    _timer?.cancel();
    _timer = Timer(delay, () => syncNow(checkRemote: false));
  }

  // ---------------------------------------------------------------- the status line

  String statusText([DateTime? now]) {
    switch (state) {
      case SyncState.off:
        return configured ? 'Auto-sync off' : 'Backup off';
      case SyncState.signIn:
        return 'Sign in to back up';
      case SyncState.syncing:
        return 'Syncing…';
      case SyncState.offline:
        return 'Offline · will sync later';
      case SyncState.failed:
        return 'Sync failed · retry';
      case SyncState.conflict:
        return 'Sync paused';
      case SyncState.synced:
        final DateTime? t = lastSync;
        if (t == null) return 'Synced';
        final Duration d = (now ?? DateTime.now()).difference(t);
        if (d.inMinutes < 1) return 'Synced · just now';
        if (d.inMinutes < 60) return 'Synced · ${d.inMinutes} min ago';
        if (d.inHours < 24) return 'Synced · ${d.inHours} h ago';
        return 'Synced · ${d.inDays} d ago';
    }
  }

  // ---------------------------------------------------------------- the sync

  /// One pass: look, and upload or take newer data if needed. [manual] is a button press (it may open Google's approval
  /// screen and always uploads). [checkRemote] false means "only if something here changed", with no network call otherwise.
  Future<void> syncNow({bool manual = false, bool checkRemote = true}) async {
    final VigilStore? store = _store;
    if (store == null) return;
    final GoogleAccount? acct = account;
    if (acct == null) {
      _settle();
      notifyListeners();
      return;
    }
    if (!manual && !autoSync) return;
    if (_busy) {
      _again = true;
      return;
    }
    _timer?.cancel();
    final Map<String, Object> local = snapshotValues(_prefs);
    final String localHash = snapshotHash(local);
    final String? lastHash = _prefs.getString('driveHash');
    if (!manual && !checkRemote && localHash == lastHash) return;

    _busy = true;
    state = SyncState.syncing;
    error = null;
    notifyListeners();
    try {
      if (!await network.online()) {
        state = SyncState.offline;
        return;
      }
      if (wifiOnly && !await network.onWifi()) {
        state = SyncState.offline;
        error = 'Waiting for Wi-Fi.';
        return;
      }
      final DriveApi api = DriveApi(await driveToken(accounts, acct, interactive: manual), client: client);
      final DriveFile? remote = await api.latest();
      final bool phoneChanged = localHash != lastHash;
      final int? syncedAt = _prefs.getInt('driveSyncedAt');
      if (remote == null) {
        if (manual || phoneChanged || lastHash == null) await _upload(api, local, null);
      } else {
        final bool driveChanged = syncedAt == null || remote.modified.millisecondsSinceEpoch > syncedAt + 1000;
        if (!driveChanged) {
          if (phoneChanged || manual) {
            await _upload(api, local, remote.id);
          } else {
            await _markSynced(remote, local);
          }
        } else if ((!phoneChanged && syncedAt != null) || (syncedAt == null && !hasUserData(local))) {
          await _pull(api, remote);
        } else {
          _conflict = remote;
          state = SyncState.conflict;
          return;
        }
      }
      state = SyncState.synced;
    } on DriveException catch (e) {
      error = e.message;
      state = e.signIn ? SyncState.signIn : SyncState.failed;
    } finally {
      _busy = false;
      notifyListeners();
      if (_again) {
        _again = false;
        _schedule();
      }
    }
  }

  Future<void> _record(DriveFile f, Map<String, Object> values, {int? sizeFallback}) async {
    await _prefs.setInt('driveSyncedAt', f.modified.millisecondsSinceEpoch);
    await _prefs.setString('driveHash', snapshotHash(values));
    await _prefs.setInt('driveBackupAt', DateTime.now().millisecondsSinceEpoch);
    final int? size = f.size ?? sizeFallback;
    if (size != null) await _prefs.setInt('driveSize', size);
  }

  Future<void> _markSynced(DriveFile remote, Map<String, Object> local) => _record(remote, local);

  Future<void> _upload(DriveApi api, Map<String, Object> values, String? existingId) async {
    final String body = encodeSnapshot(values, DateTime.now());
    final DriveFile saved = await api.upload(body, existingId: existingId);
    _lastUpload = DateTime.now();
    await _record(saved, values, sizeFallback: body.length);
  }

  Future<void> _pull(DriveApi api, DriveFile remote) async {
    final Map<String, Object> values = parseSnapshot(await api.download(remote.id)); // checked before anything is replaced
    _applying = true;
    try {
      await applySnapshot(_prefs, values);
      await _store!.reloadFromDisk();
    } finally {
      _applying = false;
    }
    await _record(remote, snapshotValues(_prefs));
  }

  // ---------------------------------------------------------------- what the user can do

  /// Chooses the Google account for the backup and starts auto-sync.
  Future<void> enable(GoogleAccount a) async {
    if (!attached) return;
    await _prefs.setString('driveAccount', a.email);
    await _prefs.setBool('driveAutoSync', true);
    _conflict = null;
    state = SyncState.synced;
    notifyListeners();
    await syncNow(checkRemote: true);
  }

  /// Chooses the account for the backup without syncing yet (the setup guide asks about a found backup first).
  Future<void> choose(GoogleAccount a) async {
    if (!attached) return;
    await _prefs.setString('driveAccount', a.email);
    await _prefs.setBool('driveAutoSync', true);
    _conflict = null;
    state = SyncState.synced;
    notifyListeners();
  }

  /// "Start fresh": this phone's data replaces [existing] at the next sync, instead of being replaced by it.
  Future<void> startFreshOver(DriveFile existing) async {
    if (!attached) return;
    await _prefs.setInt('driveSyncedAt', existing.modified.millisecondsSinceEpoch);
    await _prefs.setString('driveHash', 'fresh-start');
    notifyListeners();
    await syncNow(checkRemote: false);
  }

  Future<void> setAutoSync(bool v) async {
    if (!attached) return;
    await _prefs.setBool('driveAutoSync', v);
    if (v) {
      state = SyncState.synced;
      notifyListeners();
      await syncNow(checkRemote: true);
    } else {
      _timer?.cancel();
      state = SyncState.off;
      notifyListeners();
    }
  }

  Future<void> setWifiOnly(bool v) async {
    if (!attached) return;
    await _prefs.setBool('driveWifiOnly', v);
    notifyListeners();
  }

  /// Back up now, whatever changed.
  Future<void> backupNow() => syncNow(manual: true);

  /// Replaces this phone's data with the backup in Drive. Throws [DriveException] when there is none.
  Future<void> restoreNow() async {
    final GoogleAccount? acct = account;
    if (!attached || acct == null) throw const DriveException('Choose a Google account for the backup first.');
    state = SyncState.syncing;
    notifyListeners();
    try {
      final DriveApi api = DriveApi(await driveToken(accounts, acct), client: client);
      final DriveFile? remote = await api.latest();
      if (remote == null) throw const DriveException('No backup found in this Drive yet.');
      await _pull(api, remote);
      _conflict = null;
      state = SyncState.synced;
    } on DriveException catch (e) {
      error = e.message;
      state = SyncState.failed;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// What each side holds, so the user can see what differs before choosing. Null when the backup cannot be read.
  Future<ConflictPreview?> conflictPreview() async {
    final GoogleAccount? acct = account;
    final DriveFile? remote = _conflict;
    if (!attached || acct == null || remote == null) return null;
    try {
      final DriveApi api = DriveApi(await driveToken(accounts, acct, interactive: false), client: client);
      final int dirty = _prefs.getInt('driveDirtyAt') ?? 0;
      return ConflictPreview(snapshotValues(_prefs), parseSnapshot(await api.download(remote.id)), dirty == 0 ? null : DateTime.fromMillisecondsSinceEpoch(dirty), remote.modified);
    } on DriveException {
      return null;
    }
  }

  /// Settles a conflict. Nothing is deleted until the user chooses.
  Future<void> resolve(ConflictChoice choice) async {
    final GoogleAccount? acct = account;
    final DriveFile? remote = _conflict;
    if (!attached || acct == null || remote == null) return;
    state = SyncState.syncing;
    notifyListeners();
    try {
      final DriveApi api = DriveApi(await driveToken(accounts, acct), client: client);
      switch (choice) {
        case ConflictChoice.keepPhone:
          await _upload(api, snapshotValues(_prefs), remote.id);
        case ConflictChoice.useDrive:
          await _pull(api, remote);
        case ConflictChoice.merge:
          final Map<String, Object> theirs = parseSnapshot(await api.download(remote.id));
          final int dirtyAt = _prefs.getInt('driveDirtyAt') ?? 0;
          final Map<String, Object> merged = mergeValues(snapshotValues(_prefs), theirs, phoneNewer: dirtyAt >= remote.modified.millisecondsSinceEpoch);
          _applying = true;
          try {
            await applySnapshot(_prefs, merged);
            await _store!.reloadFromDisk();
          } finally {
            _applying = false;
          }
          await _upload(api, snapshotValues(_prefs), remote.id);
      }
      _conflict = null;
      state = SyncState.synced;
    } on DriveException catch (e) {
      error = e.message;
      state = SyncState.conflict;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// Stops syncing and forgets which account. The backup stays in Drive.
  Future<void> disconnect() async {
    if (!attached) return;
    _timer?.cancel();
    for (final String k in const <String>['driveAccount', 'driveHash', 'driveSyncedAt', 'driveBackupAt', 'driveSize', 'driveDirtyAt']) {
      await _prefs.remove(k);
    }
    _conflict = null;
    error = null;
    state = accounts.hasAny ? SyncState.off : SyncState.signIn;
    notifyListeners();
  }

  /// Deletes the backup file from Drive, and switches auto-sync off so it is not recreated behind the user's back.
  Future<void> deleteBackup() async {
    final GoogleAccount? acct = account;
    if (!attached || acct == null) throw const DriveException('Choose a Google account for the backup first.');
    final DriveApi api = DriveApi(await driveToken(accounts, acct), client: client);
    final DriveFile? remote = await api.latest();
    if (remote != null) await api.delete(remote.id);
    for (final String k in const <String>['driveHash', 'driveSyncedAt', 'driveSize']) {
      await _prefs.remove(k);
    }
    await _prefs.setBool('driveAutoSync', false);
    _timer?.cancel();
    _conflict = null;
    state = SyncState.off;
    notifyListeners();
  }
}
