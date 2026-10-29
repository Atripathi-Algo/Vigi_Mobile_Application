import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/vigil_colors.dart';

/// Lightning and sparks, drawn in code (no video), "charged, not noisy": short, tied to an action, never blocking a
/// tap. The Settings control Effects has three levels: [off] nothing, [subtle] sparks, transitions and rolling
/// numbers, [full] adds lightning strikes and the storm flicker. All of it is skipped when the system asks to reduce motion.
abstract final class ThunderFx {
  static const int off = 0;
  static const int subtle = 1;
  static const int full = 2;

  /// The Settings level: 0 off, 1 subtle, 2 full.
  static int level = full;

  /// Lightning strikes and the storm flicker.
  static bool get enabled => level >= full;

  /// Sparks, press depth, rolling numbers.
  static bool get subtleOn => level >= subtle;

  /// Where the last tap landed, so an effect that follows it can start from the same spot.
  static Offset? _lastTap;
  static DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);

  static void noteTap(BuildContext context) {
    final Offset? c = centerOf(context);
    if (c == null) return;
    _lastTap = c;
    _lastTapAt = DateTime.now();
  }

  /// The tap that happened in the last moment, or null.
  static Offset? get recentTap => DateTime.now().difference(_lastTapAt) < const Duration(milliseconds: 900) ? _lastTap : null;

  /// The centre of [context]'s widget in screen coordinates, or null when it is not laid out.
  static Offset? centerOf(BuildContext context) {
    final RenderObject? ro = context.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) return null;
    return ro.localToGlobal(ro.size.center(Offset.zero));
  }

  static OverlayState? _overlay(BuildContext context) => Overlay.maybeOf(context, rootOverlay: true);

  /// A strike: a bright flash and a jagged, branching bolt that fade in a quarter of a second. [to] is where it lands
  /// (screen coordinates); by default it lands on the element just tapped, else in the upper half. Full only.
  static void strike(BuildContext context, {Offset? to}) {
    if (!enabled || MediaQuery.disableAnimationsOf(context)) return;
    final OverlayState? overlay = _overlay(context);
    if (overlay == null) return;
    final Offset? target = to ?? recentTap;
    late final OverlayEntry entry;
    entry = OverlayEntry(builder: (BuildContext _) => StrikeFlash(to: target, onDone: () => entry.remove()));
    overlay.insert(entry);
  }

  /// A small burst of sparks from [at] (default: the element just tapped, else the centre of [context]). Subtle and full.
  static void spark(BuildContext context, {Offset? at, Color? color}) {
    if (!subtleOn || MediaQuery.disableAnimationsOf(context)) return;
    final OverlayState? overlay = _overlay(context);
    final Offset? origin = at ?? recentTap ?? centerOf(context);
    if (overlay == null || origin == null) return;
    final VigilColors c = VigilColors.of(Theme.of(context).brightness);
    late final OverlayEntry entry;
    entry = OverlayEntry(builder: (BuildContext _) => SparkBurst(origin: origin, colors: <Color>[color ?? c.violet, c.signal, c.magenta], onDone: () => entry.remove()));
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
    final VigilColors c = VigilColors.of(Theme.of(context).brightness);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext _, Widget? __) => CustomPaint(size: Size.infinite, painter: _StrikePainter(_c.value, _seed, widget.to, c.signal, c.violet)),
      ),
    );
  }
}

class _StrikePainter extends CustomPainter {
  _StrikePainter(this.p, this.seed, this.to, this.signal, this.violet);

  final double p;
  final int seed;
  final Offset? to;
  final Color signal;
  final Color violet;

  Path _bolt(math.Random r, Offset from, Offset end, int segments, double jitter) {
    final Path bolt = Path()..moveTo(from.dx, from.dy);
    for (int i = 1; i <= segments; i++) {
      final double f = i / segments;
      final double j = (i == segments) ? 0 : (r.nextDouble() - 0.5) * jitter * (1 - f * 0.5);
      bolt.lineTo(from.dx + (end.dx - from.dx) * f + j, from.dy + (end.dy - from.dy) * f);
    }
    return bolt;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // The flash: a brief wash of the signal colour that is gone in the first part of the strike.
    final double flash = math.pow(1 - p, 3).toDouble();
    canvas.drawRect(Offset.zero & size, Paint()..color = signal.withValues(alpha: 0.14 * flash));
    if (p > 0.7) return;
    final math.Random r = math.Random(seed);
    final double x0 = size.width * (0.25 + r.nextDouble() * 0.5);
    final Offset end = to ?? Offset(x0 + (r.nextDouble() - 0.5) * size.width * 0.3, size.height * (0.28 + r.nextDouble() * 0.2));
    final Offset from = Offset(to == null ? x0 : (end.dx + (x0 - end.dx) * 0.35), 0);
    final double life = (1 - p / 0.7).clamp(0.0, 1.0);
    final Path main = _bolt(r, from, end, 9, size.width * 0.16);
    // Two short branches off the main bolt.
    final List<Path> branches = <Path>[];
    for (int b = 0; b < 2; b++) {
      final double f = 0.35 + 0.3 * b + r.nextDouble() * 0.1;
      final Offset start = Offset(from.dx + (end.dx - from.dx) * f, from.dy + (end.dy - from.dy) * f);
      final double dir = (b == 0 ? -1 : 1) * (0.5 + r.nextDouble() * 0.6);
      branches.add(_bolt(r, start, Offset(start.dx + dir * size.width * 0.22, start.dy + (end.dy - start.dy) * 0.28), 4, size.width * 0.06));
    }
    final Paint glow = Paint()
      ..color = violet.withValues(alpha: 0.5 * life)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeJoin = StrokeJoin.miter
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final Paint core = Paint()
      ..color = Colors.white.withValues(alpha: life)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.miter;
    canvas.drawPath(main, glow);
    canvas.drawPath(main, core);
    for (final Path b in branches) {
      canvas.drawPath(b, glow..strokeWidth = 4);
      canvas.drawPath(b, core..strokeWidth = 1.1);
    }
  }

  @override
  bool shouldRepaint(_StrikePainter old) => old.p != p;
}

/// Sixteen sparks thrown from a point, pulled down by gravity, gone in 350 ms.
class SparkBurst extends StatefulWidget {
  const SparkBurst({super.key, required this.origin, required this.colors, required this.onDone, this.count = 16, this.seed});

  final Offset origin;
  final List<Color> colors;
  final VoidCallback onDone;
  final int count;
  final int? seed;

  @override
  State<SparkBurst> createState() => _SparkBurstState();
}

class _SparkBurstState extends State<SparkBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 350))
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
        builder: (BuildContext _, Widget? __) => CustomPaint(size: Size.infinite, painter: _SparkPainter(_c.value, widget.origin, widget.colors, widget.count, _seed)),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.t, this.origin, this.colors, this.count, this.seed);

  final double t;
  final Offset origin;
  final List<Color> colors;
  final int count;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final math.Random r = math.Random(seed);
    final double e = Curves.easeOutCubic.transform(t);
    for (int i = 0; i < count; i++) {
      final double angle = r.nextDouble() * math.pi * 2;
      final double speed = 40 + r.nextDouble() * 70;
      final Offset p = origin + Offset(math.cos(angle) * speed * e, math.sin(angle) * speed * e + 90 * t * t);
      final double radius = (1.2 + r.nextDouble() * 2.2) * (1 - t * 0.6);
      canvas.drawCircle(p, radius, Paint()..color = colors[i % colors.length].withValues(alpha: (1 - t).clamp(0.0, 1.0)));
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.t != t;
}

/// A faint, rare flicker of storm light at the top of the screen, every twenty to forty seconds. Skipped while the
/// screen is not showing, when the app is in the background, when effects are not Full, or with reduced motion.
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
    final VigilColors vc = VigilColors.of(Theme.of(context).brightness);
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
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: <Color>[vc.violet.withValues(alpha: 0.16 * v), vc.violet.withValues(alpha: 0)]),
                ),
              );
            },
          ),
        ),
      ),
    ]);
  }
}
