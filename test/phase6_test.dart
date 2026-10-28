import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigil/data/models.dart';
import 'package:vigil/data/store.dart';

void main() {
  late VigilStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = await VigilStore.load();
  });

  /// An expense dated [at].
  void spend(int paise, DateTime at, {String title = 'Spend'}) {
    store.txns.add(Txn(id: store.nextId(), title: title, category: 'FOOD', paise: paise, at: at));
    store.changed();
  }

  DateTime lastMonth() {
    final DateTime n = DateTime.now();
    return DateTime(n.year, n.month - 1, 15);
  }

  group('protocol reminders', () {
    test('a protocol keeps its unit, target, reminder time and days', () async {
      store.addProtocol('Read', unit: 'Pages', target: 20, remindMin: 21 * 60, days: <int>[5, 1, 3, 3, 9, 0]);
      final Protocol p = store.protocols.single;
      expect((p.name, p.unit, p.target, p.remindMin), ('Read', 'Pages', 20, 21 * 60));
      expect(p.days, <int>[1, 3, 5], reason: 'sorted, no repeats, only real weekdays');
      await store.reloadFromDisk();
      final Protocol back = store.protocols.single;
      expect((back.unit, back.target, back.remindMin), ('Pages', 20, 21 * 60));
      expect(back.days, <int>[1, 3, 5]);
    });

    test('all seven days, or none picked, means every day', () {
      store.addProtocol('A', days: <int>[1, 2, 3, 4, 5, 6, 7]);
      store.addProtocol('B');
      expect(store.protocols[0].days, isEmpty);
      expect(store.protocols[1].days, isEmpty);
      expect(store.protocols[1].dueOn(DateTime(2026, 10, 25)), isTrue);
    });

    test('dueOn follows the weekdays picked', () {
      store.addProtocol('Gym', days: <int>[1, 3, 5]);
      final Protocol p = store.protocols.single;
      expect(p.dueOn(DateTime(2026, 10, 26)), isTrue, reason: 'a Monday');
      expect(p.dueOn(DateTime(2026, 10, 27)), isFalse, reason: 'a Tuesday');
      expect(p.dueOn(DateTime(2026, 10, 30)), isTrue, reason: 'a Friday');
    });

    test('a reminder time outside the day is kept inside it, and a zero target is ignored', () {
      store.addProtocol('Late', unit: 'Min', target: 0, remindMin: 5000);
      final Protocol p = store.protocols.single;
      expect(p.remindMin, 1439);
      expect(p.target, isNull);
    });

    test('protocols saved by older builds, with no reminder fields, still load', () async {
      store.addProtocol('Old');
      await store.reloadFromDisk();
      expect(store.protocols.single.remindMin, isNull);
      expect(store.protocols.single.days, isEmpty);
    });
  });

  group('budget', () {
    test('without roll-over the limit is exactly what was set', () {
      store.setBudget(2500000);
      spend(1000000, lastMonth());
      expect((store.rolledOverPaise, store.effectiveBudgetPaise), (0, 2500000));
    });

    test('with roll-over, what was left last month is added to this month', () {
      store.setBudget(2500000);
      spend(1900000, lastMonth());
      store.setBudgetOptions(rollover: true);
      expect(store.rolledOverPaise, 600000);
      expect(store.effectiveBudgetPaise, 3100000);
      spend(310000, DateTime.now());
      expect(store.monthSpentPercent, 10, reason: '₹3,100 of ₹31,000');
    });

    test('overspending last month rolls nothing over, and a first month gets no bonus', () {
      store.setBudget(2500000);
      store.setBudgetOptions(rollover: true);
      expect(store.rolledOverPaise, 0, reason: 'no spending last month: no history to roll over');
      spend(3000000, lastMonth());
      expect(store.rolledOverPaise, 0, reason: 'overspent');
    });

    test('safe-to-spend is worked out from the limit including what rolled over', () {
      store.setBudget(3000000);
      final int without = store.safeToSpendPaise;
      spend(0 + 1000000, lastMonth());
      store.setBudgetOptions(rollover: true);
      expect(store.safeToSpendPaise, greaterThan(without));
    });

    test('the options are saved, and Erase all resets them', () async {
      store.setBudget(2500000);
      store.setBudgetOptions(alert: false, rollover: true);
      await store.reloadFromDisk();
      expect((store.budgetAlert, store.budgetRollover), (false, true));
      await store.eraseAll();
      expect((store.budgetAlert, store.budgetRollover, store.monthBudgetPaise), (true, false, 0));
    });
  });

  group('the 80 % alert', () {
    late List<String> shown;

    setUp(() {
      shown = <String>[];
      store.notify = (String title, String body) => shown.add('$title | $body');
      store.setBudget(1000000); // ₹10,000
    });

    test('fires once when spending reaches 80 %, not before', () {
      spend(700000, DateTime.now());
      expect(shown, isEmpty);
      spend(100000, DateTime.now());
      expect(shown.length, 1);
      expect(shown.single, allOf(startsWith('Budget at 80 %'), contains('₹8,000'), contains('₹10,000')));
      spend(100000, DateTime.now());
      expect(shown.length, 1, reason: 'once a month');
    });

    test('is silent when switched off, and when there is no budget', () {
      store.setBudgetOptions(alert: false);
      spend(900000, DateTime.now());
      expect(shown, isEmpty, reason: 'alert off');
      store.setBudgetOptions(alert: true, rollover: false);
      shown.clear();
      store.setBudget(0);
      spend(1000, DateTime.now());
      expect(shown, isEmpty, reason: 'no budget');
    });

    test('a new month can alert again', () async {
      spend(900000, DateTime.now());
      expect(shown.length, 1);
      await store.prefs.setString('budgetAlertMonth', '2000-1');
      spend(1000, DateTime.now());
      expect(shown.length, 2);
    });

    test('counts what rolled over: 80 % of the bigger limit', () {
      spend(1000000 - 100000, lastMonth()); // spent ₹9,000 last month: ₹1,000 left
      store.setBudgetOptions(rollover: true);
      shown.clear();
      spend(850000, DateTime.now());
      expect(shown, isEmpty, reason: '₹8,500 is under 80 % of ₹11,000');
      spend(50000, DateTime.now());
      expect(shown.length, 1);
    });
  });
}
