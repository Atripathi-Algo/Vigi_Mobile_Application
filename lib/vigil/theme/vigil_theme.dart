import 'package:flutter/material.dart';

import 'vigil_colors.dart';
import 'vigil_tokens.dart';
import 'vigil_type.dart';

/// Builds the VIGIL [ThemeData]. Dark only.
///
/// ```dart
/// MaterialApp(theme: buildVigilTheme(), darkTheme: buildVigilTheme(), themeMode: ThemeMode.dark)
/// ```
ThemeData buildVigilTheme({Color signal = VigilPalette.signal, bool thor = false}) {
  final VigilColors c = (thor ? VigilColors.thor : VigilColors.dark).copyWith(signal: signal);
  final VigilType t = VigilType.base(color: c.text);

  final ColorScheme scheme = ColorScheme.dark(
    primary: c.signal,
    onPrimary: c.onSignal,
    secondary: c.steel,
    onSecondary: c.ground,
    surface: c.surface,
    onSurface: c.text,
    onSurfaceVariant: c.textMuted,
    surfaceContainerHighest: c.surfaceHigh,
    error: c.critical,
    onError: c.ground,
    outline: c.lineStrong,
    outlineVariant: c.line,
  );

  const BorderRadius square = BorderRadius.zero;

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.ground,
    canvasColor: c.ground,
    splashFactory: InkRipple.splashFactory,
    highlightColor: c.text.withValues(alpha: 0.04),
    splashColor: c.text.withValues(alpha: 0.06),
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
        padding: const EdgeInsets.symmetric(horizontal: 18),
        textStyle: t.button,
        shape: VigilShapes.chamfer(10),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.textMuted,
        minimumSize: const Size(VigilSize.touch, VigilSize.button),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: t.button,
        side: BorderSide(color: c.lineStrong),
        shape: VigilShapes.square(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.textMuted,
        minimumSize: const Size(VigilSize.touch, VigilSize.touch),
        textStyle: t.button,
        shape: VigilShapes.square(),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: t.body.copyWith(color: c.textFaint),
      labelStyle: t.label.copyWith(color: c.textFaint),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      border: OutlineInputBorder(borderRadius: square, borderSide: BorderSide(color: c.lineStrong)),
      enabledBorder: OutlineInputBorder(borderRadius: square, borderSide: BorderSide(color: c.lineStrong)),
      focusedBorder: OutlineInputBorder(borderRadius: square, borderSide: BorderSide(color: c.signal)),
      errorBorder: OutlineInputBorder(borderRadius: square, borderSide: BorderSide(color: c.critical)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: square, borderSide: BorderSide(color: c.critical, width: 2)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.signal,
      selectionColor: c.signal.withValues(alpha: 0.3),
      selectionHandleColor: c.signal,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: VigilShapes.sheet(),
      modalBarrierColor: c.stealth.withValues(alpha: 0.62),
      showDragHandle: true,
      dragHandleColor: c.lineStrong,
      dragHandleSize: const Size(40, 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: VigilShapes.chamfer(14, BorderSide(color: c.lineStrong)),
      titleTextStyle: t.title,
      contentTextStyle: t.body.copyWith(color: c.textMuted),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surfaceHigh,
      contentTextStyle: t.body,
      actionTextColor: c.signal,
      behavior: SnackBarBehavior.floating,
      shape: VigilShapes.square(BorderSide(color: c.lineStrong)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.signal,
      linearTrackColor: c.line,
      circularTrackColor: c.line,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: c.surfaceHigh, border: Border.all(color: c.lineStrong)),
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
