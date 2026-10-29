import 'package:flutter/material.dart';

import '../theme/vigil_tokens.dart';

/// The "hot card" edge: a 1 dp gradient border (signal, violet, magenta) with a faint bolt watermark in the
/// bottom-right corner. One per screen. The class keeps its old name so existing call sites compile.
class CornerBrackets extends StatelessWidget {
  const CornerBrackets({
    super.key,
    required this.child,
    this.color,
    this.length = VigilSize.bracket,
    this.stroke = 2,
    this.allCorners = false,
    this.radius = KRadius.card,
  });

  final Widget child;
  final Color? color;
  final double length;
  final double stroke;
  final bool allCorners;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    return CustomPaint(
      foregroundPainter: _HotEdgePainter(
        gradient: color == null ? c.hotGradient : LinearGradient(colors: <Color>[color!, color!]),
        radius: radius,
        bolt: (color ?? c.violet).withValues(alpha: c.isDark ? 0.10 : 0.07),
      ),
      child: child,
    );
  }
}

class _HotEdgePainter extends CustomPainter {
  _HotEdgePainter({required this.gradient, required this.radius, required this.bolt});

  final Gradient gradient;
  final double radius;
  final Color bolt;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = Offset.zero & size;
    final RRect rr = RRect.fromRectAndRadius(r.deflate(0.5), Radius.circular(radius));
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = gradient.createShader(r)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    // A faint bolt in the bottom-right corner.
    canvas.save();
    canvas.clipRRect(rr);
    final double s = (size.shortestSide * 0.5).clamp(30.0, 70.0);
    final Offset o = Offset(size.width - s * 0.95, size.height - s * 1.05);
    final Path p = Path()
      ..moveTo(o.dx + s * 0.62, o.dy)
      ..lineTo(o.dx + s * 0.12, o.dy + s * 0.58)
      ..lineTo(o.dx + s * 0.46, o.dy + s * 0.58)
      ..lineTo(o.dx + s * 0.30, o.dy + s)
      ..lineTo(o.dx + s * 0.86, o.dy + s * 0.38)
      ..lineTo(o.dx + s * 0.52, o.dy + s * 0.38)
      ..close();
    canvas.drawPath(p, Paint()..color = bolt);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HotEdgePainter old) => old.gradient != gradient || old.radius != radius || old.bolt != bolt;
}

/// The faint 26 px grid behind every screen (text colour at 3 % opacity).
class GridBackground extends StatelessWidget {
  const GridBackground({super.key, required this.child, this.spacing = 26, this.diagonal = false, this.color});

  final Widget child;
  final double spacing;

  /// Diagonal hatch (used on widgets / lock screen) instead of the square grid.
  final bool diagonal;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color line = color ?? context.vigil.text.withValues(alpha: diagonal ? 0.035 : 0.03);
    return CustomPaint(
      painter: _GridPainter(color: line, spacing: diagonal ? 14 : spacing, diagonal: diagonal),
      child: child,
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.color, required this.spacing, required this.diagonal});

  final Color color;
  final double spacing;
  final bool diagonal;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = 1;
    if (diagonal) {
      for (double x = -size.height; x < size.width; x += spacing) {
        canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
      }
      return;
    }
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color || old.spacing != spacing || old.diagonal != diagonal;
}

/// The K mark: octagon, a K, and a lightning bolt cut through its diagonal.
/// Drawn in code (32 x 32 design box) so it scales crisply at any size.
class VigilEmblem extends StatelessWidget {
  const VigilEmblem({
    super.key,
    this.size = 28,
    this.outline,
    this.visor,
    this.pupil,
    this.showPupil = true,
    this.semanticLabel = 'K',
  });

  final double size;

  /// Colour of the K and the bolt core. Defaults to the ice highlight.
  final Color? outline;

  /// Colour of the octagon and the bolt glow. Defaults to the signal blue.
  final Color? visor;

  /// Unused; kept so existing call sites compile.
  final Color? pupil;
  final bool showPupil;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final Widget paint = CustomPaint(
      size: Size.square(size),
      painter: _EmblemPainter(
        glyph: outline ?? c.steel,
        signal: visor ?? c.signal,
        core: outline ?? Colors.white,
        stroke: size >= 40 ? 1.6 : (size >= 24 ? 2.0 : 3.0),
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: paint);
    return Semantics(label: semanticLabel, image: true, child: paint);
  }
}

class _EmblemPainter extends CustomPainter {
  _EmblemPainter({required this.glyph, required this.signal, required this.core, required this.stroke});

  final Color glyph;
  final Color signal;
  final Color core;
  final double stroke;

  static Path _poly(List<double> p) {
    final Path path = Path()..moveTo(p[0], p[1]);
    for (int i = 2; i < p.length; i += 2) {
      path.lineTo(p[i], p[i + 1]);
    }
    return path..close();
  }

  static final Path _octagon = _poly(<double>[9.4, 1, 22.6, 1, 31, 9.4, 31, 22.6, 22.6, 31, 9.4, 31, 1, 22.6, 1, 9.4]);
  static final Path _k = _poly(<double>[8, 7, 12.6, 7, 12.6, 15, 19.6, 7, 25, 7, 17.2, 15.4, 25.2, 25, 19.6, 25, 14, 18.2, 12.6, 19.8, 12.6, 25, 8, 25]);
  static final Path _boltGlow = _poly(<double>[23.6, 5.2, 16.4, 13.2, 18.8, 13.4, 11.2, 22.4, 14.6, 15.8, 12.2, 15.6, 19.8, 5.2]);
  static final Path _boltCore = _poly(<double>[22.6, 6, 16.9, 12.6, 18.9, 12.8, 12.6, 20.4, 15.2, 15.2, 13.4, 15, 19.6, 6]);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    canvas.drawPath(_octagon, Paint()
      ..color = signal
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 32 / size.width * 0.8
      ..strokeJoin = StrokeJoin.miter);
    canvas.drawPath(_k, Paint()..color = glyph);
    canvas.drawPath(_boltGlow, Paint()..color = signal);
    canvas.drawPath(_boltCore, Paint()..color = core);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EmblemPainter old) => old.glyph != glyph || old.signal != signal || old.core != core || old.stroke != stroke;
}
