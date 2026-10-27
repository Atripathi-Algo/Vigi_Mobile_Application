import 'dart:ui' show VoidCallback;

import 'package:http/http.dart' as http;

import '../api/cloud_ai.dart';
import '../app/env.dart';
import '../app/fmt.dart';
import '../services/local_brain.dart';
import '../vigil/vigil.dart';
import 'agent.dart';
import 'brain_prompt.dart';
import 'capture_parser.dart';
import 'models.dart';
import 'store.dart';

/// The assistant, K. Order of preference:
///  1. Cloud AI, only if the user switched it on and gave a key (optional; never the default).
///  2. K's on-device brain (MiniCPM5-1B) once it is downloaded: understands plain language, answers, and can make
///     small undoable changes (see agent.dart). No key, no network, no cost.
///  3. A keyword router over the store, which always works and is also the fallback when a model call fails.
/// Numbers always come from the store.
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

  /// Earlier turns for the model, newest last, without the message being answered.
  List<ChatTurn> _history(String current) {
    final List<ChatMsg> chat = store.chat;
    final List<ChatMsg> prior = chat.isNotEmpty && chat.last.fromUser && chat.last.text == current ? chat.sublist(0, chat.length - 1) : chat;
    return <ChatTurn>[for (final ChatMsg m in prior.skip(prior.length > 10 ? prior.length - 10 : 0)) ChatTurn(m.fromUser, m.text)];
  }

  List<(bool, String)> _pairs(String current) => <(bool, String)>[for (final ChatTurn t in _history(current)) (t.fromUser, t.text)];

  /// Applies a model's JSON reply to the store and turns it into a chat message.
  ChatMsg _fromPlan(String raw, String? note, DateTime now) {
    final AgentPlan plan = parseAgentPlan(raw);
    final AgentResult res = applyAgentPlan(store, plan, now: now);
    final String spoken = <String>[if (plan.say.isNotEmpty) plan.say, ...res.failed].join(' ');
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

  Future<ChatMsg> reply(String text) async {
    final String q = text.toLowerCase().trim();
    final DateTime now = DateTime.now();
    lastWasCloud = false;
    lastWasLocal = false;
    lastModel = null;
    String? cloudNote;

    ChatMsg msg(String t, {List<(String, String)>? diff, List<double>? chart, bool alert = false, VoidCallback? undo, String? note}) =>
        ChatMsg(fromUser: false, text: t, at: now, diff: diff, chart: chart, alert: alert, undoable: undo != null, onUndo: undo, note: note ?? cloudNote);

    // Cloud AI on: the model handles the request and may act on it. If the call fails, say why and answer locally.
    if (store.toggles['cloudAi'] == true && Env.hasCloudAi) {
      final CloudReply r = await askCloudDetailed(
        text,
        store.sitrep(now),
        system: buildAgentSystem(now: now, callsign: store.callsign, persona: store.persona, verbosity: store.verbosity),
        history: _history(text),
        json: true,
        client: client,
      );
      if (r.text != null) {
        lastWasCloud = true;
        lastModel = r.model;
        return _fromPlan(r.text!, r.note, now);
      }
      cloudNote = 'Cloud AI failed: ${r.error}';
    }

    // An explicit amount of water is exact, so it needs no model.
    final RegExpMatch? water = RegExp(r'\b(\d{2,4})\s*ml\b').firstMatch(q);
    if (water != null && _has(q, r'\b(water|drank|drink|log|hydrat)')) {
      final int ml = int.parse(water.group(1)!);
      store.logWater(ml);
      return msg('Logged. Hydration ${Fmt.litres(store.waterMl)} of ${Fmt.litres(store.waterTargetMl)} L.', diff: <(String, String)>[('LOGGED', '+$ml ml water')], undo: () => store.logWater(-ml));
    }

    // K's on-device brain handles everything else in plain language. If it fails, the router below still answers.
    if (cloudNote == null && brain.usable) {
      final CloudReply r = await brain.ask(factsFromStore(store, now), text.trim(), _pairs(text));
      if (r.text != null) {
        lastWasLocal = true;
        lastModel = r.model;
        return _fromPlan(r.text!, r.note, now);
      }
      cloudNote = r.error;
    }

    // Commands first, so ordinary words in a task title cannot hijack them.
    final RegExpMatch? cmd = RegExp(r'^(add|remind me to|remind me|remind|log|capture)\s+(.+)$').firstMatch(q);
    if (cmd != null) {
      final String body = text.trim().substring(text.trim().length - cmd.group(2)!.length);
      final CaptureDraft d = CaptureParser.parse(body);
      final VoidCallback? undo = store.commitCapture(d, Threat.routine);
      if (undo != null) {
        return msg('Logged ${CaptureParser.typeLabel(d.type).toLowerCase()}.', diff: <(String, String)>[('LOGGED', d.type == CaptureType.spend ? '${d.title} ${Fmt.money(d.paise ?? 0)}' : d.raw)], undo: undo);
      }
      return msg('Could not log that. For a spend, include an amount.');
    }
    if (_has(q, r'\b(overdue|late|behind)\b')) {
      final List<Objective> o = store.open.where((Objective e) => e.isOverdue(now)).toList();
      if (o.isEmpty) return msg('No overdue objectives.');
      return msg('${o.length} overdue: ${o.map((Objective e) => e.title).join('; ')}. Recommend clearing "${o.first.title}" first.', alert: true);
    }
    if (_has(q, r'\b(water|hydrat\w*)\b')) {
      return msg('Hydration ${Fmt.litres(store.waterMl)} of ${Fmt.litres(store.waterTargetMl)} L. Recommend 500 ml now.');
    }
    if (_has(q, r'\b(steps?|walk\w*)\b')) {
      final int? s = store.steps;
      return msg(s == null ? 'No data for steps. Grant Activity access in Boot or Vitals.' : 'Steps $s of ${store.stepTarget}. ${store.stepTarget - s > 0 ? '${store.stepTarget - s} to target.' : 'Target met.'}');
    }
    if (_has(q, r'\b(sleep|bed|bedtime|wake)\b')) {
      final String sl = store.lastNight == null ? 'No data for sleep. Connect Health Connect or log a night.' : (store.hasSleepStats ? 'Last night ${Fmt.dur(store.lastNight!.asleep)}, debt ${Fmt.dur(store.debtMin)}.' : 'Last night ${Fmt.dur(store.lastNight!.asleep)}. Debt builds after 3 nights.');
      return msg('$sl Lights out ${Fmt.hm(store.recommendedBed)}, wake ${Fmt.hm(store.tonightRow.wake)}. Wind-down ${Fmt.hm(store.windDownAt)}.');
    }
    if (_has(q, r'\b(week|report|spend|spending|money|ledger|budget)\b')) {
      if (store.monthTxns.isEmpty) return msg('No data for spend. Log an expense first, for example: spent 250 on lunch.');
      final int? pct = store.monthSpentPercent;
      return msg(pct == null
          ? 'Month spend ${Fmt.money(store.monthSpentPaise)}. No budget set: add one in the Ledger.'
          : 'Month spend ${Fmt.money(store.monthSpentPaise)} of ${Fmt.money(store.monthBudgetPaise)} ($pct%). Recommend a cap of ${Fmt.money(store.safeToSpendPaise)} today.');
    }
    if (_has(q, r'\b(screen|phone|usage)\b')) {
      return msg('No data for screen time. The usage-access bridge is not built yet.');
    }

    // Broadest match last, so "how much water today" is a water question and not a plan.
    if (_has(q, r'\b(plan|schedule)\b|\bmy day\b|\btoday\b')) {
      final Block? nb = store.nextBlock(now);
      final Objective? crit = store.open.where((Objective e) => e.threat == Threat.crit).firstOrNull;
      return msg(
        '${store.open.length} objectives open, ${store.critCount} critical. '
        '${nb == null ? 'No more meetings today.' : 'Next op ${Fmt.hm(nb.startMin)} ${nb.title}.'} '
        '${crit == null ? '' : 'Protect the focus window for "${crit.title}". '}Focus planned ${Fmt.durCompact(store.focusMinPlanned)}.',
      );
    }

    if (cloudNote != null) return msg('Local mode: reduced planning. Ask about plan, overdue, water, steps, sleep, spend or screen.', alert: true);
    return msg('No handler for that on-device. Try: plan my day, what\'s overdue, week report, sleep, steps, or turn on Cloud AI in Loadout.');
  }
}
