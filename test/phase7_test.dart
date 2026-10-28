import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigil/data/briefing_script.dart';
import 'package:vigil/data/inbox.dart';
import 'package:vigil/data/models.dart';
import 'package:vigil/data/store.dart';
import 'package:vigil/vigil/vigil.dart';

void main() {
  late VigilStore store;
  final DateTime evening = DateTime(2026, 10, 28, 19, 42);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = await VigilStore.load();
  });

  List<String> ids(List<InboxItem> l) => <String>[for (final InboxItem i in l) i.id];

  group('the inbox', () {
    test('a new phone has nothing in it before the morning', () {
      final List<InboxItem> items = loadInbox(store, DateTime(2026, 10, 28, 5, 0));
      expect(items, isEmpty);
      expect(unreadCount(store, DateTime(2026, 10, 28, 5, 0)), 0);
    });

    test('an overdue objective is shown with how late it is, and goes away once it is done', () {
      final Objective o = store.addObjective('Renew insurance', threat: Threat.crit, dueMin: 18 * 60, tag: 'HOME');
      final List<InboxItem> items = loadInbox(store, evening);
      final InboxItem it = items.firstWhere((InboxItem i) => i.kind == InboxKind.overdue);
      expect((it.title, it.body, it.threat, it.objectiveId), ('Overdue — Renew insurance', 'Due 18:00 · 1h 42m overdue', Threat.crit, o.id));
      store.toggleObjective(o.id, true);
      expect(loadInbox(store, evening).where((InboxItem i) => i.kind == InboxKind.overdue), isEmpty);
    });

    test('an unpaid bill past its date is shown until it is paid', () {
      store.addBill('Credit card', 842000, DateTime(2026, 10, 25));
      final InboxItem it = loadInbox(store, evening).firstWhere((InboxItem i) => i.kind == InboxKind.bill);
      expect(it.title, 'Bill overdue — Credit card ₹8,420');
      expect(it.route, '/vault/ledger');
      store.bills.single.paid = true;
      store.changed();
      expect(loadInbox(store, evening).where((InboxItem i) => i.kind == InboxKind.bill), isEmpty);
    });

    test('a streak at risk shows only in the evening', () {
      store.addProtocol('Hydrate');
      store.protocols.single.missedDays = 2;
      expect(loadInbox(store, DateTime(2026, 10, 28, 12, 0)).where((InboxItem i) => i.kind == InboxKind.streak), isEmpty);
      expect(loadInbox(store, evening).where((InboxItem i) => i.kind == InboxKind.streak).length, 1);
    });

    test('the dawn briefing appears after the wake time, and the debrief half an hour before bed', () {
      expect(ids(loadInbox(store, DateTime(2026, 10, 28, 6, 0))), isEmpty);
      expect(ids(loadInbox(store, DateTime(2026, 10, 28, 7, 0))), <String>['dawn:2026-10-28']);
      final List<InboxItem> late = loadInbox(store, DateTime(2026, 10, 28, 23, 0));
      expect(ids(late), <String>['debrief:2026-10-28', 'dawn:2026-10-28'], reason: 'newest first');
      expect(late.first.route, '/debrief');
    });

    test('yesterday\'s briefing is still there tomorrow, and nothing lasts past fourteen days', () {
      loadInbox(store, DateTime(2026, 10, 28, 7, 0));
      final List<InboxItem> next = loadInbox(store, DateTime(2026, 10, 29, 5, 0));
      expect(ids(next), <String>['dawn:2026-10-28']);
      expect(inboxGroup(next.single.at, DateTime(2026, 10, 29, 5, 0)), 'Yesterday');
      expect(loadInbox(store, DateTime(2026, 11, 13, 5, 0)), isEmpty, reason: 'more than fourteen days old');
    });

    test('a finished backup is listed once a day, with its time', () {
      final DateTime at = DateTime(2026, 10, 28, 19, 40);
      loadInbox(store, evening, lastBackup: DateTime(2026, 10, 28, 18, 0));
      final List<InboxItem> items = loadInbox(store, evening, lastBackup: at);
      final List<InboxItem> backups = items.where((InboxItem i) => i.kind == InboxKind.backup).toList();
      expect(backups.length, 1);
      expect(backups.single.body, 'Google Drive · everything up to 19:40');
    });

    test('reading and dismissing are remembered', () {
      store.addObjective('A', threat: Threat.high, dueMin: 600);
      store.addObjective('B', threat: Threat.high, dueMin: 610);
      final List<InboxItem> items = loadInbox(store, evening);
      final int base = items.length;
      expect(unreadCount(store, evening), base);
      markInboxRead(store, <String>[items.first.id]);
      expect(unreadCount(store, evening), base - 1);
      dismissInbox(store, items.last.id);
      expect(loadInbox(store, evening).length, base - 1);
      markInboxRead(store, loadInbox(store, evening).map((InboxItem i) => i.id));
      expect(unreadCount(store, evening), 0);
    });

    test('the log is saved with the other data, so a restart keeps it', () async {
      loadInbox(store, DateTime(2026, 10, 28, 7, 0));
      await store.reloadFromDisk();
      expect(ids(loadInbox(store, DateTime(2026, 10, 29, 5, 0))), <String>['dawn:2026-10-28']);
    });

    test('snoozing moves a timed objective later, and past midnight makes it tomorrow\'s', () {
      final Objective o = store.addObjective('Call', threat: Threat.high, dueMin: 600);
      final DateTime n = DateTime.now();
      store.snoozeObjective(o.id, 60);
      final int expected = n.hour * 60 + n.minute + 60;
      if (expected < 1440) {
        expect(o.dueMin, anyOf(expected, expected + 1));
      } else {
        expect((o.dueMin, o.dueLabel), (null, 'TOMORROW'));
      }
    });
  });

  group('what K says in the briefings', () {
    test('the dawn script is the real day, in plain sentences', () {
      store.completeBoot(name: 'Asha Rao', call: 'Ash', wake: 390, bed: 1380, armed: <String>{});
      store.addObjective('Renew insurance', threat: Threat.crit, dueMin: 9 * 60);
      store.addObjective('Buy floss');
      store.blocks.add(Block(id: 'e', kind: BlockKind.event, title: 'Client review', startMin: 10 * 60, endMin: 11 * 60));
      final String s = dawnScript(store, DateTime(2026, 10, 28, 6, 30));
      expect(s, startsWith('Morning, Ash.'));
      expect(s, contains('2 objectives open, 1 critical, and 1 event today.'));
      expect(s, contains('Start with Renew insurance, due at 09:00.'));
      expect(s, contains('First event: Client review at 10:00.'));
    });

    test('with nothing logged it says so without inventing anything, and never throws', () {
      final String s = dawnScript(store, DateTime(2026, 10, 28, 6, 30));
      expect(s, contains('0 objectives open.'));
      expect(s, isNot(contains('Start with')));
      expect(s, isNot(contains('slept')));
      final String n = nightScript(store, DateTime(2026, 10, 28, 22, 30));
      expect(n, startsWith('Stand down.'));
      expect(n, contains('0 objectives cleared, 0 still open.'));
      expect(n, isNot(contains('spent')));
    });

    test('the night script counts what was done and spent today', () {
      store.completeBoot(name: '', call: 'Ash', wake: 390, bed: 1380, armed: <String>{});
      final Objective a = store.addObjective('Pay bill');
      store.addObjective('Draft outline');
      store.toggleObjective(a.id, true);
      store.logWater(1500);
      final DateTime now = DateTime.now();
      store.txns.add(Txn(id: 't', title: 'Lunch', category: 'FOOD', paise: 25000, at: now));
      store.changed();
      final String s = nightScript(store, now);
      expect(s, contains('Stand down, Ash.'));
      expect(s, contains('1 objective cleared, 1 still open.'));
      expect(s, contains('Water 1.5 of 3.0 litres.'));
      expect(s, contains('You spent ₹250 today.'));
      expect(s, contains('First up tomorrow: Draft outline.'));
    });
  });
}
