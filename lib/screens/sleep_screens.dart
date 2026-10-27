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
import '../services/sfx.dart';
import '../vigil/vigil.dart';
import 'log_sheets.dart';

/// 13a · Sleep tracker and 13b · Weekly schedule (pushed, no tab bar).
class SleepScreen extends ConsumerStatefulWidget {
  const SleepScreen({super.key, required this.schedule});

  final bool schedule;

  @override
  ConsumerState<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends ConsumerState<SleepScreen> {
  int? _expanded;

  @override
  Widget build(BuildContext context) {
    final VigilStore s = ref.watch(storeProvider);
    return VigilScaffold(
      title: 'Sleep',
      subtitle: widget.schedule ? 'WEEKLY SCHEDULE · ALARMS ON-DEVICE' : 'NEED ${Fmt.dur(s.needMin)} · ${s.healthSyncedAt == null ? 'MANUAL LOG' : 'SYNCED ${Fmt.time(s.healthSyncedAt!)}'}',
      leading: VigilIconButton(icon: VigilIcons.chevronLeft, semanticLabel: 'Back', onPressed: () => context.pop()),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        VigilSegmented<bool>(
          segments: const <(bool, String)>[(false, 'TRACKER'), (true, 'SCHEDULE')],
          selected: widget.schedule,
          onSelected: (bool v) => v == widget.schedule ? null : context.pushReplacement(v ? '/protocols/vitals/sleep/schedule' : '/protocols/vitals/sleep'),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
            children: widget.schedule ? _schedule(context, s) : _tracker(context, s),
          ),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ tracker
  List<Widget> _tracker(BuildContext context, VigilStore s) {
    final c = context.vigil;
    final t = context.vtype;
    final int rec = s.recommendedBed;
    final int plan = s.tonightRow.bed;
    final int wake = s.tonightRow.wake;
    final int inBed = 1440 + wake - rec;
    // The chart axis grows to fit the logged nights (default 21:00 to 09:00, never beyond 18:00 to 12:00).
    final List<SleepNight> ns = s.nights;
    int axisStart = 1260, axisEnd = 1980;
    for (final SleepNight n in ns) {
      if (n.bed < axisStart) axisStart = (n.bed ~/ 60) * 60;
      if (n.wake > axisEnd) axisEnd = ((n.wake + 59) ~/ 60) * 60;
    }
    axisStart = axisStart.clamp(1080, 1260);
    axisEnd = axisEnd.clamp(1980, 2160);
    return <Widget>[
      VigilCard(
        brackets: true,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            Expanded(child: Text('K // TONIGHT · ${Fmt.dayStamp(DateTime.now()).substring(0, 3)} → ${Fmt.dayStamp(DateTime.now().add(const Duration(days: 1))).substring(0, 3)}', style: t.label.copyWith(color: c.signal))),
            Text('PLAN ${Fmt.hm(plan)}', style: t.meta.copyWith(color: c.textFaint)),
          ]),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text('LIGHTS OUT', style: t.micro.copyWith(color: c.textFaint)), Text(Fmt.hm(rec), style: t.hero.copyWith(color: c.signal))])),
            VigilIcon(VigilIcons.arrowRight, color: c.textMuted),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text('WAKE', style: t.micro.copyWith(color: c.textFaint)), Text(Fmt.hm(wake), style: t.hero)])),
          ]),
          const SizedBox(height: 6),
          Text('${Fmt.dur(inBed)} IN BED', style: t.meta.copyWith(color: c.textMuted)),
          const SizedBox(height: 10),
          Text(
            s.hasSleepStats && s.debtMin > 0
                ? 'Lights out ${Fmt.hm(rec)} pays back ${Fmt.dur(s.debtMin)} debt. Wind-down ${Fmt.hm(s.windDownAt)}: mute and Night Shield.'
                : 'Lights out ${Fmt.hm(rec)} gives ${Fmt.dur(s.needMin)} before the ${Fmt.hm(wake)} wake. Wind-down ${Fmt.hm(s.windDownAt)}: mute and Night Shield.',
            style: t.body,
          ),
          const SizedBox(height: 14),
          if (s.armedTonight)
            Row(children: <Widget>[
              Expanded(child: Text('ARMED · WIND-DOWN ${Fmt.hm(s.windDownAt)}', style: t.label.copyWith(color: c.signal))),
              VigilButton(label: 'Undo', variant: VigilButtonVariant.secondary, onPressed: () { s.armedTonight = false; s.changed(); }),
            ])
          else
            Row(children: <Widget>[
              Expanded(
                child: VigilButton(
                  label: 'Arm ${Fmt.hm(rec)}',
                  expand: true,
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    SfxService.play(Sfx.engage);
                    s.armedTonight = true;
                    s.changed();
                    showVigilSnack(context, 'Armed. Alarm bridge is not built, so nothing will ring yet');
                  },
                ),
              ),
              const SizedBox(width: 8),
              VigilButton(label: 'Adjust', variant: VigilButtonVariant.secondary, onPressed: () => context.pushReplacement('/protocols/vitals/sleep/schedule')),
            ]),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: <Widget>[
        Expanded(child: StatTile(label: 'AVG · ${s.nights.isEmpty ? 7 : s.nights.length}N', value: s.nights.isEmpty ? '—' : Fmt.dur(s.avgSleep))),
        const SizedBox(width: 8),
        Expanded(child: StatTile(label: 'Debt', value: !s.hasSleepStats ? '—' : (s.debtMin == 0 ? '0h 00m' : '−${Fmt.dur(s.debtMin)}'), valueColor: s.hasSleepStats && s.debtMin > 0 ? c.critical : null)),
        const SizedBox(width: 8),
        Expanded(child: StatTile(label: 'Bedtime', value: s.nights.length < 2 ? '—' : '\u00b1${s.bedtimeVariance ~/ 2} min')),
      ]),
      const SizedBox(height: 12),
      VigilCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            Expanded(child: Text(s.nights.length == 1 ? 'LAST NIGHT' : 'LAST ${s.nights.isEmpty ? 7 : s.nights.length} NIGHTS', style: t.label.copyWith(color: c.textFaint))),
            if (s.nights.isNotEmpty) ...<Widget>[
              SizedBox(width: 8, height: 8, child: ColoredBox(color: c.steel)),
              Text(' ASLEEP  ', style: t.micro.copyWith(color: c.textFaint)),
              Text('PLAN', style: t.micro.copyWith(color: c.signal)),
              const SizedBox(width: 10),
            ],
            VigilButton(label: 'Log night', variant: VigilButtonVariant.secondary, onPressed: () => showLogSleepSheet(context)),
          ]),
          const SizedBox(height: 10),
          if (s.nights.isEmpty) ...<Widget>[
            Text('Sleep data builds after 3 nights. Connect Health Connect (a watch or band app writes it), or log a night yourself.', style: t.caption.copyWith(color: c.textMuted)),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: VigilButton(
                label: 'Connect Health Connect',
                variant: VigilButtonVariant.accent,
                onPressed: () async {
                  final bool ok = await HealthService.connect(s);
                  if (context.mounted) showVigilSnack(context, 'Health Connect · ${HealthService.status.value}${ok ? '' : '. Install or allow it, or log by hand'}');
                },
              ),
            ),
          ],
          for (int i = 0; i < s.nights.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: <Widget>[
                SizedBox(width: 34, child: Text(s.nights[i].label, style: t.micro.copyWith(color: i == 0 ? c.signal : c.textFaint))),
                Expanded(
                  child: WindowBar(
                    axisStart: axisStart.toDouble(),
                    axisEnd: axisEnd.toDouble(),
                    planStart: s.nights[i].planBed.toDouble(),
                    planEnd: s.nights[i].planWake.toDouble(),
                    actualStart: s.nights[i].bed.toDouble(),
                    actualEnd: s.nights[i].wake.toDouble(),
                    actualColor: i == 0 ? c.signal : c.steel,
                    semanticLabel: '${s.nights[i].label}: asleep ${Fmt.dur(s.nights[i].asleep)}',
                  ),
                ),
                SizedBox(
                  width: 58,
                  child: Text(Fmt.durCompact(s.nights[i].asleep), textAlign: TextAlign.right, style: t.meta.copyWith(color: s.nights[i].asleep < s.needMin ? c.critical : c.text)),
                ),
              ]),
            ),
          if (s.nights.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 34, right: 58),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[for (int i = 0; i < 5; i++) Text(Fmt.hm(axisStart + ((axisEnd - axisStart) * i / 4).round()).substring(0, 2), style: t.micro.copyWith(color: c.textFaint))]),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      if (s.hasSleepStats && s.bedtimeVariance > 60) IntelCard(
        tag: 'INTEL · BEDTIME DRIFT',
        message: s.insightApplied
            ? 'Applied. Weekday bedtimes set to 23:00 and weekend drift capped at 60 min.'
            : 'Bedtime drift is ${s.bedtimeVariance} min across ${s.nights.length} nights. Recommend fixing weekend lights-out to 00:00.',
        actions: s.insightApplied
            ? const <Widget>[]
            : <Widget>[
                VigilButton(
                  label: 'Apply',
                  onPressed: () {
                    for (final ScheduleRow r in s.schedule.skip(4).take(2)) {
                      r.bed = 24 * 60;
                    }
                    s.insightApplied = true;
                    s.changed();
                  },
                ),
              ],
      ),
      const SizedBox(height: 8),
      Text('SOURCE: ${s.nights.any((SleepNight n) => n.source == 'health') ? 'HEALTH CONNECT + MANUAL' : 'MANUAL LOG'}${s.healthSyncedAt == null ? '' : ' · CHECKED ${Fmt.time(s.healthSyncedAt!)}'}', style: t.micro.copyWith(color: c.textFaint)),
    ];
  }

  // ----------------------------------------------------------------- schedule
  List<Widget> _schedule(BuildContext context, VigilStore s) {
    final c = context.vigil;
    final t = context.vtype;
    final int todayIdx = (DateTime.now().weekday - 1) % 7;
    final int drift = s.schedule.map((ScheduleRow r) => r.bed).reduce((int a, int b) => a > b ? a : b) - s.schedule.map((ScheduleRow r) => r.bed).reduce((int a, int b) => a < b ? a : b);
    return <Widget>[
      VigilCard(
        child: Row(children: <Widget>[
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('SLEEP NEED', style: t.label.copyWith(color: c.textFaint)),
              const SizedBox(height: 2),
              Text('+15 MIN TO FALL ASLEEP IS ADDED', style: t.micro.copyWith(color: c.textMuted)),
            ]),
          ),
          VigilStepper(
            valueLabel: Fmt.dur(s.needMin),
            semanticName: 'Sleep need',
            valueWidth: 84,
            onDecrement: s.needMin > 360 ? () { s.needMin -= 15; s.changed(); } : null,
            onIncrement: s.needMin < 600 ? () { s.needMin += 15; s.changed(); } : null,
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: <Widget>[
          Expanded(flex: 4, child: Text('NIGHT', style: t.micro.copyWith(color: c.textFaint))),
          Expanded(flex: 2, child: Text('BED', style: t.micro.copyWith(color: c.textFaint))),
          Expanded(flex: 2, child: Text('WAKE', style: t.micro.copyWith(color: c.textFaint))),
          Expanded(flex: 2, child: Text('IN BED', textAlign: TextAlign.right, style: t.micro.copyWith(color: c.textFaint))),
        ]),
      ),
      const SizedBox(height: 6),
      RowList(children: <Widget>[
        for (int i = 0; i < s.schedule.length; i++) _row(context, s, i, i == todayIdx),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
        VigilButton(
          label: 'Copy ${s.schedule[todayIdx].night.substring(0, 3)} to Mon–Thu',
          variant: VigilButtonVariant.secondary,
          onPressed: () {
            final ScheduleRow src = s.schedule[todayIdx];
            for (int i = 0; i < 4; i++) {
              s.schedule[i].bed = src.bed;
              s.schedule[i].wake = src.wake;
            }
            s.changed();
          },
        ),
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(border: Border.all(color: drift > 60 ? c.critical : c.lineStrong)),
          child: Text('DRIFT $drift MIN', style: t.micro.copyWith(color: drift > 60 ? c.critical : c.textMuted)),
        ),
      ]),
      const SizedBox(height: 16),
      RowList(children: <Widget>[
        _opt(context, s, 'ramp', 'Gentle alarm ramp', '10 MIN'),
        _opt(context, s, 'windDown', 'Wind-down', '30 MIN BEFORE BED · MUTE + NIGHT SHIELD'),
        _opt(context, s, 'autoFirstOp', 'Auto-adjust for first op', 'WAKES EARLIER IF THE CALENDAR NEEDS IT'),
      ]),
    ];
  }

  Widget _row(BuildContext context, VigilStore s, int i, bool tonight) {
    final c = context.vigil;
    final t = context.vtype;
    final ScheduleRow r = s.schedule[i];
    final bool open = _expanded == i;
    final bool short = r.inBed < s.needMin + 15;
    return Container(
      color: open ? c.surfaceHigh : null,
      child: Column(children: <Widget>[
        InkWell(
          onTap: () => setState(() => _expanded = open ? null : i),
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: <Widget>[
                Expanded(
                  flex: 4,
                  child: Row(children: <Widget>[
                    Flexible(child: Text(r.night, style: t.meta.copyWith(color: c.text, fontSize: 12))),
                    if (tonight) ...<Widget>[
                      const SizedBox(width: 6),
                      Container(height: 18, padding: const EdgeInsets.symmetric(horizontal: 5), alignment: Alignment.center, color: c.signal, child: Text('TONIGHT', style: t.micro.copyWith(fontSize: 9, color: c.onSignal, fontWeight: FontWeight.w600))),
                    ],
                  ]),
                ),
                Expanded(flex: 2, child: Text(Fmt.hm(r.bed), style: t.rowTitle.copyWith(fontFamily: t.metric.fontFamily, fontSize: 17, color: r.bed >= 1440 ? c.textMuted : c.text))),
                Expanded(flex: 2, child: Text(Fmt.hm(r.wake), style: t.rowTitle.copyWith(fontFamily: t.metric.fontFamily, fontSize: 17))),
                Expanded(flex: 2, child: Text(Fmt.durCompact(r.inBed), textAlign: TextAlign.right, style: t.meta.copyWith(color: short ? c.critical : c.textMuted))),
              ]),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(children: <Widget>[
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(children: <Widget>[
                    Text('BED', style: t.micro.copyWith(color: c.textFaint)),
                    VigilStepper(valueLabel: Fmt.hm(r.bed), semanticName: 'Bed time ${r.night}', valueWidth: 64, onDecrement: () { r.bed -= 15; s.changed(); }, onIncrement: () { r.bed += 15; s.changed(); }),
                  ]),
                ),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(children: <Widget>[
                    Text('WAKE', style: t.micro.copyWith(color: c.textFaint)),
                    VigilStepper(valueLabel: Fmt.hm(r.wake), semanticName: 'Wake time ${r.night}', valueWidth: 64, onDecrement: () { r.wake -= 15; s.changed(); }, onIncrement: () { r.wake += 15; s.changed(); }),
                  ]),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _opt(BuildContext context, VigilStore s, String key, String title, String sub) {
    final c = context.vigil;
    final t = context.vtype;
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 8),
        child: Row(children: <Widget>[
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(title, style: t.rowTitle),
            const SizedBox(height: 2),
            Text(sub, style: t.micro.copyWith(color: c.textFaint), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          VigilSwitch(value: s.toggles[key] ?? false, onChanged: (bool v) => s.setToggle(key, v), semanticLabel: title),
        ]),
      ),
    );
  }
}
