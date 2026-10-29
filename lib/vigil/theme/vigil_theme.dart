import 'package:flutter/material.dart';

import 'vigil_colors.dart';
import 'vigil_tokens.dart';
import 'vigil_type.dart';

/// Builds the K [ThemeData] for one brightness (Storm violet). Light is the default.
///
/// ```dart
/// MaterialApp(theme: buildVigilTheme(Brightness.light), darkTheme: buildVigilTheme(Brightness.dark), themeMode: mode)
/// ```
ThemeData buildVigilTheme([Brightness brightness = Brightness.light]) {
  final VigilColors c = VigilColors.of(brightness);
  final VigilType t = VigilType.base(color: c.text);
  final bool dark = c.isDark;

  final ColorScheme base = dark ? const ColorScheme.dark() : const ColorScheme.light();
  final ColorScheme scheme = base.copyWith(
    primary: c.signal,
    onPrimary: c.onSignal,
    secondary: c.violet,
    onSecondary: c.onSignal,
    surface: c.surface,
    onSurface: c.text,
    onSurfaceVariant: c.textMuted,
    surfaceContainerHighest: c.surfaceHigh,
    error: c.critical,
    onError: c.onSignal,
    outline: c.lineStrong,
    outlineVariant: c.line,
  );

  final OutlinedBorder fieldShape = VigilShapes.field();
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(KRadius.field), borderSide: BorderSide(color: color, width: width));

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.ground,
    canvasColor: c.ground,
    splashFactory: InkRipple.splashFactory,
    highlightColor: c.text.withValues(alpha: 0.04),
    splashColor: c.violet.withValues(alpha: 0.10),
    textTheme: TextTheme(
      displayLarge: t.display,
      displayMedium: t.hero,
      headlineLarge: t.h1,
      headlineMedium: t.h2,
      titleLarge: t.section,
      titleMedium: t.title,
      titleSmall: t.rowTitle,
      bodyLarge: t.body,
      bodyMedium: t.body,
      bodySmall: t.caption,
      labelLarge: t.button,
      labelMedium: t.label,
      labelSmall: t.micro,
    ),
    iconTheme: IconThemeData(color: c.text, size: VigilSize.icon),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.signal,
        foregroundColor: c.onSignal,
        minimumSize: const Size(VigilSize.touch, VigilSize.button),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        textStyle: t.button,
        shape: VigilShapes.pill(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.textMuted,
        minimumSize: const Size(VigilSize.touch, VigilSize.button),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        textStyle: t.button,
        side: BorderSide(color: c.lineStrong),
        shape: VigilShapes.pill(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.signal2,
        minimumSize: const Size(VigilSize.touch, VigilSize.touch),
        textStyle: t.button,
        shape: VigilShapes.pill(),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: t.body.copyWith(color: c.textFaint),
      labelStyle: t.label.copyWith(color: c.textMuted),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      border: border(c.lineStrong),
      enabledBorder: border(c.lineStrong),
      focusedBorder: border(c.violet, 3),
      errorBorder: border(c.critical),
      focusedErrorBorder: border(c.critical, 3),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.violet,
      selectionColor: c.violet.withValues(alpha: 0.3),
      selectionHandleColor: c.violet,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.raised,
      surfaceTintColor: Colors.transparent,
      shape: VigilShapes.sheet(),
      modalBarrierColor: Colors.black.withValues(alpha: dark ? 0.72 : 0.36),
      showDragHandle: true,
      dragHandleColor: c.lineStrong,
      dragHandleSize: const Size(40, 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.raised,
      surfaceTintColor: Colors.transparent,
      shape: VigilShapes.dialog(),
      titleTextStyle: t.h2,
      contentTextStyle: t.body.copyWith(color: c.textMuted),
    ),
    // The snackbar stays dark in both themes (#1C1F45, text #F1F2FF).
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1C1F45),
      contentTextStyle: t.body.copyWith(color: const Color(0xFFF1F2FF)),
      actionTextColor: VigilPalette.signal2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.signal,
      linearTrackColor: c.surfaceHigh,
      circularTrackColor: c.surfaceHigh,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: ShapeDecoration(color: c.surfaceHigh, shape: fieldShape),
      textStyle: t.meta,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.ground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: t.section,
      foregroundColor: c.text,
    ),
    extensions: <ThemeExtension<dynamic>>[c, t],
  );
}
