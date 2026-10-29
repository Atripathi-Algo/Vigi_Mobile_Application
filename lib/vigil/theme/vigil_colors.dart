import 'package:flutter/material.dart';

/// Raw dark palette (Storm violet). Widgets should read colours through [VigilColors] (`context.vigil`) so they
/// follow the Light / Dark / System setting; these constants are for the few places that have no BuildContext.
abstract final class VigilPalette {
  static const Color ground = Color(0xFF060716);
  static const Color stealth = Color(0xFF03030C);
  static const Color surface = Color(0xFF0D1029);
  static const Color surfaceHigh = Color(0xFF1B2048);
  static const Color raised = Color(0xFF141838);
  static const Color navBar = Color(0xFF0D1029);
  static const Color line = Color(0x218492FF);
  static const Color lineStrong = Color(0x428492FF);
  static const Color rule = Color(0x218492FF);
  static const Color neutral = Color(0xFF7D86B2);
  static const Color text = Color(0xFFEEF1FF);
  static const Color textMuted = Color(0xFFA9B1D6);
  static const Color textFaint = Color(0xFF7D86B2);

  /// Signal blue.
  static const Color signal = Color(0xFF4F8BFF);
  static const Color signal2 = Color(0xFFA3C0FF);
  static const Color onSignal = Color(0xFFFFFFFF);
  static const Color violet = Color(0xFF9D6BFF);
  static const Color magenta = Color(0xFFE25CFF);
  static const Color critical = Color(0xFFFF5C72);
  static const Color steel = Color(0xFFDCE6FF);
  static const Color sleepBand = Color(0xFF141838);

  /// HIGH threat, system notes, Cloud.
  static const Color warning = Color(0xFFFFB547);

  /// Synced, applied, from your data.
  static const Color success = Color(0xFF3BE3B6);
}

/// The primary gradient: 135 degrees, same in both themes. Primary buttons, mic, switches on, active segment.
abstract final class KGradients {
  static const Color start = Color(0xFF2759F0);
  static const Color mid = Color(0xFF6D3CF5);
  static const Color end = Color(0xFF8A3CF0);

  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[start, mid, end],
    stops: <double>[0, 0.6, 1],
  );

  /// The destructive gradient.
  static const LinearGradient destructive = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFFE8364F), Color(0xFFB8236F)],
  );

  /// Orb plasma: radial white to deep indigo.
  static const RadialGradient plasma = RadialGradient(
    colors: <Color>[Color(0xFFFFFFFF), Color(0xFFF0ABFC), Color(0xFFC026D3), Color(0xFF6D28D9), Color(0xFF1E1B4B)],
    stops: <double>[0, 0.14, 0.32, 0.56, 0.78],
  );
}

/// Icon tile gradients (40 dp tiles, white glyph, always beside a label).
enum KTile {
  blue(Color(0xFF3B82F6), Color(0xFF2563EB)),
  violet(Color(0xFFA855F7), Color(0xFF6D28D9)),
  cyan(Color(0xFF22D3EE), Color(0xFF0E7490)),
  green(Color(0xFF34D399), Color(0xFF047857)),
  orange(Color(0xFFFB923C), Color(0xFFC2410C)),
  pink(Color(0xFFE879F9), Color(0xFFA21CAF)),
  red(Color(0xFFFB7185), Color(0xFFBE123C));

  const KTile(this.a, this.b);
  final Color a;
  final Color b;

  LinearGradient get gradient => LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[a, b]);
}

/// Semantic colour tokens exposed as a [ThemeExtension], one light and one dark instance (see
/// docs/design/K_DESIGN_HANDOFF.md). Field names are kept from the earlier design so screens keep working:
/// `surface` is the card colour, `surfaceHigh` the pressed/track colour (the handoff's raised-2).
@immutable
class VigilColors extends ThemeExtension<VigilColors> {
  const VigilColors({
    required this.brightness,
    required this.ground,
    required this.stealth,
    required this.surface,
    required this.surfaceHigh,
    required this.raised,
    required this.navBar,
    required this.line,
    required this.lineStrong,
    required this.rule,
    required this.neutral,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.signal,
    required this.signal2,
    required this.onSignal,
    required this.violet,
    required this.magenta,
    required this.critical,
    required this.warning,
    required this.success,
    required this.steel,
    required this.sleepBand,
    required this.calA,
    required this.calB,
    required this.shadow,
  });

  final Brightness brightness;
  final Color ground;
  final Color stealth;

  /// Cards, fields, bubbles.
  final Color surface;

  /// Pressed rows, tracks.
  final Color surfaceHigh;

  /// Sheets, dialogs, diff chips.
  final Color raised;
  final Color navBar;
  final Color line;
  final Color lineStrong;
  final Color rule;
  final Color neutral;
  final Color text;
  final Color textMuted;
  final Color textFaint;

  /// Progress, links, Instant source.
  final Color signal;

  /// Signal-coloured text.
  final Color signal2;
  final Color onSignal;

  /// K, focus ring, on-device AI.
  final Color violet;

  /// Orb core, unread dot, live mic.
  final Color magenta;
  final Color critical;
  final Color warning;
  final Color success;

  /// Big readouts.
  final Color steel;
  final Color sleepBand;

  /// Google account 1 (Personal) and 2 (Work).
  final Color calA;
  final Color calB;

  /// Soft violet shadow base (light) or glow base (dark).
  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  static const VigilColors light = VigilColors(
    brightness: Brightness.light,
    ground: Color(0xFFF3F4FA),
    stealth: Color(0xFFE6E8F5),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFECEEF8),
    raised: Color(0xFFFFFFFF),
    navBar: Color(0xFFFFFFFF),
    line: Color(0x1F34388C),
    lineStrong: Color(0x3834388C),
    rule: Color(0x1F34388C),
    neutral: Color(0xFF62678A),
    text: Color(0xFF14162E),
    textMuted: Color(0xFF474C6B),
    textFaint: Color(0xFF62678A),
    signal: Color(0xFF2F5FE0),
    signal2: Color(0xFF2B4FCC),
    onSignal: Color(0xFFFFFFFF),
    violet: Color(0xFF6A3CF0),
    magenta: Color(0xFFA51DB8),
    critical: Color(0xFFC21D43),
    warning: Color(0xFF9A5700),
    success: Color(0xFF05735A),
    steel: Color(0xFF191B3D),
    sleepBand: Color(0xFFE4E7F6),
    calA: Color(0xFF3B5BDB),
    calB: Color(0xFF8B3FD9),
    shadow: Color(0xFF281E78),
  );

  static const VigilColors dark = VigilColors(
    brightness: Brightness.dark,
    ground: VigilPalette.ground,
    stealth: VigilPalette.stealth,
    surface: VigilPalette.surface,
    surfaceHigh: VigilPalette.surfaceHigh,
    raised: VigilPalette.raised,
    navBar: VigilPalette.navBar,
    line: VigilPalette.line,
    lineStrong: VigilPalette.lineStrong,
    rule: VigilPalette.rule,
    neutral: VigilPalette.neutral,
    text: VigilPalette.text,
    textMuted: VigilPalette.textMuted,
    textFaint: VigilPalette.textFaint,
    signal: VigilPalette.signal,
    signal2: VigilPalette.signal2,
    onSignal: VigilPalette.onSignal,
    violet: VigilPalette.violet,
    magenta: VigilPalette.magenta,
    critical: VigilPalette.critical,
    warning: VigilPalette.warning,
    success: VigilPalette.success,
    steel: VigilPalette.steel,
    sleepBand: VigilPalette.sleepBand,
    calA: Color(0xFFDCE6FF),
    calB: Color(0xFFB18CFF),
    shadow: Color(0xFF6848FF),
  );

  /// Kept as an alias for older call sites.
  static const VigilColors thor = dark;

  static VigilColors of(Brightness b) => b == Brightness.dark ? dark : light;

  /// Signal tint used behind focus blocks (14 %) and in switch tracks (15 %).
  Color signalTint(double alpha) => signal.withValues(alpha: alpha);

  /// Soft gradient: signal to violet at low opacity (selected chips, nav pill, hands-free on).
  LinearGradient get softGradient {
    final double a = isDark ? 0.23 : 0.15;
    return LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[signal.withValues(alpha: a), violet.withValues(alpha: a)]);
  }

  /// The hot border: signal through violet to magenta.
  LinearGradient get hotGradient => LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[signal, violet, magenta]);

  /// Card shadow: soft violet in light; none in dark (dark uses glow on gradient actions instead).
  List<BoxShadow> get cardShadow => isDark ? const <BoxShadow>[] : <BoxShadow>[BoxShadow(color: shadow.withValues(alpha: 0.32), blurRadius: 26, offset: const Offset(0, 10), spreadRadius: -18)];

  /// Glow under gradient actions (dark) or a soft lift (light).
  List<BoxShadow> get actionShadow => <BoxShadow>[BoxShadow(color: shadow.withValues(alpha: isDark ? 0.75 : 0.35), blurRadius: 28, offset: const Offset(0, 10), spreadRadius: -10)];

  @override
  VigilColors copyWith({
    Brightness? brightness,
    Color? ground,
    Color? stealth,
    Color? surface,
    Color? surfaceHigh,
    Color? raised,
    Color? navBar,
    Color? line,
    Color? lineStrong,
    Color? rule,
    Color? neutral,
    Color? text,
    Color? textMuted,
    Color? textFaint,
    Color? signal,
    Color? signal2,
    Color? onSignal,
    Color? violet,
    Color? magenta,
    Color? critical,
    Color? warning,
    Color? success,
    Color? steel,
    Color? sleepBand,
    Color? calA,
    Color? calB,
    Color? shadow,
  }) {
    return VigilColors(
      brightness: brightness ?? this.brightness,
      ground: ground ?? this.ground,
      stealth: stealth ?? this.stealth,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      raised: raised ?? this.raised,
      navBar: navBar ?? this.navBar,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      rule: rule ?? this.rule,
      neutral: neutral ?? this.neutral,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      signal: signal ?? this.signal,
      signal2: signal2 ?? this.signal2,
      onSignal: onSignal ?? this.onSignal,
      violet: violet ?? this.violet,
      magenta: magenta ?? this.magenta,
      critical: critical ?? this.critical,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      steel: steel ?? this.steel,
      sleepBand: sleepBand ?? this.sleepBand,
      calA: calA ?? this.calA,
      calB: calB ?? this.calB,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  VigilColors lerp(ThemeExtension<VigilColors>? other, double t) {
    if (other is! VigilColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return VigilColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      ground: l(ground, other.ground),
      stealth: l(stealth, other.stealth),
      surface: l(surface, other.surface),
      surfaceHigh: l(surfaceHigh, other.surfaceHigh),
      raised: l(raised, other.raised),
      navBar: l(navBar, other.navBar),
      line: l(line, other.line),
      lineStrong: l(lineStrong, other.lineStrong),
      rule: l(rule, other.rule),
      neutral: l(neutral, other.neutral),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      textFaint: l(textFaint, other.textFaint),
      signal: l(signal, other.signal),
      signal2: l(signal2, other.signal2),
      onSignal: l(onSignal, other.onSignal),
      violet: l(violet, other.violet),
      magenta: l(magenta, other.magenta),
      critical: l(critical, other.critical),
      warning: l(warning, other.warning),
      success: l(success, other.success),
      steel: l(steel, other.steel),
      sleepBand: l(sleepBand, other.sleepBand),
      calA: l(calA, other.calA),
      calB: l(calB, other.calB),
      shadow: l(shadow, other.shadow),
    );
  }
}
