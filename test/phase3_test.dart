import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigil/data/agent.dart';
import 'package:vigil/data/assistant.dart';
import 'package:vigil/data/brain_eval.dart';
import 'package:vigil/data/brain_pipeline.dart';
import 'package:vigil/data/brain_prompt.dart';
import 'package:vigil/data/models.dart';
import 'package:vigil/data/store.dart';

AgentPlan plan(List<Map<String, dynamic>> actions, [String say = 'ok']) => AgentPlan(say, <AgentAction>[for (final Map<String, dynamic> a in actions) AgentAction(a['type'] as String, a)]);

void main() {
  late VigilStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dotenv.testLoad(fileInput: '');
    store = await VigilStore.load();
  });

  Block addBlock(String title, int start, int end, {String? src}) {
    final Block b = Block(id: 'u:${store.nextId()}', kind: BlockKind.event, title: title, startMin: start, endMin: end, src: src);
    store.blocks.add(b);
    return b;
  }

  group('partialSay', () {
    test('is null until the sentence starts, then grows word by word', () {
      expect(partialSay('{"actions":[]'), isNull);
      expect(partialSay('{"actions":[],"say"'), isNull);
      expect(partialSay('{"actions":[],"say":'), isNull);
      expect(partialSay('{"actions":[],"say":"'), '');
      expect(partialSay('{"actions":[],"say":"Par'), 'Par');
      expect(partialSay('{"actions":[],"say":"Paris."}'), 'Paris.');
    });

    test('handles escaped quotes and stops at the closing quote', () {
      expect(partialSay(r'{"actions":[],"say":"He said \"hi\" and left"}'), 'He said "hi" and left');
      expect(partialSay(r'{"actions":[],"say":"one\ntwo"}'), 'one two');
      expect(partialSay(r'{"actions":[],"say":"half\'), 'half');
    });
  });

  group('move_event', () {
    test('moves an event made on this phone, keeps its length, and can be undone', () {
      final Block b = addBlock('Leg day', 20 * 60 + 30, 21 * 60 + 30);
      final AgentResult r = applyAgentPlan(store, plan(<Map<String, dynamic>>[
        <String, dynamic>{'type': 'move_event', 'title': 'leg day', 'start': '21:00'},
      ]));
      expect(r.failed, isEmpty);
      expect(r.diff.single, ('MOVED', 'Leg day → 21:00'));
      expect((b.startMin, b.endMin), (21 * 60, 22 * 60));
      r.undo!();
      expect((b.startMin, b.endMin), (20 * 60 + 30, 21 * 60 + 30));
    });

    test('an event from Google is read-only, and a missing or ambiguous one is reported', () {
      final Block g = addBlock('Standup', 9 * 60, 9 * 60 + 30, src: 'PERSONAL');
      addBlock('Review A', 10 * 60, 11 * 60);
      addBlock('Review B', 12 * 60, 13 * 60);
      final AgentResult r = applyAgentPlan(store, plan(<Map<String, dynamic>>[
        <String, dynamic>{'type': 'move_event', 'title': 'Standup', 'start': '10:00'},
        <String, dynamic>{'type': 'move_event', 'title': 'Review', 'start': '15:00'},
        <String, dynamic>{'type': 'move_event', 'title': 'Nothing', 'start': '15:00'},
        <String, dynamic>{'type': 'move_event', 'title': 'Review A'},
      ]));
      expect(r.diff, isEmpty);
      expect(r.failed.length, 4);
      expect(g.startMin, 9 * 60);
    });
  });

  group('rules for moving, and one change at a time', () {
    Decision? decide(String q) => decideWithoutModel(q, kEvalFacts);

    test('"move standup to 10 am" is decided by the rules against the real events', () {
      final Decision? d = decide('move standup to 10 am');
      expect(d?.source, DecisionSource.rules);
      final AgentAction a = d!.plan!.actions.single;
      expect((a.type, a.args['title'], a.args['start']), ('move_event', 'Standup', '10:00'));
    });

    test('an event that does not exist, or no time, is left to the model', () {
      expect(decide('move gym to 9 pm'), isNull);
      expect(decide('move standup to later'), isNull);
    });

    test('two changes in one sentence get one question, and change nothing', () {
      final Decision? d = decide('move standup to 10 am and add a note about the roadmap');
      expect(d?.source, DecisionSource.rules);
      expect(d!.plan!.actions, isEmpty);
      expect(d.plan!.say, contains('one thing at a time'));
    });

    test('a note that happens to contain "and add" is still one note', () {
      final Decision? d = decide('note: buy milk and add eggs');
      expect(d!.plan!.actions.single.type, 'add_note');
    });

    test('the model\'s move needs a time and a move word from the user', () {
      var v = validateModelPlan(plan(<Map<String, dynamic>>[<String, dynamic>{'type': 'move_event', 'title': 'Standup', 'start': '10:00'}]), 'shift the standup to 10 am', kEvalFacts);
      expect(v.dropped, isFalse);
      v = validateModelPlan(plan(<Map<String, dynamic>>[<String, dynamic>{'type': 'move_event', 'title': 'Standup', 'start': '10:00'}]), 'what is the capital of France', kEvalFacts);
      expect(v.dropped, isTrue);
    });
  });

  group('reply sources', () {
    test('a command is INSTANT, a question about the data is FROM YOUR DATA, and both are timed', () async {
      final Assistant a = Assistant(store);
      final ChatMsg cmd = await a.reply('log a glass of water');
      expect((cmd.source, cmd.undoable), (ReplySource.instant, true));
      expect(cmd.ms, isNotNull);
      final ChatMsg q = await a.reply('how much water today');
      expect(q.source, ReplySource.data);
      expect(q.text, contains('Hydration 0.3 of 3.0 L'));
    });

    test('moving an event through the assistant', () async {
      final Block b = addBlock('Standup', 9 * 60, 9 * 60 + 30);
      final ChatMsg m = await Assistant(store).reply('move standup to 10 am');
      expect(m.source, ReplySource.instant);
      expect(m.diff!.single.$1, 'MOVED');
      expect(b.startMin, 10 * 60);
    });

    test('when nothing could be done, the promise is not made', () async {
      addBlock('Standup', 9 * 60, 9 * 60 + 30, src: 'PERSONAL');
      final ChatMsg m = await Assistant(store).reply('move standup to 10 am');
      expect(m.text, isNot(contains('Moved')));
      expect(m.text, contains('read-only'));
      expect(m.alert, isTrue);
      expect(m.diff, isNull);
    });

    test('a request that nothing can answer has no source tag', () async {
      final ChatMsg m = await Assistant(store).reply('tell me a joke');
      expect(m.source, isNull);
    });
  });
}
