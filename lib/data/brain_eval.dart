import '../services/local_brain.dart';
import 'agent.dart';
import 'brain_prompt.dart';

/// A fixed set of requests with the action each should produce, run on the phone to measure how accurate the
/// chosen model file is (Q4_K_M or Q8_0) before trusting it. It only reads the plan; nothing is applied.
class BrainCase {
  const BrainCase(this.utterance, this.type, {this.args = const <String, Object>{}, this.say});

  final String utterance;

  /// The expected action type, or null when the right answer is no action at all.
  final String? type;

  /// Fields that must match: strings compared case-insensitively after trimming, numbers exactly.
  final Map<String, Object> args;

  /// Words the spoken reply must contain (case-insensitive), for questions answered from the context.
  final String? say;
}

/// The facts every case is asked against.
final BrainFacts kEvalFacts = BrainFacts(
  now: DateTime(2026, 10, 23, 14, 30),
  callsign: 'Batman',
  objectives: const <String>['Send weekly report · due 17:00 · high', 'Call the plumber', 'Book dentist appointment'],
  events: const <String>['09:00-09:30 Standup', '16:00-17:00 Vendor sync'],
  protocols: const <String>['Read 20 pages', 'Workout 30 min', 'Meditate 10 min (done)'],
  waterMl: 750,
  steps: 4200,
  sleep: 'last night 6h 50m, debt 1h 20m',
  money: 'spent ₹12,400 this month of ₹40,000',
);

const List<BrainCase> kEvalCases = <BrainCase>[
  BrainCase('log a glass of water', 'log_water', args: <String, Object>{'ml': 250}),
  BrainCase('I drank 500 ml of water', 'log_water', args: <String, Object>{'ml': 500}),
  BrainCase('add 300 millilitres of water', 'log_water', args: <String, Object>{'ml': 300}),
  BrainCase('remind me to call mom tomorrow at 6 pm', 'add_objective', args: <String, Object>{'due': '18:00', 'day': 'tomorrow'}),
  BrainCase('add a task to buy groceries', 'add_objective'),
  BrainCase('I need to submit the tax form by 9 pm tonight, it is critical', 'add_objective', args: <String, Object>{'due': '21:00', 'threat': 'crit'}),
  BrainCase('schedule a meeting with Ravi at 11 am tomorrow', 'add_event', args: <String, Object>{'start': '11:00', 'day': 'tomorrow'}),
  BrainCase('put lunch with Priya on my calendar at 1 pm for an hour', 'add_event', args: <String, Object>{'start': '13:00', 'end': '14:00'}),
  BrainCase('spent 250 on lunch', 'log_expense', args: <String, Object>{'amount': 250, 'category': 'FOOD'}),
  BrainCase('paid 1200 for the electricity bill', 'log_expense', args: <String, Object>{'amount': 1200, 'category': 'BILLS'}),
  BrainCase('uber to the airport cost 640', 'log_expense', args: <String, Object>{'amount': 640, 'category': 'TRANSPORT'}),
  BrainCase('note: ask the landlord about the deposit', 'add_note'),
  BrainCase('I called the plumber', 'complete_objective', args: <String, Object>{'title': 'Call the plumber'}),
  BrainCase('the weekly report is done', 'complete_objective', args: <String, Object>{'title': 'Send weekly report'}),
  BrainCase('I did my workout', 'check_protocol', args: <String, Object>{'name': 'Workout 30 min'}),
  BrainCase('tick off reading', 'check_protocol', args: <String, Object>{'name': 'Read 20 pages'}),
  BrainCase('how much water have I had today?', null, say: '750'),
  BrainCase('how many steps so far?', null, say: '4200'),
  BrainCase('how did I sleep?', null, say: '6'),
  BrainCase('what is on my calendar today?', null, say: 'vendor'),
  BrainCase('what is the capital of Japan?', null, say: 'tokyo'),
  BrainCase('what is 15 percent of 2400?', null, say: '360'),
  BrainCase('hello K', null),
  BrainCase('thanks', null),
];

class EvalResult {
  const EvalResult(this.c, this.ok, this.detail, this.ms);

  final BrainCase c;
  final bool ok;
  final String detail;
  final int ms;
}

class EvalReport {
  const EvalReport(this.results);

  final List<EvalResult> results;

  int get passed => results.where((EvalResult r) => r.ok).length;

  double get accuracy => results.isEmpty ? 0 : passed / results.length;

  int get averageMs => results.isEmpty ? 0 : (results.fold(0, (int a, EvalResult r) => a + r.ms) / results.length).round();
}

/// Whether [plan] is the right answer to [c]. Pure, so it is unit-tested without a model.
({bool ok, String detail}) judge(BrainCase c, AgentPlan plan) {
  if (c.type == null) {
    if (plan.actions.isNotEmpty) return (ok: false, detail: 'did ${plan.actions.map((AgentAction a) => a.type).join(', ')} but should only answer');
  } else {
    final Iterable<AgentAction> hits = plan.actions.where((AgentAction a) => a.type == c.type);
    if (hits.isEmpty) return (ok: false, detail: 'expected ${c.type}, got ${plan.actions.isEmpty ? 'no action' : plan.actions.map((AgentAction a) => a.type).join(', ')}');
    if (plan.actions.length > 1) return (ok: false, detail: 'did extra actions: ${plan.actions.map((AgentAction a) => a.type).join(', ')}');
    final AgentAction a = hits.first;
    for (final MapEntry<String, Object> e in c.args.entries) {
      final dynamic got = a.args[e.key];
      final Object want = e.value;
      final bool same = want is num ? got is num && got.toDouble() == want.toDouble() : got is String && got.trim().toLowerCase() == (want as String).trim().toLowerCase();
      if (!same) return (ok: false, detail: '${e.key} was ${got ?? 'missing'}, expected $want');
    }
  }
  if (c.say != null && !plan.say.toLowerCase().contains(c.say!.toLowerCase())) return (ok: false, detail: 'reply "${plan.say}" lacks "${c.say}"');
  return (ok: true, detail: 'ok');
}

/// Runs every case through the real model. [onProgress] gets (done, total).
Future<EvalReport> runBrainEval(LocalBrain brain, {void Function(int done, int total)? onProgress, List<BrainCase> cases = kEvalCases}) async {
  final List<EvalResult> out = <EvalResult>[];
  for (int i = 0; i < cases.length; i++) {
    final BrainCase c = cases[i];
    final Stopwatch sw = Stopwatch()..start();
    final reply = await brain.ask(kEvalFacts, c.utterance, const <(bool, String)>[]);
    if (reply.text == null) {
      out.add(EvalResult(c, false, reply.error ?? 'no reply', sw.elapsedMilliseconds));
    } else {
      final r = judge(c, parseAgentPlan(reply.text!));
      out.add(EvalResult(c, r.ok, r.detail, sw.elapsedMilliseconds));
    }
    onProgress?.call(i + 1, cases.length);
  }
  return EvalReport(out);
}
