import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/common.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/health.dart';
import '../services/steps.dart';
import 'log_sheets.dart';
import '../vigil/vigil.dart';

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
          ProtocolsView.habits => VigilIconButton(icon: VigilIcons.plus, semanticLabel: 'Add protocol', onPressed: () => showVigilSnack(context, 'Protocol editor is not designed yet')),
          ProtocolsView.vitals => VigilIconButton(icon: VigilIcons.sync, semanticLabel: 'Sync vitals', onPressed: () => _syncVitals(context, s)),
          ProtocolsView.screen => VigilIconButton(icon: VigilIcons.shield, semanticLabel: 'App limits', onPressed: () => showVigilSnack(context, 'App-limit editor is not designed yet')),
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

  static String _month(DateTime d) => const <String>['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'][d.month - 1];

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
    final List<List<int>> heat = s.heatmap;
    final int done = heat.expand((List<int> w) => w).where((int v) => v > 0).length;
    final int total = heat.expand((List<int> w) => w).where((int v) => v >= 0).length;
    Color lvl(int v) => v < 0 ? Colors.transparent : (v == 0 ? c.line : c.signal.withValues(alpha: <double>[0, 0.28, 0.5, 0.75, 1][v.clamp(0, 4)]));
    return <Widget>[
      VigilCard(
        brackets: true,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          const SectionLabel('Consistency · 12 weeks'),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
            Expanded(
              child: Semantics(
                label: 'Consistency heatmap, ${(done * 100 / total).round()} percent over 12 weeks',
                child: Row(children: <Widget>[
                  for (int w = 0; w < 12; w++) ...<Widget>[
                    if (w > 0) const SizedBox(width: 3),
                    Expanded(
                      child: Column(children: <Widget>[
                        for (int d = 0; d < 7; d++) ...<Widget>[
                          if (d > 0) const SizedBox(height: 3),
                          AspectRatio(
                            aspectRatio: 1,
                            child: heat[w][d] < 0
                                ? DecoratedBox(decoration: BoxDecoration(border: Border.all(color: c.lineStrong)))
                                : ColoredBox(color: lvl(heat[w][d])),
                          ),
                        ],
                      ]),
                    ),
                  ],
                ]),
              ),
            ),
            const SizedBox(width: 14),
            Text('${(done * 100 / total).round()}%', style: t.metric.copyWith(color: c.signal, fontSize: 26)),
          ]),
          const SizedBox(height: 10),
          Row(children: <Widget>[
            Text(_month(DateTime.now().subtract(const Duration(days: 77))), style: t.micro.copyWith(color: c.textFaint)),
            const Spacer(),
            Text('LESS ', style: t.micro.copyWith(color: c.textFaint)),
            for (int i = 0; i < 5; i++) Padding(padding: const EdgeInsets.only(right: 3), child: SizedBox(width: 9, height: 9, child: ColoredBox(color: lvl(i)))),
            Text(' MORE', style: t.micro.copyWith(color: c.textFaint)),
            const Spacer(),
            Text(_month(DateTime.now()), style: t.micro.copyWith(color: c.textFaint)),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: <Widget>[
        Expanded(child: Text('DAILY', style: t.label.copyWith(color: c.textFaint))),
        Text('LAST 7 DAYS', style: t.label.copyWith(color: c.textFaint)),
      ]),
      const SizedBox(height: 8),
      if (s.protocols.isEmpty)
        const EmptyState(message: 'No protocols armed.')
      else
        RowList(children: <Widget>[
          for (final Protocol p in s.protocols)
            InkWell(
              onLongPress: () => showVigilSnack(context, 'Edit and pause are not designed yet'),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 58),
                child: Row(children: <Widget>[
                  const SizedBox(width: 6),
                  VigilCheckbox(
                    value: p.doneToday,
                    critical: p.atRisk,
                    semanticLabel: p.name,
                    onChanged: (bool v) {
                      HapticFeedback.lightImpact();
                      s.toggleProtocol(p.id);
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
    final Protocol workout = s.protocols.firstWhere((Protocol p) => p.name.startsWith('Workout'));
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
            Expanded(child: VigilButton(label: '+250 ml', variant: VigilButtonVariant.secondary, expand: true, onPressed: () => s.logWater(250))),
            const SizedBox(width: 8),
            Expanded(child: VigilButton(label: '+500 ml', expand: true, onPressed: () => s.logWater(500))),
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
    final int hourNow = DateTime.now().hour;
    final bool over = s.screenTodayMin > s.screenLineMin;
    return <Widget>[
      VigilCard(
        brackets: true,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          const SectionLabel('Today'),
          const SizedBox(height: 8),
          Text.rich(TextSpan(children: <InlineSpan>[
            TextSpan(text: Fmt.dur(s.screenTodayMin), style: t.hero.copyWith(fontSize: 34, color: over ? c.critical : c.text)),
            TextSpan(text: ' / ${Fmt.dur(s.screenLineMin)} LINE', style: t.meta.copyWith(color: c.textMuted, fontSize: 12)),
          ])),
          const SizedBox(height: 10),
          SegmentBar(fraction: s.screenTodayMin / s.screenLineMin, thickness: 6, color: over ? c.critical : c.signal),
          const SizedBox(height: 8),
          Text('7-DAY AVG ${Fmt.dur(s.screenAvgMin)}', style: t.meta.copyWith(color: c.textMuted)),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            for (final (String, String) x in const <(String, String)>[('UNLOCKS', '64'), ('ALERTS', '143'), ('FIRST PICKUP', '06:41')])
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text(x.$1, style: t.micro.copyWith(color: c.textFaint)), Text(x.$2, style: t.metric.copyWith(fontSize: 18))])),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      VigilCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          const SectionLabel('By hour'),
          const SizedBox(height: 10),
          MiniBars(
            values: s.hourly,
            colors: <Color>[for (int h = 0; h < 24; h++) h == hourNow ? c.text : (h > hourNow ? c.line : c.steel)],
            height: 64,
            gap: 2,
            semanticLabel: 'Screen time by hour of day',
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[for (final String h in <String>['00', '06', '12', '18', '24']) Text(h, style: t.micro.copyWith(color: c.textFaint))]),
        ]),
      ),
      const SizedBox(height: 14),
      Text('TOP CATEGORIES', style: t.label.copyWith(color: c.textFaint)),
      const SizedBox(height: 8),
      RowList(children: <Widget>[
        for (final AppCategory a in s.categories)
          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: <Widget>[
                SizedBox(width: 92, child: Text(a.name, style: t.rowTitle.copyWith(color: a.over ? c.critical : c.text, fontSize: 14))),
                Expanded(child: SegmentBar(fraction: a.minutes / 90, thickness: 8, marker: a.limit == null ? null : a.limit! / 90, color: a.over ? c.critical : c.steel)),
                SizedBox(width: 64, child: Text('${a.minutes}m${a.over ? ' +${a.minutes - a.limit!}' : ''}', textAlign: TextAlign.right, style: t.meta.copyWith(color: a.over ? c.critical : c.text))),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      if (s.nightShieldArmed)
        IntelCard(tag: 'NIGHT SHIELD · ARMED', message: 'Social and video are blocked ${Fmt.hm(s.bedMin - 30)} to ${Fmt.hm(s.wakeMin)}.', actions: <Widget>[VigilButton(label: 'Disarm', variant: VigilButtonVariant.secondary, onPressed: () { s.nightShieldArmed = false; s.changed(); })])
      else
        IntelCard(
          tag: 'INTEL · SOCIAL OVER LINE',
          tone: IntelTone.alert,
          message: 'Social is 13 min over its line. Recommend arming Night Shield from ${Fmt.hm(s.bedMin - 30)}.',
          actions: <Widget>[VigilButton(label: 'Arm', onPressed: () { s.nightShieldArmed = true; s.changed(); })],
        ),
      const SizedBox(height: 8),
      Text('Sample data. The usage-stats bridge is not built yet.', style: t.meta.copyWith(color: c.textFaint, fontSize: 11)),
    ];
  }
}
