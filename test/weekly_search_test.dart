import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigil/data/assistant.dart';
import 'package:vigil/data/garage.dart';
import 'package:vigil/data/models.dart';
import 'package:vigil/data/search.dart';
import 'package:vigil/data/store.dart';
import 'package:vigil/data/weekly.dart';

void main() {
  late VigilStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dotenv.testLoad(fileInput: '');
    store = await VigilStore.load();
  });

  group('the Sunday review', () {
    test('counts the week: tasks done, spending against the week before, fuel', () {
      final DateTime now = DateTime(2026, 11, 1, 10); // a Sunday
      final Objective done = store.addObjective('Send report');
      store.toggleObjective(done.id, true);
      done.doneAt = now.subtract(const Duration(days: 2)).millisecondsSinceEpoch;
      final Objective old = store.addObjective('Old job');
      store.toggleObjective(old.id, true);
      old.doneAt = now.subtract(const Duration(days: 12)).millisecondsSinceEpoch;
      store.txns
        ..add(Txn(id: 'a', title: 'Lunch', category: 'FOOD', paise: 45000, at: now.subtract(const Duration(days: 1))))
        ..add(Txn(id: 'b', title: 'Rent', category: 'BILLS', paise: 100000, at: now.subtract(const Duration(days: 9))));
      final Bike b = store.addBike(make: 'Royal Enfield', model: 'Meteor 350', tankL: 15, odometer: 9000)!;
      store.fillups.add(FillUp(id: 'f', bikeId: b.id, day: now.subtract(const Duration(days: 3)), odometer: 9100, litres: 10, totalPaise: 105000));
      final WeeklyReview w = weeklyReview(store, now);
      expect((w.tasksDone, w.spentPaise, w.spentBeforePaise), (1, 45000, 100000));
      expect((w.fuelPaise, w.fuelLitres), (105000, 10.0));
      expect(w.hasAnything, isTrue);
    });

    test('an empty week has nothing to show, and "Not now" hides it for the day', () {
      final DateTime now = DateTime(2026, 11, 1, 10);
      expect(weeklyReview(store, now).hasAnything, isFalse);
      expect(store.weeklyDismissed(now), isFalse);
      store.dismissWeekly(now);
      expect(store.weeklyDismissed(now), isTrue);
      expect(store.weeklyDismissed(now.add(const Duration(days: 1))), isFalse);
    });
  });

  group('search', () {
    setUp(() {
      store.addObjective('Call Ravi about the loan');
      store.notes.insert(0, Note(id: 'n', title: 'Ravi prefers morning calls', body: 'Ravi prefers morning calls', at: DateTime.now()));
      store.addProtocol('Read');
      store.txns
        ..add(Txn(id: 't1', title: 'Petrol', category: 'TRANSPORT', paise: 105000, at: DateTime.now()))
        ..add(Txn(id: 't2', title: 'Fuel top-up', category: 'TRANSPORT', paise: 50000, at: DateTime.now()));
    });

    test('finds across tasks, notes, habits and spending, every word must match', () {
      expect(searchAll(store, 'ravi').map((SearchHit h) => h.kind), <HitKind>[HitKind.task, HitKind.note]);
      expect(searchAll(store, 'ravi loan').single.kind, HitKind.task);
      expect(searchAll(store, 'ravi nothing'), isEmpty);
      expect(searchAll(store, 'read').single.kind, HitKind.habit);
      expect(searchAll(store, '   '), isEmpty);
    });

    test('a note whose body repeats its title shows a date instead, and spends show amounts', () {
      final SearchHit note = searchAll(store, 'ravi').firstWhere((SearchHit h) => h.kind == HitKind.note);
      expect(note.detail, isNot('Ravi prefers morning calls'));
      expect(searchAll(store, 'petrol').single.detail, contains('₹1,050'));
    });

    test('a spending total answers "how much on fuel"', () {
      expect(spendTotal(store, 'transport')?.paise, 155000);
      expect(spendTotal(store, 'fuel')?.count, 1);
      expect(spendTotal(store, 'xyz'), isNull);
    });

    test('K finds it from chat, on the phone, and offers the full list', () async {
      final ChatMsg m = await Assistant(store).reply('find the note about Ravi');
      expect(m.text, contains('Ravi'));
      expect(m.route, startsWith('/search?q='));
      expect(m.source, ReplySource.data);
      expect((await Assistant(store).reply('search for zebra')).text, 'Nothing matches "zebra".');
    });
  });
}
