import '../app/fmt.dart';
import 'garage.dart';
import 'models.dart';
import 'store.dart';

enum HitKind { task, event, habit, note, spend, bill, bike }

/// One result of a search across the whole app.
class SearchHit {
  const SearchHit(this.kind, this.title, this.detail, this.route);

  final HitKind kind;
  final String title;
  final String detail;

  /// Where tapping it goes.
  final String route;

  String get kindLabel => switch (kind) {
        HitKind.task => 'Task',
        HitKind.event => 'Event',
        HitKind.habit => 'Habit',
        HitKind.note => 'Note',
        HitKind.spend => 'Spend',
        HitKind.bill => 'Bill',
        HitKind.bike => 'Bike',
      };
}

/// Every word of [query] must appear (case-insensitive) in an item's text. The amount of a spend is searchable too
/// ("fuel", "lunch 450"). Newest first within each kind, at most [limit] per kind.
List<SearchHit> searchAll(VigilStore s, String query, {int limit = 8}) {
  final List<String> words = query.toLowerCase().split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const <SearchHit>[];
  bool match(String text) {
    final String t = text.toLowerCase();
    return words.every(t.contains);
  }

  final List<SearchHit> out = <SearchHit>[];
  void add(Iterable<SearchHit> hits) => out.addAll(hits.take(limit));

  add(s.objectives.where((Objective o) => !o.dropped && match('${o.title} ${o.tag} ${o.sub ?? ''}')).map((Objective o) => SearchHit(HitKind.task, o.title, o.done ? 'Done' : o.meta, '/ops/objectives')));
  add(s.blocks.where((Block b) => b.kind == BlockKind.event && match(b.title)).map((Block b) => SearchHit(HitKind.event, b.title, '${Fmt.hm(b.startMin)}–${Fmt.hm(b.endMin)}${b.src == null ? '' : ' · ${b.src}'}', '/ops/timeline')));
  add(s.protocols.where((Protocol p) => match(p.name)).map((Protocol p) => SearchHit(HitKind.habit, p.name, 'Streak ${p.streakNow}', '/protocols/habits')));
  final List<Note> notes = s.notes.where((Note n) => match('${n.title} ${n.body}')).toList()..sort((Note a, Note b) => b.at.compareTo(a.at));
  add(notes.map((Note n) => SearchHit(HitKind.note, n.title, n.body.trim().isEmpty || n.body.trim() == n.title.trim() ? Fmt.dayStamp(n.at) : n.body, '/vault/log')));
  final List<Txn> spends = s.txns.where((Txn t) => match('${t.title} ${t.category} ${(t.paise / 100).round()}')).toList()..sort((Txn a, Txn b) => b.at.compareTo(a.at));
  add(spends.map((Txn t) => SearchHit(HitKind.spend, t.title, '${Fmt.money(t.paise)} · ${Fmt.dayStamp(t.at)} · ${t.category.toLowerCase()}', '/vault/ledger')));
  add(s.bills.where((Bill b) => match(b.name)).map((Bill b) => SearchHit(HitKind.bill, b.name, '${Fmt.money(b.paise)} · due ${b.due}', '/vault/ledger')));
  add(s.bikes.where((Bike b) => match('${b.make} ${b.model}')).map((Bike b) => SearchHit(HitKind.bike, b.name, '${b.odometer} km', '/ops/garage')));
  return out;
}

/// What the matching spends add up to ("how much on fuel"), or null when none match.
({int paise, int count})? spendTotal(VigilStore s, String query) {
  final List<String> words = query.toLowerCase().split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).toList();
  if (words.isEmpty) return null;
  final List<Txn> hits = s.txns.where((Txn t) => words.every('${t.title} ${t.category}'.toLowerCase().contains)).toList();
  if (hits.isEmpty) return null;
  return (paise: hits.fold(0, (int a, Txn t) => a + t.paise), count: hits.length);
}
