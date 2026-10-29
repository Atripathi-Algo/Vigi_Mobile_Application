import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigil/data/agent.dart';
import 'package:vigil/data/assistant.dart';
import 'package:vigil/data/brain_prompt.dart';
import 'package:vigil/data/garage.dart';
import 'package:vigil/data/models.dart';
import 'package:vigil/data/skills.dart';
import 'package:vigil/data/store.dart';

void main() {
  late VigilStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dotenv.testLoad(fileInput: '');
    store = await VigilStore.load();
  });

  group('the router picks the specialist', () {
    test('each area of the app is found by its own words', () {
      expect(routeSkills('remind me to call the bank').skills, <Skill>[Skill.ops]);
      expect(routeSkills('what is on my calendar').skills, <Skill>[Skill.calendar]);
      expect(routeSkills('spent 250 on lunch').skills, <Skill>[Skill.money]);
      expect(routeSkills('how is my bike mileage').skills, <Skill>[Skill.garage]);
      expect(routeSkills('did I keep my streak').skills, <Skill>[Skill.protocols]);
      expect(routeSkills('jot down an idea').skills, <Skill>[Skill.notes]);
      expect(routeSkills('how much water today').skills, <Skill>[Skill.health]);
      expect(routeSkills('turn off the haptics').skills, <Skill>[Skill.settings]);
    });

    test('open chat has no area and no actions; an unclear command keeps every action', () {
      final SkillRoute chat = routeSkills('what is the capital of France');
      expect(chat.isChat, isTrue);
      expect(chat.actions, isEmpty);
      final SkillRoute unsure = routeSkills('buy milk on the way home');
      expect(unsure.unsure, isFalse, reason: 'no command word, so it is chat');
      final SkillRoute cmd = routeSkills('put milk on the list for the way home');
      expect(cmd.unsure, isTrue);
      expect(cmd.actions, kBrainActionTypes);
    });

    test('a mixed sentence keeps its two best areas so the model can still do the right thing', () {
      final SkillRoute r = routeSkills('remind me to drink water');
      expect(r.skills, <Skill>[Skill.health, Skill.ops]);
      expect(r.actions, containsAll(<String>['add_objective', 'log_water']));
    });
  });

  group('the routed prompt is smaller', () {
    BrainFacts facts() => factsFromStore(store, DateTime(2026, 10, 28, 10));

    test('chat carries no action list, an area carries only its own', () {
      final String chat = buildSkillSystem(routeSkills('what is the capital of France'));
      expect(chat, isNot(contains('add_objective')));
      final String money = buildSkillSystem(routeSkills('spent 250 on lunch'));
      expect(money, contains('log_expense'));
      expect(money, isNot(contains('add_event')));
      expect(chat.length, lessThan(kBrainSystem.length));
      expect(money.length, lessThan(kBrainSystem.length + 200));
    });

    test('the facts are cut to the area asked about', () {
      store.addObjective('Send report');
      store.addProtocol('Read');
      final BrainFacts f = facts();
      final String ops = skillContext(f, routeSkills('what tasks are open'));
      expect(ops, contains('Send report'));
      expect(ops, isNot(contains('PROTOCOLS')));
      final String chat = skillContext(f, routeSkills('what is the capital of France'));
      expect(chat, isNot(contains('Send report')));
      expect(skillContext(f, routeSkills('what is the capital of France')).split('\n').length, lessThanOrEqualTo(2));
    });

    test('the schema offers only the area\'s actions', () {
      final Map<String, dynamic> s = schemaFor(routeSkills('spent 250 on lunch'));
      final Map<String, dynamic> items = ((s['properties'] as Map<String, dynamic>)['actions'] as Map<String, dynamic>)['items'] as Map<String, dynamic>;
      expect((((items['properties'] as Map<String, dynamic>)['type']) as Map<String, dynamic>)['enum'], <String>['log_expense']);
      expect(schemaFor(routeSkills('what is the capital of France')), same(kBrainSchema));
    });
  });

  group('controlling the rest of the app', () {
    Future<ChatMsg> say(String t, [Assistant? a]) => (a ?? Assistant(store)).reply(t);

    test('open a screen: the reply carries the route', () async {
      final ChatMsg m = await say('open the garage');
      expect((m.route, m.source), ('/ops/garage', ReplySource.instant));
      expect((await say('take me to my ledger')).route, '/vault/ledger');
      expect((await say('open the vault door')).route, isNull);
    });

    test('settings switch from chat, undo restores them, and security settings are refused', () async {
      final ChatMsg m = await say('turn off haptics');
      expect(store.effectsLevel, 0);
      m.onUndo!();
      expect(store.effectsLevel, 2);
      await say('disable thunder effects');
      expect(store.effectsLevel, 0);
      final ChatMsg refused = await say('turn off vault lock');
      expect(store.toggles['vaultLock'], isTrue);
      expect(refused.text, contains('Settings'));
      await say('turn on cloud ai');
      expect(store.toggles['cloudAi'], isFalse);
    });

    test('snooze moves the due time, and can be undone', () async {
      final Objective o = store.addObjective('Call the plumber', dueMin: 9 * 60);
      final ChatMsg m = await say('snooze call the plumber for 2 hours');
      expect(o.dueMin, isNot(9 * 60));
      expect(m.diff!.single.$1, 'SNOOZED');
      m.onUndo!();
      expect(o.dueMin, 9 * 60);
    });

    test('a deletion asks first, then needs a yes, and can still be undone', () async {
      store.addObjective('Old chore');
      final Assistant a = Assistant(store);
      final ChatMsg ask = await say('delete the task old chore', a);
      expect(store.open.map((Objective o) => o.title), contains('Old chore'));
      expect(ask.text, contains('Say yes'));
      final ChatMsg done = await say('yes', a);
      expect(store.open.map((Objective o) => o.title), isNot(contains('Old chore')));
      done.onUndo!();
      expect(store.open.map((Objective o) => o.title), contains('Old chore'));
    });

    test('anything but a yes leaves it alone, and a late yes does nothing', () async {
      store.addProtocol('Read');
      final Assistant a = Assistant(store);
      await say('delete the protocol read', a);
      final ChatMsg no = await say('no', a);
      expect(no.text, 'Left as it is.');
      expect(store.protocols, hasLength(1));
      await say('delete the protocol read', a);
      await say('what is the capital of France', a);
      await say('yes', a);
      expect(store.protocols, hasLength(1), reason: 'a message in between cancels the question');
    });

    test('a user event can be deleted; one from Google cannot', () async {
      store.blocks.add(Block(id: 'u:1', kind: BlockKind.event, title: 'Dentist', startMin: 600, endMin: 660));
      final Assistant a = Assistant(store);
      await say('remove the event dentist', a);
      await say('yes', a);
      expect(store.blocks.where((Block b) => b.title == 'Dentist'), isEmpty);
      final AgentResult r = applyAgentPlan(
        store,
        AgentPlan('x', <AgentAction>[AgentAction('delete_event', <String, dynamic>{'type': 'delete_event', 'title': 'Standup'})]),
      );
      expect(r.failed, isNotEmpty);
    });

    test('a delete with no match says so and changes nothing', () async {
      final ChatMsg m = await say('delete the moon landing');
      expect(m.text, contains('could not find'));
    });

    test('budget, new protocol and odometer', () async {
      await say('set my budget to 25k');
      expect(store.monthBudgetPaise, 2500000);
      final ChatMsg p = await say('add a habit stretch at 7 am');
      expect(store.protocols.single.name, 'Stretch');
      expect(store.protocols.single.remindMin, 7 * 60);
      p.onUndo!();
      expect(store.protocols, isEmpty);
      final Bike b = store.addBike(make: 'Royal Enfield', model: 'Meteor 350', tankL: 15, odometer: 9000)!;
      await say('set the meteor odometer to 9500');
      expect(b.odometer, 9500);
      final ChatMsg back = await say('set the meteor odometer to 100');
      expect(b.odometer, 9500);
      expect(back.text, contains('forward'));
    });

    test('an edit in the middle of a fill-up phrase is still a fill-up, not an odometer change', () async {
      final Bike b = store.addBike(make: 'Royal Enfield', model: 'Meteor 350', tankL: 15, odometer: 9000)!;
      await say('filled 10 litres for 1000 on the meteor odometer 9100');
      expect(store.fillups, hasLength(1));
      expect(b.odometer, 9100);
    });
  });
}
