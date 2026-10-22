import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../data/models.dart';
import '../data/sleep_analyzer.dart';
import '../data/store.dart';

/// Reads sleep, weight and resting heart rate from Android Health Connect
/// (free, on-device). Health Connect only holds what other apps write to it
/// (a watch or band app, Samsung Health, and so on), so with no source the
/// result is empty and VIGIL falls back to manual logging.
abstract final class HealthService {
  static final Health _health = Health();
  static bool _configured = false;
  static DateTime? _lastSync;

  /// Human-readable state for Loadout and Vitals.
  static final ValueNotifier<String> status = ValueNotifier<String>('OFF');

  /// What the user is asked to allow (read only).
  static const List<HealthDataType> _asked = <HealthDataType>[
    HealthDataType.SLEEP_SESSION,
    HealthDataType.WEIGHT,
    HealthDataType.RESTING_HEART_RATE,
  ];

  /// What is read. SLEEP_AWAKE is a sleep stage covered by the same READ_SLEEP permission.
  static const List<HealthDataType> _read = <HealthDataType>[
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.WEIGHT,
    HealthDataType.RESTING_HEART_RATE,
  ];

  static Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// True if the user allowed at least one of the three types. A partial grant
  /// is fine: the plugin returns an empty list for a type that is not allowed.
  static Future<bool> _anyGranted() async {
    for (final HealthDataType t in _asked) {
      if (await _health.hasPermissions(<HealthDataType>[t]) == true) return true;
    }
    return false;
  }

  /// Ask for read access and pull the first data. Returns true when connected.
  static Future<bool> connect(VigilStore store) async {
    try {
      await _configure();
      final HealthConnectSdkStatus? st = await _health.getHealthConnectSdkStatus();
      if (st != HealthConnectSdkStatus.sdkAvailable) {
        status.value = 'INSTALL';
        await _health.installHealthConnect();
        return false;
      }
      await _health.requestAuthorization(_asked);
      if (!await _anyGranted()) {
        status.value = 'DENIED';
        store.setLink('Health Connect', 'DENIED');
        return false;
      }
      store.setLink('Health Connect', 'OK');
      return sync(store, force: true);
    } catch (e) {
      debugPrint('Health Connect connect failed: $e');
      status.value = 'ERROR';
      return false;
    }
  }

  /// Read the last 35 days. Throttled to every 10 minutes unless [force].
  static Future<bool> sync(VigilStore store, {bool force = false}) async {
    if (store.linkStatus['Health Connect'] != 'OK') return false;
    final DateTime now = DateTime.now();
    if (!force && _lastSync != null && now.difference(_lastSync!).inMinutes < 10) return true;
    try {
      await _configure();
      if (!await _anyGranted()) {
        status.value = 'DENIED';
        store.setLink('Health Connect', 'DENIED');
        return false;
      }
      status.value = 'SYNCING';
      final DateTime since = now.subtract(const Duration(days: 35));
      final List<HealthDataPoint> pts = await _health.getHealthDataFromTypes(types: _read, startTime: since, endTime: now);

      final List<({DateTime from, DateTime to})> awake = <({DateTime from, DateTime to})>[];
      final List<({DateTime from, DateTime to})> spans = <({DateTime from, DateTime to})>[];
      final List<WeightPoint> weights = <WeightPoint>[];
      final List<({DateTime at, int bpm})> rhr = <({DateTime at, int bpm})>[];
      for (final HealthDataPoint p in pts) {
        switch (p.type) {
          case HealthDataType.SLEEP_SESSION:
            // The plugin's value is the whole span (awake time included), so only the times are used.
            spans.add((from: p.dateFrom.toLocal(), to: p.dateTo.toLocal()));
          case HealthDataType.SLEEP_AWAKE:
            awake.add((from: p.dateFrom.toLocal(), to: p.dateTo.toLocal()));
          case HealthDataType.WEIGHT:
            final HealthValue v = p.value;
            if (v is NumericHealthValue && v.numericValue > 20 && v.numericValue < 400) {
              weights.add(WeightPoint(p.dateFrom.toLocal(), double.parse(v.numericValue.toStringAsFixed(1)), source: 'health'));
            }
          case HealthDataType.RESTING_HEART_RATE:
            final HealthValue v = p.value;
            if (v is NumericHealthValue) rhr.add((at: p.dateFrom, bpm: v.numericValue.round()));
          default:
            break;
        }
      }
      final List<RawSleepSession> sessions = <RawSleepSession>[
        for (final ({DateTime from, DateTime to}) s in spans)
          RawSleepSession(s.from, s.to, asleepMin: (s.to.difference(s.from).inMinutes - SleepAnalyzer.awakeOverlap(s.from, s.to, awake)).clamp(0, s.to.difference(s.from).inMinutes)),
      ];
      rhr.sort((a, b) => a.at.compareTo(b.at));
      store.setHealthSleep(SleepAnalyzer.nightsFromSessions(sessions), since: since);
      store.setHealthBody(weights, rhr.isEmpty ? null : rhr.last.bpm, since: since);
      _lastSync = now;
      status.value = (sessions.isEmpty && weights.isEmpty && rhr.isEmpty) ? 'NO DATA' : 'LINKED';
      return true;
    } catch (e) {
      debugPrint('Health Connect sync failed: $e');
      status.value = 'ERROR';
      return false;
    }
  }
}
