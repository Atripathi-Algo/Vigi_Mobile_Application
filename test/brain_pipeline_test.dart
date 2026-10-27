import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/data/agent.dart';
import 'package:vigil/data/brain_eval.dart';
import 'package:vigil/data/brain_pipeline.dart';

AgentAction only(Decision? d) {
  expect(d, isNotNull);
  expect(d!.source, DecisionSource.rules);
  expect(d.plan!.actions.length, 1, reason: 'exactly one action');
  return d.plan!.actions.single;
}

Decision? decide(String q) => decideWithoutModel(q, kEvalFacts);

AgentPlan modelPlan(List<Map<String, dynamic>> actions, [String say = 'ok']) => AgentPlan(say, <AgentAction>[for (final Map<String, dynamic> a in actions) AgentAction(a['type'] as String, a)]);

void main() {
  group('rules decide clear commands exactly', () {
    test('water', () {
      expect(only(decide('log a glass of water')).args['ml'], 250);
      expect(only(decide('I drank 500 ml of water')).args['ml'], 500);
      expect(only(decide('add 300 millilitres of water')).args['ml'], 300);
      expect(only(decide('log 500 ml water')).args['ml'], 500);
      expect(only(decide('I drank two glasses of water')).args['ml'], 500);
      expect(only(decide('had a bottle of water')).args['ml'], 500);
      expect(only(decide('drank 1.5 litres of water')).args['ml'], 1500);
      expect(decide('I drank a glass of milk'), isNull, reason: 'not water');
    });

    test('reminders and tasks, with time, day and urgency', () {
      AgentAction a = only(decide('remind me to call mom tomorrow at 6 pm'));
      expect(a.type, 'add_objective');
      expect((a.args['title'], a.args['due'], a.args['day']), ('Call mom', '18:00', 'tomorrow'));

      a = only(decide('remind me to call mom tomorrow evening'));
      expect((a.args['title'], a.args.containsKey('due'), a.args['day']), ('Call mom', false, 'tomorrow'));

      a = only(decide('add a task to buy groceries'));
      expect((a.args['title'], a.args.containsKey('due'), a.args.containsKey('day')), ('Buy groceries', false, false));

      a = only(decide('I need to submit the tax form by 9 pm tonight, it is critical'));
      expect((a.args['title'], a.args['due'], a.args['day'], a.args['threat']), ('Submit the tax form', '21:00', 'today', 'crit'));

      a = only(decide('remind me to pay 500 to Ravi tomorrow'));
      expect((a.type, a.args['title']), ('add_objective', 'Pay 500 to Ravi'), reason: 'a reminder, not a spend');

      expect(decide('remind me to call mom on friday'), isNull, reason: 'weekdays are left to the model or the user');
    });

    test('events, with their length', () {
      AgentAction a = only(decide('schedule a meeting with Ravi at 11 am tomorrow'));
      expect(a.type, 'add_event');
      expect((a.args['title'], a.args['start'], a.args['end'], a.args['day']), ('Meeting with Ravi', '11:00', '11:30', 'tomorrow'));

      a = only(decide('put lunch with Priya on my calendar at 1 pm for an hour'));
      expect((a.args['title'], a.args['start'], a.args['end']), ('Lunch with Priya', '13:00', '14:00'));

      a = only(decide('book a call with the vendor at 15:30 for 45 minutes'));
      expect((a.args['start'], a.args['end']), ('15:30', '16:15'));

      expect(decide('schedule a meeting with Ravi'), isNull, reason: 'no time, so ask the model or the user');
    });

    test('spending, with category', () {
      AgentAction a = only(decide('spent 250 on lunch'));
      expect((a.type, a.args['amount'], a.args['category'], a.args['title']), ('log_expense', 250, 'FOOD', 'Lunch'));
      a = only(decide('paid 1200 for the electricity bill'));
      expect((a.args['amount'], a.args['category']), (1200, 'BILLS'));
      a = only(decide('uber to the airport cost 640'));
      expect((a.args['amount'], a.args['category'], a.args['title']), (640, 'TRANSPORT', 'Uber to the airport'));
      a = only(decide('spent Rs. 1,250 on shoes'));
      expect((a.args['amount'], a.args['category']), (1250, 'SHOPPING'));
      expect(decide('I worked out for 30 minutes'), isNull, reason: 'a quantity, not money');
      expect(decide('meeting at 3 pm'), isNull, reason: 'a time, not money');
    });

    test('notes', () {
      expect(only(decide('note: ask the landlord about the deposit')).args['text'], 'Ask the landlord about the deposit');
      expect(only(decide('remember that the wifi password is on the fridge')).args['text'], 'The wifi password is on the fridge');
    });

    test('finishing something matches the user\'s real objectives and protocols', () {
      AgentAction a = only(decide('I called the plumber'));
      expect((a.type, a.args['title']), ('complete_objective', 'Call the plumber'));
      a = only(decide('the weekly report is done'));
      expect((a.type, a.args['title']), ('complete_objective', 'Send weekly report'));
      a = only(decide('I did my workout'));
      expect((a.type, a.args['name']), ('check_protocol', 'Workout 30 min'));
      a = only(decide('tick off reading'));
      expect((a.type, a.args['name']), ('check_protocol', 'Read 20 pages'));
      a = only(decide('finished booking the dentist'));
      expect((a.type, a.args['title']), ('complete_objective', 'Book dentist appointment'));
      expect(decide('I finished the quarterly audit'), isNull, reason: 'matches nothing the user has');
    });
  });

  group('questions and chat are not commands', () {
    test('questions about the user\'s own data go to the router', () {
      for (final String q in <String>['how much water have I had today?', 'how many steps so far?', 'how did I sleep?', 'what is on my calendar today?', 'what did I spend this month', 'what is overdue?']) {
        expect(decide(q)?.source, DecisionSource.router, reason: q);
        expect(decide(q)?.plan, isNull);
      }
    });

    test('general questions and chat go to the model, never to a rule', () {
      for (final String q in <String>['what is the capital of Japan?', 'what is 15 percent of 2400?', 'hello K', 'thanks', 'tell me a joke', 'who wrote Hamlet?']) {
        expect(decide(q), isNull, reason: q);
      }
    });

    test('a question never triggers a rule even when it mentions a command word', () {
      expect(decide('did I log my water today?')?.source, DecisionSource.router);
      expect(decide('should I add a task for this?')?.source, isNot(DecisionSource.rules), reason: 'a question is never acted on');
    });
  });

  group('what the model proposes is checked against the user\'s words', () {
    test('an unrelated action is dropped, a supported one is kept', () {
      var v = validateModelPlan(modelPlan(<Map<String, dynamic>>[<String, dynamic>{'type': 'log_water', 'ml': 750}], 'I logged 750 ml.'), 'what is the capital of France', kEvalFacts);
      expect(v.dropped, isTrue);
      expect(v.plan.actions, isEmpty);
      v = validateModelPlan(modelPlan(<Map<String, dynamic>>[<String, dynamic>{'type': 'log_water', 'ml': 750}]), 'uber to the airport cost 640 maybe', kEvalFacts);
      expect(v.dropped, isTrue, reason: 'no mention of water');
      v = validateModelPlan(modelPlan(<Map<String, dynamic>>[<String, dynamic>{'type': 'log_expense', 'title': 'Taxi', 'amount': 640}]), 'the taxi cost 640 yesterday, log it', kEvalFacts);
      expect((v.dropped, v.plan.actions.single.type), (false, 'log_expense'));
      v = validateModelPlan(modelPlan(<Map<String, dynamic>>[<String, dynamic>{'type': 'log_expense', 'title': 'Taxi', 'amount': 999}]), 'the taxi cost 640, log it', kEvalFacts);
      expect(v.dropped, isTrue, reason: 'the amount is not what the user said');
    });

    test('at most one action survives, and duplicates are cut', () {
      final v = validateModelPlan(
        modelPlan(<Map<String, dynamic>>[
          <String, dynamic>{'type': 'log_expense', 'title': 'Lunch', 'amount': 250},
          <String, dynamic>{'type': 'log_expense', 'title': 'Lunch', 'amount': 250},
          <String, dynamic>{'type': 'log_water', 'ml': 250},
        ]),
        'log 250 for the lunch i had',
        kEvalFacts,
      );
      expect(v.plan.actions.length, 1);
      expect(v.dropped, isTrue);
    });

    test('a completion must name something the user said', () {
      var v = validateModelPlan(modelPlan(<Map<String, dynamic>>[<String, dynamic>{'type': 'complete_objective', 'title': 'Call the plumber'}]), 'did the plumber come', kEvalFacts);
      expect(v.dropped, isTrue, reason: 'a question');
      v = validateModelPlan(modelPlan(<Map<String, dynamic>>[<String, dynamic>{'type': 'complete_objective', 'title': 'Send weekly report'}]), 'ok the weekly report is sorted', kEvalFacts);
      expect(v.dropped, isFalse);
      v = validateModelPlan(modelPlan(<Map<String, dynamic>>[<String, dynamic>{'type': 'check_protocol', 'name': 'Workout 30 min'}]), 'I am so tired today', kEvalFacts);
      expect(v.dropped, isTrue);
    });

    test('a plan with no actions passes untouched', () {
      final v = validateModelPlan(modelPlan(const <Map<String, dynamic>>[], 'Paris.'), 'what is the capital of France', kEvalFacts);
      expect((v.dropped, v.plan.say), (false, 'Paris.'));
    });
  });

  test('every sample request is either decided right by the rules, answered by the router, or left to the model', () {
    int rules = 0, router = 0, model = 0;
    for (final BrainCase c in kEvalCases) {
      final Decision? d = decide(c.utterance);
      if (d == null) {
        model++;
        expect(c.type, isNull, reason: '"${c.utterance}" should not need the model: it expects ${c.type}');
      } else if (d.source == DecisionSource.router) {
        router++;
        expect(c.type, isNull, reason: c.utterance);
      } else {
        rules++;
        final r = judge(c, d.plan!);
        expect(r.ok, isTrue, reason: '"${c.utterance}": ${r.detail}');
      }
    }
    expect((rules, router, model), (16, 4, 4));
  });
}
