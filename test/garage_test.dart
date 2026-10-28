import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigil/data/agent.dart';
import 'package:vigil/data/assistant.dart';
import 'package:vigil/data/brain_pipeline.dart';
import 'package:vigil/data/brain_prompt.dart';
import 'package:vigil/data/garage.dart';
import 'package:vigil/data/models.dart';
import 'package:vigil/data/store.dart';
import 'package:vigil/services/drive_backup.dart';
import 'package:vigil/vigil/vigil.dart';

FillUp fill(String id, int odo, double litres, {int paise = 100000, bool full = true, String bike = 'b'}) =>
    FillUp(id: id, bikeId: bike, day: DateTime(2026, 10, 1).add(Duration(days: odo ~/ 100)), odometer: odo, litres: litres, totalPaise: paise, full: full);

void main() {
  final Bike meteor = Bike(id: 'b', make: 'Royal Enfield', model: 'Meteor 350', tankL: 15, odometer: 9412);

  group('mileage', () {
    test('is measured between two full tanks, and the first full tank only starts the count', () {
      final BikeStats s = BikeStats.of(meteor, <FillUp>[fill('a', 9055, 9.0), fill('b', 9412, 10.2)]);
      expect(s.points.length, 1);
      expect(s.points.single.km, 357);
      expect(s.points.single.kmPerLitre, closeTo(35.0, 0.01));
      expect(s.avgKmPerLitre, closeTo(35.0, 0.01));
    });

    test('a partial fill in between adds its litres to the next full tank, so it cannot distort the result', () {
      final BikeStats s = BikeStats.of(meteor, <FillUp>[fill('a', 1000, 10), fill('p', 1150, 3, full: false), fill('c', 1300, 6)]);
      expect(s.points.length, 1);
      expect(s.points.single.litres, 9, reason: '3 + 6 litres were needed to refill after 300 km');
      expect(s.points.single.kmPerLitre, closeTo(300 / 9, 0.01));
    });

    test('the average is total distance over total litres, not an average of averages', () {
      final BikeStats s = BikeStats.of(meteor, <FillUp>[fill('a', 0, 10), fill('b', 100, 5), fill('c', 600, 10)]);
      // 100 km on 5 L (20) and 500 km on 10 L (50): 600 km on 15 L = 40, not 35
      expect(s.avgKmPerLitre, closeTo(40, 0.001));
    });

    test('cost per km comes from what the measured stretches cost', () {
      final BikeStats s = BikeStats.of(meteor, <FillUp>[fill('a', 0, 10, paise: 100000), fill('b', 400, 10, paise: 104900)]);
      expect(s.paisePerKm, closeTo(104900 / 400, 0.001));
    });

    test('with no measurable stretch there is no average, and nothing is invented', () {
      expect(BikeStats.of(meteor, <FillUp>[]).avgKmPerLitre, isNull);
      expect(BikeStats.of(meteor, <FillUp>[fill('a', 100, 9)]).avgKmPerLitre, isNull);
      expect(BikeStats.of(meteor, <FillUp>[fill('a', 100, 9), fill('b', 100, 9)]).points, isEmpty, reason: 'no distance');
      expect(BikeStats.of(meteor, <FillUp>[fill('a', 100, 9, bike: 'other'), fill('b', 400, 9, bike: 'other')]).points, isEmpty, reason: 'another bike');
    });

    test('range left comes from the tank, the distance since the last fill, and the average', () {
      final Bike b = Bike(id: 'b', make: '', model: 'Meteor', tankL: 15, odometer: 9412);
      final BikeStats s = BikeStats.of(b, <FillUp>[fill('a', 9055, 9.0), fill('b', 9412 - 357 + 357, 10.2)]);
      expect(s.sinceLastFillKm, 0);
      expect(s.rangeKm, (15 * 35).round());
      b.odometer = 9412 + 175; // half a tank of distance
      final BikeStats later = BikeStats.of(b, <FillUp>[fill('a', 9055, 9.0), fill('b', 9412, 10.2)]);
      expect(later.sinceLastFillKm, 175);
      expect(later.litresLeft, closeTo(15 - 175 / 35, 0.01));
    });

    test('a preview says how the tank about to be saved compares with the average', () {
      final List<FillUp> existing = <FillUp>[fill('a', 0, 10), fill('b', 350, 10)]; // 35 km/l
      final ({double kmPerLitre, int km, double? vsAveragePercent})? p = previewMileage(meteor, existing, odometer: 665, litres: 10, full: true);
      expect(p!.km, 315);
      expect(p.kmPerLitre, closeTo(31.5, 0.001));
      expect(p.vsAveragePercent, closeTo(-10, 0.01));
      expect(previewMileage(meteor, existing, odometer: 665, litres: 10, full: false), isNull, reason: 'not a full tank');
      expect(previewMileage(meteor, <FillUp>[], odometer: 100, litres: 5, full: true), isNull, reason: 'no earlier full tank');
    });
  });

  group('reminders', () {
    final DateTime today = DateTime(2026, 10, 27);

    test('by distance: ok, soon inside the heads-up, overdue past it', () {
      final Reminder r = Reminder(id: 'r', kind: ReminderKind.chain, everyKm: 500, lastKm: 9050);
      expect(dueStatus(r, 9100, today).level, DueLevel.ok);
      final DueStatus soon = dueStatus(r, 9412, today);
      expect((soon.level, soon.kmLeft), (DueLevel.soon, 138));
      expect(dueStatus(r, 9551, today).level, DueLevel.overdue);
      expect(dueText(dueStatus(r, 9551, today)), 'Overdue');
      expect(dueText(soon), '138 km');
    });

    test('by date, and a paper with a valid-till date', () {
      final Reminder tyres = Reminder(id: 't', kind: ReminderKind.tyres, mode: ReminderMode.date, everyDays: 14, lastDate: DateTime(2026, 10, 13));
      expect((dueStatus(tyres, 0, today).level, dueStatus(tyres, 0, today).daysLeft), (DueLevel.soon, 0));
      expect(dueText(dueStatus(tyres, 0, today)), 'Today');
      final Reminder puc = Reminder(id: 'p', kind: ReminderKind.puc, mode: ReminderMode.date, dueDate: DateTime(2026, 11, 9));
      final DueStatus ps = dueStatus(puc, 0, today);
      expect((ps.level, ps.daysLeft, dueText(ps)), (DueLevel.soon, 13, '13 days'));
      final Reminder gone = Reminder(id: 'i', kind: ReminderKind.insurance, mode: ReminderMode.date, dueDate: DateTime(2026, 10, 26));
      expect(dueStatus(gone, 0, today).level, DueLevel.overdue);
      final Reminder far = Reminder(id: 'f', kind: ReminderKind.insurance, mode: ReminderMode.date, dueDate: DateTime(2027, 3, 14));
      expect((dueStatus(far, 0, today).level, dueStatus(far, 0, today).daysLeft), (DueLevel.ok, 138));
    });

    test('first of both: whichever is nearer decides', () {
      final Reminder r = Reminder(id: 's', kind: ReminderKind.service, mode: ReminderMode.both, everyKm: 5000, everyDays: 365, lastKm: 5000, lastDate: DateTime(2026, 3, 18));
      expect(dueStatus(r, 9412, today).level, DueLevel.ok, reason: '588 km and 142 days left');
      final Reminder byKm = Reminder(id: 's2', kind: ReminderKind.service, mode: ReminderMode.both, everyKm: 5000, everyDays: 365, lastKm: 5000, lastDate: DateTime(2026, 10, 1));
      expect(dueStatus(byKm, 9900, today).level, DueLevel.soon, reason: '100 km left');
      expect(dueStatus(byKm, 10100, today).level, DueLevel.overdue);
    });

    test('numbers are written the way people read them', () {
      expect((kmText(142), kmText(4642), kmText(18642), kmText(1234567)), ('142', '4,642', '18,642', '1,234,567'));
      expect((rupees2(293.4), rupees2(10490), rupees2(303)), ('₹2.93', '₹104.90', '₹3.03'));
      final Reminder r = Reminder(id: 's', kind: ReminderKind.service, everyKm: 5000, lastKm: 9054);
      expect(dueText(dueStatus(r, 9412, today)), '4,642 km');
    });

    test('they are saved and read back', () {
      final Reminder r = Reminder(id: 'r', kind: ReminderKind.custom, label: 'Brake pads', mode: ReminderMode.both, everyKm: 8000, everyDays: 200, lastKm: 100, lastDate: DateTime(2026, 5, 1), headsUpKm: 500);
      final Reminder back = Reminder.fromJson(r.toJson());
      expect((back.title, back.mode, back.everyKm, back.everyDays, back.lastKm, back.lastDate, back.headsUpKm), ('Brake pads', ReminderMode.both, 8000, 200, 100, DateTime(2026, 5, 1), 500));
    });
  });

  group('in the store', () {
    late VigilStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      store = await VigilStore.load();
    });

    Bike addMeteor({int odo = 9412}) => store.addBike(make: 'Royal Enfield', model: 'Meteor 350', tankL: 15, odometer: odo, insuranceUntil: DateTime.now().add(const Duration(days: 138)), pucUntil: DateTime.now().add(const Duration(days: 114)))!;

    test('a new bike comes with the usual reminders, and only two bikes are kept', () {
      final Bike b = addMeteor();
      expect(b.reminders.map((Reminder r) => r.kind), <ReminderKind>[ReminderKind.chain, ReminderKind.service, ReminderKind.tyres, ReminderKind.insurance, ReminderKind.puc]);
      expect(store.addBike(make: 'Bajaj', model: 'Avenger', tankL: 13), isNotNull);
      expect(store.addBike(make: 'Third', model: 'Bike', tankL: 10), isNull);
      expect(store.addBike(make: '', model: '', tankL: 10), isNull);
      store.removeBike(b.id);
      expect(store.bikes.length, 1);
    });

    test('a fill-up is counted in Vault under Transport, moves the odometer, and can be undone', () {
      final Bike b = addMeteor(odo: 9000);
      final undo = store.addFillUp(bikeId: b.id, odometer: 9412, litres: 10.2, totalPaise: 107000);
      expect(undo, isNotNull);
      expect(b.odometer, 9412);
      final Txn t = store.txns.first;
      expect((t.title, t.category, t.paise), ('Fuel · Meteor 350', 'TRANSPORT', 107000));
      expect(store.fuelThisMonth().litres, closeTo(10.2, 0.001));
      expect(store.fuelThisMonth().paise, 107000);
      undo!();
      expect(store.fillups, isEmpty);
      expect(store.txns, isEmpty);
      expect(b.odometer, 9000);
    });

    test('nonsense is refused', () {
      final Bike b = addMeteor();
      expect(store.addFillUp(bikeId: b.id, odometer: 9500, litres: 0, totalPaise: 1000), isNull);
      expect(store.addFillUp(bikeId: b.id, odometer: 9500, litres: 10, totalPaise: 0), isNull);
      expect(store.addFillUp(bikeId: b.id, odometer: 9500, litres: 40, totalPaise: 1000), isNull, reason: 'far more than the tank holds');
      expect(store.addFillUp(bikeId: 'nope', odometer: 9500, litres: 10, totalPaise: 1000), isNull);
      expect(store.txns, isEmpty);
    });

    test('a fill-up kept lower than an earlier reading never moves the odometer back', () {
      final Bike b = addMeteor(odo: 9412);
      store.addFillUp(bikeId: b.id, odometer: 9000, litres: 5, totalPaise: 50000);
      expect(b.odometer, 9412);
    });

    test('removing a bike or a fill-up takes its Vault entry with it', () {
      final Bike b = addMeteor();
      store.addFillUp(bikeId: b.id, odometer: 9500, litres: 5, totalPaise: 50000);
      store.addFillUp(bikeId: b.id, odometer: 9800, litres: 6, totalPaise: 60000);
      store.removeFillUp(store.fillups.first.id);
      expect(store.txns.length, 1);
      store.removeBike(b.id);
      expect(store.fillups, isEmpty);
      expect(store.txns, isEmpty);
    });

    test('a reminder that falls due becomes an Ops objective, red when overdue, and goes away once done', () {
      final Bike b = addMeteor(odo: 9000);
      final Reminder chain = b.reminders.first; // every 500 km from 9000, heads-up 100
      expect(store.objectives.where((Objective o) => o.id.startsWith('g:')), isEmpty);
      store.setOdometer(b.id, 9420);
      Objective o = store.objectives.firstWhere((Objective o) => o.id == 'g:${chain.id}');
      expect((o.title, o.threat, o.tag), ('Meteor 350 · Chain lube & clean', Threat.high, 'GARAGE'));
      store.setOdometer(b.id, 9600);
      o = store.objectives.firstWhere((Objective o) => o.id == 'g:${chain.id}');
      expect((o.threat, o.dueLabel), (Threat.crit, 'OVERDUE'));
      store.markReminderDone(b.id, chain.id);
      expect(store.objectives.where((Objective o) => o.id == 'g:${chain.id}'), isEmpty);
      expect(chain.lastKm, 9600);
    });

    test('clearing the objective in Ops counts as doing the job', () {
      final Bike b = addMeteor(odo: 9000);
      final Reminder chain = b.reminders.first;
      store.setOdometer(b.id, 9600);
      store.toggleObjective('g:${chain.id}', true);
      expect(chain.lastKm, 9600);
      store.bikeEdited();
      expect(store.objectives.where((Objective o) => o.id == 'g:${chain.id}' && !o.done), isEmpty);
    });

    test('the garage is saved, comes back after a restart, and is part of the backup', () async {
      final Bike b = addMeteor();
      store.addFillUp(bikeId: b.id, odometer: 9500, litres: 5, totalPaise: 50000);
      await store.reloadFromDisk();
      expect(store.bikes.single.name, 'Meteor 350');
      expect(store.bikes.single.reminders.length, 5);
      expect(store.fillups.single.litres, 5);
      expect(snapshotValues(store.prefs).keys, containsAll(<String>['bikes', 'fillups']));
    });

    test('a deleted objective can be put back where it was', () {
      final Objective a = store.addObjective('First');
      final Objective b = store.addObjective('Second');
      final int at = store.objectives.indexWhere((Objective e) => e.id == a.id);
      store.removeObjective(a.id);
      expect(store.objectives.map((Objective e) => e.title), <String>['Second']);
      store.restoreObjective(a, at);
      expect(store.objectives.map((Objective e) => e.id), <String>[b.id, a.id]);
      store.restoreObjective(a, 0);
      expect(store.objectives.length, 2, reason: 'never twice');
    });

    test('Erase all empties the garage', () async {
      addMeteor();
      await store.eraseAll();
      expect(store.bikes, isEmpty);
      expect(store.fillups, isEmpty);
    });

    test('a bike is found by name, or is the only bike', () {
      final Bike m = addMeteor();
      expect(store.bikeByName(null)!.id, m.id);
      expect(store.bikeByName('the meteor')!.id, m.id);
      final Bike a = store.addBike(make: 'Bajaj', model: 'Avenger', tankL: 13)!;
      expect(store.bikeByName(null), isNull, reason: 'two bikes and no name');
      expect(store.bikeByName('avenger')!.id, a.id);
      expect(store.bikeByName('royal enfield')!.id, m.id);
    });
  });

  group('telling K', () {
    BrainFacts facts(List<String> bikes) => BrainFacts(now: DateTime(2026, 10, 23, 14, 30), callsign: 'Alex', bikes: bikes);
    Decision? decide(String q, List<String> bikes) => decideWithoutModel(q, facts(bikes));
    AgentAction only(Decision? d) {
      expect(d?.source, DecisionSource.rules);
      return d!.plan!.actions.single;
    }

    test('a fill-up in plain words is understood: litres, rupees, the odometer and which bike', () {
      final AgentAction a = only(decide('filled 10 litres in the Meteor for ₹1,050 at 9,412', <String>['Meteor 350', 'Avenger']));
      expect(a.type, 'log_fill_up');
      expect((a.args['bike'], a.args['litres'], a.args['amount'], a.args['odometer'], a.args.containsKey('full')), ('Meteor 350', 10.0, 1050.0, 9412, false));
    });

    test('with one bike the name is not needed, and a top-up is not a full tank', () {
      final AgentAction a = only(decide('topped up 3 litres of petrol for rs 300', <String>['Meteor 350']));
      expect((a.args['litres'], a.args['amount'], a.args.containsKey('bike'), a.args['full']), (3.0, 300.0, false, false));
      final AgentAction b = only(decide('put 8.6 litres for 902 in the avenger at 18642 km', <String>['Meteor 350', 'Avenger']));
      expect((b.args['bike'], b.args['litres'], b.args['amount'], b.args['odometer']), ('Avenger', 8.6, 902.0, 18642));
    });

    test('without a bike, or without litres or rupees, the rule stays out of it', () {
      expect(decide('filled 10 litres for 1050', <String>[])?.plan?.actions.single.type, isNot('log_fill_up'), reason: 'no bike to put it on');
      expect(decide('filled the tank', <String>['Meteor 350']), isNull);
      expect(decide('10 litres of water', <String>['Meteor 350'])?.plan?.actions.single.type, isNot('log_fill_up'));
    });

    test('a question about fuel goes to the data, not to a rule', () {
      expect(decide('how much fuel did I put this month?', <String>['Meteor 350'])?.source, DecisionSource.router);
    });

    Bike addMeteor(VigilStore store) => store.addBike(make: 'Royal Enfield', model: 'Meteor 350', tankL: 15, odometer: 9000)!;

    test('through the assistant: saved, counted in Vault, shown with Undo', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final VigilStore store = await VigilStore.load();
      final Bike b = addMeteor(store);
      final ChatMsg m = await Assistant(store).reply('filled 10 litres for 1050 at 9412');
      expect(m.source, ReplySource.instant);
      expect(m.diff!.single.$1, 'FILL-UP');
      expect(m.diff!.single.$2, contains('Meteor 350'));
      expect((store.fillups.single.odometer, store.fillups.single.totalPaise, b.odometer), (9412, 105000, 9412));
      expect(store.txns.first.category, 'TRANSPORT');
      m.onUndo!();
      expect(store.fillups, isEmpty);
    });

    test('two bikes and no name: K asks which, and saves nothing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final VigilStore store = await VigilStore.load();
      addMeteor(store);
      store.addBike(make: 'Bajaj', model: 'Avenger', tankL: 13);
      final ChatMsg m = await Assistant(store).reply('filled 10 litres for 1050');
      expect(m.text, contains('Which bike?'));
      expect(m.diff, isNull);
      expect(store.fillups, isEmpty);
    });

    test('bike questions are answered from the Garage', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final VigilStore store = await VigilStore.load();
      final Assistant a = Assistant(store);
      expect((await a.reply('how is my bike mileage?')).text, contains('No bikes yet'));
      final Bike b = addMeteor(store);
      store.addFillUp(bikeId: b.id, odometer: 9000, litres: 10, totalPaise: 100000);
      store.addFillUp(bikeId: b.id, odometer: 9350, litres: 10, totalPaise: 104900);
      final ChatMsg m = await a.reply('how is my bike mileage?');
      expect(m.source, ReplySource.data);
      expect(m.text, allOf(contains('Meteor 350: 9350 km'), contains('35.0 km/l'), contains('Next:')));
    });
  });
}
