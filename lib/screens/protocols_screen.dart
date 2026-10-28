import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/common.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/health.dart';
import '../services/sfx.dart';
import '../services/steps.dart';
import 'data_sheets.dart';
import 'log_sheets.dart';
import '../vigil/vigil.dart';
import '../services/haptics.dart';

enum ProtocolsView { habits, vitals, screen }

/// 12 · Protocols, 13 · Vitals, 13c · Screen (tab 4).
class ProtocolsScreen extends ConsumerWidget {
  const ProtocolsScreen({super.key, required this.view});

  final ProtocolsView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vigil;
    final VigilStore s = ref.watch(storeProvider);
    final DateTime now = ref.now;
    final (String, String) head = switch (view) {
      ProtocolsView.habits => ('Protocols', '${s.protocolsDone} / ${s.protocols.length} TODAY'),
      ProtocolsView.vitals => ('Vitals', s.healthSyncedAt == null ? 'STEPS · PHONE SENSOR' : 'HEALTH CONNECT · SYNCED ${Fmt.time(s.healthSyncedAt!)}'),
      ProtocolsView.screen => ('Screen', 'USAGE ACCESS · DATA STAYS ON-DEVICE'),
    };
    return VigilScaffold(
      title: head.$1,
      subtitle: head.$2,
      actions: <Widget>[
        switch (view) {
          ProtocolsView.habits => VigilIconButton(icon: VigilIcons.plus, semanticLabel: 'Add protocol', onPressed: () => showAddProtocolSheet(context, s)),
          ProtocolsView.vitals => VigilIconButton(icon: VigilIcons.sync, semanticLabel: 'Sync vitals', onPressed: () => _syncVitals(context, s)),
          ProtocolsView.screen => const SizedBox.shrink(),
        },
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        VigilSegmented<ProtocolsView>(
          segments: const <(ProtocolsView, String)>[(ProtocolsView.habits, 'PROTOCOLS'), (ProtocolsView.vitals, 'VITALS'), (ProtocolsView.screen, 'SCREEN')],
          selected: view,
          onSelected: (ProtocolsView v) => context.go('/protocols/${v.name == 'habits' ? 'habits' : v.name}'),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(bottom: tabBottomPad(context)),
            children: switch (view) {
              ProtocolsView.habits => _habits(context, s, c),
              ProtocolsView.vitals => _vitals(context, s, c),
              ProtocolsView.screen => _screen(context, s, c),
            },
          ),
        ),
      ]),
    );
  }

  static String _grouped(int n) => n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (Match m) => '${m[1]},');

  /// Step sensor first, then Health Connect (ask on first use, otherwise a forced sync).
  static Future<void> _syncVitals(BuildContext context, VigilStore s) async {
    if (await StepService.start(s, request: true)) s.setLink('Step sensor', 'OK');
    final bool hc = s.linkStatus['Health Connect'] == 'OK' ? await HealthService.sync(s, force: true) : await HealthService.connect(s);
    if (context.mounted) showVigilSnack(context, hc ? 'Health Connect · ${HealthService.status.value}' : 'Health Connect · ${HealthService.status.value}. Install or allow it, or log by hand');
  }

  // ------------------------------------------------------------------ habits
  List<Widget> _habits(BuildContext context, VigilStore s, VigilColors c) {
    final t = context.vtype;
    final List<int> levels = s.weekLevels;
    Color lvl(int v) => v == 0 ? c.line : c.signal.withValues(alpha: <double>[0, 0.28, 0.5, 0.75, 1][v.clamp(0, 4)]);
    final int doneCells = s.protocols.fold(0, (int a, Protocol p) => a + p.week.where((bool d) => d).length);
    final int pct = s.protocols.isEmpty ? 0 : (doneCells * 100 / (s.protocols.length * 7)).round();
    return <Widget>[
      if (s.protocols.isNotEmpty) ...<Widget>[
        VigilCard(
          brackets: true,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            const SectionLabel('Consistency · last 7 days'),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: <Widget>[
              Expanded(
                child: Semantics(
                  label: 'Consistency, $pct percent over 7 days',
                  child: Row(children: <Widget>[
                    for (int d = 0; d < 7; d++) ...<Widget>[
                      if (d > 0) const SizedBox(width: 4),
                      Expanded(child: AspectRatio(aspectRatio: 1, child: ColoredBox(color: lvl(levels[d])))),
                    ],
                  ]),
                ),
              ),
              const SizedBox(width: 14),
              Text('$pct%', style: t.metric.copyWith(color: c.signal, fontSize: 26)),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
      ],
      Row(children: <Widget>[
        Expanded(child: Text('DAILY', style: t.label.copyWith(color: c.textFaint))),
        Text('LAST 7 DAYS', style: t.label.copyWith(color: c.textFaint)),
      ]),
      const SizedBox(height: 8),
      if (s.protocols.isEmpty)
        const EmptyState(message: 'No protocols yet. Tap + to add one.')
      else
        RowList(children: <Widget>[
          for (final Protocol p in s.protocols)
            InkWell(
              onLongPress: () async {
                if (await confirmDelete(context, title: 'DELETE PROTOCOL?', message: '${p.name} and its streak are removed.')) s.removeProtocol(p.id);
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 58),
                child: Row(children: <Widget>[
                  const SizedBox(width: 6),
                  VigilCheckbox(
                    value: p.doneToday,
                    critical: p.atRisk,
                    semanticLabel: p.name,
                    onChanged: (bool v) {
                      s.toggleProtocol(p.id);
                      if (p.doneToday) {
                        Haptics.strike();
                        ThunderFx.strike(context);
                      } else {
                        Haptics.tick();
                      }
                      SfxService.play(p.doneToday ? Sfx.clear : Sfx.tick);
                    },
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.rowTitle.copyWith(color: p.doneToday ? c.textFaint : c.text, decoration: p.doneToday ? TextDecoration.lineThrough : null)),
                      const SizedBox(height: 2),
                      Text(p.atRisk ? 'AT RISK · ${p.missedDays} DAYS MISSED' : 'STREAK ${p.streakNow} · DAILY', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.meta.copyWith(color: p.atRisk ? c.critical : c.textFaint)),
                    ]),
                  ),
                  for (int i = 0; i < 7; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Container(
                        width: 9,
                        height: 18,
                        decoration: BoxDecoration(
                          color: p.week[i] ? c.signal : c.line,
                          border: i == 6 && !p.week[i] ? Border.all(color: c.textFaint) : null,
                        ),
                      ),
                    ),
                  const SizedBox(width: 14),
                ]),
              ),
            ),
        ]),
    ];
  }

  // ------------------------------------------------------------------ vitals
  List<Widget> _vitals(BuildContext context, VigilStore s, VigilColors c) {
    final t = context.vtype;
    final int tanks = 12;
    final int filled = (s.waterMl / 250).floor().clamp(0, tanks);
    final Protocol? workout = s.protocols.where((Protocol p) => p.name.startsWith('Workout')).firstOrNull;
    final SleepNight? last = s.lastNight;
    return <Widget>[
      VigilCard(
        brackets: true,
        bracketColor: c.steel,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          const SectionLabel('Hydration'),
          const SizedBox(height: 8),
          Text.rich(TextSpan(children: <InlineSpan>[
            TextSpan(text: Fmt.litres(s.waterMl), style: t.hero.copyWith(color: c.steel)),
            TextSpan(text: ' / ${Fmt.litres(s.waterTargetMl)} L', style: t.metric.copyWith(color: c.textMuted)),
          ])),
          const SizedBox(height: 12),
          Semantics(
            label: 'Hydration tank, $filled of $tanks cells filled',
            child: Row(children: <Widget>[
              for (int i = 0; i < tanks; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 3),
                Expanded(child: SizedBox(height: 22, child: ColoredBox(color: i < filled ? c.steel : c.line))),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: <Widget>[
            Expanded(child: VigilButton(label: '+250 ml', variant: VigilButtonVariant.secondary, expand: true, onPressed: () { SfxService.play(Sfx.water); s.logWater(250); })),
            const SizedBox(width: 8),
            Expanded(child: VigilButton(label: '+500 ml', expand: true, onPressed: () { SfxService.play(Sfx.water); s.logWater(500); })),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Expanded(
          child: VigilCard(
            onTap: () => context.push('/protocols/vitals/sleep'),
            semanticLabel: last == null ? 'Sleep, no data' : 'Sleep ${Fmt.dur(last.asleep)}',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[Expanded(child: Text('SLEEP', style: t.micro.copyWith(color: c.textFaint))), VigilIcon(VigilIcons.chevronRight, size: 16, color: c.textMuted)]),
              const SizedBox(height: 4),
              if (last == null) ...<Widget>[
                Text('No data', style: t.metric.copyWith(color: c.textMuted)),
                const SizedBox(height: 4),
                Text('CONNECT OR LOG A NIGHT', style: t.micro.copyWith(color: c.textMuted)),
              ] else ...<Widget>[
                Text(Fmt.dur(last.asleep), style: t.metric),
                Text('${Fmt.hm(last.bed)} → ${Fmt.hm(last.wake)}', style: t.meta.copyWith(color: c.textMuted)),
                if (s.nights.length >= 2) ...<Widget>[
                  const SizedBox(height: 10),
                  MiniBars(
                    values: s.nights.reversed.map((SleepNight n) => n.asleep.toDouble()).toList(),
                    colors: <Color>[for (int i = 0; i < s.nights.length; i++) i == s.nights.length - 1 ? c.signal : c.steel],
                    height: 36,
                    gap: 3,
                    refLine: s.needMin.toDouble(),
                    semanticLabel: 'Sleep, last ${s.nights.length} nights',
                  ),
                ],
              ],
            ]),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: VigilCard(
            semanticLabel: s.steps == null ? 'Steps, no data' : 'Steps ${s.steps}',
            child: s.steps == null
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text('STEPS', style: t.micro.copyWith(color: c.textFaint)),
                    const SizedBox(height: 4),
                    Text(s.linkStatus['Step sensor'] == 'OK' ? (StepService.noSensor.value ? 'No sensor' : 'Waiting') : 'No data', style: t.metric.copyWith(color: c.textMuted)),
                    const SizedBox(height: 8),
                    if (s.linkStatus['Step sensor'] == 'OK')
                      Text(StepService.noSensor.value ? 'THIS DEVICE HAS NO STEP COUNTER' : 'WALK A FEW STEPS', style: t.micro.copyWith(color: c.textMuted))
                    else
                      VigilButton(
                      label: 'Connect',
                      variant: VigilButtonVariant.accent,
                      onPressed: () async {
                        final bool ok = await StepService.start(s, request: true);
                        if (ok) s.setLink('Step sensor', 'OK');
                        if (context.mounted) showVigilSnack(context, ok ? 'Step sensor connected. Walk a little' : 'Activity permission denied');
                      },
                    ),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text('STEPS', style: t.micro.copyWith(color: c.textFaint)),
                    const SizedBox(height: 4),
                    Text(_grouped(s.steps!), style: t.metric),
                    Text('/ ${_grouped(s.stepTarget)}', style: t.meta.copyWith(color: c.textMuted)),
                    const SizedBox(height: 8),
                    Center(child: ReadinessRing(value: (s.steps! * 100 / s.stepTarget).round().clamp(0, 100), caption: '', size: 60, stroke: 6)),
                    const SizedBox(height: 6),
                    Text(s.steps! >= s.stepTarget ? 'TARGET MET' : '${_grouped(s.stepTarget - s.steps!)} TO TARGET', style: t.micro.copyWith(color: c.textMuted)),
                  ]),
          ),
        ),
      ]),
      if (workout != null) ...<Widget>[
      const SizedBox(height: 12),
      VigilCard(
        borderColor: workout.atRisk ? c.critical : null,
        child: Row(children: <Widget>[
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('WORKOUT', style: t.micro.copyWith(color: c.textFaint)),
              const SizedBox(height: 4),
              Text(workout.doneToday ? 'Done today' : (workout.atRisk ? 'AT RISK · ${workout.missedDays} DAYS MISSED' : 'Not done yet'),
                  style: t.rowTitle.copyWith(color: workout.atRisk ? c.critical : c.text)),
            ]),
          ),
          if (workout.atRisk) VigilButton(label: 'Start 20 min', onPressed: () => context.push('/deep-ops?mode=workout')),
        ]),
      ),
      ],
      const SizedBox(height: 12),
      VigilCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Expanded(child: Text('BODY', style: t.micro.copyWith(color: c.textFaint))),
            VigilButton(label: 'Log weight', variant: VigilButtonVariant.secondary, onPressed: () => showLogWeightSheet(context)),
          ]),
          const SizedBox(height: 4),
          if (s.weightKg == null && s.restingHr == null)
            Text('No data · connect Health Connect or log your weight', style: t.meta.copyWith(color: c.textMuted))
          else ...<Widget>[
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
              if (s.weightKg != null) Text('${s.weightKg!.toStringAsFixed(1)} kg', style: t.metric),
              if (s.weightKg != null) const SizedBox(width: 8),
              if (s.weightDelta != null) Text('${s.weightDelta! < 0 ? '\u2212' : '+'}${s.weightDelta!.abs().toStringAsFixed(1)} KG', style: t.meta.copyWith(color: c.steel)),
              const Spacer(),
              if (s.restingHr != null) Text('RESTING HR ${s.restingHr}', style: t.meta.copyWith(color: c.textMuted)),
            ]),
            if (s.weightSeries.length >= 2) ...<Widget>[
              const SizedBox(height: 10),
              MiniBars(
                values: <double>[for (final double v in s.weightSeries) v - (s.weightSeries.reduce((double a, double b) => a < b ? a : b) - 1)],
                colors: <Color>[c.steel],
                height: 30,
                gap: 3,
                semanticLabel: 'Weight trend, last 30 days',
              ),
            ],
          ],
        ]),
      ),
    ];
  }

  // ------------------------------------------------------------------ screen
  List<Widget> _screen(BuildContext context, VigilStore s, VigilColors c) {
    final t = context.vtype;
    return <Widget>[
      VigilCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          const SectionLabel('Screen time'),
          const SizedBox(height: 8),
          Text('No data', style: t.metric.copyWith(color: c.textMuted)),
          const SizedBox(height: 6),
          Text('Reading screen time needs Android\'s usage access, and that bridge is not built yet. Nothing is shown here until it is real.', style: t.caption.copyWith(color: c.textMuted)),
        ]),
      ),
    ];
  }
}
