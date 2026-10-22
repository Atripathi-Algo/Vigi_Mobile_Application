import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/calendar_api.dart';
import '../app/common.dart';
import '../app/env.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/store.dart';
import '../services/notifications.dart';
import '../services/steps.dart';
import '../vigil/vigil.dart';

/// 00 · Boot · Onboarding
class BootScreen extends ConsumerStatefulWidget {
  const BootScreen({super.key});

  @override
  ConsumerState<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends ConsumerState<BootScreen> {
  static const List<String> _links = VigilStore.linkKeys;
  static const List<String> _allModules = <String>['OBJECTIVES', 'TIMELINE', 'PROTOCOLS', 'VITALS', 'DEEP OPS', 'FIELD LOG', 'LEDGER'];

  final TextEditingController _name = TextEditingController(text: 'Abhishek');
  final TextEditingController _call = TextEditingController(text: 'Batman');
  int _wake = 6 * 60 + 30;
  int _bed = 23 * 60;
  final Set<String> _armed = <String>{..._allModules};
  int _shown = 0;
  bool _visor = false;
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _shown = _links.length;
      _visor = true;
      return;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 600), (Timer t) {
      if (!mounted) return t.cancel();
      setState(() {
        if (_shown < _links.length) {
          _shown++;
        } else {
          _visor = true;
          t.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    _call.dispose();
    super.dispose();
  }

  Future<void> _grant(String key) async {
    final VigilStore s = ref.read(storeProvider);
    if (key == 'Calendar link') {
      if (!Env.hasCalendar) {
        showVigilSnack(context, 'Add GOOGLE_CALENDAR_API_KEY to .env to link');
        return;
      }
      final List<RemoteEvent>? ev = await fetchTodayEvents();
      if (!mounted) return;
      if (ev == null) {
        s.setLink(key, 'DENIED');
        showVigilSnack(context, 'Calendar sync failed. Check the key and calendar id');
      } else {
        s.setLink(key, 'OK');
      }
      return;
    }
    if (key == 'Notifications') {
      final bool ok = await NotificationService.requestPermission();
      if (mounted) s.setLink(key, ok ? 'OK' : 'DENIED');
      return;
    }
    if (key == 'Step sensor') {
      final bool ok = await StepService.start(s, request: true);
      if (mounted) s.setLink(key, ok ? 'OK' : 'DENIED');
      return;
    }
    if (key == 'Exact alarms') {
      await NotificationService.requestExactAlarms();
      final bool ok = await NotificationService.canScheduleExact();
      if (mounted) s.setLink(key, ok ? 'OK' : 'DENIED');
      return;
    }
    s.setLink(key, 'DENIED');
    showVigilSnack(context, '$key bridge is not built in v1.0. Module shows sample data');
  }

  Future<void> _pick(bool wake) async {
    final TimeOfDay? v = await pickVigilTime(context, wake ? _wake : _bed);
    if (v != null) setState(() => wake ? _wake = v.hour * 60 + v.minute : _bed = v.hour * 60 + v.minute);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final VigilStore s = ref.watch(storeProvider);
    return Scaffold(
      backgroundColor: c.ground,
      body: GridBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
            children: <Widget>[
              Center(
                child: SizedBox(
                  width: 124,
                  height: 124,
                  child: CornerBrackets(
                    allCorners: true,
                    length: 18,
                    child: Center(
                      child: VigilEmblem(size: 80, visor: _visor ? null : c.line, showPupil: _visor),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(child: Text('VIGIL', style: t.section.copyWith(fontSize: 42, letterSpacing: 42 * 0.34))),
              const SizedBox(height: 4),
              Center(child: Text('PERSONAL OPS SYSTEM · v1.0', style: t.micro.copyWith(color: c.textFaint))),
              const SizedBox(height: 22),
              const SectionLabel('System links'),
              const SizedBox(height: 8),
              RowList(children: <Widget>[
                for (int i = 0; i < _links.length; i++)
                  if (i < _shown) _linkRow(context, s, _links[i]) else const SizedBox(height: 46),
              ]),
              const SizedBox(height: 18),
              Row(children: <Widget>[
                Expanded(child: VigilField(controller: _name, label: 'Name', hint: 'Your name')),
                const SizedBox(width: 12),
                Expanded(child: VigilField(controller: _call, label: 'Callsign', hint: 'Callsign')),
              ]),
              const SizedBox(height: 14),
              Row(children: <Widget>[
                Expanded(child: _timeField('Wake · weekdays', _wake, VigilIcons.sun, () => _pick(true))),
                const SizedBox(width: 12),
                Expanded(child: _timeField('Bed · weekdays', _bed, VigilIcons.sleep, () => _pick(false))),
              ]),
              const SizedBox(height: 18),
              SectionLabel('Arm modules', trailing: '${_armed.length} / ${_allModules.length}'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                for (final String m in _allModules)
                  Semantics(
                    button: true,
                    selected: _armed.contains(m),
                    label: m,
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: () => setState(() => _armed.contains(m) ? _armed.remove(m) : _armed.add(m)),
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(border: Border.all(color: _armed.contains(m) ? c.signal : c.lineStrong)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                          SizedBox(width: 8, height: 8, child: ColoredBox(color: _armed.contains(m) ? c.signal : c.neutral)),
                          const SizedBox(width: 8),
                          Text(m, style: t.button.copyWith(fontSize: 11, fontWeight: FontWeight.w400, color: _armed.contains(m) ? c.text : c.textMuted)),
                        ]),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 24),
              VigilButton(
                label: 'Initiate',
                size: VigilButtonSize.large,
                expand: true,
                icon: VigilIcons.arrowRight,
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  s.completeBoot(name: _name.text, call: _call.text, wake: _wake, bed: _bed, armed: _armed);
                  context.go('/');
                },
              ),
              const SizedBox(height: 8),
              Center(
                child: VigilButton(
                  label: 'Restore from Drive',
                  variant: VigilButtonVariant.ghost,
                  onPressed: () => showVigilSnack(context, 'Drive restore needs Google sign-in. Not built yet'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkRow(BuildContext context, VigilStore s, String key) {
    final c = context.vigil;
    final t = context.vtype;
    final String st = s.linkStatus[key] ?? 'ASK';
    return SizedBox(
      height: 46,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: <Widget>[
          Expanded(child: Text(key.toUpperCase(), style: t.button.copyWith(fontWeight: FontWeight.w400, color: c.text))),
          if (st == 'OK')
            Text('OK', style: t.button.copyWith(color: c.signal))
          else if (st == 'DENIED')
            InkWell(onTap: () => _grant(key), child: Padding(padding: const EdgeInsets.all(8), child: Text('DENIED · TAP TO RETRY', style: t.meta.copyWith(color: c.textMuted))))
          else
            SizedBox(
              height: 30,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(44, 30), padding: const EdgeInsets.symmetric(horizontal: 10), foregroundColor: c.signal, side: BorderSide(color: c.signal)),
                onPressed: () => _grant(key),
                child: Text('GRANT', style: t.button.copyWith(fontSize: 11, color: c.signal)),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _timeField(String label, int minutes, VigilIcons icon, VoidCallback onTap) {
    final c = context.vigil;
    final t = context.vtype;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text(label.toUpperCase(), style: t.label.copyWith(color: c.textFaint)),
      const SizedBox(height: 6),
      InkWell(
        onTap: onTap,
        child: Container(
          height: VigilSize.input,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.lineStrong)),
          child: Row(children: <Widget>[
            Expanded(child: Text(Fmt.hm(minutes), style: t.title)),
            VigilIcon(icon, size: 18, color: c.textMuted),
          ]),
        ),
      ),
    ]);
  }
}
