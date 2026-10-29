import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/common.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/search.dart';
import '../data/store.dart';
import '../vigil/vigil.dart';

/// Search across tasks, events, habits, notes, spending, bills and bikes. Everything is matched on the phone.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initial = ''});

  final String initial;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _q = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final VigilStore s = ref.watch(storeProvider);
    final String q = _q.text.trim();
    final List<SearchHit> hits = searchAll(s, q);
    final ({int paise, int count})? total = q.isEmpty ? null : spendTotal(s, q);
    final Map<HitKind, List<SearchHit>> groups = <HitKind, List<SearchHit>>{};
    for (final SearchHit h in hits) {
      groups.putIfAbsent(h.kind, () => <SearchHit>[]).add(h);
    }
    return VigilScaffold(
      title: 'Search',
      leading: VigilIconButton(icon: VigilIcons.chevronLeft, semanticLabel: 'Back', onPressed: () => context.pop()),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        VigilField(
          controller: _q,
          hint: 'Tasks, notes, spending…',
          semanticLabel: 'Search everything',
          autofocus: widget.initial.isEmpty,
          onChanged: (_) => setState(() {}),
          prefix: Padding(padding: const EdgeInsets.all(14), child: VigilIcon(VigilIcons.search, size: 18, color: c.textMuted)),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: q.isEmpty
              ? Center(child: Text('Search tasks, events, habits, notes, spending, bills and bikes.\nTry "fuel", "Ravi" or "lunch".', textAlign: TextAlign.center, style: t.caption.copyWith(color: c.textFaint)))
              : hits.isEmpty
                  ? Center(child: Text('Nothing matches "$q".', style: t.caption.copyWith(color: c.textFaint)))
                  : ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24), children: <Widget>[
                      if (total != null) ...<Widget>[
                        VigilCard(
                          child: Text('${total.count} ${total.count == 1 ? 'spend' : 'spends'} match: ${Fmt.money(total.paise)} in all.', style: t.rowTitle),
                        ),
                        const SizedBox(height: 12),
                      ],
                      for (final MapEntry<HitKind, List<SearchHit>> g in groups.entries) ...<Widget>[
                        SectionLabel(g.value.first.kindLabel + (g.value.length > 1 ? 's' : ''), trailing: '${g.value.length}'),
                        const SizedBox(height: 6),
                        RowList(children: <Widget>[
                          for (final SearchHit h in g.value)
                            InkWell(
                              onTap: () => context.go(h.route),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                child: Row(children: <Widget>[
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                                      Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.rowTitle),
                                      if (h.detail.isNotEmpty) Text(h.detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption.copyWith(color: c.textFaint)),
                                    ]),
                                  ),
                                  VigilIcon(VigilIcons.chevronRight, size: 16, color: c.textMuted),
                                ]),
                              ),
                            ),
                        ]),
                        const SizedBox(height: 14),
                      ],
                    ]),
        ),
      ]),
    );
  }
}
