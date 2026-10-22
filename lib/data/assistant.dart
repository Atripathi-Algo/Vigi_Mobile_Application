import '../api/cloud_ai.dart';
import '../app/fmt.dart';
import '../vigil/vigil.dart';
import 'capture_parser.dart';
import 'models.dart';
import 'store.dart';

/// On-device assistant: a keyword router over the store, with an optional
/// cloud answer for open-ended questions when a key is set in `.env` and
/// "Cloud AI" is switched on in Loadout. Numbers always come from the store.
class Assistant {
  Assistant(this.store);

  final VigilStore store;

  /// True when the last reply came from the cloud model.
  bool lastWasCloud = false;

  static bool _has(String q, String pattern) => RegExp(pattern).hasMatch(q);

  Future<ChatMsg> reply(String text) async {
    final String q = text.toLowerCase().trim();
    final DateTime now = DateTime.now();
    lastWasCloud = false;

    ChatMsg msg(String t, {List<(String, String)>? diff, List<double>? chart, bool alert = false, bool undoable = false}) =>
        ChatMsg(fromUser: false, text: t, at: now, diff: diff, chart: chart, alert: alert, undoable: undoable);

    // Commands first, so ordinary words in a task title cannot hijack them.
    final RegExpMatch? cmd = RegExp(r'^(add|remind me to|remind me|remind|log|capture)\s+(.+)$').firstMatch(q);
    if (cmd != null) {
      final String body = text.trim().substring(text.trim().length - cmd.group(2)!.length);
      final CaptureDraft d = CaptureParser.parse(body);
      final bool ok = store.commitCapture(d, Threat.routine) != null;
      if (ok) {
        return msg('Logged ${CaptureParser.typeLabel(d.type).toLowerCase()}.', diff: <(String, String)>[('LOGGED', d.type == CaptureType.spend ? '${d.title} ${Fmt.money(d.paise ?? 0)}' : d.raw)], undoable: true);
      }
      return msg('Could not log that. For a spend, include an amount.');
    }
    final RegExpMatch? water = RegExp(r'\b(\d{2,4})\s*ml\b').firstMatch(q);
    if (water != null && _has(q, r'\b(water|drank|drink|log|hydrat)')) {
      final int ml = int.parse(water.group(1)!);
      store.logWater(ml);
      return msg('Logged. Hydration ${Fmt.litres(store.waterMl)} of ${Fmt.litres(store.waterTargetMl)} L.', diff: <(String, String)>[('LOGGED', '+$ml ml water')], undoable: true);
    }

    if (_has(q, r'\b(overdue|late|behind)\b')) {
      final List<Objective> o = store.open.where((Objective e) => e.isOverdue(now)).toList();
      if (o.isEmpty) return msg('No overdue objectives.');
      return msg('${o.length} overdue: ${o.map((Objective e) => e.title).join('; ')}. Recommend clearing "${o.first.title}" first.', alert: true);
    }
    if (_has(q, r'\b(plan|schedule)\b|\bmy day\b|\btoday\b')) {
      final Block? nb = store.nextBlock(now);
      final Objective? crit = store.open.where((Objective e) => e.threat == Threat.crit).firstOrNull;
      return msg(
        '${store.open.length} objectives open, ${store.critCount} critical. '
        '${nb == null ? 'No more meetings today.' : 'Next op ${Fmt.hm(nb.startMin)} ${nb.title}.'} '
        '${crit == null ? '' : 'Protect the focus window for "${crit.title}". '}Focus planned ${Fmt.durCompact(store.focusMinPlanned)}.',
      );
    }
    if (_has(q, r'\b(water|hydrat\w*)\b')) {
      return msg('Hydration ${Fmt.litres(store.waterMl)} of ${Fmt.litres(store.waterTargetMl)} L. Recommend 500 ml now.');
    }
    if (_has(q, r'\b(steps?|walk\w*)\b')) {
      final int? s = store.steps;
      return msg(s == null ? 'No data for steps. Grant Activity access in Boot or Vitals.' : 'Steps $s of ${store.stepTarget}. ${store.stepTarget - s > 0 ? '${store.stepTarget - s} to target.' : 'Target met.'}');
    }
    if (_has(q, r'\b(sleep|bed|bedtime|wake)\b')) {
      return msg('Sleep debt ${Fmt.dur(store.debtMin)}. Lights out ${Fmt.hm(store.recommendedBed)}, wake ${Fmt.hm(store.tonightRow.wake)}. Wind-down ${Fmt.hm(store.windDownAt)}.');
    }
    if (_has(q, r'\b(week|report|spend|spending|money|ledger|budget)\b')) {
      final int pct = (store.monthSpentPaise * 100 / store.monthBudgetPaise).round();
      final (String, int)? op = store.overPaceCategory;
      return msg(
        'Month spend ${Fmt.money(store.monthSpentPaise)} of ${Fmt.money(store.monthBudgetPaise)} ($pct%). '
        '${op == null ? 'All categories on pace.' : '${op.$1[0]}${op.$1.substring(1).toLowerCase()} is ${op.$2}% over pace.'} '
        'Recommend a cap of ${Fmt.money(store.safeToSpendPaise)} today.',
        chart: <double>[3, 5, 4, 7, 6, 2, 4],
      );
    }
    if (_has(q, r'\b(screen|phone|usage)\b')) {
      return msg('Screen ${Fmt.durCompact(store.screenTodayMin)} of ${Fmt.durCompact(store.screenLineMin)} line. Social is 13 min over. Recommend arming Night Shield.');
    }

    if (store.toggles['cloudAi'] == true) {
      final String? ans = await askCloud(text, store.sitrep(now));
      if (ans != null) {
        lastWasCloud = true;
        return msg(ans);
      }
      return msg('Local mode: reduced planning. Ask about plan, overdue, water, steps, sleep, spend or screen.');
    }
    return msg('No handler for that on-device. Try: plan my day, what\'s overdue, week report, sleep, steps, or turn on Cloud AI in Loadout.');
  }
}
