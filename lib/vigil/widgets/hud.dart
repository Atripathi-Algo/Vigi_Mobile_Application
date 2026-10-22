import 'package:flutter/material.dart';

import '../theme/vigil_tokens.dart';

/// Draws the HUD corner brackets used on "intel" and hero cards:
/// a 12 px L in the top-left and bottom-right corners, 2 px stroke, signal colour.
class CornerBrackets extends StatelessWidget {
  const CornerBrackets({
    super.key,
    required this.child,
    this.color,
    this.length = VigilSize.bracket,
    this.stroke = 2,
    this.allCorners = false,
  });

  final Widget child;
  final Color? color;
  final double length;
  final double stroke;
  final bool allCorners;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _BracketPainter(
        color: color ?? context.vigil.signal,
        length: length,
        stroke: stroke,
        allCorners: allCorners,
      ),
      child: child,
    );
  }
}

class _BracketPainter extends CustomPainter {
  _BracketPainter({required this.color, required this.length, required this.stroke, required this.allCorners});

  final Color color;
  final double length;
  final double stroke;
  final bool allCorners;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter;
    final double h = stroke / 2;
    final double w = size.width;
    final double ht = size.height;
    final Path path = Path()
      // top-left
      ..moveTo(h, length)
      ..lineTo(h, h)
      ..lineTo(length, h)
      // bottom-right
      ..moveTo(w - h, ht - length)
      ..lineTo(w - h, ht - h)
      ..lineTo(w - length, ht - h);
    if (allCorners) {
      path
        ..moveTo(w - length, h)
        ..lineTo(w - h, h)
        ..lineTo(w - h, length)
        ..moveTo(h, ht - length)
        ..lineTo(h, ht - h)
        ..lineTo(length, ht - h);
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_BracketPainter old) =>
      old.color != color || old.length != length || old.stroke != stroke || old.allCorners != allCorners;
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

/// The VIGIL emblem: shield outline + visor slit + optional centre diamond.
/// Drawn in code (48 × 48 design box) so it scales crisply; the same geometry
/// ships as `assets/svg/emblem*.svg` for launcher icons.
class VigilEmblem extends StatelessWidget {
  const VigilEmblem({
    super.key,
    this.size = 28,
    this.outline,
    this.visor,
    this.pupil,
    this.showPupil = true,
    this.semanticLabel = 'VIGIL',
  });

  final double size;
  final Color? outline;
  final Color? visor;
  final Color? pupil;

  /// The centre diamond is dropped automatically below 24 px.
  final bool showPupil;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final double stroke = size >= 64
        ? 2.2
        : size >= 40
            ? 2.4
            : size >= 24
                ? 2.6
                : 3.4;
    final Widget paint = CustomPaint(
      size: Size.square(size),
      painter: _EmblemPainter(
        outline: outline ?? c.text,
        visor: visor ?? c.signal,
        pupil: (showPupil && size >= 24) ? (pupil ?? c.ground) : null,
        stroke: stroke,
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: paint);
    return Semantics(label: semanticLabel, image: true, child: paint);
  }
}

class _EmblemPainter extends CustomPainter {
  _EmblemPainter({required this.outline, required this.visor, required this.pupil, required this.stroke});

  final Color outline;
  final Color visor;
  final Color? pupil;
  final double stroke;

  static final Path _shield = Path()
    ..moveTo(24, 3)
    ..lineTo(42, 9)
    ..lineTo(40, 29)
    ..lineTo(24, 45)
    ..lineTo(8, 29)
    ..lineTo(6, 9)
    ..close();

  static final Path _visor = Path()
    ..moveTo(12, 19)
    ..lineTo(36, 19)
    ..lineTo(32, 25.5)
    ..lineTo(16, 25.5)
    ..close();

  static final Path _pupil = Path()
    ..moveTo(24, 19.6)
    ..lineTo(26.6, 22.25)
    ..lineTo(24, 24.9)
    ..lineTo(21.4, 22.25)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    canvas.drawPath(
      _shield,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.miter,
    );
    canvas.drawPath(_visor, Paint()..color = visor);
    if (pupil != null) canvas.drawPath(_pupil, Paint()..color = pupil!);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EmblemPainter old) =>
      old.outline != outline || old.visor != visor || old.pupil != pupil || old.stroke != stroke;
}
