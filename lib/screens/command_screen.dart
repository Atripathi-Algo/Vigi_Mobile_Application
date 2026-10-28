import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/common.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/inbox.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/drive_sync.dart';
import '../services/sfx.dart';
import '../vigil/vigil.dart';
import 'capture_sheet.dart';
import 'drive_sheet.dart';
import 'notifications_screen.dart';

/// 02 · Command · Home
class CommandScreen extends ConsumerStatefulWidget {
  const CommandScreen({super.key});

  @override
  ConsumerState<CommandScreen> createState() => _CommandScreenState();
}

class _CommandScreenState extends ConsumerState<CommandScreen> {
  String? _resolved; // confirmation text replacing the intel card body
  DateTime? _resolvedAt;

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
                  const VigilEmblem(size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text('K', style: t.button.copyWith(fontSize: 13, letterSpacing: 3.4)),
                      const SizedBox(height: 2),
                      Text('● SYSTEMS NOMINAL', style: t.micro.copyWith(color: c.signal)),
                    ]),
                  ),
                  VigilIconButton(
                    icon: VigilIcons.alert,
                    badge: unreadCount(s, now, lastBackup: lastBackupForInbox()) > 0,
                    semanticLabel: 'Notifications',
                    onPressed: () => context.push('/notifications'),
                  ),
                  const SizedBox(width: 8),
                  VigilIconButton(icon: VigilIcons.loadout, semanticLabel: 'Loadout settings', onPressed: () => context.push('/loadout')),
                ]),
              ),
              const SizedBox(height: 18),
              Text('${Fmt.dayStamp(now)} · ${Fmt.time(now)} IST', style: t.meta.copyWith(color: c.textFaint, letterSpacing: 1.3, fontSize: 12)),
              const SizedBox(height: 6),
              Text(s.nickname.isEmpty ? '${Fmt.greeting(now)}.' : '${Fmt.greeting(now)}, ${s.nickname}.', style: t.h1),
              const SizedBox(height: 6),
              Text.rich(TextSpan(style: t.body.copyWith(color: c.textMuted), children: <InlineSpan>[
                TextSpan(text: '$open objectives open. '),
                if (crit > 0) TextSpan(text: '$crit critical', style: TextStyle(color: c.critical)),
                if (crit > 0) const TextSpan(text: '. '),
                TextSpan(text: next == null ? 'No more ops today.' : 'Next op in ${next.startMin - (now.hour * 60 + now.minute)} min.'),
              ])),
              const SizedBox(height: 18),
              if (showBriefing) ...<Widget>[
                VigilCard(
                  onTap: () => context.push('/briefing'),
                  semanticLabel: 'Open dawn briefing',
                  child: Row(children: <Widget>[
                    Text('DAWN BRIEFING READY', style: t.label.copyWith(color: c.signal)),
                    const Spacer(),
                    VigilIcon(VigilIcons.chevronRight, size: 18, color: c.textMuted),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              VigilCard(
                brackets: true,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                  ListenableBuilder(
                    listenable: DriveSync.instance,
                    builder: (BuildContext ctx, Widget? _) {
                      final DriveSync d = DriveSync.instance;
                      if (!d.configured) return SectionLabel('Ops readiness', trailing: 'UPD ${Fmt.time(now)}');
                      return InkWell(
                        onTap: () => openSyncStatus(context, s),
                        child: Semantics(
                          button: true,
                          label: 'Drive backup: ${d.statusText()}',
                          child: SectionLabel('Ops readiness', trailing: d.statusText(), trailingColor: syncColor(context, d.state)),
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
                        StatBar(label: 'Objectives', value: '${s.cleared.length} / ${s.objectivesToday}', fraction: s.objectivesToday == 0 ? 0 : s.cleared.length / s.objectivesToday),
                        const SizedBox(height: 10),
                        StatBar(label: 'Protocols', value: '${s.protocolsDone} / ${s.protocols.length}', fraction: s.protocols.isEmpty ? 0 : s.protocolsDone / s.protocols.length),
                        const SizedBox(height: 10),
                        StatBar(label: 'Deep ops', value: '${Fmt.durCompact(s.focusTodayMin)} / ${Fmt.durCompact(s.focusTargetMin).replaceAll('h00', 'h')}', fraction: s.focusTodayMin / s.focusTargetMin, color: c.steel),
                      ]),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              _intel(context, s, now),
              const SizedBox(height: 12),
              _nextOp(context, s, next, now),
              const SizedBox(height: 12),
              Row(children: <Widget>[
                for (final (VigilIcons icon, String label, Color? tint, VoidCallback action, VoidCallback? long) in <(VigilIcons, String, Color?, VoidCallback, VoidCallback?)>[
                  (VigilIcons.deepOps, 'DEEP OPS', c.signal, () => context.push('/deep-ops'), null),
                  (VigilIcons.plus, 'CAPTURE', null, () => showCaptureSheet(context), null),
                  (VigilIcons.water, 'WATER', c.steel, () => _water(250), () => _water(500)),
                  (VigilIcons.vault, 'EXPENSE', null, () => showCaptureSheet(context, type: 'spend'), null),
                ]) ...<Widget>[
                  if (label != 'DEEP OPS') const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onLongPress: long == null
                          ? null
                          : () {
                              HapticFeedback.mediumImpact();
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
                            Text(label, style: t.micro.copyWith(color: c.text)),
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
    HapticFeedback.lightImpact();
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
              HapticFeedback.mediumImpact();
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
        tag: 'K · ALERT',
        tone: IntelTone.alert,
        time: Fmt.time(now),
        message: '${conflict.$1.title} overlaps ${conflict.$2.title} by ${conflict.$1.endMin - conflict.$2.startMin} min${conflict.$1.clashWith(conflict.$2) == null ? '' : ' (${conflict.$1.clashWith(conflict.$2)})'}. Recommend moving ${conflict.$2.title}.',
        actions: <Widget>[VigilButton(label: 'Resolve', onPressed: () => context.go('/ops/timeline'))],
      );
    }
    final Block? nb = s.nextBlock(now);
    return IntelCard(time: Fmt.time(now), message: nb == null ? 'All clear.' : 'All clear. Next op ${Fmt.hm(nb.startMin)}.');
  }

  Widget _nextOp(BuildContext context, VigilStore s, Block? next, DateTime now) {
    final c = context.vigil;
    final t = context.vtype;
    String title, meta, big;
    if (next != null) {
      final int mins = next.startMin - (now.hour * 60 + now.minute);
      title = next.title;
      meta = '${Fmt.hm(next.startMin)}–${Fmt.hm(next.endMin)} · MEET · ${next.attendees} ATTENDEES';
      big = '$mins';
    } else if (s.open.isNotEmpty) {
      final Objective o = s.open.first;
      title = o.title;
      meta = o.meta;
      big = '—';
    } else {
      title = 'Nothing scheduled';
      meta = 'ALL CLEAR';
      big = '—';
    }
    return VigilCard(
      onTap: () => context.go('/ops/timeline'),
      semanticLabel: 'Next op: $title',
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: <Widget>[
        Container(
          width: 52,
          padding: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(border: Border(right: BorderSide(color: c.line))),
          child: Column(children: <Widget>[
            Text('T–MIN', style: t.micro.copyWith(color: c.textFaint)),
            Text(big, style: t.metric.copyWith(color: c.signal)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(title, style: t.rowTitle.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(meta, style: t.meta.copyWith(color: c.textFaint, fontSize: 12)),
          ]),
        ),
        VigilIcon(VigilIcons.chevronRight, size: 18, color: c.textMuted),
      ]),
    );
  }
}
