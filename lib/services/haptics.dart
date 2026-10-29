import 'package:flutter/services.dart';

/// Taps that mirror the sounds, switched by the Effects setting. Spark is a light tick, Strike a firm double tap,
/// Rumble one long heavy buzz.
abstract final class Haptics {
  /// The Settings control Effects: 0 off, 1 subtle (ticks and taps), 2 full (adds the double tap on a strike).
  static int level = 2;

  static bool get enabled => level > 0;

  /// Light tick: taps, tab changes, un-checking.
  static void tick() {
    if (enabled) HapticFeedback.selectionClick();
  }

  /// A firm single tap: confirming something.
  static void tap() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  /// A firm double tap: something cleared, K succeeded.
  static void strike() {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
    if (level < 2) return;
    Future<void>.delayed(const Duration(milliseconds: 90), () {
      if (enabled) HapticFeedback.mediumImpact();
    });
  }

  /// One long low buzz: a cold start, a session ending.
  static void rumble() {
    if (enabled) HapticFeedback.heavyImpact();
  }
}
