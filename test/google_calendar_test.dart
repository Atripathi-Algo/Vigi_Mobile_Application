import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigil/api/calendar_api.dart';
import 'package:vigil/data/models.dart';
import 'package:vigil/data/store.dart';
import 'package:vigil/services/calendar_sync.dart';
import 'package:vigil/services/google_accounts.dart';

class FakeGoogle implements GoogleAuthPlatform {
  FakeGoogle({List<String?>? picks, Map<String, AuthResult>? auth})
      : picks = picks ?? <String?>[],
        auth = auth ?? <String, AuthResult>{};

  final List<String?> picks;
  final Map<String, AuthResult> auth;
  final List<String> revoked = <String>[];
  final List<bool> interactiveCalls = <bool>[];
  bool playServices = true;

  @override
  Future<bool> available() async => playServices;

  @override
  Future<String?> signingSha1() async => 'AA:BB';

  @override
  Future<String?> pickAccount() async => picks.isEmpty ? null : picks.removeAt(0);

  @override
  Future<AuthResult> authorize(String email, {required bool interactive}) async {
    interactiveCalls.add(interactive);
    return auth[email] ?? const AuthResult(AuthStatus.error, message: 'no such account');
  }

  @override
  Future<void> revoke(String email) async => revoked.add(email);
}

AuthResult tokenFor(String t) => AuthResult(AuthStatus.ok, token: t);

http.Response json(int code, Object body) => http.Response(jsonEncode(body), code, headers: <String, String>{'content-type': 'application/json'});

/// A Calendar API item at [hour]:[min] today for [mins] minutes.
Map<String, dynamic> item(String title, int hour, int min, int mins, {String? uid, String? status, List<Map<String, dynamic>>? attendees, bool allDay = false}) {
  final DateTime n = DateTime.now();
  final DateTime s = DateTime(n.year, n.month, n.day, hour, min);
  return <String, dynamic>{
    'summary': title,
    if (uid != null) 'iCalUID': uid,
    if (status != null) 'status': status,
    if (attendees != null) 'attendees': attendees,
    'start': allDay ? <String, String>{'date': '2026-01-01'} : <String, String>{'dateTime': s.toUtc().toIso8601String()},
    'end': allDay ? <String, String>{'date': '2026-01-02'} : <String, String>{'dateTime': s.add(Duration(minutes: mins)).toUtc().toIso8601String()},
  };
}

String listBody(List<Map<String, dynamic>> items) => jsonEncode(<String, dynamic>{'items': items});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dotenv.testLoad(fileInput: '');
  });

  group('parseCalendarEvents', () {
    test('keeps timed events with their uid and account, and drops the rest', () {
      final List<RemoteEvent> r = parseCalendarEvents(
        listBody(<Map<String, dynamic>>[
          item('Standup', 10, 0, 30, uid: 'u1'),
          item('Holiday', 0, 0, 0, allDay: true),
          item('Cancelled', 11, 0, 30, status: 'cancelled'),
          item('Declined', 12, 0, 30, attendees: <Map<String, dynamic>>[
            <String, dynamic>{'self': true, 'responseStatus': 'declined'},
          ]),
          item('Accepted', 13, 0, 30, attendees: <Map<String, dynamic>>[
            <String, dynamic>{'self': true, 'responseStatus': 'accepted'},
            <String, dynamic>{'responseStatus': 'declined'},
          ]),
        ]),
        account: 'WORK',
      );
      expect(r.map((RemoteEvent e) => e.title), <String>['Standup', 'Accepted']);
      expect(r.first.uid, 'u1');
      expect(r.first.account, 'WORK');
      expect(r.first.start.hour, 10);
      expect(r.first.end.difference(r.first.start), const Duration(minutes: 30));
    });

    test('an event with no title is called Event', () {
      final Map<String, dynamic> e = item('x', 9, 0, 15)..remove('summary');
      expect(parseCalendarEvents(listBody(<Map<String, dynamic>>[e])).single.title, 'Event');
    });
  });

  group('dedupeEvents', () {
    DateTime at(int h) => DateTime(2026, 10, 23, h);

    test('the same meeting in both accounts shows once, tagged with both', () {
      final List<RemoteEvent> r = dedupeEvents(<RemoteEvent>[
        RemoteEvent('Review', at(11), at(12), uid: 'same', account: 'PERSONAL'),
        RemoteEvent('Review', at(11), at(12), uid: 'same', account: 'WORK'),
        RemoteEvent('Gym', at(7), at(8), uid: 'g', account: 'PERSONAL'),
      ]);
      expect(r.map((RemoteEvent e) => '${e.title}:${e.account}'), <String>['Gym:PERSONAL', 'Review:PERSONAL+WORK']);
    });

    test('without a uid, title and times decide', () {
      final List<RemoteEvent> r = dedupeEvents(<RemoteEvent>[
        RemoteEvent('Call', at(9), at(10), account: 'A'),
        RemoteEvent('Call', at(9), at(10), account: 'B'),
        RemoteEvent('Call', at(14), at(15), account: 'B'),
      ]);
      expect(r.length, 2);
      expect(r.first.account, 'A+B');
    });

    test('two different events at the same time are both kept', () {
      expect(dedupeEvents(<RemoteEvent>[
        RemoteEvent('One', at(9), at(10), uid: '1', account: 'A'),
        RemoteEvent('Two', at(9), at(10), uid: '2', account: 'B'),
      ]).length, 2);
    });
  });

  group('Calendar API', () {
    test('lists today from the primary calendar with a bearer token and no key in the URL', () async {
      late http.Request seen;
      final MockClient client = MockClient((http.Request r) async {
        seen = r;
        return http.Response(listBody(<Map<String, dynamic>>[item('Standup', 10, 0, 30)]), 200);
      });
      final List<RemoteEvent> r = await fetchAccountEvents('tok', DateTime.now(), account: 'WORK', client: client);
      expect(r.single.account, 'WORK');
      expect(seen.url.path, '/calendar/v3/calendars/primary/events');
      expect(seen.headers['authorization'], 'Bearer tok');
      expect(seen.url.queryParameters['singleEvents'], 'true');
      expect(seen.url.queryParameters.containsKey('key'), isFalse);
      final DateTime min = DateTime.parse(seen.url.queryParameters['timeMin']!);
      final DateTime max = DateTime.parse(seen.url.queryParameters['timeMax']!);
      expect(max.difference(min).inHours, inInclusiveRange(23, 25), reason: 'one local day');
    });

    test('an error carries Google\'s message', () async {
      final MockClient client = MockClient((http.Request r) async => json(403, <String, dynamic>{
            'error': <String, dynamic>{'message': 'Google Calendar API has not been used in project 123 before or it is disabled.'},
          }));
      await expectLater(
        fetchAccountEvents('tok', DateTime.now(), client: client),
        throwsA(isA<CalendarApiException>().having((CalendarApiException e) => e.message, 'message', startsWith('HTTP 403: Google Calendar API has not been used'))),
      );
    });

    test('a network failure becomes a message', () async {
      final MockClient client = MockClient((http.Request r) async => throw http.ClientException('offline'));
      await expectLater(fetchAccountEvents('t', DateTime.now(), client: client), throwsA(isA<CalendarApiException>().having((CalendarApiException e) => e.message, 'message', startsWith('Could not reach Google'))));
    });

    test('creates an event with UTC times and returns its id', () async {
      late http.Request seen;
      final MockClient client = MockClient((http.Request r) async {
        seen = r;
        return json(200, <String, dynamic>{'id': 'evt1'});
      });
      final DateTime start = DateTime(2026, 10, 23, 15);
      final String id = await createCalendarEvent('tok', title: 'Dentist', start: start, end: start.add(const Duration(minutes: 45)), client: client);
      expect(id, 'evt1');
      expect(seen.method, 'POST');
      expect(seen.url.path, '/calendar/v3/calendars/primary/events');
      expect(seen.headers['authorization'], 'Bearer tok');
      final Map<String, dynamic> body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['summary'], 'Dentist');
      expect(DateTime.parse(body['start']['dateTime'] as String).isUtc, isTrue);
      expect(DateTime.parse(body['end']['dateTime'] as String).difference(DateTime.parse(body['start']['dateTime'] as String)), const Duration(minutes: 45));
    });
  });

  group('GoogleAccounts', () {
    test('links an account into the first slot, persists it, and reloads', () async {
      final FakeGoogle p = FakeGoogle(picks: <String?>['me@gmail.com'], auth: <String, AuthResult>{'me@gmail.com': tokenFor('t')});
      final GoogleAccounts g = GoogleAccounts(platform: p);
      expect(await g.link(0), isNull);
      expect(g.bySlot(0)!.label, 'PERSONAL');
      expect(p.interactiveCalls, <bool>[true]);

      final GoogleAccounts again = GoogleAccounts(platform: p);
      await again.load();
      expect(again.accounts.single.email, 'me@gmail.com');
    });

    test('two accounts, and the same one cannot take both slots', () async {
      final FakeGoogle p = FakeGoogle(
        picks: <String?>['a@gmail.com', 'A@gmail.com', 'b@work.com'],
        auth: <String, AuthResult>{'a@gmail.com': tokenFor('ta'), 'A@gmail.com': tokenFor('ta'), 'b@work.com': tokenFor('tb')},
      );
      final GoogleAccounts g = GoogleAccounts(platform: p);
      expect(await g.link(0), isNull);
      expect(await g.link(1), 'A@gmail.com is already linked as PERSONAL.');
      expect(await g.link(1), isNull);
      expect(g.accounts.map((GoogleAccount a) => '${a.slot}:${a.label}:${a.email}'), <String>['0:PERSONAL:a@gmail.com', '1:WORK:b@work.com']);
      expect(await g.link(2), 'Only two accounts can be linked.');
    });

    test('backing out, no Play services, and a refused approval link nothing', () async {
      final FakeGoogle p = FakeGoogle(picks: <String?>[null, 'x@gmail.com'], auth: <String, AuthResult>{'x@gmail.com': const AuthResult(AuthStatus.cancelled)});
      final GoogleAccounts g = GoogleAccounts(platform: p);
      expect(await g.link(0), 'No account chosen.');
      expect(await g.link(0), 'Cancelled. Nothing was linked.');
      expect(g.hasAny, isFalse);

      final FakeGoogle none = FakeGoogle()..playServices = false;
      expect(await GoogleAccounts(platform: none).link(0), 'Google Play services is not available on this phone.');
    });

    test('unlinking revokes access and removes the account', () async {
      final FakeGoogle p = FakeGoogle(picks: <String?>['me@gmail.com'], auth: <String, AuthResult>{'me@gmail.com': tokenFor('t')});
      final GoogleAccounts g = GoogleAccounts(platform: p);
      await g.link(0);
      await g.unlink(0);
      expect(g.hasAny, isFalse);
      expect(p.revoked, <String>['me@gmail.com']);
      final GoogleAccounts reloaded = GoogleAccounts(platform: p);
      await reloaded.load();
      expect(reloaded.hasAny, isFalse, reason: 'the removal was saved');
    });

    test('a token is fetched silently; a lapsed approval is flagged on the account', () async {
      final FakeGoogle p = FakeGoogle(picks: <String?>['me@gmail.com'], auth: <String, AuthResult>{'me@gmail.com': tokenFor('t1')});
      final GoogleAccounts g = GoogleAccounts(platform: p);
      await g.link(0);
      final GoogleAccount a = g.bySlot(0)!;
      expect(await g.token(a), 't1');
      expect(p.interactiveCalls.last, isFalse, reason: 'background syncs never open a screen');
      expect(g.noteOf(a), isNull);

      p.auth['me@gmail.com'] = const AuthResult(AuthStatus.consentNeeded);
      expect(await g.token(a), isNull);
      expect(g.noteOf(a), startsWith('Approve again'));

      p.auth['me@gmail.com'] = tokenFor('t2');
      expect(await g.token(a), 't2');
      expect(g.noteOf(a), isNull, reason: 'cleared once it works again');
    });

    test('an unreadable saved list starts clean instead of crashing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'google_accounts': '{not json'});
      final GoogleAccounts g = GoogleAccounts(platform: FakeGoogle());
      await g.load();
      expect(g.hasAny, isFalse);
    });

    test('Google errors are explained in plain words', () {
      expect(explainAuthError(const AuthResult(AuthStatus.error, message: '10: ')), contains('SHA-1'));
      expect(explainAuthError(const AuthResult(AuthStatus.error, message: '10: ')), contains(kAppPackage));
      expect(explainAuthError(const AuthResult(AuthStatus.error, message: '7: network error')), startsWith('No connection'));
      expect(explainAuthError(const AuthResult(AuthStatus.error, message: 'access_denied')), contains('Test user'));
      expect(explainAuthError(const AuthResult(AuthStatus.error, message: 'boom')), 'Google said: boom');
      expect(explainAuthError(const AuthResult(AuthStatus.error)), 'Google sign-in failed.');
    });
  });

  group('syncCalendars', () {
    late VigilStore store;
    late FakeGoogle platform;
    late GoogleAccounts accounts;

    Future<void> twoAccounts() async {
      platform = FakeGoogle(
        picks: <String?>['me@gmail.com', 'me@work.com'],
        auth: <String, AuthResult>{'me@gmail.com': tokenFor('tp'), 'me@work.com': tokenFor('tw')},
      );
      accounts = GoogleAccounts(platform: platform);
      await accounts.link(0);
      await accounts.link(1);
    }

    MockClient calendars(Map<String, List<Map<String, dynamic>>> byToken, {Set<String> failing = const <String>{}}) => MockClient((http.Request r) async {
          final String token = r.headers['authorization']!.replaceFirst('Bearer ', '');
          if (failing.contains(token)) return json(500, <String, dynamic>{'error': <String, dynamic>{'message': 'backend error'}});
          return http.Response(listBody(byToken[token] ?? <Map<String, dynamic>>[]), 200);
        });

    List<Block> pulled() => store.todayBlocks.where((Block b) => b.id.startsWith('g:')).toList();

    setUp(() async {
      store = await VigilStore.load();
    });

    test('merges both accounts, shows a shared meeting once, and tags each event', () async {
      await twoAccounts();
      final MockClient client = calendars(<String, List<Map<String, dynamic>>>{
        'tp': <Map<String, dynamic>>[item('Dentist', 10, 0, 60, uid: 'd'), item('Review', 14, 0, 60, uid: 'shared')],
        'tw': <Map<String, dynamic>>[item('Standup', 9, 0, 15, uid: 's'), item('Review', 14, 0, 60, uid: 'shared')],
      });
      final CalendarSyncResult r = await syncCalendars(store, accounts: accounts, client: client);
      expect(r.errors, isEmpty);
      expect(r.sources, 2);
      expect(pulled().map((Block b) => '${b.title}:${b.src}').toList(), unorderedEquals(<String>['Dentist:PERSONAL', 'Standup:WORK', 'Review:PERSONAL+WORK']));
      expect(store.linkStatus['Calendar link'], 'OK');
    });

    test('an overlap between the two accounts is a conflict that names both', () async {
      await twoAccounts();
      final MockClient client = calendars(<String, List<Map<String, dynamic>>>{
        'tp': <Map<String, dynamic>>[item('Dentist', 10, 0, 60, uid: 'd')],
        'tw': <Map<String, dynamic>>[item('Client call', 10, 30, 60, uid: 'c')],
      });
      await syncCalendars(store, accounts: accounts, client: client);
      final List<Block> p = pulled()..sort((Block a, Block b) => a.startMin.compareTo(b.startMin));
      expect(p.length, 2);
      expect(p.first.overlaps(p.last), isTrue);
      expect(p.first.clashWith(p.last), 'PERSONAL × WORK');
      expect(p.first.clashWith(p.first), isNull);
    });

    test('the same meeting in both accounts does not clash with itself', () async {
      await twoAccounts();
      final MockClient client = calendars(<String, List<Map<String, dynamic>>>{
        'tp': <Map<String, dynamic>>[item('Review', 14, 0, 60, uid: 'shared')],
        'tw': <Map<String, dynamic>>[item('Review', 14, 0, 60, uid: 'shared')],
      });
      await syncCalendars(store, accounts: accounts, client: client);
      expect(pulled().length, 1);
    });

    test('an account that fails keeps its last events; the other refreshes', () async {
      await twoAccounts();
      await syncCalendars(
        store,
        accounts: accounts,
        client: calendars(<String, List<Map<String, dynamic>>>{
          'tp': <Map<String, dynamic>>[item('Dentist', 10, 0, 60, uid: 'd')],
          'tw': <Map<String, dynamic>>[item('Standup', 9, 0, 15, uid: 's')],
        }),
      );
      final CalendarSyncResult r = await syncCalendars(
        store,
        accounts: accounts,
        client: calendars(<String, List<Map<String, dynamic>>>{
          'tp': <Map<String, dynamic>>[item('Dentist moved', 11, 0, 60, uid: 'd')],
        }, failing: <String>{'tw'}),
      );
      expect(r.errors.keys, <String>['WORK']);
      expect(r.errors['WORK'], 'HTTP 500: backend error');
      expect(r.anyOk, isTrue);
      expect(pulled().map((Block b) => b.title), unorderedEquals(<String>['Dentist moved', 'Standup']));
    });

    test('when every source fails the Timeline keeps what it had', () async {
      await twoAccounts();
      await syncCalendars(store, accounts: accounts, client: calendars(<String, List<Map<String, dynamic>>>{
        'tp': <Map<String, dynamic>>[item('Dentist', 10, 0, 60, uid: 'd')],
      }));
      final CalendarSyncResult r = await syncCalendars(store, accounts: accounts, client: calendars(<String, List<Map<String, dynamic>>>{}, failing: <String>{'tp', 'tw'}));
      expect(r.anyOk, isFalse);
      expect(r.events, 0);
      expect(pulled().map((Block b) => b.title), <String>['Dentist']);
    });

    test('an account whose approval lapsed is reported without calling Google', () async {
      await twoAccounts();
      platform.auth['me@work.com'] = const AuthResult(AuthStatus.consentNeeded);
      int calls = 0;
      final MockClient client = MockClient((http.Request r) async {
        calls++;
        return http.Response(listBody(<Map<String, dynamic>>[]), 200);
      });
      final CalendarSyncResult r = await syncCalendars(store, accounts: accounts, client: client);
      expect(calls, 1, reason: 'only the account that still has a token is queried');
      expect(r.errors['WORK'], startsWith('Approve again'));
    });

    test('with nothing linked it does nothing', () async {
      final CalendarSyncResult r = await syncCalendars(store, accounts: GoogleAccounts(platform: FakeGoogle()), client: calendars(<String, List<Map<String, dynamic>>>{}));
      expect(r.sources, 0);
      expect(r.summary, 'No calendar linked.');
      expect(pulled(), isEmpty);
    });

    test('pulled events survive a restart with their source', () async {
      await twoAccounts();
      await syncCalendars(store, accounts: accounts, client: calendars(<String, List<Map<String, dynamic>>>{
        'tp': <Map<String, dynamic>>[item('Dentist', 10, 0, 60, uid: 'd')],
      }));
      final VigilStore reloaded = await VigilStore.load();
      expect(reloaded.todayBlocks.where((Block b) => b.id.startsWith('g:')).single.src, 'PERSONAL');
    });

    test('a block sent to Google is removed locally so it is not shown twice', () async {
      store.removeBlock('does-not-exist'); // harmless
      final int before = store.todayBlocks.length;
      final Block b = Block(id: 'u:1', kind: BlockKind.event, title: 'Dentist', startMin: 600, endMin: 660, dayKey: VigilStore.dayKey(DateTime.now()));
      store.blocks.add(b);
      expect(store.todayBlocks.length, before + 1);
      store.removeBlock('u:1');
      expect(store.todayBlocks.length, before);
    });
  });
}
