import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigil/data/models.dart';
import 'package:vigil/data/store.dart';
import 'package:vigil/services/drive_backup.dart';
import 'package:vigil/services/google_accounts.dart';

import 'support/fake_google.dart';

http.Response json(int code, Object body) => http.Response(jsonEncode(body), code, headers: <String, String>{'content-type': 'application/json'});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('snapshot', () {
    test('keeps every type, and leaves device-only settings out', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'name': 'Abhishek',
        'wake': 390,
        'ratio': 1.5,
        'on': true,
        'list': <String>['a', 'b'],
        'google_accounts': '[{"email":"me@gmail.com"}]',
      });
      final SharedPreferences p = await SharedPreferences.getInstance();
      final String body = buildSnapshot(p, DateTime.utc(2026, 10, 23, 8));
      expect(body, isNot(contains('me@gmail.com')));
      final Map<String, Object> back = parseSnapshot(body);
      expect(back, <String, Object>{'name': 'Abhishek', 'wake': 390, 'ratio': 1.5, 'on': true, 'list': <String>['a', 'b']});
    });

    test('restoring replaces what was there but keeps this phone\'s linked accounts', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'old': 'gone', 'google_accounts': 'keep me', 'n': 1});
      final SharedPreferences p = await SharedPreferences.getInstance();
      await applySnapshot(p, <String, Object>{'n': 2, 'fresh': <String>['x'], 'flag': true});
      expect(p.getKeys(), <String>{'google_accounts', 'n', 'fresh', 'flag'});
      expect(p.getString('google_accounts'), 'keep me');
      expect(p.getInt('n'), 2);
      expect(p.getStringList('fresh'), <String>['x']);
    });

    test('a file that is not a VIGIL backup is refused', () {
      for (final String bad in <String>['{not json', '[]', '{"app":"other","prefs":{}}', '{"app":"vigil"}']) {
        expect(() => parseSnapshot(bad), throwsA(isA<DriveException>().having((DriveException e) => e.message, 'message', 'That file is not a VIGIL backup.')), reason: bad);
      }
    });
  });

  group('DriveApi', () {
    test('finds the newest backup in the private app folder', () async {
      late http.Request seen;
      final MockClient client = MockClient((http.Request r) async {
        seen = r;
        return json(200, <String, dynamic>{
          'files': <Map<String, String>>[
            <String, String>{'id': 'f1', 'modifiedTime': '2026-10-23T08:00:00.000Z'},
          ],
        });
      });
      final DriveFile? f = await DriveApi('tok', client: client).latest();
      expect(f!.id, 'f1');
      expect(f.modified.toUtc(), DateTime.utc(2026, 10, 23, 8));
      expect(seen.url.queryParameters['spaces'], 'appDataFolder');
      expect(seen.url.queryParameters['q'], contains(kBackupName));
      expect(seen.headers['authorization'], 'Bearer tok');
    });

    test('no backup yet is null', () async {
      final MockClient client = MockClient((http.Request r) async => json(200, <String, dynamic>{'files': <dynamic>[]}));
      expect(await DriveApi('t', client: client).latest(), isNull);
    });

    test('the first upload creates the file inside the app folder', () async {
      late http.Request seen;
      final MockClient client = MockClient((http.Request r) async {
        seen = r;
        return json(200, <String, dynamic>{'id': 'new1', 'modifiedTime': '2026-10-23T09:00:00.000Z'});
      });
      final DriveFile f = await DriveApi('tok', client: client).upload('{"app":"vigil"}');
      expect(f.id, 'new1');
      expect(seen.method, 'POST');
      expect(seen.url.path, '/upload/drive/v3/files');
      expect(seen.url.queryParameters['uploadType'], 'multipart');
      expect(seen.headers['content-type'], startsWith('multipart/related; boundary='));
      expect(seen.body, contains('"parents":["appDataFolder"]'));
      expect(seen.body, contains('"name":"$kBackupName"'));
      expect(seen.body, contains('{"app":"vigil"}'));
    });

    test('later uploads overwrite the same file', () async {
      late http.Request seen;
      final MockClient client = MockClient((http.Request r) async {
        seen = r;
        return json(200, <String, dynamic>{'id': 'f1', 'modifiedTime': '2026-10-23T10:00:00.000Z'});
      });
      await DriveApi('tok', client: client).upload('{"a":1}', existingId: 'f1');
      expect(seen.method, 'PATCH');
      expect(seen.url.path, '/upload/drive/v3/files/f1');
      expect(seen.body, '{"a":1}');
    });

    test('Google\'s message comes through, and a network failure is explained', () async {
      final MockClient off = MockClient((http.Request r) async => throw http.ClientException('offline'));
      await expectLater(DriveApi('t', client: off).latest(), throwsA(isA<DriveException>().having((DriveException e) => e.message, 'message', startsWith('Could not reach Google Drive'))));
      final MockClient bad = MockClient((http.Request r) async => json(403, <String, dynamic>{
            'error': <String, dynamic>{'message': 'Google Drive API has not been used in project 1 before or it is disabled.'},
          }));
      await expectLater(DriveApi('t', client: bad).download('x'), throwsA(isA<DriveException>().having((DriveException e) => e.message, 'message', startsWith('HTTP 403: Google Drive API has not been used'))));
    });
  });

  group('backup and restore', () {
    late VigilStore store;
    late FakeGoogle platform;
    late GoogleAccounts accounts;
    late GoogleAccount account;

    setUp(() async {
      store = await VigilStore.load();
      platform = FakeGoogle(picks: <String?>['me@gmail.com'], auth: <String, AuthResult>{'me@gmail.com': tokenFor('cal')});
      platform.driveAuth['me@gmail.com'] = tokenFor('drv');
      accounts = GoogleAccounts(platform: platform);
      await accounts.link(0);
      account = accounts.bySlot(0)!;
    });

    test('backs up, then restores onto a clean phone', () async {
      store.addProtocol('Read 20 pages');
      store.setBudget(4000000);
      String? stored;
      final MockClient drive = MockClient((http.Request r) async {
        expect(r.headers['authorization'], 'Bearer drv', reason: 'the Drive scope token, not the calendar one');
        if (r.method == 'GET' && r.url.queryParameters['alt'] == 'media') return http.Response(stored!, 200);
        if (r.method == 'GET') {
          return json(200, <String, dynamic>{
            'files': stored == null ? <dynamic>[] : <Map<String, String>>[<String, String>{'id': 'f1', 'modifiedTime': '2026-10-23T08:00:00.000Z'}],
          });
        }
        if (r.method == 'POST') {
          final String part = r.body.split('--vigil_backup_boundary_7f3a91')[2]; // metadata part, then the content part
          stored = part.substring(part.indexOf('\r\n\r\n') + 4).trimRight();
        } else {
          stored = r.body;
        }
        return json(200, <String, dynamic>{'id': 'f1', 'modifiedTime': '2026-10-23T08:00:00.000Z'});
      });

      final DriveFile saved = await backupToDrive(store, accounts, account, client: drive);
      expect(saved.id, 'f1');
      expect(store.prefs.getInt('driveBackupAt'), isNotNull);
      expect(platform.scopesAsked.last, <String>[kDriveScope]);

      // A clean phone: wipe, then restore.
      await store.eraseAll();
      expect(store.protocols, isEmpty);
      expect(store.monthBudgetPaise, 0);

      final DriveFile? latest = await latestBackup(accounts, account, client: drive);
      await restoreFromDrive(store, accounts, account, latest!, client: drive);
      expect(store.protocols.map((Protocol p) => p.name), <String>['Read 20 pages']);
      expect(store.monthBudgetPaise, 4000000);
    });

    test('Drive approval is asked for only when it has not been given', () async {
      platform.driveAuth['me@gmail.com'] = const AuthResult(AuthStatus.consentNeeded);
      final MockClient drive = MockClient((http.Request r) async => json(200, <String, dynamic>{'files': <dynamic>[]}));
      await expectLater(latestBackup(accounts, account, client: drive), throwsA(isA<DriveException>()));
      // silent first, then the interactive request
      expect(platform.interactiveCalls.sublist(platform.interactiveCalls.length - 2), <bool>[false, true]);
    });

    test('a bad file is refused before anything is erased', () async {
      store.addProtocol('Keep me');
      final MockClient drive = MockClient((http.Request r) async => http.Response('{"hello":"world"}', 200));
      await expectLater(restoreFromDrive(store, accounts, account, DriveFile('f1', DateTime.now()), client: drive), throwsA(isA<DriveException>()));
      expect(store.protocols.single.name, 'Keep me');
    });
  });
}
