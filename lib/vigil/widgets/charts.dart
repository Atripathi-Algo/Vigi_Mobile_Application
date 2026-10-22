import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/vigil_tokens.dart';

/// Ops readiness ring (Command, widgets): 7 px arc from 12 o'clock,
/// four 5 px compass ticks, value + caption in the middle.
class ReadinessRing extends StatelessWidget {
  const ReadinessRing({
    super.key,
    required this.value,
    this.caption = 'READY',
    this.size = 84,
    this.stroke = 7,
    this.color,
  });

  /// 0–100.
  final int value;
  final String caption;
  final double size;
  final double stroke;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    return Semantics(
      label: 'Ops readiness $value percent',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(
            fraction: value / 100,
            color: color ?? c.signal,
            track: c.line,
            tick: c.neutral,
            stroke: stroke,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('$value', style: t.metric.copyWith(fontSize: size * 0.31, height: 1)),
                if (caption.isNotEmpty)
                  Text(caption, style: t.micro.copyWith(fontSize: 9, color: c.textMuted, letterSpacing: 1.4)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.color, required this.track, required this.tick, required this.stroke});

  final double fraction;
  final Color color;
  final Color track;
  final Color tick;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double r = size.width / 2 - stroke / 2 - 2;
    final Paint base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawCircle(center, r, base..color = track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      2 * math.pi * fraction.clamp(0.0, 1.0),
      false,
      base..color = color,
    );
    final Paint tp = Paint()
      ..color = tick
      ..strokeWidth = 1.5;
    final double w = size.width;
    canvas.drawLine(Offset(w / 2, 0), Offset(w / 2, 5), tp);
    canvas.drawLine(Offset(w / 2, w - 5), Offset(w / 2, w), tp);
    canvas.drawLine(Offset(0, w / 2), Offset(5, w / 2), tp);
    canvas.drawLine(Offset(w - 5, w / 2), Offset(w, w / 2), tp);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.tick != tick ||
      old.stroke != stroke;
}

/// Deep Ops tick ring: 48 radial ticks (every 4th long) that light up
/// clockwise as the session progresses. Put the timer in [child].
class TickRing extends StatelessWidget {
  const TickRing({super.key, required this.progress, this.size = 264, this.ticks = 48, this.child});

  final double progress;
  final double size;
  final int ticks;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _TickPainter(
          progress: progress,
          ticks: ticks,
          lit: c.signal,
          major: c.neutral,
          minor: c.line,
          inner: c.rule,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter({
    required this.progress,
    required this.ticks,
    required this.lit,
    required this.major,
    required this.minor,
    required this.inner,
  });

  final double progress;
  final int ticks;
  final Color lit;
  final Color major;
  final Color minor;
  final Color inner;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double outer = size.width / 2;
    final int litCount = (progress.clamp(0.0, 1.0) * ticks).round();
    final Paint p = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.butt;
    for (int i = 0; i < ticks; i++) {
      final double a = -math.pi / 2 + 2 * math.pi * i / ticks;
      final bool isMajor = i % 4 == 0;
      final double len = isMajor ? 16 : 9;
      p.color = i < litCount ? lit : (isMajor ? major : minor);
      final Offset dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(center + dir * (outer - len), center + dir * outer, p);
    }
    canvas.drawCircle(
      center,
      outer - 30,
      Paint()
        ..color = inner
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_TickPainter old) =>
      old.progress != progress ||
      old.ticks != ticks ||
      old.lit != lit ||
      old.major != major ||
      old.minor != minor ||
      old.inner != inner;
}

/// One bar in a time-window chart (sleep tracker, ops window):
/// a dashed "plan" outline and a solid "actual" bar on a [start, end] axis.
class WindowBar extends StatelessWidget {
  const WindowBar({
    super.key,
    required this.axisStart,
    required this.axisEnd,
    this.planStart,
    this.planEnd,
    this.actualStart,
    this.actualEnd,
    this.actualColor,
    this.planColor,
    this.height = 22,
    this.semanticLabel,
  });

  /// All values in minutes on the same axis (e.g. minutes after 21:00).
  final double axisStart;
  final double axisEnd;
  final double? planStart;
  final double? planEnd;
  final double? actualStart;
  final double? actualEnd;
  final Color? actualColor;
  final Color? planColor;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: _WindowPainter(
            a0: axisStart,
            a1: axisEnd,
            p0: planStart,
            p1: planEnd,
            x0: actualStart,
            x1: actualEnd,
            actual: actualColor ?? c.steel,
            plan: planColor ?? c.signal,
            bg: c.ground,
            grid: c.rule,
          ),
        ),
      ),
    );
  }
}

class _WindowPainter extends CustomPainter {
  _WindowPainter({
    required this.a0,
    required this.a1,
    required this.p0,
    required this.p1,
    required this.x0,
    required this.x1,
    required this.actual,
    required this.plan,
    required this.bg,
    required this.grid,
  });

  final double a0, a1;
  final double? p0, p1, x0, x1;
  final Color actual, plan, bg, grid;

  double _x(double v, double w) => a1 == a0 ? 0 : ((v - a0) / (a1 - a0)).clamp(0.0, 1.0) * w;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final Paint g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final double f in <double>[0.25, 0.5, 0.75]) {
      canvas.drawLine(Offset(w * f, 0), Offset(w * f, h), g);
    }
    if (p0 != null && p1 != null) {
      _dashedRect(canvas, Rect.fromLTRB(_x(p0!, w), 1, _x(p1!, w), h - 1), plan);
    }
    if (x0 != null && x1 != null) {
      canvas.drawRect(Rect.fromLTRB(_x(x0!, w), 6, _x(x1!, w), h - 6), Paint()..color = actual);
    }
  }

  void _dashedRect(Canvas canvas, Rect r, Color color) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = 1;
    const double dash = 3, gap = 3;
    for (double x = r.left; x < r.right; x += dash + gap) {
      final double e = math.min(x + dash, r.right);
      canvas.drawLine(Offset(x, r.top), Offset(e, r.top), p);
      canvas.drawLine(Offset(x, r.bottom), Offset(e, r.bottom), p);
    }
    for (double y = r.top; y < r.bottom; y += dash + gap) {
      final double e = math.min(y + dash, r.bottom);
      canvas.drawLine(Offset(r.left, y), Offset(r.left, e), p);
      canvas.drawLine(Offset(r.right, y), Offset(r.right, e), p);
    }
  }

  @override
  bool shouldRepaint(_WindowPainter old) =>
      old.p0 != p0 || old.p1 != p1 || old.x0 != x0 || old.x1 != x1 || old.actual != actual || old.plan != plan;
}

/// Simple vertical bar chart (hourly screen time, 7-day spend, sleep nights).
class MiniBars extends StatelessWidget {
  const MiniBars({
    super.key,
    required this.values,
    required this.colors,
    this.height = 56,
    this.gap = 2,
    this.refLine,
    this.semanticLabel,
  });

  final List<double> values;

  /// One colour per bar (lets callers highlight today / over-limit bars).
  final List<Color> colors;
  final double height;
  final double gap;

  /// Optional dashed reference line in value units.
  final double? refLine;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final double maxV = values.fold<double>(refLine ?? 0, math.max);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            return Stack(
              children: <Widget>[
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      for (int i = 0; i < values.length; i++) ...<Widget>[
                        if (i > 0) SizedBox(width: gap),
                        Expanded(
                          child: Container(
                            height: maxV == 0 ? 2 : math.max(2, height * values[i] / maxV),
                            color: colors.isEmpty ? c.signal : colors[i % colors.length],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (refLine != null && maxV > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: height * refLine! / maxV,
                    child: CustomPaint(size: const Size(double.infinity, 1), painter: _DashPainter(c.textMuted)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 3, size.width), 0), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
