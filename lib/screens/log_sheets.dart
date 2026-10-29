import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/common.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/sfx.dart';
import '../vigil/vigil.dart';

Future<void> showLogSleepSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (BuildContext ctx) => const _LogSleepSheet(),
    );

Future<void> showLogWeightSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (BuildContext ctx) => const _LogWeightSheet(),
    );

/// Log a night by hand. Used when there is no watch or band writing to Health Connect.
class _LogSleepSheet extends ConsumerStatefulWidget {
  const _LogSleepSheet();

  @override
  ConsumerState<_LogSleepSheet> createState() => _LogSleepSheetState();
}

class _LogSleepSheetState extends ConsumerState<_LogSleepSheet> {
  late DateTime _night;
  late int _bed; // minutes after midnight of _night; 1080 (18:00) to 1800 (06:00 next day)
  late int _wake; // minutes after midnight of the following day, 0 to 720

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _night = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    _load(ref.read(storeProvider));
  }

  /// Start from what is already logged for the night, else from the schedule.
  void _load(VigilStore s) {
    final SleepNight? existing = s.sleepFor(_night);
    final ScheduleRow row = s.schedule[_night.weekday - 1];
    _bed = (existing?.bed ?? row.bed).clamp(1080, 1800);
    _wake = ((existing?.wake ?? (1440 + row.wake)) - 1440).clamp(0, 720);
  }

  int get _asleep => 1440 + _wake - _bed;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final VigilStore s = ref.watch(storeProvider);
    final DateTime today = DateTime.now();
    // Tonight has not happened yet, so the latest night to log is last night.
    final DateTime yesterday = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 1));
    final bool canNext = _night.isBefore(yesterday);
    final bool canPrev = DateTime(today.year, today.month, today.day).difference(_night).inDays < 14;
    final bool hasEntry = s.sleepFor(_night) != null;
    final bool valid = _asleep >= 60 && _asleep <= 16 * 60;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text('Log a night', style: t.section.copyWith(fontSize: 22)),
        Text('For when no watch or band writes sleep data', style: t.micro.copyWith(color: c.textFaint)),
        const SizedBox(height: 16),
        Row(children: <Widget>[
          VigilIconButton(icon: VigilIcons.chevronLeft, semanticLabel: 'Earlier night', onPressed: canPrev ? () => setState(() { _night = _night.subtract(const Duration(days: 1)); _load(s); }) : null),
          Expanded(child: Center(child: Text('Night of ${Fmt.dayStamp(_night)}', style: t.label.copyWith(color: c.text)))),
          VigilIconButton(icon: VigilIcons.chevronRight, semanticLabel: 'Later night', onPressed: canNext ? () => setState(() { _night = _night.add(const Duration(days: 1)); _load(s); }) : null),
        ]),
        const SizedBox(height: 16),
        Row(children: <Widget>[
          Expanded(child: Text('Lights out', style: t.label.copyWith(color: c.textFaint))),
          VigilStepper(valueLabel: Fmt.hm(_bed), semanticName: 'Lights out', valueWidth: 76, onDecrement: _bed > 1080 ? () => setState(() => _bed -= 15) : null, onIncrement: _bed < 1800 ? () => setState(() => _bed += 15) : null),
        ]),
        const SizedBox(height: 10),
        Row(children: <Widget>[
          Expanded(child: Text('Wake', style: t.label.copyWith(color: c.textFaint))),
          VigilStepper(valueLabel: Fmt.hm(_wake), semanticName: 'Wake', valueWidth: 76, onDecrement: _wake > 0 ? () => setState(() => _wake -= 15) : null, onIncrement: _wake < 720 ? () => setState(() => _wake += 15) : null),
        ]),
        const SizedBox(height: 14),
        Text(valid ? 'ASLEEP ${Fmt.dur(_asleep)}' : 'Pick times between 1h and 16h apart.', style: t.meta.copyWith(color: valid ? c.signal : c.critical)),
        const SizedBox(height: 16),
        Row(children: <Widget>[
          if (hasEntry) ...<Widget>[
            VigilButton(
              label: 'Delete',
              variant: VigilButtonVariant.secondary,
              onPressed: () {
                s.removeSleep(_night);
                Navigator.pop(context);
              },
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: VigilButton(
              label: 'Save night',
              expand: true,
              onPressed: valid
                  ? () {
                      SfxService.play(Sfx.clear);
                      s.logSleep(_night, _bed, 1440 + _wake);
                      Navigator.pop(context);
                      showVigilSnack(context, 'Night logged · ${Fmt.dur(_asleep)}');
                    }
                  : null,
            ),
          ),
        ]),
      ]),
    );
  }
}

class _LogWeightSheet extends ConsumerStatefulWidget {
  const _LogWeightSheet();

  @override
  ConsumerState<_LogWeightSheet> createState() => _LogWeightSheetState();
}

class _LogWeightSheetState extends ConsumerState<_LogWeightSheet> {
  late double _kg;

  @override
  void initState() {
    super.initState();
    _kg = ref.read(storeProvider).weightKg ?? 70.0;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text('Log weight', style: t.section.copyWith(fontSize: 22)),
        Text('Kept on this phone', style: t.micro.copyWith(color: c.textFaint)),
        const SizedBox(height: 18),
        Center(
          child: VigilStepper(
            valueLabel: '${_kg.toStringAsFixed(1)} kg',
            semanticName: 'Weight',
            valueWidth: 120,
            onDecrement: _kg > 30 ? () => setState(() => _kg = (_kg * 10 - 1).round() / 10) : null,
            onIncrement: _kg < 250 ? () => setState(() => _kg = (_kg * 10 + 1).round() / 10) : null,
          ),
        ),
        const SizedBox(height: 18),
        VigilButton(
          label: 'Save weight',
          expand: true,
          onPressed: () {
            SfxService.play(Sfx.clear);
            ref.read(storeProvider).logWeight(_kg);
            Navigator.pop(context);
            showVigilSnack(context, 'Weight logged');
          },
        ),
      ]),
    );
  }
}
