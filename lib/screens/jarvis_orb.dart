import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../services/voice.dart';

/// VIGIL's face: a core with rotating rings and a radial waveform. It idles slowly, widens and reacts to
/// the microphone level while listening, spins faster while thinking, and pulses while speaking.
class JarvisOrb extends StatefulWidget {
  const JarvisOrb({super.key, required this.state, required this.level, required this.color, this.size = 180, this.onTap});

  final VoiceState state;

  /// 0..1 microphone loudness.
  final ValueListenable<double> level;
  final Color color;
  final double size;
  final VoidCallback? onTap;

  @override
  State<JarvisOrb> createState() => _JarvisOrbState();
}

class _JarvisOrbState extends State<JarvisOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
  double _energy = 0; // eases toward the target for the current state
  double _spin = 0;
  double _t = 0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _c.addListener(_tick);
  }

  void _tick() {
    final Duration now = _c.lastElapsedDuration ?? Duration.zero;
    double dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (dt < 0 || dt > 0.25) dt = 0.016; // the controller wrapped or the app was paused
    _t += dt;
    final double target = switch (widget.state) {
      VoiceState.idle => 0.0,
      VoiceState.listening => 0.35 + widget.level.value * 0.65,
      VoiceState.thinking => 0.45,
      VoiceState.speaking => 0.6 + 0.4 * math.sin(_t * 7).abs(),
    };
    _energy += (target - _energy) * math.min(1, dt * 7);
    _spin += dt * switch (widget.state) {
      VoiceState.idle => 0.25,
      VoiceState.listening => 0.5,
      VoiceState.thinking => 2.6,
      VoiceState.speaking => 0.9,
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect "remove animations": hold still.
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String get _label => switch (widget.state) {
        VoiceState.idle => 'VIGIL, ready',
        VoiceState.listening => 'VIGIL, listening',
        VoiceState.thinking => 'VIGIL, thinking',
        VoiceState.speaking => 'VIGIL, speaking',
      };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      label: _label,
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: RepaintBoundary(child: CustomPaint(painter: _OrbPainter(this, repaint: _c))),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.s, {required Listenable repaint}) : super(repaint: repaint);

  final _JarvisOrbState s;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.shortestSide / 2;
    final Color col = s.widget.color;
    final double e = s._energy;
    final double t = s._t;
    final double breathe = 0.5 + 0.5 * math.sin(t * 1.6);

    // Glow
    final double glowR = r * (0.55 + 0.12 * breathe + 0.3 * e);
    canvas.drawCircle(
      c,
      glowR,
      Paint()..shader = RadialGradient(colors: <Color>[col.withValues(alpha: 0.30 + 0.25 * e), col.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: glowR)),
    );

    // Outer ring: four long arcs
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..color = col.withValues(alpha: 0.85)
      ..strokeWidth = r * 0.018;
    for (int i = 0; i < 4; i++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.92), s._spin * 0.8 + i * math.pi / 2, math.pi / 3.2, false, ring);
    }

    // Tick ring turning the other way
    final Paint tick = Paint()
      ..color = col.withValues(alpha: 0.55)
      ..strokeWidth = r * 0.012
      ..strokeCap = StrokeCap.butt;
    const int ticks = 72;
    for (int i = 0; i < ticks; i++) {
      final double a = -s._spin * 0.6 + i * 2 * math.pi / ticks;
      final bool major = i % 6 == 0;
      final double r0 = r * (major ? 0.74 : 0.77);
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r0, c + Offset(math.cos(a), math.sin(a)) * r * 0.82, tick..color = col.withValues(alpha: major ? 0.8 : 0.4));
    }

    // Sweeping arcs: the "thinking" ring
    final Paint sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = col.withValues(alpha: 0.9)
      ..strokeWidth = r * 0.035;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.64), s._spin * 1.7, math.pi * (0.35 + 0.5 * e), false, sweep);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.64), s._spin * 1.7 + math.pi, math.pi * (0.2 + 0.4 * e), false, sweep..color = col.withValues(alpha: 0.6));

    // Radial waveform
    const int bars = 56;
    final Paint bar = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.028
      ..color = col;
    for (int i = 0; i < bars; i++) {
      final double a = i * 2 * math.pi / bars;
      final double wave = 0.5 + 0.5 * math.sin(a * 5 + t * 6) * math.sin(a * 3 - t * 4);
      final double len = r * (0.025 + e * 0.17 * (0.35 + 0.65 * wave));
      final double r0 = r * 0.50;
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r0, c + Offset(math.cos(a), math.sin(a)) * (r0 + len), bar..color = col.withValues(alpha: 0.45 + 0.5 * wave * (0.3 + e)));
    }

    // Core
    final double coreR = r * (0.22 + 0.03 * breathe + 0.05 * e);
    canvas.drawCircle(c, coreR, Paint()..color = col.withValues(alpha: 0.18 + 0.12 * e));
    canvas.drawCircle(c, coreR * 0.78, Paint()..shader = RadialGradient(colors: <Color>[Colors.white.withValues(alpha: 0.95), col, col.withValues(alpha: 0.6)], stops: const <double>[0, 0.45, 1]).createShader(Rect.fromCircle(center: c, radius: coreR * 0.78)));
    canvas.drawCircle(c, coreR, Paint()..style = PaintingStyle.stroke..strokeWidth = r * 0.012..color = col);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => true;
}
