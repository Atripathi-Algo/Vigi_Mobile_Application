import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_error.dart';
import '../data/store.dart';
import 'google_accounts.dart';

/// Backs VIGIL's data up to the private app folder of a linked Google account's Drive, and restores it.
/// The folder is invisible in the user's Drive and to other apps; one file holds the latest snapshot.
const String kBackupName = 'vigil-backup.json';

/// Settings that belong to this phone and are never copied to or from a backup.
const Set<String> _deviceOnlyKeys = <String>{'google_accounts'};

class DriveException implements Exception {
  const DriveException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DriveFile {
  const DriveFile(this.id, this.modified);

  final String id;
  final DateTime modified;
}

/// Everything the app saved, as JSON. Strings, numbers, booleans and string lists keep their types.
String buildSnapshot(SharedPreferences prefs, DateTime now) {
  final Map<String, Object> data = <String, Object>{
    for (final String k in prefs.getKeys())
      if (!_deviceOnlyKeys.contains(k) && prefs.get(k) != null) k: prefs.get(k)!,
  };
  return jsonEncode(<String, dynamic>{'app': 'vigil', 'format': 1, 'savedAt': now.toUtc().toIso8601String(), 'prefs': data});
}

/// The saved values in [body]; throws [DriveException] when it is not a VIGIL backup.
Map<String, Object> parseSnapshot(String body) {
  try {
    final Map<String, dynamic> j = jsonDecode(body) as Map<String, dynamic>;
    if (j['app'] != 'vigil' || j['prefs'] is! Map) throw const FormatException('not a VIGIL backup');
    final Map<String, Object> out = <String, Object>{};
    (j['prefs'] as Map<String, dynamic>).forEach((String k, dynamic v) {
      if (_deviceOnlyKeys.contains(k)) return;
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
    throw const DriveException('That file is not a VIGIL backup.');
  }
}

/// Replaces everything saved on this phone (except device-only settings) with [values].
Future<void> applySnapshot(SharedPreferences prefs, Map<String, Object> values) async {
  for (final String k in prefs.getKeys().toList()) {
    if (!_deviceOnlyKeys.contains(k)) await prefs.remove(k);
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

/// Drive REST calls for the backup file, with an access token for the `drive.appdata` scope.
class DriveApi {
  DriveApi(this.token, {http.Client? client}) : _client = client;

  final String token;
  final http.Client? _client;

  static const String _boundary = 'vigil_backup_boundary_7f3a91';

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

  /// The newest backup file in the app folder, or null when none exists.
  Future<DriveFile?> latest() => _run((http.Client c) async {
        final Uri uri = Uri.https('www.googleapis.com', '/drive/v3/files', <String, String>{
          'spaces': 'appDataFolder',
          'q': "name = '$kBackupName' and trashed = false",
          'orderBy': 'modifiedTime desc',
          'pageSize': '1',
          'fields': 'files(id,modifiedTime)',
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
                Uri.https('www.googleapis.com', '/upload/drive/v3/files', <String, String>{'uploadType': 'multipart', 'fields': 'id,modifiedTime'}),
                headers: <String, String>{..._auth, 'content-type': 'multipart/related; boundary=$_boundary'},
                body: utf8.encode(body),
              )
              .timeout(const Duration(seconds: 30));
        } else {
          r = await c
              .patch(
                Uri.https('www.googleapis.com', '/upload/drive/v3/files/$existingId', <String, String>{'uploadType': 'media', 'fields': 'id,modifiedTime'}),
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

  static DriveFile _file(Map<String, dynamic> j) =>
      DriveFile(j['id'] as String, DateTime.tryParse((j['modifiedTime'] as String?) ?? '')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0));
}

/// A Drive token for [a]: silently if approved already; otherwise Google's approval screen, which is only
/// opened because the user pressed a backup or restore button.
Future<String> driveToken(GoogleAccounts accounts, GoogleAccount a) async {
  AuthResult r = await accounts.authorizeScopes(a, <String>[kDriveScope]);
  if (r.status == AuthStatus.consentNeeded) r = await accounts.authorizeScopes(a, <String>[kDriveScope], interactive: true);
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
