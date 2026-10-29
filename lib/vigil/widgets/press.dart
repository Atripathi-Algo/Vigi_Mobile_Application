import 'package:flutter/material.dart';

import 'thunder.dart';

/// Press depth: the child sinks to 98 % for 120 ms while a finger is down. Skipped when Effects is off or the system
/// asks to reduce motion. It never takes part in hit testing, so taps work exactly as before.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final bool on = _down && ThunderFx.subtleOn && !MediaQuery.disableAnimationsOf(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(scale: on ? 0.98 : 1, duration: const Duration(milliseconds: 120), curve: Curves.easeOut, child: widget.child),
    );
  }
}
