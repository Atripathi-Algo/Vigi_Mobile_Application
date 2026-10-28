import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/common.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../app/shell.dart';
import '../data/garage.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/sfx.dart';
import '../vigil/vigil.dart';
import 'calendar_sheets.dart';
import 'capture_sheet.dart';
import 'garage_screen.dart';
import '../services/haptics.dart';

/// 10 · Objectives and 11 · Timeline (tab 2).
class OpsScreen extends ConsumerStatefulWidget {
  const OpsScreen({super.key, required this.timeline, this.garage = false});

  final bool timeline;

  /// The Garage tab (bikes, fuel, service reminders).
  final bool garage;

  @override
  ConsumerState<OpsScreen> createState() => _OpsScreenState();
}

class _OpsScreenState extends ConsumerState<OpsScreen> {
  String _filter = 'ALL';
  bool _showCleared = false;
  bool _search = false;
  final TextEditingController _q = TextEditingController();

  /// Rows checked during this visit stay in their group until the tab is left (spec 10).
  final Set<String> _pinned = <String>{};

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _check(VigilStore s, Objective o, bool done) {
    if (done) {
      Haptics.strike();
      ThunderFx.strike(context);
    } else {
      Haptics.tick();
    }
    SfxService.play(done ? Sfx.clear : Sfx.tick);
    if (done) {
      _pinned.add(o.id);
    } else {
      _pinned.remove(o.id);
    }
    s.toggleObjective(o.id, done);
  }

  @override
  Widget build(BuildContext context) {
    final VigilStore s = ref.watch(storeProvider);
    final DateTime now = ref.now;
    // The shell keeps this branch alive; when it goes off-screen, forget the pinned rows.
    if (!TickerMode.valuesOf(context).enabled && _pinned.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pinned.clear());
    }
    final DateTime monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final DateTime selDay = monday.add(Duration(days: s.selectedDayIndex));
    final List<Block> dayBlocks = s.blocksFor(selDay);
    final int focus = dayBlocks.where((Block b) => b.kind == BlockKind.focus).fold(0, (int a, Block b) => a + b.endMin - b.startMin);
    int garageDue = 0;
    for (final Bike b in s.bikes) {
      for (final Reminder r in b.reminders) {
        if (dueStatus(r, b.odometer, now).level == DueLevel.overdue) garageDue++;
      }
    }
    final String subtitle = widget.garage
        ? '${s.bikes.length} ${s.bikes.length == 1 ? 'BIKE' : 'BIKES'} · $garageDue OVERDUE'
        : widget.timeline
            ? '${Fmt.dayStamp(selDay)} · ${dayBlocks.length} OPS · ${Fmt.durCompact(focus)} FOCUS'
            : '${s.open.length} OPEN · ${s.cleared.length} CLEARED · ${s.overdueCount} OVERDUE';

    return VigilScaffold(
      title: 'Ops',
      subtitle: subtitle,
      actions: <Widget>[
        if (!widget.garage)
        VigilIconButton(
          icon: widget.timeline ? VigilIcons.calendar : VigilIcons.search,
          semanticLabel: widget.timeline ? 'Month view' : 'Search',
          onPressed: () {
            if (widget.timeline) {
              showVigilSnack(context, 'Month view is not designed yet');
            } else {
              setState(() {
                _search = !_search;
                if (!_search) _q.clear();
              });
            }
          },
        ),
      ],
      floatingActionButton: widget.timeline || widget.garage ? null : const CaptureFab(type: 'objective'),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        VigilSegmented<String>(
          segments: const <(String, String)>[('o', 'OBJECTIVES'), ('t', 'TIMELINE'), ('g', 'GARAGE')],
          selected: widget.garage ? 'g' : (widget.timeline ? 't' : 'o'),
          onSelected: (String v) => context.go(v == 'o' ? '/ops/objectives' : (v == 't' ? '/ops/timeline' : '/ops/garage')),
        ),
        const SizedBox(height: 12),
        Expanded(child: widget.garage ? const GarageView() : (widget.timeline ? _timeline(context, s, now, selDay, dayBlocks) : _objectives(context, s, now))),
      ]),
    );
  }

  // ---------------------------------------------------------------- objectives
  Widget _objectives(BuildContext context, VigilStore s, DateTime now) {
    final c = context.vigil;
    final t = context.vtype;
    final String q = _search ? _q.text.toLowerCase() : '';
    bool match(Objective o) {
      if (q.isNotEmpty && !o.title.toLowerCase().contains(q)) return false;
      return switch (_filter) {
        'WORK' => o.tag == 'WORK',
        'HOME' => o.tag == 'HOME',
        'RECURRING' => o.recurring,
        'NO DATE' => !o.hasDate,
        _ => true,
      };
    }

    final List<Objective> open = s.objectives.where((Objective o) => !o.dropped && (!o.done || _pinned.contains(o.id)) && match(o)).toList();
    final List<Objective> cleared = s.cleared.where((Objective o) => !_pinned.contains(o.id) && match(o)).toList();
    Widget group(Threat th, String label, Color col) {
      final List<Objective> l = open.where((Objective o) => o.threat == th).toList();
      if (l.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        GroupLabel('$label · ${l.where((Objective o) => !o.done).length}', color: col),
        RowList(children: <Widget>[for (final Objective o in l) _row(context, s, o, now)]),
        const SizedBox(height: 14),
      ]);
    }

    return ListView(
      padding: EdgeInsets.only(bottom: tabBottomPad(context) + 60),
      children: <Widget>[
        if (_search) ...<Widget>[
          VigilField(controller: _q, hint: 'Search objectives', semanticLabel: 'Search objectives', onChanged: (_) => setState(() {}), prefix: Padding(padding: const EdgeInsets.all(14), child: VigilIcon(VigilIcons.search, size: 18, color: c.textFaint))),
          const SizedBox(height: 12),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: <Widget>[
            for (final String f in <String>['ALL', 'WORK', 'HOME', 'RECURRING', 'NO DATE']) ...<Widget>[
              VigilFilterChip(label: f, selected: _filter == f, onTap: () => setState(() => _filter = f)),
              const SizedBox(width: 8),
            ],
          ]),
        ),
        const SizedBox(height: 14),
        if (open.isEmpty && cleared.isEmpty)
          EmptyState(message: 'No objectives. Clear skies.', action: 'Capture', onAction: () => showCaptureSheet(context, type: 'objective'))
        else ...<Widget>[
          group(Threat.crit, 'CRITICAL', c.critical),
          group(Threat.high, 'HIGH', c.signal),
          group(Threat.routine, 'ROUTINE', c.textMuted),
          if (cleared.isNotEmpty)
            InkWell(
              onTap: () => setState(() => _showCleared = !_showCleared),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(border: Border.all(color: c.lineStrong)),
                child: Row(children: <Widget>[
                  Expanded(child: Text('CLEARED TODAY · ${cleared.length}', style: t.label.copyWith(color: c.textMuted))),
                  VigilIcon(_showCleared ? VigilIcons.chevronDown : VigilIcons.chevronRight, size: 18, color: c.textMuted),
                ]),
              ),
            ),
          if (_showCleared && cleared.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            RowList(children: <Widget>[for (final Objective o in cleared) _row(context, s, o, now)]),
          ],
        ],
      ],
    );
  }

  Widget _row(BuildContext context, VigilStore s, Objective o, DateTime now) {
    final c = context.vigil;
    final t = context.vtype;
    final bool overdue = o.isOverdue(now);
    return Dismissible(
      key: ValueKey<String>('obj-${o.id}'),
      background: Container(color: c.signalTint(0.18), alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 18), child: VigilIcon(VigilIcons.check, color: c.signal)),
      secondaryBackground: Container(color: c.critical.withValues(alpha: 0.18), alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 18), child: Icon(Icons.delete_outline, color: c.critical)),
      confirmDismiss: (DismissDirection d) async {
        if (d == DismissDirection.startToEnd) {
          _check(s, o, true);
        } else {
          // Swipe left deletes, with a few seconds to take it back.
          final int at = s.objectives.indexWhere((Objective e) => e.id == o.id);
          s.removeObjective(o.id);
          Haptics.tap();
          showVigilSnack(context, 'Deleted ${o.title}', action: 'Undo', onAction: () => s.restoreObjective(o, at));
        }
        return false; // rows stay in place until the next visit, per the spec
      },
      child: InkWell(
        onTap: () => _detail(context, s, o),
        child: SizedBox(
          height: VigilSize.row,
          child: Row(children: <Widget>[
            const SizedBox(width: 6),
            VigilCheckbox(
              value: o.done,
              critical: o.threat == Threat.crit,
              semanticLabel: o.title,
              onChanged: (bool v) => _check(s, o, v),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(o.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.rowTitle.copyWith(color: o.done ? c.textFaint : c.text, decoration: o.done ? TextDecoration.lineThrough : null)),
                const SizedBox(height: 2),
                Text(o.meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.meta.copyWith(color: overdue ? c.critical : c.textFaint)),
              ]),
            ),
            if (o.estimate != null && !o.done)
              VigilIconButton(icon: VigilIcons.deepOps, size: 44, semanticLabel: 'Deep ops on ${o.title}', onPressed: () => context.push('/deep-ops?objective=${o.id}'))
            else
              const SizedBox(width: 10),
          ]),
        ),
      ),
    );
  }

  void _reschedule(BuildContext context, VigilStore s, Objective o) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (BuildContext ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text('RESCHEDULE', style: ctx.vtype.section.copyWith(fontSize: 20)),
            const SizedBox(height: 12),
            for (final (String, String) opt in const <(String, String)>[('Tomorrow', 'TOMORROW'), ('Next week', 'NEXT WEEK')]) ...<Widget>[
              VigilButton(
                label: opt.$1,
                variant: VigilButtonVariant.secondary,
                expand: true,
                onPressed: () {
                  s.rescheduleObjective(o.id, opt.$2);
                  Navigator.pop(ctx);
                  showVigilSnack(context, 'Moved → ${opt.$2}');
                },
              ),
              const SizedBox(height: 8),
            ],
            VigilButton(
              label: 'Pick date',
              variant: VigilButtonVariant.secondary,
              expand: true,
              onPressed: () async {
                Navigator.pop(ctx);
                final DateTime? d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) s.rescheduleObjective(o.id, Fmt.dayStamp(d));
              },
            ),
          ]),
        ),
      ),
    );
  }

  void _detail(BuildContext context, VigilStore s, Objective o) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (BuildContext ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Align(alignment: Alignment.centerLeft, child: ThreatTag(o.threat)),
            const SizedBox(height: 10),
            Text(o.title, style: ctx.vtype.title),
            const SizedBox(height: 4),
            Text(o.meta, style: ctx.vtype.meta.copyWith(color: ctx.vigil.textFaint)),
            const SizedBox(height: 16),
            Row(children: <Widget>[
              Expanded(
                child: VigilButton(
                  label: o.done ? 'Reopen' : 'Complete',
                  expand: true,
                  onPressed: () {
                    _check(s, o, !o.done);
                    Navigator.pop(ctx);
                  },
                ),
              ),
              const SizedBox(width: 8),
              if (!o.done)
                VigilButton(
                  label: 'Reschedule',
                  variant: VigilButtonVariant.secondary,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _reschedule(context, s, o);
                  },
                ),
              if (!o.done) const SizedBox(width: 8),
              VigilButton(
                label: 'Delete',
                variant: VigilButtonVariant.secondary,
                onPressed: () {
                  s.removeObjective(o.id);
                  Navigator.pop(ctx);
                },
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ timeline
  Widget _timeline(BuildContext context, VigilStore s, DateTime now, DateTime day, List<Block> blocks) {
    final c = context.vigil;
    final t = context.vtype;
    final bool isToday = s.selectedDayIndex == now.weekday - 1;
    final (Block, Block)? conflict = isToday ? s.conflict : null;
    const int h0 = 8, h1 = 22;
    const double hh = 30;
    final int nowMin = now.hour * 60 + now.minute;

    Widget block(Block b) {
      final double top = (b.startMin - h0 * 60) / 60 * hh;
      final double height = (b.endMin - b.startMin) / 60 * hh;
      final bool inConflict = conflict != null && (conflict.$1.id == b.id || conflict.$2.id == b.id);
      Color fill, border;
      bool dashed = false;
      switch (b.kind) {
        case BlockKind.event:
          fill = inConflict ? c.critical.withValues(alpha: 0.12) : c.surfaceHigh;
          border = inConflict ? c.critical : c.lineStrong;
        case BlockKind.focus:
          fill = c.signalTint(0.14);
          border = c.signal;
        case BlockKind.personal:
        case BlockKind.task:
          fill = Colors.transparent;
          border = c.neutral;
          dashed = true;
      }
      final bool left = inConflict && b.id == conflict.$1.id;
      final bool right = inConflict && b.id == conflict.$2.id;
      return Positioned(
        top: top,
        height: height < 22 ? 22 : height,
        left: 52,
        right: 0,
        child: FractionallySizedBox(
          alignment: left ? Alignment.centerLeft : (right ? Alignment.centerRight : Alignment.center),
          widthFactor: inConflict ? 0.5 : 1,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => canAddToCalendar(b)
                ? showAddToCalendarSheet(context, s, b)
                : showVigilSnack(context, '${b.title} · ${Fmt.hm(b.startMin)}–${Fmt.hm(b.endMin)}${b.src == null ? '' : ' · ${b.src}'}'),
            child: Container(
              margin: const EdgeInsets.only(left: 4, bottom: 1),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: fill, border: Border.all(color: border)),
              child: Text('${b.title}\n${Fmt.hm(b.startMin)}–${Fmt.hm(b.endMin)}${b.src == null ? '' : ' · ${b.src}'}',
                  maxLines: height < 40 ? 1 : 2, overflow: TextOverflow.ellipsis, style: t.meta.copyWith(color: dashed ? c.textMuted : c.text, fontSize: 11, height: 1.25)),
            ),
          ),
        ),
      );
    }

    final bool linked = s.linkStatus['Calendar link'] == 'OK';
    return GestureDetector(
      // Swipe the timeline sideways to change day.
      onHorizontalDragEnd: (DragEndDetails d) {
        final double v = d.primaryVelocity ?? 0;
        if (v < -250) s.selectDay(s.selectedDayIndex + 1);
        if (v > 250) s.selectDay(s.selectedDayIndex - 1);
      },
      child: ListView(
        padding: EdgeInsets.only(bottom: tabBottomPad(context)),
        children: <Widget>[
          if (!linked)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: VigilCard(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                child: Row(children: <Widget>[
                  Expanded(child: Text('Calendar not linked', style: t.caption.copyWith(color: c.textMuted))),
                  VigilButton(label: 'Link', variant: VigilButtonVariant.accent, onPressed: () => context.push('/loadout/accounts')),
                ]),
              ),
            ),
          Row(children: <Widget>[
            for (int i = 0; i < 7; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: _dayChip(context, s, day.subtract(Duration(days: s.selectedDayIndex - i)), i, now)),
            ],
          ]),
          const SizedBox(height: 14),
          // Tap an empty slot to capture an event at that time.
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (TapUpDetails d) {
              final int min = (h0 * 60 + (d.localPosition.dy / hh * 60 / 15).round() * 15).clamp(h0 * 60, h1 * 60 - 15);
              final String dayWord = isToday ? '' : ' ${Fmt.dayStamp(day).substring(0, 3)}';
              showCaptureSheet(context, type: 'event', initialText: 'Meeting$dayWord at ${Fmt.hm(min)}');
            },
            child: SizedBox(
              height: (h1 - h0) * hh + 10,
              child: Stack(children: <Widget>[
                for (int h = h0; h <= h1; h++)
                  Positioned(
                    top: (h - h0) * hh,
                    left: 0,
                    right: 0,
                    child: Row(children: <Widget>[
                      SizedBox(width: 44, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('${h.toString().padLeft(2, '0')}:00', style: t.micro.copyWith(color: c.textFaint)))),
                      Expanded(child: Divider(height: 1, color: c.rule)),
                    ]),
                  ),
                for (final Block b in blocks) block(b),
                if (isToday && nowMin >= h0 * 60 && nowMin <= h1 * 60)
                  Positioned(
                    top: (nowMin - h0 * 60) / 60 * hh - 8,
                    left: 0,
                    right: 0,
                    child: Row(children: <Widget>[
                      Container(constraints: const BoxConstraints(minWidth: 36), height: 16, padding: const EdgeInsets.symmetric(horizontal: 3), color: c.critical, alignment: Alignment.center, child: Text(Fmt.time(now), style: t.micro.copyWith(color: c.onSignal, fontWeight: FontWeight.w600))),
                      Expanded(child: SizedBox(height: 2, child: ColoredBox(color: c.critical))),
                    ]),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          if (isToday)
            if (conflict != null)
              VigilCard(
                borderColor: c.critical,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                  Text('CONFLICT · ${conflict.$1.endMin - conflict.$2.startMin} MIN OVERLAP${conflict.$1.clashWith(conflict.$2) == null ? '' : ' · ${conflict.$1.clashWith(conflict.$2)}'}', style: t.label.copyWith(color: c.critical)),
                  const SizedBox(height: 6),
                  Text('${conflict.$1.title} (${Fmt.hm(conflict.$1.startMin)}–${Fmt.hm(conflict.$1.endMin)}) runs into ${conflict.$2.title}. Recommend moving ${conflict.$2.title} to ${Fmt.hm(conflict.$1.endMin)}.', style: t.body),
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: VigilButton(label: 'Resolve', onPressed: () { SfxService.play(Sfx.clear); s.resolveConflict(); })),
                ]),
              )
            else if (s.justResolved)
              VigilCard(child: Row(children: <Widget>[Expanded(child: Text('No conflicts today.', style: t.body.copyWith(color: c.textMuted))), Text('RESOLVED', style: t.label.copyWith(color: c.signal))])),
        ],
      ),
    );
  }

  Widget _dayChip(BuildContext context, VigilStore s, DateTime d, int i, DateTime now) {
    final c = context.vigil;
    final t = context.vtype;
    final bool sel = i == s.selectedDayIndex;
    final bool today = d.day == now.day && d.month == now.month;
    final int load = s.blocksFor(d).length;
    final Color fg = sel ? c.onSignal : c.text;
    return Semantics(
      button: true,
      selected: sel,
      label: '${Fmt.dayStamp(d)}, $load ops',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => s.selectDay(i),
        child: Container(
          height: 60,
          decoration: BoxDecoration(color: sel ? c.signal : c.surface, border: Border.all(color: sel ? c.signal : c.line)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
            Text(Fmt.dayStamp(d).substring(0, 1), style: t.micro.copyWith(color: sel ? c.onSignal : c.textFaint)),
            Text('${d.day}', style: t.metric.copyWith(fontSize: 16, color: fg)),
            const SizedBox(height: 3),
            SizedBox(width: (load * 7).clamp(0, 30).toDouble(), height: 3, child: ColoredBox(color: sel ? c.onSignal : (today ? c.signal : c.neutral))),
          ]),
        ),
      ),
    );
  }
}
