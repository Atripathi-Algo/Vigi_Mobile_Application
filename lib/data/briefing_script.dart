import '../app/fmt.dart';
import 'models.dart';
import 'store.dart';

String _count(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// What K says aloud in the dawn briefing: the day ahead in a few plain sentences, from the user's own data.
String dawnScript(VigilStore s, DateTime now) {
  final String name = s.nickname;
  final List<Objective> primary = s.prioritised().take(3).toList();
  final List<Block> events = s.todayBlocks.where((Block b) => b.kind == BlockKind.event).toList()..sort((Block a, Block b) => a.startMin.compareTo(b.startMin));
  final int crit = s.critCount;
  final List<String> p = <String>[
    '${Fmt.greeting(now)}${name.isEmpty ? '' : ', $name'}.',
    '${_count(s.open.length, 'objective', 'objectives')} open${crit > 0 ? ', $crit critical' : ''}${events.isEmpty ? '' : ', and ${_count(events.length, 'event', 'events')} today'}.',
    if (primary.isNotEmpty) 'Start with ${primary.first.title}${primary.first.dueMin == null ? '' : ', due at ${Fmt.hm(primary.first.dueMin!)}'}.',
    if (events.isNotEmpty) 'First event: ${events.first.title} at ${Fmt.hm(events.first.startMin)}.',
    if (s.lastNight != null) 'You slept ${Fmt.dur(s.lastNight!.asleep)}.',
  ];
  return p.join(' ');
}

/// What K says aloud in the night debrief.
String nightScript(VigilStore s, DateTime now) {
  final String name = s.nickname;
  final int spent = s.txns.where((Txn t) => t.at.year == now.year && t.at.month == now.month && t.at.day == now.day).fold(0, (int a, Txn t) => a + t.paise);
  final List<Objective> next = s.prioritised();
  final List<String> p = <String>[
    'Stand down${name.isEmpty ? '' : ', $name'}.',
    '${_count(s.cleared.length, 'objective', 'objectives')} cleared, ${s.open.length} still open.',
    'Water ${Fmt.litres(s.waterMl)} of ${Fmt.litres(s.waterTargetMl)} litres.',
    if (spent > 0) 'You spent ${Fmt.money(spent)} today.',
    if (next.isNotEmpty) 'First up tomorrow: ${next.first.title}.',
  ];
  return p.join(' ');
}
