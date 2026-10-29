import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/common.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/inbox.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../data/assistant.dart';
import '../services/drive_sync.dart';
import '../services/sfx.dart';
import '../vigil/vigil.dart';
import 'capture_sheet.dart';
import 'drive_sheet.dart';
import 'notifications_screen.dart';
import '../services/haptics.dart';

/// 02 · Command · Home
class CommandScreen extends ConsumerStatefulWidget {
  const CommandScreen({super.key});

  @override
  ConsumerState<CommandScreen> createState() => _CommandScreenState();
}

class _CommandScreenState extends ConsumerState<CommandScreen> {
  String? _resolved; // confirmation text replacing the intel card body
  DateTime? _resolvedAt;
  final TextEditingController _quick = TextEditingController();

  @override
  void dispose() {
    _quick.dispose();
    super.dispose();
  }

  /// The quick-add bar: the exact rules file a clear command as a task, spend, note or water straight away (with
  /// Undo); anything else is handed to K.
  void _quickAdd(String text) {
    final String q = text.trim();
    if (q.isEmpty) return;
    final VigilStore s = ref.read(storeProvider);
    final ChatMsg? m = Assistant(s).quick(q);
    _quick.clear();
    FocusScope.of(context).unfocus();
    if (m == null) {
      ref.read(pendingPromptProvider.notifier).state = q;
      context.go('/vigil');
      return;
    }
    if (m.diff != null) {
      Haptics.strike();
      ThunderFx.strike(context);
      SfxService.play(Sfx.clear);
    }
    showVigilSnack(context, m.text, action: m.undoable ? 'Undo' : null, onAction: m.onUndo);
  }

  void _resolve(String text) => setState(() {
        _resolved = text;
        _resolvedAt = DateTime.now();
      });

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final VigilStore s = ref.watch(storeProvider);
    final DateTime now = ref.now;
    final Block? next = s.nextBlock(now);
    final int open = s.open.length;
    final int crit = s.critCount;
    final bool showBriefing = now.hour < 10 && s.toggles['dawn'] == true;

    return Scaffold(
      backgroundColor: c.ground,
      body: GridBackground(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(VigilSpace.gutter, 12, VigilSpace.gutter, tabBottomPad(context)),
            children: <Widget>[
              SizedBox(
                height: VigilSize.touch,
                child: Row(children: <Widget>[
                  const KBadge(size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text('K', style: t.section.copyWith(fontSize: 18)),
                      Text('● Systems nominal', style: t.micro.copyWith(color: c.success)),
                    ]),
                  ),
                  VigilIconButton(
                    icon: VigilIcons.alert,
                    badge: unreadCount(s, now, lastBackup: lastBackupForInbox()) > 0,
                    semanticLabel: 'Notifications',
                    onPressed: () => context.push('/notifications'),
                  ),
                  const SizedBox(width: 8),
                  VigilIconButton(icon: VigilIcons.loadout, semanticLabel: 'Settings', onPressed: () => context.push('/loadout')),
                ]),
              ),
              const SizedBox(height: 18),
              Text('${Fmt.dayStamp(now)} · ${Fmt.time(now)}', style: t.meta.copyWith(color: c.textMuted)),
              const SizedBox(height: 6),
              Text(s.nickname.isEmpty ? '${Fmt.greeting(now)}.' : '${Fmt.greeting(now)}, ${s.nickname}.', style: t.h1),
              const SizedBox(height: 6),
              Text.rich(TextSpan(style: t.body.copyWith(color: c.textMuted), children: <InlineSpan>[
                TextSpan(text: open == 0 ? 'No open tasks.' : '$open ${open == 1 ? 'task' : 'tasks'} open'),
                if (crit > 0) TextSpan(text: ', $crit urgent', style: TextStyle(color: c.critical)),
                if (open > 0) const TextSpan(text: '.'),
              ])),
              const SizedBox(height: 14),
              Row(children: <Widget>[
                Expanded(child: VigilField(controller: _quick, hint: 'Add a task, expense, note or water…', semanticLabel: 'Quick add', onSubmitted: _quickAdd, onChanged: (_) => setState(() {}))),
                const SizedBox(width: 8),
                CircleButton(size: 48, semanticLabel: 'Add', onPressed: _quick.text.trim().isEmpty ? null : () => _quickAdd(_quick.text), child: VigilIcon(VigilIcons.arrowRight, color: c.onSignal)),
              ]),
              const SizedBox(height: 16),
              if (showBriefing) ...<Widget>[
                VigilCard(
                  onTap: () => context.push('/briefing'),
                  semanticLabel: 'Open dawn briefing',
                  child: Row(children: <Widget>[
                    Text('Morning briefing is ready', style: t.rowTitle),
                    const Spacer(),
                    VigilIcon(VigilIcons.chevronRight, size: 18, color: c.textMuted),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              VigilCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                  ListenableBuilder(
                    listenable: DriveSync.instance,
                    builder: (BuildContext ctx, Widget? _) {
                      final DriveSync d = DriveSync.instance;
                      if (!d.configured) return SectionLabel('Today\'s readiness', trailing: 'UPD ${Fmt.time(now)}');
                      return InkWell(
                        onTap: () => openSyncStatus(context, s),
                        child: Semantics(
                          button: true,
                          label: 'Drive backup: ${d.statusText()}',
                          child: SectionLabel('Today\'s readiness', trailing: d.statusText(), trailingColor: syncColor(context, d.state)),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(children: <Widget>[
                    ReadinessRing(value: s.readiness),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(children: <Widget>[
                        StatBar(label: 'Tasks', value: '${s.cleared.length} / ${s.objectivesToday}', fraction: s.objectivesToday == 0 ? 0 : s.cleared.length / s.objectivesToday),
                        const SizedBox(height: 10),
                        StatBar(label: 'Habits', value: '${s.protocolsDone} / ${s.protocols.length}', fraction: s.protocols.isEmpty ? 0 : s.protocolsDone / s.protocols.length),
                        const SizedBox(height: 10),
                        StatBar(label: 'Focus', value: '${Fmt.durCompact(s.focusTodayMin)} / ${Fmt.durCompact(s.focusTargetMin).replaceAll('h00', 'h')}', fraction: s.focusTodayMin / s.focusTargetMin, color: c.steel),
                      ]),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              _intel(context, s, now),
              const SizedBox(height: 12),
              if (next != null) ...<Widget>[_nextOp(context, s, next, now), const SizedBox(height: 12)],
              _todayTasks(context, s),
              const SizedBox(height: 12),
              Row(children: <Widget>[
                for (final (VigilIcons icon, String label, Color? tint, VoidCallback action, VoidCallback? long) in <(VigilIcons, String, Color?, VoidCallback, VoidCallback?)>[
                  (VigilIcons.deepOps, 'Focus', c.violet, () => context.push('/deep-ops'), null),
                  (VigilIcons.plus, 'Capture', null, () => showCaptureSheet(context), null),
                  (VigilIcons.water, 'Water', c.steel, () => _water(250), () => _water(500)),
                  (VigilIcons.vault, 'Expense', null, () => showCaptureSheet(context, type: 'spend'), null),
                ]) ...<Widget>[
                  if (label != 'Focus') const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onLongPress: long == null
                          ? null
                          : () {
                              Haptics.tap();
                              long();
                            },
                      child: VigilCard(
                        onTap: action,
                        semanticLabel: label,
                        padding: EdgeInsets.zero,
                        child: SizedBox(
                          height: 72,
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                            VigilIcon(icon, color: tint ?? c.text),
                            const SizedBox(height: 7),
                            Text(label, style: t.meta.copyWith(color: c.text)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ],
              ]),
            ],
          ),
        ),
      ),
    );
  }

  void _water(int ml) {
    final VigilStore s = ref.read(storeProvider);
    Haptics.tick();
    SfxService.play(Sfx.water);
    s.logWater(ml);
    showVigilSnack(context, '+$ml ml logged · ${Fmt.litres(s.waterMl)} L', action: 'UNDO', onAction: () => s.logWater(-ml));
  }

  Widget _intel(BuildContext context, VigilStore s, DateTime now) {
    final (Block, Block)? conflict = s.conflict;
    // A resolved card is shown for two minutes, then the rules engine speaks again.
    if (_resolved != null && _resolvedAt != null && now.difference(_resolvedAt!).inMinutes < 2) {
      return IntelCard(time: Fmt.time(_resolvedAt!), message: _resolved!);
    }
    if (s.hydrationBehind(now)) {
      return IntelCard(
        time: Fmt.time(now),
        message: 'Hydration ${Fmt.litres(s.waterMl)} of ${Fmt.litres(s.waterTargetMl)} L. Recommend 500 ml now.',
        actions: <Widget>[
          VigilButton(
            label: 'Log 500 ml',
            onPressed: () {
              Haptics.tap();
              SfxService.play(Sfx.water);
              s.logWater(500);
              _resolve('Logged. Hydration ${Fmt.litres(s.waterMl)} of ${Fmt.litres(s.waterTargetMl)} L. Next check at ${Fmt.hm((now.hour + 1) * 60 + 30)}.');
            },
          ),
          VigilButton(label: 'Snooze 15m', variant: VigilButtonVariant.secondary, onPressed: () => _resolve('Snoozed 15 min.')),
        ],
      );
    }
    if (conflict != null) {
      return IntelCard(
        tag: 'K · Alert',
        tone: IntelTone.alert,
        time: Fmt.time(now),
        message: '${conflict.$1.title} overlaps ${conflict.$2.title} by ${conflict.$1.endMin - conflict.$2.startMin} min${conflict.$1.clashWith(conflict.$2) == null ? '' : ' (${conflict.$1.clashWith(conflict.$2)})'}. Recommend moving ${conflict.$2.title}.',
        actions: <Widget>[VigilButton(label: 'Resolve', onPressed: () => context.go('/ops/timeline'))],
      );
    }
    final Block? nb = s.nextBlock(now);
    return IntelCard(time: Fmt.time(now), message: nb == null ? 'All clear.' : 'All clear. Next up at ${Fmt.hm(nb.startMin)}.');
  }

  /// The open tasks, a few at a time, so the screen is never empty. Ticking one off is the same strike as in Plan.
  Widget _todayTasks(BuildContext context, VigilStore s) {
    final c = context.vigil;
    final t = context.vtype;
    final List<Objective> list = s.open.take(4).toList();
    return VigilCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text('Today\'s tasks', style: t.title)),
          VigilButton(label: 'See all', variant: VigilButtonVariant.ghost, size: VigilButtonSize.small, onPressed: () => context.go('/ops/objectives')),
        ]),
        if (list.isEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 8, right: 8), child: Text('No open tasks. Clear skies.', style: t.caption.copyWith(color: c.textMuted)))
        else
          for (final Objective o in list)
            Row(children: <Widget>[
              VigilCheckbox(
                value: o.done,
                critical: o.threat == Threat.crit,
                semanticLabel: o.title,
                onChanged: (bool v) {
                  s.toggleObjective(o.id, true);
                  Haptics.strike();
                  ThunderFx.strike(context);
                  SfxService.play(Sfx.clear);
                },
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(o.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.rowTitle),
                  Text(o.meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption.copyWith(color: c.textFaint)),
                ]),
              ),
              const SizedBox(width: 8),
            ]),
      ]),
    );
  }

  Widget _nextOp(BuildContext context, VigilStore s, Block next, DateTime now) {
    final c = context.vigil;
    final t = context.vtype;
    final int mins = next.startMin - (now.hour * 60 + now.minute);
    final String title = next.title;
    final String meta = '${Fmt.hm(next.startMin)}–${Fmt.hm(next.endMin)}${next.attendees > 0 ? ' · ${next.attendees} attendees' : ''}';
    final String big = '$mins';
    return VigilCard(
      onTap: () => context.go('/ops/timeline'),
      semanticLabel: 'Next: $title',
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: <Widget>[
        Container(
          width: 52,
          padding: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(border: Border(right: BorderSide(color: c.line))),
          child: Column(children: <Widget>[
            Text('min', style: t.micro.copyWith(color: c.textFaint)),
            Text(big, style: t.metric.copyWith(color: c.signal2)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('Next up', style: t.label.copyWith(color: c.textMuted)),
            Text(title, style: t.rowTitle.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(meta, style: t.meta.copyWith(color: c.textFaint)),
          ]),
        ),
        VigilIcon(VigilIcons.chevronRight, size: 18, color: c.textMuted),
      ]),
    );
  }
}
