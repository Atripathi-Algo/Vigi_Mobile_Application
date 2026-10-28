import 'package:flutter/services.dart';

/// Taps that mirror the sounds, switched by one setting in Loadout. Spark is a light tick, Strike a firm double tap,
/// Rumble one long heavy buzz.
abstract final class Haptics {
  static bool enabled = true;

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
    Future<void>.delayed(const Duration(milliseconds: 90), () {
      if (enabled) HapticFeedback.mediumImpact();
    });
  }

  /// One long low buzz: a cold start, a session ending.
  static void rumble() {
    if (enabled) HapticFeedback.heavyImpact();
  }
}
