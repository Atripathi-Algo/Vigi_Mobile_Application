import 'package:flutter/material.dart';

import 'vigil_colors.dart';
import 'vigil_type.dart';

/// Spacing scale (logical px).
abstract final class VigilSpace {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;

  /// Screen side padding.
  static const double gutter = 20;

  /// Default gap between stacked sections.
  static const double stack = 12;
}

/// Component sizes (logical px).
abstract final class VigilSize {
  static const double touch = 44;
  static const double button = 44;
  static const double buttonLarge = 54;
  static const double input = 48;
  static const double row = 56;
  static const double rowCompact = 44;
  static const double navBar = 66; // + bottom inset (min 18)
  static const double navMinInset = 18;
  static const double core = 58;
  static const double coreLift = 20;
  static const double fab = 56;
  static const double checkbox = 20;
  static const double icon = 22;
  static const double bracket = 12;
}

/// Motion tokens.
abstract final class VigilMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration sheet = Duration(milliseconds: 220);
  static const Duration reveal = Duration(milliseconds: 600);
  static const Curve curve = Curves.easeOutCubic;
}

/// Shapes. The VIGIL chamfer cuts the top-right and bottom-left corners.
/// Everything else is square (radius 0).
abstract final class VigilShapes {
  static OutlinedBorder chamfer([double cut = 10, BorderSide side = BorderSide.none]) {
    return BeveledRectangleBorder(
      side: side,
      borderRadius: BorderRadius.only(
        topRight: Radius.circular(cut),
        bottomLeft: Radius.circular(cut),
      ),
    );
  }

  /// Regular octagon (30 % cut) for the core VIGIL button and the FAB.
  static OutlinedBorder octagon(double size, [BorderSide side = BorderSide.none]) {
    return BeveledRectangleBorder(side: side, borderRadius: BorderRadius.circular(size * 0.3));
  }

  static OutlinedBorder square([BorderSide side = BorderSide.none]) {
    return RoundedRectangleBorder(side: side);
  }

  /// Bottom sheet: both top corners chamfered 18 px.
  static OutlinedBorder sheet([BorderSide side = BorderSide.none]) {
    return BeveledRectangleBorder(
      side: side,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(18),
        topRight: Radius.circular(18),
      ),
    );
  }
}

/// Convenience accessors: `context.vigil.signal`, `context.vtype.label`.
extension VigilThemeX on BuildContext {
  VigilColors get vigil => Theme.of(this).extension<VigilColors>() ?? VigilColors.dark;
  VigilType get vtype => Theme.of(this).extension<VigilType>() ?? VigilType.base();
}
