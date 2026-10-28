import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/common.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../app/shell.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/vault_auth.dart';
import '../services/sfx.dart';
import '../vigil/vigil.dart';
import 'capture_sheet.dart';
import 'data_sheets.dart';

/// True while the Vault is unlocked. Locks again after 60 s in the background.
final StateProvider<bool> vaultUnlocked = StateProvider<bool>((Ref ref) => false);

/// 14 · Ledger and 15 · Field Log (tab 5).
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key, required this.log});

  final bool log;

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> with WidgetsBindingObserver {
  DateTime? _pausedAt;
  final TextEditingController _entry = TextEditingController();
  final TextEditingController _search = TextEditingController();
  String? _confirmBill;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final VigilStore st = ref.read(storeProvider);
    _entry.text = st.logDraft;
    _entry.addListener(() => st.logDraft = _entry.text);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _entry.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Asks the phone's screen lock (fingerprint, face, PIN). With no screen lock set there is nothing to check
  /// against, so the Vault opens and says why.
  Future<void> _unlock() async {
    final VaultAuthResult r = await ref.read(vaultAuthProvider).unlock();
    if (!mounted) return;
    if (r == VaultAuthResult.ok || r == VaultAuthResult.unavailable) ref.read(vaultUnlocked.notifier).state = true;
    if (r == VaultAuthResult.unavailable) showVigilSnack(context, 'No screen lock is set on this phone, so the Vault opened without a check. Set one in Android settings to protect it');
    if (r == VaultAuthResult.failed) showVigilSnack(context, 'Not unlocked');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _pausedAt = DateTime.now();
    if (state == AppLifecycleState.resumed && _pausedAt != null) {
      if (DateTime.now().difference(_pausedAt!).inSeconds > 60) ref.read(vaultUnlocked.notifier).state = false;
      _pausedAt = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final VigilStore s = ref.watch(storeProvider);
    // "Locks on exit": leaving the Vault tab locks it again.
    if (!TickerMode.valuesOf(context).enabled && ref.read(vaultUnlocked)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(vaultUnlocked.notifier).state = false);
    }
    final bool unlocked = ref.watch(vaultUnlocked) || s.toggles['vaultLock'] != true;
    return VigilScaffold(
      title: 'Vault',
      subtitle: widget.log ? 'ENCRYPTED · ON-DEVICE' : 'BIOMETRIC · LOCKS ON EXIT',
      actions: <Widget>[
        VigilIconButton(
          icon: widget.log ? VigilIcons.tag : VigilIcons.plus,
          semanticLabel: widget.log ? 'Tags' : 'Add spend',
          onPressed: () => widget.log ? showVigilSnack(context, 'Tags are not designed yet') : showCaptureSheet(context, type: 'spend'),
        ),
      ],
      floatingActionButton: unlocked && widget.log ? const CaptureFab(type: 'note', icon: VigilIcons.edit, label: 'New note') : null,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        VigilSegmented<bool>(
          segments: const <(bool, String)>[(false, 'LEDGER'), (true, 'FIELD LOG')],
          selected: widget.log,
          onSelected: (bool v) => context.go(v ? '/vault/log' : '/vault/ledger'),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: unlocked
              ? ListView(padding: EdgeInsets.only(bottom: tabBottomPad(context) + 60), children: widget.log ? _log(context, s) : _ledger(context, s))
              : Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    VigilIcon(VigilIcons.vault, size: 40, color: c.textFaint),
                    const SizedBox(height: 14),
                    Text('Vault locked.', style: t.body.copyWith(color: c.textMuted)),
                    const SizedBox(height: 16),
                    VigilButton(label: 'Unlock', onPressed: _unlock),
                    const SizedBox(height: 8),
                    Text("Uses this phone's screen lock · Loadout › Data & privacy", style: t.micro.copyWith(color: c.textFaint)),
                  ]),
                ),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ ledger
  List<Widget> _ledger(BuildContext context, VigilStore s) {
    final c = context.vigil;
    final t = context.vtype;
    final DateTime now = DateTime.now();
    final int daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);
    final double pace = now.day / daysInMonth;
    final int spent = s.monthSpentPaise;
    final bool hasBudget = s.effectiveBudgetPaise > 0;
    final bool overPace = hasBudget && spent / s.effectiveBudgetPaise > pace;
    final Map<String, int> cats = s.categorySpend;
    final List<Color> palette = <Color>[c.signal, c.steel, c.text, c.textMuted, c.neutral];
    final int totalCats = cats.values.fold(0, (int a, int b) => a + b);
    final List<Txn> recent = s.txns.take(6).toList();
    return <Widget>[
      VigilCard(
        brackets: true,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            Expanded(child: Text('${DateFormatMonth.name(now)} · DAY ${now.day} / $daysInMonth', style: t.label.copyWith(color: c.textFaint))),
            Text(hasBudget ? (overPace ? 'OVER PACE' : 'UNDER PACE') : 'NO BUDGET', style: t.label.copyWith(color: hasBudget ? (overPace ? c.critical : c.signal) : c.textFaint)),
          ]),
          const SizedBox(height: 10),
          Text.rich(TextSpan(children: <InlineSpan>[
            TextSpan(text: Fmt.money(spent), style: t.hero.copyWith(fontSize: 34)),
            if (hasBudget) TextSpan(text: ' / ${Fmt.money(s.effectiveBudgetPaise)}', style: t.metric.copyWith(color: c.textMuted, fontSize: 16)),
          ])),
          const SizedBox(height: 10),
          if (hasBudget) ...<Widget>[
            SegmentBar(fraction: (spent / s.effectiveBudgetPaise).clamp(0, 1).toDouble(), thickness: 8, marker: pace, color: overPace ? c.critical : c.signal),
            const SizedBox(height: 10),
            if (s.rolledOverPaise > 0) ...<Widget>[
              Text('Includes ${Fmt.money(s.rolledOverPaise)} rolled over from last month', style: t.caption.copyWith(color: c.textMuted)),
              const SizedBox(height: 8),
            ],
            Row(children: <Widget>[
              Expanded(child: Text('SAFE TO SPEND TODAY ${Fmt.money(s.safeToSpendPaise)}', style: t.meta.copyWith(color: c.text))),
              Text('PACE ${(pace * 100).round()}%', style: t.meta.copyWith(color: c.textMuted)),
            ]),
          ] else
            Text('Set a monthly budget to see pace and a safe daily spend.', style: t.caption.copyWith(color: c.textMuted)),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: VigilButton(label: hasBudget ? 'Change budget' : 'Set budget', variant: VigilButtonVariant.secondary, onPressed: () => showBudgetSheet(context, s))),
        ]),
      ),
      if (cats.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        VigilCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            const SectionLabel('By category'),
            const SizedBox(height: 10),
            Row(children: <Widget>[
              for (int i = 0; i < cats.length; i++)
                Expanded(flex: cats.values.elementAt(i), child: Container(height: 10, margin: EdgeInsets.only(right: i == cats.length - 1 ? 0 : 2), color: palette[i])),
            ]),
            const SizedBox(height: 10),
            Wrap(runSpacing: 6, children: <Widget>[
              for (int i = 0; i < cats.length; i++)
                FractionallySizedBox(
                  widthFactor: 0.5,
                  child: Row(children: <Widget>[
                    SizedBox(width: 8, height: 8, child: ColoredBox(color: palette[i])),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${cats.keys.elementAt(i)} ${Fmt.money(cats.values.elementAt(i))}', style: t.meta.copyWith(color: c.text, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
            ]),
            const SizedBox(height: 2),
            Text('TOTAL ${Fmt.money(totalCats)}', style: t.micro.copyWith(color: c.textFaint)),
          ]),
        ),
      ],
      const SizedBox(height: 14),
      Row(children: <Widget>[
        Expanded(child: Text('BILLS DUE', style: t.label.copyWith(color: c.textFaint))),
        VigilIconButton(icon: VigilIcons.plus, semanticLabel: 'Add bill', onPressed: () => showAddBillSheet(context, s)),
      ]),
      const SizedBox(height: 8),
      if (s.bills.isEmpty)
        const EmptyState(message: 'No bills added. Tap + to track one.')
      else
        RowList(children: <Widget>[
          for (final Bill b in s.bills)
            InkWell(
              onLongPress: () async {
                if (await confirmDelete(context, title: 'DELETE BILL?', message: '${b.name} is removed from the list.')) s.removeBill(b.id);
              },
              child: _bill(context, s, b),
            ),
        ]),
      const SizedBox(height: 14),
      if (recent.isEmpty)
        const EmptyState(message: 'Ledger clean. Log the first spend.')
      else ...<Widget>[
        Text('RECENT', style: t.label.copyWith(color: c.textFaint)),
        const SizedBox(height: 8),
        RowList(children: <Widget>[
          for (final Txn x in recent)
            SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: <Widget>[
                  Container(width: 34, height: 34, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: c.lineStrong)), child: Text(x.category.substring(0, 1), style: t.button.copyWith(color: c.textMuted))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(x.title, style: t.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${Fmt.time(x.at)} · ${x.category}', style: t.meta.copyWith(color: c.textFaint)),
                  ])),
                  Text(Fmt.debit(x.paise), style: t.metric.copyWith(fontSize: 15)),
                ]),
              ),
            ),
        ]),
      ],
    ];
  }

  Widget _bill(BuildContext context, VigilStore s, Bill b) {
    final c = context.vigil;
    final t = context.vtype;
    final bool confirming = _confirmBill == b.id;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: confirming
            ? Row(children: <Widget>[
                Expanded(child: Text('Mark paid? K doesn\'t move money.', style: t.caption.copyWith(fontSize: 12))),
                VigilButton(label: 'Confirm', onPressed: () { b.paid = true; setState(() => _confirmBill = null); s.changed(); }),
                const SizedBox(width: 6),
                VigilButton(label: 'Cancel', variant: VigilButtonVariant.secondary, onPressed: () => setState(() => _confirmBill = null)),
              ])
            : Row(children: <Widget>[
                Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(b.name, style: t.rowTitle),
                  Text('DUE ${b.due}', style: t.meta.copyWith(color: b.dueToday && !b.paid ? c.critical : c.textFaint)),
                ])),
                Text(Fmt.money(b.paise), style: t.metric.copyWith(fontSize: 15)),
                const SizedBox(width: 10),
                if (b.paid) Text('PAID ✓', style: t.button.copyWith(color: c.signal)) else VigilButton(label: 'Pay', onPressed: () => setState(() => _confirmBill = b.id)),
              ]),
      ),
    );
  }

  // --------------------------------------------------------------- field log
  List<Widget> _log(BuildContext context, VigilStore s) {
    final c = context.vigil;
    final t = context.vtype;
    final DateTime now = DateTime.now();
    final bool sealed = s.sealedAt != null;
    final String q = _search.text.toLowerCase();
    final List<Note> notes = s.notes.where((Note n) => q.isEmpty || n.title.toLowerCase().contains(q) || n.body.toLowerCase().contains(q)).toList();
    const List<String> moods = <String>['LOW', 'FLAT', 'STEADY', 'GOOD', 'PEAK'];
    final Widget nightLog = sealed
        ? VigilCard(child: Text('Sealed ${s.sealedAt} · ${moods[s.sealedMood]}', style: t.label.copyWith(color: c.textMuted)))
        : VigilCard(
            brackets: true,
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Row(children: <Widget>[Expanded(child: Text('NIGHT LOG · ${Fmt.dayStamp(now)}', style: t.label.copyWith(color: c.textFaint))), Text('STREAK ${s.logStreak}', style: t.meta.copyWith(color: c.signal))]),
              const SizedBox(height: 12),
              Row(children: <Widget>[
                for (int i = 0; i < 5; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: s.logMood == i,
                      label: 'Mood ${moods[i]}',
                      excludeSemantics: true,
                      child: InkWell(
                        onTap: () => setState(() => s.logMood = i),
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(color: s.logMood == i ? c.surfaceHigh : null, border: Border.all(color: s.logMood == i ? c.signal : c.lineStrong)),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                            Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                              for (int b = 0; b <= i; b++) Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: SizedBox(width: 3, height: 6.0 + b * 3, child: ColoredBox(color: s.logMood == i ? c.signal : c.neutral))),
                            ]),
                            const SizedBox(height: 6),
                            Text(moods[i], style: t.micro.copyWith(fontSize: 9, color: s.logMood == i ? c.text : c.textMuted)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 12),
              VigilField(controller: _entry, hint: 'What moved the mission forward today?', semanticLabel: 'Night log entry', maxLines: 2, fillColor: c.ground),
              const SizedBox(height: 12),
              Row(children: <Widget>[
                VigilButton(label: 'Dictate', variant: VigilButtonVariant.secondary, icon: VigilIcons.voice, onPressed: () => showVigilSnack(context, 'Voice uplink is not connected yet')),
                const SizedBox(width: 8),
                Expanded(
                  child: VigilButton(
                    label: 'Seal entry',
                    expand: true,
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      SfxService.play(Sfx.clear);
                      s.sealLog(_entry.text, s.logMood);
                      _entry.clear();
                    },
                  ),
                ),
              ]),
            ]),
          );
    return <Widget>[
      nightLog,
      const SizedBox(height: 12),
      VigilField(controller: _search, hint: 'Search notes', semanticLabel: 'Search notes', onChanged: (_) => setState(() {}), prefix: Padding(padding: const EdgeInsets.all(14), child: VigilIcon(VigilIcons.search, size: 18, color: c.textFaint))),
      const SizedBox(height: 14),
      Text('FIELD NOTES · ${notes.length}', style: t.label.copyWith(color: c.textFaint)),
      const SizedBox(height: 8),
      if (notes.isEmpty)
        const EmptyState(message: 'No notes yet.')
      else
        RowList(children: <Widget>[
          for (final Note n in notes)
            SizedBox(
              height: 68,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: <Widget>[
                  SizedBox(
                    width: 64,
                    child: Text(n.kind.name.toUpperCase(), style: t.micro.copyWith(color: n.kind == NoteKind.pinned ? c.signal : (n.kind == NoteKind.voice ? c.steel : c.neutral), fontWeight: FontWeight.w600)),
                  ),
                  Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(n.title, style: t.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(n.body, style: t.caption.copyWith(color: c.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  Text(_age(now.difference(n.at)), style: t.meta.copyWith(color: c.textFaint)),
                ]),
              ),
            ),
        ]),
    ];
  }

  String _age(Duration d) => d.inHours < 24 ? '${d.inHours.clamp(0, 99)}H' : '${d.inDays}D';
}

abstract final class DateFormatMonth {
  static String name(DateTime d) => const <String>['JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'][d.month - 1];
}
