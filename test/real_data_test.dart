import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigil/data/models.dart';
import 'package:vigil/data/store.dart';

void main() {
  test('a fresh install has no data of any kind', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final VigilStore s = await VigilStore.load();
    expect(s.objectives, isEmpty);
    expect(s.blocks, isEmpty);
    expect(s.protocols, isEmpty);
    expect(s.bills, isEmpty);
    expect(s.txns, isEmpty);
    expect(s.notes, isEmpty);
    expect(s.logStreak, 0);
    expect(s.focusTodayMin, 0);
    expect(s.monthBudgetPaise, 0);
    expect(s.monthSpentPercent, isNull);
    expect(s.safeToSpendPaise, 0);
    expect(s.weekLevels, isEmpty);
    expect(s.blocksFor(DateTime.now().add(const Duration(days: 2))), isEmpty);
  });

  test('sample data saved by older builds is dropped once; the user\'s own entries stay', () async {
    final DateTime now = DateTime.now();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'objectives': jsonEncode(<Map<String, dynamic>>[
        Objective(id: 'o1', title: 'Submit client deck v2').toJson(),
        Objective(id: 'c2', title: 'Send weekly report').toJson(),
        Objective(id: '1700-1', title: 'Call the plumber').toJson(),
      ]),
      'notes': jsonEncode(<Map<String, dynamic>>[
        Note(id: 'n1', title: 'Q4 priorities', body: 'x', at: now).toJson(),
        Note(id: '1700-2', title: 'My note', body: 'y', at: now).toJson(),
      ]),
      'txns': jsonEncode(<Map<String, dynamic>>[
        Txn(id: 't1', title: 'Swiggy', category: 'FOOD', paise: 18000, at: now).toJson(),
        Txn(id: '1700-3', title: 'Lunch', category: 'FOOD', paise: 25000, at: now).toJson(),
      ]),
      'blocks': jsonEncode(<Map<String, dynamic>>[
        Block(id: 'b1', kind: BlockKind.event, title: 'Daily standup', startMin: 540, endMin: 570).toJson(),
        Block(id: 'u:1', kind: BlockKind.event, title: 'Dentist', startMin: 600, endMin: 660, dayKey: VigilStore.dayKey(now)).toJson(),
      ]),
      'protocols': jsonEncode(<Map<String, dynamic>>[
        <String, dynamic>{'id': 'p1', 'streak': 12, 'done': false, 'missed': 0, 'week': <bool>[true, true, true, true, true, true, false]},
      ]),
      'day': VigilStore.dayKey(now),
      'logStreak': 15,
      'focusToday': 130,
    });
    final VigilStore s = await VigilStore.load();
    expect(s.objectives.map((Objective o) => o.title), <String>['Call the plumber']);
    expect(s.notes.map((Note n) => n.title), <String>['My note']);
    expect(s.txns.map((Txn t) => t.title), <String>['Lunch']);
    expect(s.blocks.map((Block b) => b.title), <String>['Dentist']);
    expect(s.protocols, isEmpty);
    expect(s.logStreak, 0);
    expect(s.focusTodayMin, 0);

    // Saved, so it does not run again and cannot touch later entries.
    final VigilStore again = await VigilStore.load();
    expect(again.objectives.length, 1);
    expect(s.prefs.getBool('realData1'), isTrue);
  });

  test('protocols, bills and the budget are saved and come back', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final VigilStore s = await VigilStore.load();
    s.addProtocol('Read 20 pages');
    s.toggleProtocol(s.protocols.single.id);
    s.addBill('Electricity', 184000, DateTime.now());
    s.setBudget(4500000);
    s.txns.add(Txn(id: '1-1', title: 'Lunch', category: 'FOOD', paise: 25000, at: DateTime.now()));
    s.changed();

    final VigilStore b = await VigilStore.load();
    expect(b.protocols.single.name, 'Read 20 pages');
    expect(b.protocols.single.doneToday, isTrue);
    expect(b.weekLevels.last, 4);
    expect(b.bills.single.dueToday, isTrue);
    expect(b.bills.single.due, 'TODAY');
    expect(b.monthBudgetPaise, 4500000);
    expect(b.monthSpentPaise, 25000);
    expect(b.monthSpentPercent, 1);
  });

  test('only this month\'s spend counts', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final VigilStore s = await VigilStore.load();
    final DateTime n = DateTime.now();
    s.txns
      ..add(Txn(id: '1-1', title: 'Now', category: 'FOOD', paise: 100, at: n))
      ..add(Txn(id: '1-2', title: 'Last month', category: 'FOOD', paise: 999, at: DateTime(n.year, n.month - 1, 15)));
    expect(s.monthSpentPaise, 100);
    expect(s.categorySpend, <String, int>{'FOOD': 100});
  });
}
