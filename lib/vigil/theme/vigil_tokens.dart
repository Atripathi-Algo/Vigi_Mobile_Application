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
  static const double gutter = 16;

  /// Default gap between stacked sections.
  static const double stack = 12;
}

/// Component sizes (logical px).
abstract final class VigilSize {
  static const double touch = 48;
  static const double button = 48;
  static const double buttonSmall = 38;
  static const double buttonLarge = 54;
  static const double input = 48;
  static const double row = 56;
  static const double rowCompact = 44;
  static const double navBar = 64; // + bottom inset (min 20)
  static const double navMinInset = 20;
  static const double core = 56;
  static const double coreLift = 22;
  static const double fab = 56;
  static const double checkbox = 22;
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

/// Radii in dp (handoff): cards 18, sheets 26 (top), dialogs 22, fields 14, tiles 12, buttons and chips pill,
/// checkboxes 7. The K mark is the one hard shape (octagon).
abstract final class KRadius {
  static const double card = 18;
  static const double tile = 16;
  static const double sheet = 26;
  static const double dialog = 22;
  static const double field = 14;
  static const double iconTile = 12;
  static const double checkbox = 7;
  static const double pill = 999;
}

/// Shapes. Rounded everywhere except the K octagon.
abstract final class VigilShapes {
  static OutlinedBorder pill([BorderSide side = BorderSide.none]) => StadiumBorder(side: side);

  static OutlinedBorder card([BorderSide side = BorderSide.none]) => RoundedRectangleBorder(side: side, borderRadius: BorderRadius.circular(KRadius.card));

  static OutlinedBorder field([BorderSide side = BorderSide.none]) => RoundedRectangleBorder(side: side, borderRadius: BorderRadius.circular(KRadius.field));

  static OutlinedBorder dialog([BorderSide side = BorderSide.none]) => RoundedRectangleBorder(side: side, borderRadius: BorderRadius.circular(KRadius.dialog));

  /// Kept for older call sites: now a rounded rectangle of radius [cut].
  static OutlinedBorder chamfer([double cut = 10, BorderSide side = BorderSide.none]) => RoundedRectangleBorder(side: side, borderRadius: BorderRadius.circular(cut));

  /// Regular octagon (30 % cut) for the K button and the FAB.
  static OutlinedBorder octagon(double size, [BorderSide side = BorderSide.none]) {
    return BeveledRectangleBorder(side: side, borderRadius: BorderRadius.circular(size * 0.29));
  }

  /// Generic rounded rectangle (fields, small panels).
  static OutlinedBorder square([BorderSide side = BorderSide.none]) => field(side);

  /// Bottom sheet: both top corners rounded 26.
  static OutlinedBorder sheet([BorderSide side = BorderSide.none]) {
    return RoundedRectangleBorder(
      side: side,
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(KRadius.sheet), topRight: Radius.circular(KRadius.sheet)),
    );
  }
}

/// Convenience accessors: `context.vigil.signal`, `context.vtype.label`.
extension VigilThemeX on BuildContext {
  VigilColors get vigil => Theme.of(this).extension<VigilColors>() ?? VigilColors.dark;
  VigilType get vtype => Theme.of(this).extension<VigilType>() ?? VigilType.base();
}
