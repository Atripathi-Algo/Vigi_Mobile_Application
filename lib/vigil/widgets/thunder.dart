import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/vigil_colors.dart';

/// Lightning effects, drawn in code (no video), "charged, not noisy": short, tied to an action, never blocking a tap.
/// All of them are skipped when the user turned thunder effects off or asked the system to reduce motion.
abstract final class ThunderFx {
  /// The Loadout switch "Thunder effects".
  static bool enabled = true;

  /// A strike: a bright flash and a jagged bolt that fade in a quarter of a second. [to] is where it lands (a point in
  /// screen coordinates); otherwise it falls somewhere in the upper half.
  static void strike(BuildContext context, {Offset? to}) {
    if (!enabled || MediaQuery.disableAnimationsOf(context)) return;
    final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(builder: (BuildContext _) => StrikeFlash(to: to, onDone: () => entry.remove()));
    overlay.insert(entry);
  }
}

/// The flash and bolt of one strike. Removes itself through [onDone] when finished.
class StrikeFlash extends StatefulWidget {
  const StrikeFlash({super.key, this.to, required this.onDone, this.duration = const Duration(milliseconds: 280), this.seed});

  final Offset? to;
  final VoidCallback onDone;
  final Duration duration;

  /// Fixes the bolt's shape (tests); otherwise each strike is different.
  final int? seed;

  @override
  State<StrikeFlash> createState() => _StrikeFlashState();
}

class _StrikeFlashState extends State<StrikeFlash> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration)
    ..addStatusListener((AnimationStatus s) {
      if (s == AnimationStatus.completed) widget.onDone();
    })
    ..forward();
  late final int _seed = widget.seed ?? DateTime.now().microsecondsSinceEpoch;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext _, Widget? __) => CustomPaint(size: Size.infinite, painter: _StrikePainter(_c.value, _seed, widget.to)),
      ),
    );
  }
}

class _StrikePainter extends CustomPainter {
  _StrikePainter(this.p, this.seed, this.to);

  final double p;
  final int seed;
  final Offset? to;

  @override
  void paint(Canvas canvas, Size size) {
    // The flash: a brief wash of the signal colour that is gone in the first part of the strike.
    final double flash = math.pow(1 - p, 3).toDouble();
    canvas.drawRect(Offset.zero & size, Paint()..color = VigilPalette.signal.withValues(alpha: 0.16 * flash));
    if (p > 0.7) return;
    final math.Random r = math.Random(seed);
    final double x0 = size.width * (0.25 + r.nextDouble() * 0.5);
    final Offset end = to ?? Offset(x0 + (r.nextDouble() - 0.5) * size.width * 0.3, size.height * (0.28 + r.nextDouble() * 0.2));
    final Path bolt = Path()..moveTo(x0, 0);
    const int segments = 9;
    for (int i = 1; i <= segments; i++) {
      final double f = i / segments;
      final double jitter = (i == segments) ? 0 : (r.nextDouble() - 0.5) * size.width * 0.16 * (1 - f * 0.5);
      bolt.lineTo(x0 + (end.dx - x0) * f + jitter, end.dy * f);
    }
    final double life = (1 - p / 0.7).clamp(0.0, 1.0);
    canvas.drawPath(bolt, Paint()
      ..color = VigilPalette.signal.withValues(alpha: 0.55 * life)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeJoin = StrokeJoin.miter
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawPath(bolt, Paint()
      ..color = Colors.white.withValues(alpha: life)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.miter);
  }

  @override
  bool shouldRepaint(_StrikePainter old) => old.p != p;
}

/// A faint, rare flicker of storm light at the top of the screen, every twenty to forty seconds. Skipped while the
/// screen is not showing, when the app is in the background, when thunder effects are off, or with reduced motion.
class StormFlicker extends StatefulWidget {
  const StormFlicker({super.key, required this.child, this.minGap = const Duration(seconds: 20), this.maxGap = const Duration(seconds: 40)});

  final Widget child;
  final Duration minGap;
  final Duration maxGap;

  @override
  State<StormFlicker> createState() => _StormFlickerState();
}

class _StormFlickerState extends State<StormFlicker> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  final math.Random _rng = math.Random();
  Timer? _timer;

  // The brightness over the flicker: up, down, up a little, away.
  static final TweenSequence<double> _shape = TweenSequence<double>(<TweenSequenceItem<double>>[
    TweenSequenceItem<double>(tween: Tween<double>(begin: 0, end: 0.75), weight: 15),
    TweenSequenceItem<double>(tween: Tween<double>(begin: 0.75, end: 0.1), weight: 20),
    TweenSequenceItem<double>(tween: Tween<double>(begin: 0.1, end: 0.5), weight: 20),
    TweenSequenceItem<double>(tween: Tween<double>(begin: 0.5, end: 0), weight: 45),
  ]);

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final int span = widget.maxGap.inMilliseconds - widget.minGap.inMilliseconds;
    final Duration wait = widget.minGap + Duration(milliseconds: span <= 0 ? 0 : _rng.nextInt(span));
    _timer = Timer(wait, () {
      if (!mounted) return;
      final bool showing = TickerMode.valuesOf(context).enabled && (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) == AppLifecycleState.resumed;
      if (ThunderFx.enabled && showing && !MediaQuery.disableAnimationsOf(context)) _c.forward(from: 0);
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: <Widget>[
      widget.child,
      Positioned.fill(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _c,
            builder: (BuildContext _, Widget? __) {
              if (_c.isDismissed || _c.isCompleted) return const SizedBox.shrink();
              final double v = _shape.transform(_c.value);
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: <Color>[VigilPalette.signal.withValues(alpha: 0.16 * v), VigilPalette.signal.withValues(alpha: 0)]),
                ),
              );
            },
          ),
        ),
      ),
    ]);
  }
}
