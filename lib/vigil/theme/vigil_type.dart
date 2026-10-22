import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'vigil_colors.dart';

/// VIGIL type scale. Letter-spacing in the design is in em; Flutter wants
/// logical pixels, so every style converts `em × fontSize`.
///
/// Families: Chakra Petch (display, numerals), IBM Plex Sans (body),
/// IBM Plex Mono (labels, readouts, buttons). Labels are written in
/// UPPERCASE at the call site; styles do not transform case.
@immutable
class VigilType extends ThemeExtension<VigilType> {
  const VigilType({
    required this.display,
    required this.hero,
    required this.h1,
    required this.section,
    required this.h2,
    required this.metric,
    required this.title,
    required this.rowTitle,
    required this.body,
    required this.caption,
    required this.button,
    required this.cta,
    required this.label,
    required this.meta,
    required this.micro,
  });

  /// 66 / 1.0 Chakra 600, tabular — Deep Ops timer.
  final TextStyle display;

  /// 40 / 1.0 Chakra 700 — sleep plan times, big readouts.
  final TextStyle hero;

  /// 31 / 1.1 Chakra 600 — Command greeting.
  final TextStyle h1;

  /// 26 / 1.0 Chakra 700 +14 % — screen titles (OPS, PROTOCOLS…).
  final TextStyle section;

  /// 24 / 1.22 Chakra 600 — briefing headline.
  final TextStyle h2;

  /// 22 / 1.05 Chakra 700 — tile values.
  final TextStyle metric;

  /// 17 / 1.3 Plex Sans 600.
  final TextStyle title;

  /// 15 / 1.3 Plex Sans 500 — list row titles.
  final TextStyle rowTitle;

  /// 15 / 1.45 Plex Sans 400.
  final TextStyle body;

  /// 13 / 1.35 Plex Sans 400.
  final TextStyle caption;

  /// 12 Plex Mono 600 +14 % — button labels (UPPERCASE).
  final TextStyle button;

  /// 16 Chakra 700 +22 % — full-width CTAs (UPPERCASE).
  final TextStyle cta;

  /// 11 Plex Mono 500 +16 % — section labels (UPPERCASE).
  final TextStyle label;

  /// 11 Plex Mono 400 +4 % — row metadata (UPPERCASE).
  final TextStyle meta;

  /// 10 Plex Mono 400 +10 % — nav labels, axis ticks (UPPERCASE).
  final TextStyle micro;

  static const List<FontFeature> _tabular = <FontFeature>[FontFeature.tabularFigures()];

  factory VigilType.base({Color color = VigilPalette.text}) {
    TextStyle disp(double size, FontWeight w, double h, double em) => GoogleFonts.chakraPetch(
          fontSize: size,
          fontWeight: w,
          height: h,
          letterSpacing: size * em,
          color: color,
        );
    TextStyle sans(double size, FontWeight w, double h) => GoogleFonts.ibmPlexSans(
          fontSize: size,
          fontWeight: w,
          height: h,
          color: color,
        );
    TextStyle mono(double size, FontWeight w, double h, double em) => GoogleFonts.ibmPlexMono(
          fontSize: size,
          fontWeight: w,
          height: h,
          letterSpacing: size * em,
          color: color,
        );

    return VigilType(
      display: disp(66, FontWeight.w600, 1.0, 0.04).copyWith(fontFeatures: _tabular),
      hero: disp(40, FontWeight.w700, 1.0, 0).copyWith(fontFeatures: _tabular),
      h1: disp(31, FontWeight.w600, 1.1, 0.01),
      section: disp(26, FontWeight.w700, 1.0, 0.14),
      h2: disp(24, FontWeight.w600, 1.22, 0),
      metric: disp(22, FontWeight.w700, 1.05, 0).copyWith(fontFeatures: _tabular),
      title: sans(17, FontWeight.w600, 1.3),
      rowTitle: sans(15, FontWeight.w500, 1.3),
      body: sans(15, FontWeight.w400, 1.45),
      caption: sans(13, FontWeight.w400, 1.35),
      button: mono(12, FontWeight.w600, 1.0, 0.14),
      cta: disp(16, FontWeight.w700, 1.0, 0.22),
      label: mono(11, FontWeight.w500, 1.2, 0.16),
      meta: mono(11, FontWeight.w400, 1.3, 0.04).copyWith(fontFeatures: _tabular),
      micro: mono(10, FontWeight.w400, 1.2, 0.10),
    );
  }

  @override
  VigilType copyWith({
    TextStyle? display,
    TextStyle? hero,
    TextStyle? h1,
    TextStyle? section,
    TextStyle? h2,
    TextStyle? metric,
    TextStyle? title,
    TextStyle? rowTitle,
    TextStyle? body,
    TextStyle? caption,
    TextStyle? button,
    TextStyle? cta,
    TextStyle? label,
    TextStyle? meta,
    TextStyle? micro,
  }) {
    return VigilType(
      display: display ?? this.display,
      hero: hero ?? this.hero,
      h1: h1 ?? this.h1,
      section: section ?? this.section,
      h2: h2 ?? this.h2,
      metric: metric ?? this.metric,
      title: title ?? this.title,
      rowTitle: rowTitle ?? this.rowTitle,
      body: body ?? this.body,
      caption: caption ?? this.caption,
      button: button ?? this.button,
      cta: cta ?? this.cta,
      label: label ?? this.label,
      meta: meta ?? this.meta,
      micro: micro ?? this.micro,
    );
  }

  @override
  VigilType lerp(ThemeExtension<VigilType>? other, double t) {
    if (other is! VigilType) return this;
    TextStyle l(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return VigilType(
      display: l(display, other.display),
      hero: l(hero, other.hero),
      h1: l(h1, other.h1),
      section: l(section, other.section),
      h2: l(h2, other.h2),
      metric: l(metric, other.metric),
      title: l(title, other.title),
      rowTitle: l(rowTitle, other.rowTitle),
      body: l(body, other.body),
      caption: l(caption, other.caption),
      button: l(button, other.button),
      cta: l(cta, other.cta),
      label: l(label, other.label),
      meta: l(meta, other.meta),
      micro: l(micro, other.micro),
    );
  }
}
