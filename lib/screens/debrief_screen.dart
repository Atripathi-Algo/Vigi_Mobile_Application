import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/common.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/briefing_script.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/sfx.dart';
import '../services/voice.dart';
import '../vigil/vigil.dart';
import '../services/haptics.dart';

/// 05 · Night Debrief
class DebriefScreen extends ConsumerStatefulWidget {
  const DebriefScreen({super.key});

  @override
  ConsumerState<DebriefScreen> createState() => _DebriefScreenState();
}

class _DebriefScreenState extends ConsumerState<DebriefScreen> {
  final TextEditingController _line = TextEditingController();
  String? _first;
  List<String>? _carryIds;

  final VoiceService _voice = VoiceService.instance;

  @override
  void initState() {
    super.initState();
    _voice.addListener(_onVoice);
  }

  void _onVoice() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _voice.removeListener(_onVoice);
    _voice.stopSpeaking();
    _line.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final VigilStore s = ref.watch(storeProvider);
    final DateTime now = DateTime.now();
    final int obj = s.objectivesToday == 0 ? 0 : (s.cleared.length * 100 / s.objectivesToday).round();
    final int prot = s.protocols.isEmpty ? 0 : (s.protocolsDone * 100 / s.protocols.length).round();
    final int focus = (s.focusTodayMin * 100 / s.focusTargetMin).clamp(0, 100).round();
    final int water = (s.waterMl * 100 / s.waterTargetMl).clamp(0, 100).round();
    final int score = ((obj + prot + focus + water) / 4).round();
    // The carry-over list is fixed when the screen opens, so a row keeps showing MOVED or DROPPED.
    _carryIds ??= s.prioritised().where((Objective o) => o.threat != Threat.routine).take(3).map((Objective o) => o.id).toList();
    final List<Objective> carry = _carryIds!.map((String id) => s.objectives.where((Objective o) => o.id == id).firstOrNull).whereType<Objective>().toList();
    final List<Objective> candidates = s.prioritised();
    if (_first == null || !candidates.any((Objective o) => o.id == _first)) _first = candidates.isEmpty ? null : candidates.first.id;
    final Objective? first = candidates.where((Objective o) => o.id == _first).firstOrNull;

    return VigilScaffold(
      stealth: true,
      title: 'Night debrief',
      subtitle: '${Fmt.time(now)} · ${Fmt.dayStamp(now)}',
      actions: <Widget>[VigilIconButton(icon: VigilIcons.close, semanticLabel: 'Close debrief', onPressed: () => context.go('/'))],
      body: ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 20), children: <Widget>[
        VigilCard(
          color: c.stealth,
          brackets: true,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text('MISSION SCORE', style: t.label.copyWith(color: c.textFaint)),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
              Text('$score', style: t.hero.copyWith(fontSize: 64, color: c.signal)),
              const SizedBox(width: 6),
              Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('/ 100', style: t.metric.copyWith(color: c.textMuted))),
              const Spacer(),
              if (s.weekLevels.isNotEmpty)
                SizedBox(
                  width: 110,
                  child: MiniBars(values: <double>[for (final int l in s.weekLevels) l.toDouble()], colors: <Color>[for (int i = 0; i < 7; i++) i == 6 ? c.signal : c.lineStrong], height: 44, gap: 4, semanticLabel: 'Protocols done each of the last seven days'),
                ),
            ]),
            const SizedBox(height: 6),
            Text(s.weekLevels.isNotEmpty ? 'PROTOCOLS · LAST 7 DAYS' : 'FROM OBJECTIVES, PROTOCOLS, FOCUS AND WATER', style: t.meta.copyWith(color: c.textMuted)),
          ]),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: VigilButton(
            label: _voice.state == VoiceState.speaking ? 'Stop' : 'Play debrief',
            variant: VigilButtonVariant.secondary,
            icon: VigilIcons.voice,
            onPressed: () => _voice.state == VoiceState.speaking ? _voice.stopSpeaking() : _voice.speak(nightScript(s, now)),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: <Widget>[
          Expanded(child: _metric(context, 'Objectives', '${s.cleared.length}/${s.objectivesToday}', obj / 100)),
          const SizedBox(width: 8),
          Expanded(child: _metric(context, 'Protocols', '${s.protocolsDone}/${s.protocols.length}', prot / 100)),
        ]),
        const SizedBox(height: 8),
        Row(children: <Widget>[
          Expanded(child: _metric(context, 'Deep ops', Fmt.durCompact(s.focusTodayMin), focus / 100)),
          const SizedBox(width: 8),
          Expanded(child: _metric(context, 'Hydration', '${Fmt.litres(s.waterMl)} L', water / 100, color: c.steel)),
        ]),
        const SizedBox(height: 16),
        Text('CARRY OVER', style: t.label.copyWith(color: c.textFaint)),
        const SizedBox(height: 8),
        if (carry.isEmpty)
          VigilCard(child: Text('Clean sweep. Nothing carries over.', style: t.body.copyWith(color: c.textMuted)))
        else
          RowList(children: <Widget>[
            for (final Objective o in carry)
              SizedBox(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(children: <Widget>[
                    Expanded(child: Text(o.title, style: t.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (s.carry[o.id] == 'moved')
                      Text('MOVED → ${o.dueLabel ?? ''}', style: t.meta.copyWith(color: c.signal))
                    else if (s.carry[o.id] == 'dropped')
                      Text('DROPPED', style: t.meta.copyWith(color: c.textMuted))
                    else ...<Widget>[
                      VigilButton(label: '→ ${Fmt.dayStamp(now.add(const Duration(days: 1))).substring(0, 3)}', variant: VigilButtonVariant.accent, onPressed: () { s.carry[o.id] = 'moved'; s.rescheduleObjective(o.id, Fmt.dayStamp(now.add(const Duration(days: 1))).substring(0, 3)); }),
                      const SizedBox(width: 6),
                      VigilButton(label: 'Drop', variant: VigilButtonVariant.secondary, onPressed: () { s.carry[o.id] = 'dropped'; s.dropObjective(o.id); }),
                    ],
                  ]),
                ),
              ),
          ]),
        const SizedBox(height: 16),
        Text('TOMORROW · FIRST OBJECTIVE', style: t.label.copyWith(color: c.textFaint)),
        const SizedBox(height: 8),
        VigilCard(
          onTap: candidates.isEmpty ? null : () => _pickFirst(context, candidates),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SizedBox(
            height: 52,
            child: Row(children: <Widget>[
              if (first != null) ...<Widget>[ThreatTag(first.threat, width: 54), const SizedBox(width: 12)],
              Expanded(child: Text(first?.title ?? 'No open objectives', style: t.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
              VigilIcon(VigilIcons.chevronDown, size: 18, color: c.textMuted),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        VigilField(controller: _line, label: 'One line for the log', hint: 'What moved the mission forward today?'),
        const SizedBox(height: 20),
        VigilButton(
          label: 'Stand down',
          size: VigilButtonSize.large,
          expand: true,
          icon: VigilIcons.standDown,
          onPressed: () {
            Haptics.tap();
            SfxService.play(Sfx.pulse);
            if (_line.text.trim().isNotEmpty) s.notes.insert(0, Note(id: s.nextId(), title: 'Night log · ${Fmt.dayStamp(now)}', body: _line.text.trim(), at: now));
            s.nightShieldArmed = true;
            s.tomorrowFirstId = _first;
            s.changed();
            context.go('/');
            showVigilSnack(context, 'Alerts silent until ${Fmt.hm(s.wakeMin)}');
          },
        ),
        const SizedBox(height: 8),
        Center(child: Text('ALERTS SILENT UNTIL ${Fmt.hm(s.wakeMin)}', style: t.micro.copyWith(color: c.textFaint))),
      ]),
    );
  }

  Widget _metric(BuildContext context, String label, String value, double f, {Color? color}) {
    final c = context.vigil;
    final t = context.vtype;
    return VigilCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(label.toUpperCase(), style: t.micro.copyWith(color: c.textFaint)),
        const SizedBox(height: 4),
        Text(value, style: t.metric),
        const SizedBox(height: 8),
        SegmentBar(fraction: f, thickness: 3, color: color ?? c.signal),
      ]),
    );
  }

  void _pickFirst(BuildContext context, List<Objective> l) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: <Widget>[
          for (final Objective o in l)
            ListTile(title: Text(o.title, style: ctx.vtype.rowTitle), subtitle: Text(o.meta, style: ctx.vtype.meta), onTap: () { setState(() => _first = o.id); Navigator.pop(ctx); }),
        ]),
      ),
    );
  }
}
