import 'dart:ui' show VoidCallback;

import 'package:http/http.dart' as http;

import '../api/cloud_ai.dart';
import '../app/env.dart';
import '../app/fmt.dart';
import '../services/local_brain.dart';
import '../vigil/vigil.dart';
import 'agent.dart';
import 'brain_pipeline.dart';
import 'brain_prompt.dart';
import 'capture_parser.dart';
import 'models.dart';
import 'store.dart';

/// The assistant, K. Order of preference, and what each one may do:
///  1. Rules decide clear commands exactly (instant, no model).
///  2. Questions about the user's own data are answered from the store (exact numbers; never leave the phone).
///  3. Open chat and unusual phrasing: the optional Cloud AI if the user switched it on and gave a key (it gets only
///     the question and earlier open-chat turns, never the app's data, and cannot change anything), else K's
///     on-device brain (MiniCPM5-1B), whose proposed change is checked against the user's own words first.
///  4. The keyword router, which always works and is the fallback when a model call fails.
class Assistant {
  Assistant(this.store, {this.client, LocalBrain? brain}) : brain = brain ?? LocalBrain.instance;

  final VigilStore store;

  /// K's on-device model.
  final LocalBrain brain;

  /// True when the last reply came from K's on-device model.
  bool lastWasLocal = false;

  /// For tests; the real app uses a fresh client per call.
  final http.Client? client;

  /// True when the last reply came from the cloud model.
  bool lastWasCloud = false;

  /// The model that gave the last cloud reply.
  String? lastModel;

  List<(bool, String)> _pairs(String current) {
    final List<ChatMsg> chat = store.chat;
    final List<ChatMsg> prior = chat.isNotEmpty && chat.last.fromUser && chat.last.text == current ? chat.sublist(0, chat.length - 1) : chat;
    return <(bool, String)>[for (final ChatMsg m in prior.skip(prior.length > 10 ? prior.length - 10 : 0)) (m.fromUser, m.text)];
  }

  /// Earlier open-chat turns only (questions answered by a model), so nothing from the user's own data is sent to the cloud.
  List<ChatTurn> _openChatHistory(String current) {
    final List<ChatMsg> chat = store.chat;
    final List<ChatMsg> prior = chat.isNotEmpty && chat.last.fromUser && chat.last.text == current ? chat.sublist(0, chat.length - 1) : chat;
    final List<ChatTurn> out = <ChatTurn>[];
    for (int i = 0; i + 1 < prior.length; i++) {
      final ChatMsg r = prior[i + 1];
      if (prior[i].fromUser && !r.fromUser && (r.source == ReplySource.model || r.source == ReplySource.cloud)) {
        out
          ..add(ChatTurn(true, prior[i].text))
          ..add(ChatTurn(false, r.text));
      }
    }
    return out.length > 8 ? out.sublist(out.length - 8) : out;
  }

  /// Applies a plan to the store and turns the outcome into a chat message.
  ChatMsg _apply(AgentPlan plan, String? note, DateTime now) {
    final AgentResult res = applyAgentPlan(store, plan, now: now);
    // When nothing could be done, the sentence that promised it would be false, so only the reasons are said.
    final bool nothingDone = res.diff.isEmpty && res.failed.isNotEmpty;
    final String spoken = <String>[if (plan.say.isNotEmpty && !nothingDone) plan.say, ...res.failed].join(' ');
    return ChatMsg(
      fromUser: false,
      text: spoken.isEmpty ? 'Done.' : spoken,
      at: now,
      diff: res.diff.isEmpty ? null : res.diff,
      undoable: res.undo != null,
      onUndo: res.undo,
      alert: res.failed.isNotEmpty,
      note: note,
    );
  }

  static bool _has(String q, String pattern) => RegExp(pattern).hasMatch(q);

  /// [onPartial] gets the words of an on-device answer as they are written.
  Future<ChatMsg> reply(String text, {void Function(String partial)? onPartial}) async {
    final String q = text.toLowerCase().trim();
    final DateTime now = DateTime.now();
    final Stopwatch sw = Stopwatch()..start();
    lastWasCloud = false;
    lastWasLocal = false;
    lastModel = null;
    String? note;

    ChatMsg tag(ChatMsg m, ReplySource? source) {
      m.source = source;
      m.ms = sw.elapsedMilliseconds;
      return m;
    }

    ChatMsg msg(String t, {List<(String, String)>? diff, List<double>? chart, bool alert = false, VoidCallback? undo, String? noteOverride}) =>
        ChatMsg(fromUser: false, text: t, at: now, diff: diff, chart: chart, alert: alert, undoable: undo != null, onUndo: undo, note: noteOverride ?? note);

    // Rules decide clear commands exactly (no model, the same answer every time). Questions about the user's own
    // data go to the router below, so the numbers are always the real ones.
    final BrainFacts facts = factsFromStore(store, now);
    final Decision? decided = decideWithoutModel(text.trim(), facts);
    if (decided?.source == DecisionSource.rules) return tag(_apply(decided!.plan!, null, now), ReplySource.instant);
    final bool routerOnly = decided?.source == DecisionSource.router;

    // Open chat with Cloud AI on: plain sentences only, no app data sent, nothing changed. If the call fails, say why
    // and carry on with the on-device brain.
    if (decided == null && store.toggles['cloudAi'] == true && Env.hasCloudAi) {
      final CloudReply r = await askCloudDetailed(
        text.trim(),
        '',
        system: buildChatSystem(callsign: store.nickname, persona: store.persona, verbosity: store.verbosity),
        history: _openChatHistory(text),
        client: client,
      );
      if (r.text != null) {
        lastWasCloud = true;
        lastModel = r.model;
        return tag(ChatMsg(fromUser: false, text: r.text!.trim(), at: now, note: r.note), ReplySource.cloud);
      }
      note = 'Cloud AI failed: ${r.error}';
    }

    // K's on-device brain handles open language: general questions, chat, and commands the rules did not recognise.
    // What it proposes is checked against the user's own words before anything changes.
    Future<ChatMsg?> askModel() async {
      final CloudReply r = await brain.ask(
        facts,
        text.trim(),
        _pairs(text),
        onPartial: onPartial == null
            ? null
            : (String raw) {
                final String? words = partialSay(raw);
                if (words != null && words.isNotEmpty) onPartial(words);
              },
      );
      if (r.text == null) {
        if (r.error == kBrainCancelled) return tag(msg('Stopped.', noteOverride: null), null);
        note = r.error;
        return null;
      }
      final AgentPlan proposed = parseAgentPlan(r.text!);
      final ({AgentPlan plan, bool dropped}) v = validateModelPlan(proposed, text, facts);
      if (v.dropped) {
        // Its sentence may describe a change that was not made, so it is not shown.
        note = 'K proposed a change that did not match what you said, so it was ignored.';
        return null;
      }
      lastWasLocal = true;
      lastModel = r.model;
      return tag(_apply(v.plan, r.note, now), ReplySource.model);
    }

    if (brain.usable && !routerOnly) {
      final ChatMsg? m = await askModel();
      if (m != null) return m;
    }

    // Commands first, so ordinary words in a task title cannot hijack them.
    final RegExpMatch? cmd = RegExp(r'^(add|remind me to|remind me|remind|log|capture)\s+(.+)$').firstMatch(q);
    if (cmd != null) {
      final String body = text.trim().substring(text.trim().length - cmd.group(2)!.length);
      final CaptureDraft d = CaptureParser.parse(body);
      final VoidCallback? undo = store.commitCapture(d, Threat.routine);
      if (undo != null) {
        return tag(msg('Logged ${CaptureParser.typeLabel(d.type).toLowerCase()}.', diff: <(String, String)>[('LOGGED', d.type == CaptureType.spend ? '${d.title} ${Fmt.money(d.paise ?? 0)}' : d.raw)], undo: undo), ReplySource.instant);
      }
      return tag(msg('Could not log that. For a spend, include an amount.'), null);
    }
    if (_has(q, r'\b(overdue|late|behind)\b')) {
      final List<Objective> o = store.open.where((Objective e) => e.isOverdue(now)).toList();
      if (o.isEmpty) return msg('No overdue objectives.');
      return tag(msg('${o.length} overdue: ${o.map((Objective e) => e.title).join('; ')}. Recommend clearing "${o.first.title}" first.', alert: true), ReplySource.data);
    }
    if (_has(q, r'\b(water|hydrat\w*)\b')) {
      return tag(msg('Hydration ${Fmt.litres(store.waterMl)} of ${Fmt.litres(store.waterTargetMl)} L. Recommend 500 ml now.'), ReplySource.data);
    }
    if (_has(q, r'\b(steps?|walk\w*)\b')) {
      final int? s = store.steps;
      return tag(msg(s == null ? 'No data for steps. Grant Activity access in Boot or Vitals.' : 'Steps $s of ${store.stepTarget}. ${store.stepTarget - s > 0 ? '${store.stepTarget - s} to target.' : 'Target met.'}'), ReplySource.data);
    }
    if (_has(q, r'\b(sleep|bed|bedtime|wake)\b')) {
      final String sl = store.lastNight == null ? 'No data for sleep. Connect Health Connect or log a night.' : (store.hasSleepStats ? 'Last night ${Fmt.dur(store.lastNight!.asleep)}, debt ${Fmt.dur(store.debtMin)}.' : 'Last night ${Fmt.dur(store.lastNight!.asleep)}. Debt builds after 3 nights.');
      return tag(msg('$sl Lights out ${Fmt.hm(store.recommendedBed)}, wake ${Fmt.hm(store.tonightRow.wake)}. Wind-down ${Fmt.hm(store.windDownAt)}.'), ReplySource.data);
    }
    if (_has(q, r'\b(week|report|spend|spending|money|ledger|budget)\b')) {
      if (store.monthTxns.isEmpty) return msg('No data for spend. Log an expense first, for example: spent 250 on lunch.');
      final int? pct = store.monthSpentPercent;
      return tag(msg(pct == null
          ? 'Month spend ${Fmt.money(store.monthSpentPaise)}. No budget set: add one in the Ledger.'
          : 'Month spend ${Fmt.money(store.monthSpentPaise)} of ${Fmt.money(store.monthBudgetPaise)} ($pct%). Recommend a cap of ${Fmt.money(store.safeToSpendPaise)} today.'), ReplySource.data);
    }
    if (_has(q, r'\b(screen|phone|usage)\b')) {
      return tag(msg('No data for screen time. The usage-access bridge is not built yet.'), ReplySource.data);
    }

    // Broadest match last, so "how much water today" is a water question and not a plan.
    if (_has(q, r'\b(plan|schedule)\b|\bmy day\b|\btoday\b')) {
      final Block? nb = store.nextBlock(now);
      final Objective? crit = store.open.where((Objective e) => e.threat == Threat.crit).firstOrNull;
      return tag(msg(
        '${store.open.length} objectives open, ${store.critCount} critical. '
        '${nb == null ? 'No more meetings today.' : 'Next op ${Fmt.hm(nb.startMin)} ${nb.title}.'} '
        '${crit == null ? '' : 'Protect the focus window for "${crit.title}". '}Focus planned ${Fmt.durCompact(store.focusMinPlanned)}.',
      ), ReplySource.data);
    }

    if (note != null) return tag(msg('Local mode: reduced planning. Ask about plan, overdue, water, steps, sleep, spend or screen.', alert: true), null);
    if (routerOnly && brain.usable) {
      final ChatMsg? m = await askModel();
      if (m != null) return m;
    }
    return tag(msg('No handler for that on-device. Try: plan my day, what\'s overdue, week report, sleep, steps, or turn on Cloud AI in Loadout.'), null);
  }
}
