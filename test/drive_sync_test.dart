import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigil/data/models.dart';
import 'package:vigil/data/store.dart';
import 'package:vigil/services/drive_backup.dart';
import 'package:vigil/services/drive_sync.dart';
import 'package:vigil/services/google_accounts.dart';

import 'support/fake_google.dart';

class FakeNetwork implements NetworkProbe {
  bool isOnline = true;
  bool isWifi = true;

  @override
  Future<bool> online() async => isOnline;

  @override
  Future<bool> onWifi() async => isWifi;
}

/// A tiny Google Drive: one backup file in the app folder.
class FakeDrive {
  String? content;
  DateTime modified = DateTime.utc(2026, 10, 28, 10);
  int uploads = 0;
  int downloads = 0;
  int lists = 0;
  bool deleted = false;

  void _tick() => modified = modified.add(const Duration(minutes: 1));

  /// Another phone saved [values] to this Drive.
  void otherPhoneSaved(Map<String, Object> values) {
    content = encodeSnapshot(values, DateTime.now());
    _tick();
  }

  String _meta() => jsonEncode(<String, String>{'id': 'f1', 'modifiedTime': modified.toIso8601String(), 'size': '${content!.length}'});

  MockClient get client => MockClient((http.Request r) async {
        if (r.method == 'DELETE') {
          content = null;
          deleted = true;
          return http.Response('', 204);
        }
        if (r.method == 'GET' && r.url.queryParameters['alt'] == 'media') {
          downloads++;
          return http.Response(content!, 200);
        }
        if (r.method == 'GET') {
          lists++;
          return http.Response(jsonEncode(<String, dynamic>{'files': content == null ? <dynamic>[] : <dynamic>[jsonDecode(_meta())]}), 200);
        }
        uploads++;
        if (r.method == 'POST') {
          final String part = r.body.split('--k_backup_boundary_7f3a91')[2];
          content = part.substring(part.indexOf('\r\n\r\n') + 4).trimRight();
        } else {
          content = r.body;
        }
        _tick();
        return http.Response(_meta(), 200);
      });
}

Future<VigilStore> freshPhone() async {
  SharedPreferences.resetStatic();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return VigilStore.load();
}

void main() {
  late VigilStore store;
  late FakeGoogle platform;
  late GoogleAccounts accounts;
  late GoogleAccount account;
  late FakeDrive drive;
  late FakeNetwork net;

  DriveSync makeSync() => DriveSync(accounts: accounts, network: net, client: drive.client, debounce: const Duration(milliseconds: 20), minGap: Duration.zero);

  setUp(() async {
    store = await freshPhone();
    platform = FakeGoogle(picks: <String?>['me@gmail.com'], auth: <String, AuthResult>{'me@gmail.com': tokenFor('cal')});
    platform.driveAuth['me@gmail.com'] = tokenFor('drv');
    accounts = GoogleAccounts(platform: platform);
    await accounts.link(0);
    account = accounts.bySlot(0)!;
    drive = FakeDrive();
    net = FakeNetwork();
  });

  group('auto-sync', () {
    test('a change is uploaded a few seconds later, and only when something really changed', () async {
      final DriveSync sync = makeSync()..attach(store);
      await sync.enable(account);
      expect(sync.state, SyncState.synced);
      expect(drive.uploads, 1, reason: 'the first sync saves the starting point');

      store.addProtocol('Read 20 pages');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(drive.uploads, 2);
      expect(jsonDecode(drive.content!)['prefs']['protocols'], contains('Read 20 pages'));

      store.changed(); // nothing different
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(drive.uploads, 2, reason: 'no change, no upload, no network');
      expect(sync.statusText(), startsWith('Synced'));
    });

    test('several quick changes become one upload', () async {
      final DriveSync sync = makeSync()..attach(store);
      await sync.enable(account);
      final int before = drive.uploads;
      store.addProtocol('One');
      store.addProtocol('Two');
      store.setBudget(4000000);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(drive.uploads, before + 1);
    });

    test('Wi-Fi only waits for Wi-Fi, and offline waits for a network', () async {
      final DriveSync sync = makeSync()..attach(store);
      await sync.enable(account);
      final int base = drive.uploads;
      net.isWifi = false;
      store.addProtocol('Read');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect((sync.state, sync.error), (SyncState.offline, 'Waiting for Wi-Fi.'));
      expect(drive.uploads, base);

      net.isWifi = true;
      await sync.syncNow(checkRemote: false);
      expect(sync.state, SyncState.synced);
      expect(drive.uploads, base + 1);

      net.isOnline = false;
      store.addProtocol('Stretch');
      await sync.syncNow(checkRemote: false);
      expect(sync.state, SyncState.offline);
      expect(sync.statusText(), 'Offline · will sync later');
    });

    test('switching Wi-Fi only off lets it use any connection', () async {
      final DriveSync sync = makeSync()..attach(store);
      await sync.enable(account);
      await sync.setWifiOnly(false);
      net.isWifi = false;
      store.addProtocol('Read');
      await sync.syncNow(checkRemote: false);
      expect(sync.state, SyncState.synced);
    });

    test('a lapsed Google approval asks to sign in again instead of failing quietly', () async {
      final DriveSync sync = makeSync()..attach(store);
      await sync.enable(account);
      platform.driveAuth['me@gmail.com'] = const AuthResult(AuthStatus.consentNeeded);
      platform.interactiveCalls.clear();
      store.addProtocol('Read');
      await sync.syncNow(checkRemote: false);
      expect(sync.state, SyncState.signIn);
      expect(sync.statusText(), 'Sign in to back up');
      expect(platform.interactiveCalls.where((bool b) => b), isEmpty, reason: 'background sync never opens Google\'s screen');
    });

    test('a Drive error is shown as a failed sync', () async {
      final DriveSync sync = DriveSync(accounts: accounts, network: net, client: MockClient((http.Request r) async => http.Response('{"error":{"message":"boom"}}', 500)), debounce: const Duration(milliseconds: 20))..attach(store);
      await sync.enable(account);
      expect(sync.state, SyncState.failed);
      expect(sync.error, contains('HTTP 500'));
      expect(sync.statusText(), 'Sync failed · retry');
    });

    test('auto-sync off stops uploads, and Back up now still works', () async {
      final DriveSync sync = makeSync()..attach(store);
      await sync.enable(account);
      await sync.setAutoSync(false);
      final int base = drive.uploads;
      store.addProtocol('Read');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(drive.uploads, base);
      expect(sync.state, SyncState.off);
      await sync.backupNow();
      expect(drive.uploads, base + 1);
    });
  });

  group('a second phone', () {
    test('a new phone takes the backup, and then follows later changes from the first', () async {
      final DriveSync first = makeSync()..attach(store);
      await first.enable(account);
      store.addProtocol('Read 20 pages');
      store.logWater(500);
      await first.syncNow(checkRemote: false);
      final String saved = drive.content!;

      // a fresh phone, same Google account
      final VigilStore second = await freshPhone();
      final DriveSync sync2 = makeSync()..attach(second);
      await sync2.enable(account);
      expect(second.protocols.single.name, 'Read 20 pages');
      expect(second.waterMl, 500);
      expect(drive.content, saved, reason: 'taking the backup does not rewrite it');
      expect(sync2.state, SyncState.synced);
    });

    test('newer data from another phone is taken when this phone has no changes of its own', () async {
      final DriveSync sync = makeSync()..attach(store);
      await sync.enable(account);
      final Map<String, Object> theirs = <String, Object>{...snapshotValues(store.prefs), 'budget': 4200000};
      drive.otherPhoneSaved(theirs);
      await sync.syncNow();
      expect(store.monthBudgetPaise, 4200000);
      expect(sync.state, SyncState.synced);
    });
  });

  group('setup guide paths', () {
    test('start fresh: this phone replaces the backup at the first sync instead of being replaced by it', () async {
      final VigilStore other = await freshPhone();
      other.addProtocol('Theirs');
      drive.otherPhoneSaved(snapshotValues(other.prefs));
      store = await freshPhone();
      final DriveSync sync = makeSync()..attach(store);
      await sync.choose(account);
      final DriveFile existing = DriveFile('f1', drive.modified);
      await sync.startFreshOver(existing);
      expect(store.protocols, isEmpty);
      expect(jsonDecode(drive.content!)['prefs'].containsKey('protocols') ? jsonDecode(drive.content!)['prefs']['protocols'] : '', isNot(contains('Theirs')));
      expect(sync.state, SyncState.synced);
    });

    test('restore: choosing the account does not sync by itself, and restoring takes the backup', () async {
      final VigilStore other = await freshPhone();
      other.addProtocol('Theirs');
      drive.otherPhoneSaved(snapshotValues(other.prefs));
      store = await freshPhone();
      final DriveSync sync = makeSync()..attach(store);
      await sync.choose(account);
      expect(drive.lists, 0, reason: 'nothing is looked at until the user decides');
      await sync.restoreNow();
      expect(store.protocols.single.name, 'Theirs');
      expect(sync.state, SyncState.synced);
      final int uploads = drive.uploads;
      await sync.syncNow();
      expect(drive.uploads, uploads, reason: 'after a restore the two sides agree');
    });
  });

  group('conflict', () {
    late DriveSync sync;

    /// This phone has a protocol "Mine"; the other phone saved a budget and its own protocol list.
    Future<void> makeConflict() async {
      sync = makeSync()..attach(store);
      await sync.enable(account);
      store.addProtocol('Mine');
      final Map<String, Object> theirs = <String, Object>{
        ...snapshotValues(store.prefs),
        'budget': 4200000,
        'protocols': jsonEncode(<Map<String, dynamic>>[Protocol(id: 'theirs-1', name: 'Theirs', streak: 0, week: List<bool>.filled(7, false)).toJson()]),
      };
      drive.otherPhoneSaved(theirs);
      await sync.syncNow();
    }

    test('both changed: nothing is overwritten, and the user is asked', () async {
      await makeConflict();
      expect(sync.state, SyncState.conflict);
      expect(sync.conflict, isNotNull);
      expect(sync.statusText(), 'Sync paused');
      expect(store.protocols.map((Protocol p) => p.name), <String>['Mine']);
      expect(jsonDecode(drive.content!)['prefs']['protocols'], contains('Theirs'));
      final int uploads = drive.uploads;
      store.addProtocol('More');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(drive.uploads, uploads, reason: 'paused until the user chooses');
    });

    test('keep this phone: the backup becomes this phone\'s data', () async {
      await makeConflict();
      await sync.resolve(ConflictChoice.keepPhone);
      expect(sync.state, SyncState.synced);
      expect(store.protocols.map((Protocol p) => p.name), <String>['Mine']);
      expect(jsonDecode(drive.content!)['prefs']['protocols'], allOf(contains('Mine'), isNot(contains('Theirs'))));
    });

    test('use Drive: this phone becomes the backup', () async {
      await makeConflict();
      await sync.resolve(ConflictChoice.useDrive);
      expect(sync.state, SyncState.synced);
      expect(store.protocols.map((Protocol p) => p.name), <String>['Theirs']);
      expect(store.monthBudgetPaise, 4200000);
    });

    test('merge: both phones\' records are kept, and the result is saved to both', () async {
      await makeConflict();
      await sync.resolve(ConflictChoice.merge);
      expect(sync.state, SyncState.synced);
      expect(store.protocols.map((Protocol p) => p.name).toSet(), <String>{'Mine', 'Theirs'});
      expect(jsonDecode(drive.content!)['prefs']['protocols'], allOf(contains('Mine'), contains('Theirs')));
      expect(sync.conflict, isNull);
    });
  });

  group('delete and disconnect', () {
    test('deleting the backup removes the file and switches auto-sync off', () async {
      final DriveSync sync = makeSync()..attach(store);
      await sync.enable(account);
      expect(drive.content, isNotNull);
      await sync.deleteBackup();
      expect(drive.deleted, isTrue);
      expect(drive.content, isNull);
      expect((sync.autoSync, sync.state), (false, SyncState.off));
      store.addProtocol('Read');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(drive.content, isNull, reason: 'not recreated behind the user\'s back');
    });

    test('disconnect stops syncing and leaves the backup in Drive', () async {
      final DriveSync sync = makeSync()..attach(store);
      await sync.enable(account);
      await sync.disconnect();
      expect(sync.configured, isFalse);
      expect(drive.content, isNotNull);
      store.addProtocol('Read');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(jsonDecode(drive.content!)['prefs']['protocols'] ?? '', isNot(contains('Read')));
    });

    test('restore replaces this phone\'s data with the backup', () async {
      final DriveSync sync = makeSync()..attach(store);
      store.addProtocol('Read');
      await sync.enable(account);
      store.addProtocol('Local only');
      await sync.restoreNow();
      expect(store.protocols.map((Protocol p) => p.name), <String>['Read']);
    });
  });

  group('merge and fingerprint', () {
    String recs(List<String> ids) => jsonEncode(<Map<String, String>>[for (final String i in ids) <String, String>{'id': i, 'v': 'x'}]);

    test('records join by id; the newer side wins a clash; plain values take the newer side', () {
      final Map<String, Object> phone = <String, Object>{'objectives': jsonEncode(<Map<String, String>>[<String, String>{'id': 'a', 'v': 'phone'}, <String, String>{'id': 'b', 'v': 'phone'}]), 'water': 500, 'only': 'p'};
      final Map<String, Object> drive = <String, Object>{'objectives': jsonEncode(<Map<String, String>>[<String, String>{'id': 'a', 'v': 'drive'}, <String, String>{'id': 'c', 'v': 'drive'}]), 'water': 750, 'other': 'd'};
      final Map<String, Object> a = mergeValues(phone, drive, phoneNewer: true);
      final List<dynamic> ob = jsonDecode(a['objectives']! as String) as List<dynamic>;
      expect(ob.map((dynamic e) => '${e['id']}:${e['v']}').toList(), <String>['a:phone', 'b:phone', 'c:drive']);
      expect((a['water'], a['only'], a['other']), (500, 'p', 'd'));
      final Map<String, Object> b = mergeValues(phone, drive, phoneNewer: false);
      expect(((jsonDecode(b['objectives']! as String) as List<dynamic>).first as Map<String, dynamic>)['v'], 'drive');
      expect(b['water'], 750);
    });

    test('string lists are joined and records without ids fall back to the newer side', () {
      final Map<String, Object> m = mergeValues(<String, Object>{'tags': <String>['a', 'b'], 'blob': 'p'}, <String, Object>{'tags': <String>['b', 'c'], 'blob': 'd'}, phoneNewer: true);
      expect(m['tags'], <String>['a', 'b', 'c']);
      expect(m['blob'], 'p');
      expect(mergeValues(<String, Object>{'l': recs(<String>['a'])}, <String, Object>{'l': recs(<String>['a'])}, phoneNewer: true)['l'], recs(<String>['a']));
    });

    test('the fingerprint ignores the sensor and the clock, and notices real changes', () {
      final Map<String, Object> base = <String, Object>{'budget': 100, 'objectives': '[]'};
      final String h = snapshotHash(base);
      expect(snapshotHash(<String, Object>{...base, 'stepsToday': 4000, 'day': '2026-10-28'}), h);
      expect(snapshotHash(<String, Object>{...base, 'budget': 101}), isNot(h));
      expect(snapshotHash(<String, Object>{'objectives': '[]', 'budget': 100}), h, reason: 'order does not matter');
    });

    test('device settings are never in a backup', () {
      expect(snapshotValues(store.prefs).keys.where(kDeviceOnlyKeys.contains), isEmpty);
    });
  });

  group('the chat log', () {
    test('is saved, restored, and part of the backup', () async {
      store.chat
        ..add(ChatMsg(fromUser: true, text: 'log a glass of water', at: DateTime(2026, 10, 28, 9)))
        ..add(ChatMsg(fromUser: false, text: 'Logged 250 ml of water.', at: DateTime(2026, 10, 28, 9), source: ReplySource.instant, ms: 33, diff: <(String, String)>[('LOGGED', '+250 ml water')], undoable: true));
      store.chatChanged();
      expect(snapshotValues(store.prefs)['chat'], isNotNull);

      await store.reloadFromDisk();
      expect(store.chat.length, 2);
      final ChatMsg k = store.chat.last;
      expect((k.text, k.source, k.ms, k.undoable), ('Logged 250 ml of water.', ReplySource.instant, 33, false));
      expect(k.diff!.single, ('LOGGED', '+250 ml water'));
    });

    test('only the last messages are kept, and Erase all clears them', () async {
      for (int i = 0; i < VigilStore.kChatKept + 20; i++) {
        store.chat.add(ChatMsg(fromUser: i.isEven, text: 'm$i', at: DateTime(2026, 10, 28, 9, i % 60)));
      }
      store.chatChanged();
      await store.reloadFromDisk();
      expect(store.chat.length, VigilStore.kChatKept);
      expect(store.chat.last.text, 'm${VigilStore.kChatKept + 19}');
      await store.eraseAll();
      expect(store.chat, isEmpty);
    });
  });
}
