import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/weather_api.dart';
import '../app/common.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/briefing_script.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/voice.dart';
import '../vigil/vigil.dart';

/// 01 · Dawn Briefing
class BriefingScreen extends ConsumerStatefulWidget {
  const BriefingScreen({super.key});

  @override
  ConsumerState<BriefingScreen> createState() => _BriefingScreenState();
}

class _BriefingScreenState extends ConsumerState<BriefingScreen> {
  Weather? _wx;
  bool _wxDone = false;
  final VoiceService _voice = VoiceService.instance;

  @override
  void initState() {
    super.initState();
    _voice.addListener(_onVoice);
    fetchWeather().then((Weather? w) {
      if (mounted) setState(() { _wx = w; _wxDone = true; });
    });
  }

  void _onVoice() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _voice.removeListener(_onVoice);
    _voice.stopSpeaking();
    super.dispose();
  }

  bool get _playing => _voice.state == VoiceState.speaking;

  void _toggle(String script) => _playing ? _voice.stopSpeaking() : _voice.speak(script);

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final VigilStore s = ref.watch(storeProvider);
    final DateTime now = DateTime.now();
    final List<Objective> primary = s.prioritised().take(3).toList();
    final int crit = s.critCount;
    final String script = dawnScript(s, now);
    return VigilScaffold(
      title: 'Dawn briefing',
      subtitle: '${Fmt.time(now)} · ${Fmt.dayStamp(now)}',
      actions: <Widget>[VigilIconButton(icon: VigilIcons.close, semanticLabel: 'Close briefing', onPressed: () => context.go('/'))],
      body: ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 20), children: <Widget>[
        VigilCard(
          child: Row(children: <Widget>[
            OctagonButton(size: 44, semanticLabel: _playing ? 'Stop' : 'Play briefing', onPressed: () => _toggle(script), child: VigilIcon(_playing ? VigilIcons.pause : VigilIcons.play, size: 18, color: c.onSignal)),
            const SizedBox(width: 12),
            Expanded(
              child: Row(children: <Widget>[
                for (int i = 0; i < 38; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(child: Container(height: 6.0 + ((i * 7) % 5) * 5, color: _playing ? c.signal : c.lineStrong)),
                ],
              ]),
            ),
            const SizedBox(width: 12),
            Text(_playing ? 'SPEAKING' : 'SPOKEN BY K', style: t.meta.copyWith(color: c.textMuted)),
          ]),
        ),
        const SizedBox(height: 16),
        Text.rich(TextSpan(style: t.h2, children: <InlineSpan>[
          TextSpan(text: '${s.open.length} tasks open, '),
          TextSpan(text: crit == 1 ? 'one critical' : '$crit critical', style: TextStyle(color: crit > 0 ? c.critical : null)),
          const TextSpan(text: '. Protect the focus window.'),
        ])),
        const SizedBox(height: 6),
        Text(script, style: t.caption.copyWith(color: c.textMuted)),
        const SizedBox(height: 16),
        Text('Top tasks', style: t.label.copyWith(color: c.textFaint)),
        const SizedBox(height: 8),
        RowList(children: <Widget>[
          for (final Objective o in primary)
            SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: <Widget>[
                  ThreatTag(o.threat),
                  const SizedBox(width: 12),
                  Expanded(child: Text(o.title, style: t.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text(o.dueMin != null ? Fmt.hm(o.dueMin!) : (o.dueLabel ?? '—'), style: t.meta.copyWith(color: c.textMuted)),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 16),
        Text('Schedule', style: t.label.copyWith(color: c.textFaint)),
        const SizedBox(height: 8),
        VigilCard(child: _opsWindow(context, s, now)),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Expanded(
            child: (_wx == null)
                ? StatTile(label: _wxDone ? 'Sleep' : 'Conditions', value: _wxDone ? (s.lastNight == null ? 'No data' : Fmt.dur(s.lastNight!.asleep)) : '…', caption: _wxDone ? (s.lastNight == null ? 'LOG OR CONNECT' : (!s.hasSleepStats ? 'BUILDING' : (s.debtMin == 0 ? 'NO DEBT' : 'DEBT −${Fmt.dur(s.debtMin)}'))) : 'LOADING')
                : StatTile(label: 'Conditions', value: '${_wx!.tempC.round()}°C', caption: _wx!.summary),
          ),
          const SizedBox(width: 8),
          Expanded(child: StatTile(label: 'Money', value: Fmt.money(s.yesterdaySpendPaise(now)), caption: s.monthSpentPercent == null ? 'YESTERDAY · NO BUDGET' : 'YESTERDAY · MONTH ${s.monthSpentPercent}%')),
        ]),
        const SizedBox(height: 20),
        VigilButton(label: 'Acknowledge · Deploy', size: VigilButtonSize.large, expand: true, onPressed: () => context.go('/')),
      ]),
    );
  }

  Widget _opsWindow(BuildContext context, VigilStore s, DateTime now) {
    final c = context.vigil;
    final t = context.vtype;
    const double a0 = 360, a1 = 1440;
    final double nowMin = (now.hour * 60 + now.minute).toDouble();
    return LayoutBuilder(builder: (BuildContext ctx, BoxConstraints box) {
      final double w = box.maxWidth;
      double x(double m) => ((m - a0) / (a1 - a0)).clamp(0.0, 1.0) * w;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        SizedBox(
          height: 28,
          child: Stack(children: <Widget>[
            Positioned.fill(child: ColoredBox(color: c.ground)),
            for (final Block b in s.todayBlocks.where((Block b) => b.kind == BlockKind.focus || b.kind == BlockKind.event))
              Positioned(left: x(b.startMin.toDouble()), width: (x(b.endMin.toDouble()) - x(b.startMin.toDouble())).clamp(2.0, w), top: 4, bottom: 4, child: ColoredBox(color: b.kind == BlockKind.focus ? c.signal : c.neutral)),
            Positioned(left: x(nowMin) - 1, top: 0, bottom: 0, width: 2, child: ColoredBox(color: c.critical)),
          ]),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[for (final String h in <String>['06', '09', '12', '15', '18', '21', '24']) Text(h, style: t.micro.copyWith(color: c.textFaint))]),
        const SizedBox(height: 6),
        Text('FOCUS ${Fmt.durCompact(s.focusMinPlanned)} · ${s.todayBlocks.where((Block b) => b.kind == BlockKind.event).length} MEETINGS', style: t.meta.copyWith(color: c.textMuted)),
      ]);
    });
  }
}
