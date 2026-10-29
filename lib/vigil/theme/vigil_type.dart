import 'package:flutter/material.dart';

import 'vigil_colors.dart';

/// VIGIL type scale. Letter-spacing in the design is in em; Flutter wants
/// logical pixels, so every style converts `em × fontSize`.
///
/// Families (bundled, no network): Sora (headings, numbers), Inter (UI text), IBM Plex Mono (logs only).
/// Styles never transform case; sentence case is the default, caps only for tags.
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
    required this.mono,
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

  /// IBM Plex Mono 12: timestamps, log lines, file names (Q4_K_M).
  final TextStyle mono;

  static const List<FontFeature> _tabular = <FontFeature>[FontFeature.tabularFigures()];

  factory VigilType.base({Color color = VigilPalette.text}) {
    // Sora and Inter are variable fonts: the weight is set on the wght axis as well as on the style.
    TextStyle f(String family, double size, FontWeight w, double h, double em) => TextStyle(
          fontFamily: family,
          fontSize: size,
          fontWeight: w,
          fontVariations: <FontVariation>[FontVariation.weight(w.value.toDouble())],
          height: h,
          letterSpacing: size * em,
          color: color,
        );
    TextStyle disp(double size, FontWeight w, double h, double em) => f('Sora', size, w, h, em);
    TextStyle sans(double size, FontWeight w, double h, [double em = 0]) => f('Inter', size, w, h, em);
    TextStyle mono(double size, FontWeight w, double h, double em) => TextStyle(
          fontFamily: 'IBMPlexMono',
          fontSize: size,
          fontWeight: w,
          height: h,
          letterSpacing: size * em,
          color: color,
        );

    return VigilType(
      display: disp(56, FontWeight.w600, 1.0, -0.02).copyWith(fontFeatures: _tabular),
      hero: disp(40, FontWeight.w600, 1.05, -0.02).copyWith(fontFeatures: _tabular),
      h1: disp(26, FontWeight.w600, 1.2, -0.015),
      section: disp(20, FontWeight.w700, 1.2, -0.01),
      h2: disp(19, FontWeight.w600, 1.26, -0.01),
      metric: disp(22, FontWeight.w600, 1.1, -0.02).copyWith(fontFeatures: _tabular),
      title: disp(15.5, FontWeight.w600, 1.3, 0),
      rowTitle: sans(15, FontWeight.w500, 1.3),
      body: sans(14.5, FontWeight.w400, 1.5),
      caption: sans(13, FontWeight.w400, 1.45),
      button: sans(13.5, FontWeight.w600, 1.0),
      cta: disp(16, FontWeight.w600, 1.0, 0),
      label: sans(11.5, FontWeight.w600, 1.3, 0.02),
      meta: sans(12, FontWeight.w500, 1.3, 0.03).copyWith(fontFeatures: _tabular),
      micro: sans(10.5, FontWeight.w500, 1.2, 0.04),
      mono: mono(12, FontWeight.w500, 1.4, 0),
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
    TextStyle? mono,
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
      mono: mono ?? this.mono,
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
      mono: l(mono, other.mono),
    );
  }
}
