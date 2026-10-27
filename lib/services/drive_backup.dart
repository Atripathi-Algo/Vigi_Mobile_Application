import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_error.dart';
import '../data/store.dart';
import 'google_accounts.dart';

/// Backs K's data up to the private app folder of a linked Google account's Drive, and restores it.
/// The folder is invisible in the user's Drive and to other apps; one file holds the latest snapshot.
const String kBackupName = 'k-backup.json';

/// The name builds before K used; still found and still updated in place, so nothing is lost on upgrade.
const String kLegacyBackupName = 'vigil-backup.json';

/// Settings that belong to this phone and are never copied to or from a backup: the linked Google accounts and the
/// bookkeeping of the sync itself.
const Set<String> kDeviceOnlyKeys = <String>{
  'google_accounts',
  'driveBackupAt',
  'driveSyncedAt',
  'driveHash',
  'driveDirtyAt',
  'driveAutoSync',
  'driveWifiOnly',
  'driveAccount',
  'driveSize',
};

/// Values that change on their own (the step sensor, the clock) and so must not count as "the user changed something".
const Set<String> _volatileKeys = <String>{'stepsToday', 'stepsDay', 'hcSync', 'day'};

class DriveException implements Exception {
  const DriveException(this.message, {this.signIn = false});

  final String message;

  /// True when the fix is to approve Drive access again (not a network problem).
  final bool signIn;

  @override
  String toString() => message;
}

class DriveFile {
  const DriveFile(this.id, this.modified, {this.size});

  final String id;
  final DateTime modified;
  final int? size;
}

/// Everything the app saved that belongs in a backup. Strings, numbers, booleans and string lists keep their types.
Map<String, Object> snapshotValues(SharedPreferences prefs) => <String, Object>{
      for (final String k in prefs.getKeys())
        if (!kDeviceOnlyKeys.contains(k) && prefs.get(k) != null) k: prefs.get(k)!,
    };

/// A stable fingerprint of [values], used to tell whether anything changed since the last sync (FNV-1a, 64 bit).
String snapshotHash(Map<String, Object> values) {
  final List<String> keys = values.keys.where((String k) => !_volatileKeys.contains(k)).toList()..sort();
  int h = 0xcbf29ce484222325;
  void feed(String s) {
    for (final int c in s.codeUnits) {
      h = (h ^ c) * 0x100000001b3;
    }
  }

  for (final String k in keys) {
    feed(k);
    feed('\u0000');
    feed(jsonEncode(values[k]));
    feed('\u0001');
  }
  return h.toRadixString(16);
}

/// Everything the app saved, as JSON.
String buildSnapshot(SharedPreferences prefs, DateTime now) => encodeSnapshot(snapshotValues(prefs), now);

String encodeSnapshot(Map<String, Object> values, DateTime now) => jsonEncode(<String, dynamic>{'app': 'k', 'format': 1, 'savedAt': now.toUtc().toIso8601String(), 'prefs': values});

/// The saved values in [body]; throws [DriveException] when it is not a K backup.
Map<String, Object> parseSnapshot(String body) {
  try {
    final Map<String, dynamic> j = jsonDecode(body) as Map<String, dynamic>;
    if ((j['app'] != 'k' && j['app'] != 'vigil') || j['prefs'] is! Map) throw const FormatException('not a K backup');
    final Map<String, Object> out = <String, Object>{};
    (j['prefs'] as Map<String, dynamic>).forEach((String k, dynamic v) {
      if (kDeviceOnlyKeys.contains(k)) return;
      if (v is List) {
        out[k] = v.map((dynamic e) => e as String).toList();
      } else if (v is String || v is int || v is double || v is bool) {
        out[k] = v as Object;
      }
    });
    return out;
  } on DriveException {
    rethrow;
  } catch (_) {
    throw const DriveException('That file is not a K backup.');
  }
}

/// Replaces everything saved on this phone (except device-only settings) with [values].
Future<void> applySnapshot(SharedPreferences prefs, Map<String, Object> values) async {
  for (final String k in prefs.getKeys().toList()) {
    if (!kDeviceOnlyKeys.contains(k)) await prefs.remove(k);
  }
  for (final MapEntry<String, Object> e in values.entries) {
    final Object v = e.value;
    if (v is bool) {
      await prefs.setBool(e.key, v);
    } else if (v is int) {
      await prefs.setInt(e.key, v);
    } else if (v is double) {
      await prefs.setDouble(e.key, v);
    } else if (v is String) {
      await prefs.setString(e.key, v);
    } else if (v is List<String>) {
      await prefs.setStringList(e.key, v);
    }
  }
}

/// True when [values] holds something the user entered (as opposed to a freshly installed app).
bool hasUserData(Map<String, Object> values) {
  for (final String k in const <String>['objectives', 'notes', 'txns', 'bills', 'protocols', 'blocks', 'chat']) {
    final Object? v = values[k];
    if (v is String && v.length > 2) return true;
  }
  return false;
}

/// Combines this phone's data with the backup's. Lists of records with an id (objectives, notes, expenses, ...) are
/// joined, and when both sides have the same record the one from the side that was edited last wins; a plain value
/// takes the newer side's. Nothing is dropped.
Map<String, Object> mergeValues(Map<String, Object> phone, Map<String, Object> drive, {required bool phoneNewer}) {
  final Map<String, Object> out = <String, Object>{};
  for (final String k in <String>{...phone.keys, ...drive.keys}) {
    final Object? p = phone[k];
    final Object? d = drive[k];
    if (p == null) {
      out[k] = d!;
    } else if (d == null || p == d) {
      out[k] = p;
    } else if (p is String && d is String) {
      out[k] = _mergeRecords(p, d, phoneNewer) ?? (phoneNewer ? p : d);
    } else if (p is List<String> && d is List<String>) {
      out[k] = <String>{...(phoneNewer ? p : d), ...(phoneNewer ? d : p)}.toList();
    } else {
      out[k] = phoneNewer ? p : d;
    }
  }
  return out;
}

String? _mergeRecords(String a, String b, bool aNewer) {
  try {
    final dynamic x = jsonDecode(a);
    final dynamic y = jsonDecode(b);
    bool records(dynamic l) => l is List && l.isNotEmpty && l.every((dynamic e) => e is Map && e['id'] != null);
    if (!records(x) || !records(y)) return null;
    final List<dynamic> first = aNewer ? x as List<dynamic> : y as List<dynamic>;
    final List<dynamic> second = aNewer ? y as List<dynamic> : x as List<dynamic>;
    final Set<Object?> seen = first.map((dynamic e) => (e as Map<dynamic, dynamic>)['id']).toSet();
    return jsonEncode(<dynamic>[...first, for (final dynamic e in second) if (!seen.contains((e as Map<dynamic, dynamic>)['id'])) e]);
  } catch (_) {
    return null;
  }
}

/// Drive REST calls for the backup file, with an access token for the `drive.appdata` scope.
class DriveApi {
  DriveApi(this.token, {http.Client? client}) : _client = client;

  final String token;
  final http.Client? _client;

  static const String _boundary = 'k_backup_boundary_7f3a91';

  Map<String, String> get _auth => <String, String>{'authorization': 'Bearer $token'};

  Future<T> _run<T>(Future<T> Function(http.Client c) call) async {
    final http.Client c = _client ?? http.Client();
    try {
      return await call(c);
    } on DriveException {
      rethrow;
    } on TimeoutException {
      throw const DriveException('Timed out talking to Google Drive.');
    } catch (e) {
      throw DriveException('Could not reach Google Drive: ${e.toString().split('\n').first}');
    } finally {
      if (_client == null) c.close();
    }
  }

  Never _fail(http.Response r) => throw DriveException('HTTP ${r.statusCode}: ${apiErrorMessage(r.body)}');

  /// The newest backup file in the app folder (under either name), or null when none exists.
  Future<DriveFile?> latest() => _run((http.Client c) async {
        final Uri uri = Uri.https('www.googleapis.com', '/drive/v3/files', <String, String>{
          'spaces': 'appDataFolder',
          'q': "(name = '$kBackupName' or name = '$kLegacyBackupName') and trashed = false",
          'orderBy': 'modifiedTime desc',
          'pageSize': '1',
          'fields': 'files(id,modifiedTime,size)',
        });
        final http.Response r = await c.get(uri, headers: _auth).timeout(const Duration(seconds: 20));
        if (r.statusCode != 200) _fail(r);
        final List<dynamic> files = (jsonDecode(r.body) as Map<String, dynamic>)['files'] as List<dynamic>? ?? <dynamic>[];
        if (files.isEmpty) return null;
        return _file(files.first as Map<String, dynamic>);
      });

  /// Creates the backup file, or overwrites [existingId].
  Future<DriveFile> upload(String json, {String? existingId}) => _run((http.Client c) async {
        final http.Response r;
        if (existingId == null) {
          final String body = '--$_boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n'
              '${jsonEncode(<String, dynamic>{'name': kBackupName, 'parents': <String>['appDataFolder']})}\r\n'
              '--$_boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$json\r\n--$_boundary--';
          r = await c
              .post(
                Uri.https('www.googleapis.com', '/upload/drive/v3/files', <String, String>{'uploadType': 'multipart', 'fields': 'id,modifiedTime,size'}),
                headers: <String, String>{..._auth, 'content-type': 'multipart/related; boundary=$_boundary'},
                body: utf8.encode(body),
              )
              .timeout(const Duration(seconds: 30));
        } else {
          r = await c
              .patch(
                Uri.https('www.googleapis.com', '/upload/drive/v3/files/$existingId', <String, String>{'uploadType': 'media', 'fields': 'id,modifiedTime,size'}),
                headers: <String, String>{..._auth, 'content-type': 'application/json; charset=UTF-8'},
                body: utf8.encode(json),
              )
              .timeout(const Duration(seconds: 30));
        }
        if (r.statusCode != 200) _fail(r);
        return _file(jsonDecode(r.body) as Map<String, dynamic>);
      });

  Future<String> download(String id) => _run((http.Client c) async {
        final http.Response r = await c.get(Uri.https('www.googleapis.com', '/drive/v3/files/$id', <String, String>{'alt': 'media'}), headers: _auth).timeout(const Duration(seconds: 30));
        if (r.statusCode != 200) _fail(r);
        return utf8.decode(r.bodyBytes);
      });

  /// Deletes the backup file from Drive.
  Future<void> delete(String id) => _run((http.Client c) async {
        final http.Response r = await c.delete(Uri.https('www.googleapis.com', '/drive/v3/files/$id'), headers: _auth).timeout(const Duration(seconds: 20));
        if (r.statusCode != 204 && r.statusCode != 200 && r.statusCode != 404) _fail(r);
      });

  static DriveFile _file(Map<String, dynamic> j) => DriveFile(
        j['id'] as String,
        DateTime.tryParse((j['modifiedTime'] as String?) ?? '')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
        size: int.tryParse('${j['size'] ?? ''}'),
      );
}

/// A Drive token for [a]: silently if approved already. With [interactive] (a button press) Google's approval screen
/// may open; without it, a lapsed approval is reported as [DriveException.signIn] instead.
Future<String> driveToken(GoogleAccounts accounts, GoogleAccount a, {bool interactive = true}) async {
  AuthResult r = await accounts.authorizeScopes(a, <String>[kDriveScope]);
  if (r.status == AuthStatus.consentNeeded) {
    if (!interactive) throw const DriveException('Approve Drive access again: open Drive backup and tap Back up now.', signIn: true);
    r = await accounts.authorizeScopes(a, <String>[kDriveScope], interactive: true);
  }
  if (r.status != AuthStatus.ok || r.token == null) throw DriveException(explainAuthError(r));
  return r.token!;
}

/// Saves a snapshot of the app's data to [a]'s Drive and returns when it was stored.
Future<DriveFile> backupToDrive(VigilStore store, GoogleAccounts accounts, GoogleAccount a, {http.Client? client, DateTime? now}) async {
  final DriveApi api = DriveApi(await driveToken(accounts, a), client: client);
  final DriveFile? existing = await api.latest();
  final DriveFile saved = await api.upload(buildSnapshot(store.prefs, now ?? DateTime.now()), existingId: existing?.id);
  await store.prefs.setInt('driveBackupAt', saved.modified.millisecondsSinceEpoch);
  return saved;
}

/// The newest backup on [a]'s Drive, or null. Use before [restoreFromDrive] to show its date.
Future<DriveFile?> latestBackup(GoogleAccounts accounts, GoogleAccount a, {http.Client? client}) async =>
    DriveApi(await driveToken(accounts, a), client: client).latest();

/// Replaces this phone's data with the backup [file] and reloads the app state.
Future<void> restoreFromDrive(VigilStore store, GoogleAccounts accounts, GoogleAccount a, DriveFile file, {http.Client? client}) async {
  final DriveApi api = DriveApi(await driveToken(accounts, a), client: client);
  final Map<String, Object> values = parseSnapshot(await api.download(file.id)); // validated before anything is erased
  await applySnapshot(store.prefs, values);
  await store.reloadFromDisk();
}
