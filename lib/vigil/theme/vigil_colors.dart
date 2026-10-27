import 'package:flutter/material.dart';

/// Raw palette (Thor, dark only). Widgets should read colours through [VigilColors] (`context.vigil`).
abstract final class VigilPalette {
  static const Color ground = Color(0xFF060B16);
  static const Color stealth = Color(0xFF03060C);
  static const Color surface = Color(0xFF0C1424);
  static const Color surfaceHigh = Color(0xFF121C30);
  static const Color navBar = Color(0xFF080E1B);
  static const Color line = Color(0xFF1B2A45);
  static const Color lineStrong = Color(0xFF2A3F66);
  static const Color rule = Color(0xFF16223A);
  static const Color neutral = Color(0xFF6A8CC4);
  static const Color text = Color(0xFFE6F0FF);
  static const Color textMuted = Color(0xFFA3B5D0);
  static const Color textFaint = Color(0xFF7A8FB0);

  /// Lightning blue: the one signal colour.
  static const Color signal = Color(0xFF3FB6FF);
  static const Color onSignal = Color(0xFF03101C);
  static const Color critical = Color(0xFFFF4D4D);
  static const Color steel = Color(0xFFCFE8FF);
  static const Color sleepBand = Color(0xFF182238);

  /// HIGH threat, system notes; synced, applied.
  static const Color warning = Color(0xFFFFB547);
  static const Color success = Color(0xFF3DE0C2);
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

  /// Kept as an alias: Thor is the only theme.
  static const VigilColors thor = dark;

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
