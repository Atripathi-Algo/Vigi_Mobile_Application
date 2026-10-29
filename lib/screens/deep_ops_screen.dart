import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/common.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/sfx.dart';
import '../vigil/vigil.dart';
import '../services/haptics.dart';

enum _Phase { ready, engaged, paused, done }

/// 16 · Deep Ops · Focus (stealth ground, no tab bar).
/// Time is derived from timestamps and the running session is saved, so it
/// stays correct after the app is backgrounded or killed (ticks are never counted).
class DeepOpsScreen extends ConsumerStatefulWidget {
  const DeepOpsScreen({super.key, this.objectiveId, this.workout = false});

  final String? objectiveId;

  /// 20-minute workout session from Vitals; completing it checks the workout protocol.
  final bool workout;

  @override
  ConsumerState<DeepOpsScreen> createState() => _DeepOpsScreenState();
}

class _DeepOpsScreenState extends ConsumerState<DeepOpsScreen> {
  static const List<(int, int)> _focusLengths = <(int, int)>[(25, 5), (50, 10), (90, 20)];
  static const List<(int, int)> _workoutLengths = <(int, int)>[(20, 5), (30, 5)];

  _Phase _phase = _Phase.ready;
  int _len = 0;
  DateTime? _endAt;
  int _pausedLeft = 0;
  int _session = 1;
  Timer? _tick;
  String? _targetId;

  List<(int, int)> get _lengths => widget.workout ? _workoutLengths : _focusLengths;
  int get _planned => _lengths[_len].$1 * 60;

  int get _left {
    switch (_phase) {
      case _Phase.engaged:
        return _endAt!.difference(DateTime.now()).inSeconds.clamp(0, _planned);
      case _Phase.paused:
        return _pausedLeft;
      default:
        return _planned;
    }
  }

  SharedPreferences get _prefs => ref.read(storeProvider).prefs;

  @override
  void initState() {
    super.initState();
    _targetId = widget.objectiveId;
    _restoreRun();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  // ---- persistence of a running session -------------------------------------
  void _saveRun() {
    _prefs
      ..setString('deepPhase', _phase.name)
      ..setInt('deepLen', _len)
      ..setInt('deepLeft', _pausedLeft)
      ..setInt('deepSession', _session)
      ..setBool('deepWorkout', widget.workout);
    if (_endAt != null) _prefs.setInt('deepEnd', _endAt!.millisecondsSinceEpoch);
    if (_targetId != null) _prefs.setString('deepTarget', _targetId!);
  }

  void _clearRun() {
    for (final String k in <String>['deepPhase', 'deepLen', 'deepLeft', 'deepSession', 'deepWorkout', 'deepEnd', 'deepTarget']) {
      _prefs.remove(k);
    }
  }

  void _restoreRun() {
    final String? ph = _prefs.getString('deepPhase');
    if (ph == null || (_prefs.getBool('deepWorkout') ?? false) != widget.workout) return;
    final int len = _prefs.getInt('deepLen') ?? 0;
    if (len >= _lengths.length) return;
    _len = len;
    _session = _prefs.getInt('deepSession') ?? 1;
    _targetId ??= _prefs.getString('deepTarget');
    if (ph == _Phase.paused.name) {
      _pausedLeft = _prefs.getInt('deepLeft') ?? _planned;
      _phase = _Phase.paused;
    } else if (ph == _Phase.engaged.name) {
      _endAt = DateTime.fromMillisecondsSinceEpoch(_prefs.getInt('deepEnd') ?? 0);
      if (_endAt!.isAfter(DateTime.now())) {
        _phase = _Phase.engaged;
        _startTicker();
      } else {
        // It ended while the app was closed: count it.
        WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
      }
    }
  }

  void _startTicker() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) return;
      if (_left <= 0) {
        t.cancel();
        _complete();
      } else {
        setState(() {});
      }
    });
  }

  void _complete() {
    _tick?.cancel();
    Haptics.tap();
    SfxService.play(Sfx.pulse);
    final VigilStore s = ref.read(storeProvider);
    s.logFocus(_lengths[_len].$1);
    if (widget.workout) {
      final Protocol? w = s.protocols.where((Protocol p) => p.name.startsWith('Workout')).firstOrNull;
      if (w != null && !w.doneToday) s.toggleProtocol(w.id);
    }
    _clearRun();
    if (mounted) setState(() => _phase = _Phase.done);
  }

  void _start() {
    _endAt = DateTime.now().add(Duration(seconds: _phase == _Phase.paused ? _pausedLeft : _planned));
    _phase = _Phase.engaged;
    SfxService.play(Sfx.engage);
    _saveRun();
    _startTicker();
    setState(() {});
  }

  void _hold() {
    _pausedLeft = _left;
    _tick?.cancel();
    setState(() => _phase = _Phase.paused);
    _saveRun();
  }

  Future<bool> _confirmAbort() async {
    if (_phase == _Phase.ready || _phase == _Phase.done) return true;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Abort session?'),
        content: const Text('The session is not counted toward today\'s deep ops.'),
        actions: <Widget>[
          VigilButton(label: 'Keep going', variant: VigilButtonVariant.secondary, onPressed: () => Navigator.pop(ctx, false)),
          VigilButton(label: 'Abort', variant: VigilButtonVariant.critical, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok ?? false) {
      SfxService.play(Sfx.deny);
      _clearRun();
    }
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final VigilStore s = ref.watch(storeProvider);
    Objective? target;
    final String? id = _targetId;
    if (id != null) {
      for (final Objective o in s.objectives) {
        if (o.id == id) target = o;
      }
    }
    target ??= widget.workout ? null : (s.open.where((Objective o) => o.estimate != null).firstOrNull ?? s.open.firstOrNull);
    final int total = _planned;
    final int left = _left;
    final String status = switch (_phase) { _Phase.ready => 'READY', _Phase.engaged => 'ENGAGED', _Phase.paused => 'PAUSED', _Phase.done => 'COMPLETE' };

    return PopScope(
      canPop: _phase == _Phase.ready || _phase == _Phase.done,
      onPopInvokedWithResult: (bool didPop, Object? r) async {
        if (didPop) return;
        if (await _confirmAbort() && context.mounted) {
          _tick?.cancel();
          context.pop();
        }
      },
      child: VigilScaffold(
        stealth: true,
        title: widget.workout ? 'Workout' : 'Focus',
        subtitle: 'Focus mode, $status',
        actions: <Widget>[
          VigilIconButton(
            icon: VigilIcons.close,
            semanticLabel: 'Exit focus',
            onPressed: () async {
              if (await _confirmAbort() && context.mounted) {
                _tick?.cancel();
                context.pop();
              }
            },
          ),
        ],
        body: ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 16), children: <Widget>[
          VigilCard(
            child: Row(children: <Widget>[
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('Target', style: t.micro.copyWith(color: c.textFaint)),
                  const SizedBox(height: 3),
                  Text(widget.workout ? 'Workout 30 min' : (target?.title ?? 'Free session'), style: t.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (target != null) Text('${target.threat == Threat.crit ? 'Urgent' : (target.threat == Threat.high ? 'High' : 'Normal')} · ${target.meta}', style: t.meta.copyWith(color: c.textFaint), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (!widget.workout)
                VigilButton(
                  label: 'Change',
                  variant: VigilButtonVariant.secondary,
                  onPressed: _phase == _Phase.engaged ? null : () => _change(context, s),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          Center(
            child: TickRing(
              progress: _phase == _Phase.done ? 1 : 1 - left / total,
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Text(_phase == _Phase.done ? 'DEBRIEF' : 'REMAINING', style: t.micro.copyWith(color: c.textFaint)),
                Semantics(label: '${Fmt.mmss(left)} remaining', child: Text(Fmt.mmss(left), style: t.display)),
                const SizedBox(height: 4),
                Text('Session $_session / 4', style: t.micro.copyWith(color: c.textMuted)),
                const SizedBox(height: 8),
                Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  for (int i = 1; i <= 4; i++) Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: SizedBox(width: 18, height: 4, child: ColoredBox(color: i < _session || _phase == _Phase.done && i == _session ? c.signal : (i == _session ? c.text : c.line)))),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          VigilSegmented<int>(
            segments: <(int, String)>[for (int i = 0; i < _lengths.length; i++) (i, '${_lengths[i].$1} / ${_lengths[i].$2}')],
            selected: _len,
            onSelected: (int v) {
              if (_phase == _Phase.ready || _phase == _Phase.done) {
                setState(() {
                  _len = v;
                  _phase = _Phase.ready;
                });
              }
            },
          ),
          const SizedBox(height: 14),
          Text('Shields', style: t.label.copyWith(color: c.textFaint)),
          const SizedBox(height: 8),
          RowList(children: <Widget>[
            _shield(context, 'Silence alerts', 'Critical alerts and family still break through', s.shieldSilence, (bool v) { s.shieldSilence = v; s.changed(); }),
            _shield(context, 'Block distractors', 'Needs accessibility bridge · Not built', s.shieldBlock, (bool v) { s.shieldBlock = v; s.changed(); }),
            _shield(context, 'Ambient: rain', 'Sound off in this build', s.shieldRain, (bool v) { s.shieldRain = v; s.changed(); }),
          ]),
          const SizedBox(height: 16),
          if (_phase == _Phase.done)
            VigilCard(
              borderColor: c.signal,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                Text('Session complete', style: t.label.copyWith(color: c.signal)),
                const SizedBox(height: 6),
                Text('${_lengths[_len].$1} min logged. Today ${Fmt.durCompact(s.focusTodayMin)} of ${Fmt.durCompact(s.focusTargetMin)}. Take ${_lengths[_len].$2} min.', style: t.body),
              ]),
            ),
          const SizedBox(height: 16),
          Row(children: <Widget>[
            VigilButton(
              label: 'Abort',
              variant: VigilButtonVariant.secondary,
              size: VigilButtonSize.large,
              onPressed: _phase == _Phase.ready || _phase == _Phase.done
                  ? () => context.pop()
                  : () async {
                      if (await _confirmAbort()) {
                        _tick?.cancel();
                        setState(() => _phase = _Phase.ready);
                      }
                    },
            ),
            const SizedBox(width: 10),
            Expanded(
              child: VigilButton(
                label: switch (_phase) { _Phase.ready => 'Engage', _Phase.engaged => 'Hold', _Phase.paused => 'Resume', _Phase.done => 'Next session' },
                size: VigilButtonSize.large,
                expand: true,
                icon: _phase == _Phase.engaged ? VigilIcons.pause : VigilIcons.play,
                onPressed: () {
                  Haptics.tap();
                  switch (_phase) {
                    case _Phase.engaged:
                      _hold();
                    case _Phase.done:
                      setState(() {
                        _session = _session < 4 ? _session + 1 : 1;
                        _phase = _Phase.ready;
                      });
                    default:
                      _start();
                  }
                },
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _shield(BuildContext context, String title, String sub, bool v, ValueChanged<bool> on) {
    final c = context.vigil;
    final t = context.vtype;
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 8),
        child: Row(children: <Widget>[
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(title, style: t.rowTitle),
            Text(sub, style: t.micro.copyWith(color: c.textFaint, fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          VigilSwitch(value: v, onChanged: on, semanticLabel: title),
        ]),
      ),
    );
  }

  void _change(BuildContext context, VigilStore s) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), children: <Widget>[
          Text('Choose target', style: ctx.vtype.section.copyWith(fontSize: 20)),
          const SizedBox(height: 10),
          for (final Objective o in s.open)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(o.title, style: ctx.vtype.rowTitle),
              subtitle: Text(o.meta, style: ctx.vtype.meta.copyWith(color: ctx.vigil.textFaint)),
              onTap: () {
                setState(() => _targetId = o.id);
                Navigator.pop(ctx);
              },
            ),
        ]),
      ),
    );
  }
}
