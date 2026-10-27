import 'package:flutter/material.dart';

/// Raw VIGIL palette (dark only). Widgets should read colours through
/// [VigilColors] (`context.vigil`) so the signal accent can be re-themed.
abstract final class VigilPalette {
  static const Color ground = Color(0xFF0A0B0D);
  static const Color stealth = Color(0xFF050607);
  static const Color surface = Color(0xFF121418);
  static const Color surfaceHigh = Color(0xFF1A1D22);
  static const Color navBar = Color(0xFF0E0F12);
  static const Color line = Color(0xFF262A31);
  static const Color lineStrong = Color(0xFF363B44);
  static const Color rule = Color(0xFF1E2126);
  /// Canvas uses #5A606A; raised to #646A74 so unchecked controls meet 3:1.
  static const Color neutral = Color(0xFF646A74);
  static const Color text = Color(0xFFECEAE4);
  static const Color textMuted = Color(0xFFA3A8B0);
  static const Color textFaint = Color(0xFF8A9099);
  static const Color signal = Color(0xFFF2C230);
  static const Color onSignal = Color(0xFF0A0B0D);
  static const Color critical = Color(0xFFFF5A47);
  static const Color steel = Color(0xFF7FA7C9);
  static const Color sleepBand = Color(0xFF1F2630);

  /// Alternative accents offered in Loadout (all keep ≥ 4.5:1 with onSignal).
  static const List<Color> signalOptions = <Color>[
    Color(0xFFF2C230), // signal yellow (default)
    Color(0xFF5CC8FF), // cyan
    Color(0xFFFF7A3D), // orange
    Color(0xFFECEAE4), // white
    Color(0xFF3FB6FF), // Thor: lightning blue
  ];

  /// Index in [signalOptions] of the Thor theme, which also recolours the surfaces.
  static const int thorIndex = 4;
}

/// Semantic colour tokens exposed as a [ThemeExtension].
@immutable
class VigilColors extends ThemeExtension<VigilColors> {
  const VigilColors({
    required this.ground,
    required this.stealth,
    required this.surface,
    required this.surfaceHigh,
    required this.navBar,
    required this.line,
    required this.lineStrong,
    required this.rule,
    required this.neutral,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.signal,
    required this.onSignal,
    required this.critical,
    required this.steel,
    required this.sleepBand,
  });

  final Color ground;
  final Color stealth;
  final Color surface;
  final Color surfaceHigh;
  final Color navBar;
  final Color line;
  final Color lineStrong;
  final Color rule;
  final Color neutral;
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color signal;
  final Color onSignal;
  final Color critical;
  final Color steel;
  final Color sleepBand;

  static const VigilColors dark = VigilColors(
    ground: VigilPalette.ground,
    stealth: VigilPalette.stealth,
    surface: VigilPalette.surface,
    surfaceHigh: VigilPalette.surfaceHigh,
    navBar: VigilPalette.navBar,
    line: VigilPalette.line,
    lineStrong: VigilPalette.lineStrong,
    rule: VigilPalette.rule,
    neutral: VigilPalette.neutral,
    text: VigilPalette.text,
    textMuted: VigilPalette.textMuted,
    textFaint: VigilPalette.textFaint,
    signal: VigilPalette.signal,
    onSignal: VigilPalette.onSignal,
    critical: VigilPalette.critical,
    steel: VigilPalette.steel,
    sleepBand: VigilPalette.sleepBand,
  );

  /// Thor: storm-navy surfaces, silver steel, lightning-blue signal and Asgardian red for alerts.
  static const VigilColors thor = VigilColors(
    ground: Color(0xFF060A12),
    stealth: Color(0xFF03060C),
    surface: Color(0xFF0D1422),
    surfaceHigh: Color(0xFF141E33),
    navBar: Color(0xFF0A101C),
    line: Color(0xFF1D2A44),
    lineStrong: Color(0xFF2D4166),
    rule: Color(0xFF16203A),
    neutral: Color(0xFF6A7B9C),
    text: Color(0xFFE8EEF8),
    textMuted: Color(0xFFA6B3CC),
    textFaint: Color(0xFF8D9BB6),
    signal: Color(0xFF3FB6FF),
    onSignal: Color(0xFF03101C),
    critical: Color(0xFFFF4D4D),
    steel: Color(0xFFC3D0E6),
    sleepBand: Color(0xFF182238),
  );

  /// Signal tint used behind focus blocks (14 %) and in switch tracks (15 %).
  Color signalTint(double alpha) => signal.withValues(alpha: alpha);

  @override
  VigilColors copyWith({
    Color? ground,
    Color? stealth,
    Color? surface,
    Color? surfaceHigh,
    Color? navBar,
    Color? line,
    Color? lineStrong,
    Color? rule,
    Color? neutral,
    Color? text,
    Color? textMuted,
    Color? textFaint,
    Color? signal,
    Color? onSignal,
    Color? critical,
    Color? steel,
    Color? sleepBand,
  }) {
    return VigilColors(
      ground: ground ?? this.ground,
      stealth: stealth ?? this.stealth,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      navBar: navBar ?? this.navBar,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      rule: rule ?? this.rule,
      neutral: neutral ?? this.neutral,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      signal: signal ?? this.signal,
      onSignal: onSignal ?? this.onSignal,
      critical: critical ?? this.critical,
      steel: steel ?? this.steel,
      sleepBand: sleepBand ?? this.sleepBand,
    );
  }

  @override
  VigilColors lerp(ThemeExtension<VigilColors>? other, double t) {
    if (other is! VigilColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return VigilColors(
      ground: l(ground, other.ground),
      stealth: l(stealth, other.stealth),
      surface: l(surface, other.surface),
      surfaceHigh: l(surfaceHigh, other.surfaceHigh),
      navBar: l(navBar, other.navBar),
      line: l(line, other.line),
      lineStrong: l(lineStrong, other.lineStrong),
      rule: l(rule, other.rule),
      neutral: l(neutral, other.neutral),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      textFaint: l(textFaint, other.textFaint),
      signal: l(signal, other.signal),
      onSignal: l(onSignal, other.onSignal),
      critical: l(critical, other.critical),
      steel: l(steel, other.steel),
      sleepBand: l(sleepBand, other.sleepBand),
    );
  }
}
