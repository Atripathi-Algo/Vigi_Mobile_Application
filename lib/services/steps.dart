import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/store.dart';

/// Steps from the phone's built-in step-counter sensor (Android
/// TYPE_STEP_COUNTER). Needs the Activity recognition permission. The sensor
/// reports a count since boot; [VigilStore.onStepCounter] turns it into "today".
abstract final class StepService {
  static StreamSubscription<StepCount>? _sub;

  /// `true` once the sensor has delivered a value this session.
  static final ValueNotifier<bool> available = ValueNotifier<bool>(false);

  /// `true` when the platform reported that this device has no step counter.
  static final ValueNotifier<bool> noSensor = ValueNotifier<bool>(false);

  static Future<bool> hasPermission() async => (await Permission.activityRecognition.status).isGranted;

  /// Starts listening. With [request] false it only starts if already allowed.
  static Future<bool> start(VigilStore store, {bool request = false}) async {
    PermissionStatus st = await Permission.activityRecognition.status;
    if (!st.isGranted) {
      if (!request) return false;
      st = await Permission.activityRecognition.request();
      if (!st.isGranted) return false;
    }
    await _sub?.cancel();
    _sub = Pedometer.stepCountStream.listen(
      (StepCount e) {
        available.value = true;
        noSensor.value = false;
        store.onStepCounter(e.steps);
      },
      onError: (Object e) {
        debugPrint('Step sensor error: $e');
        available.value = false;
        noSensor.value = true;
        store.setLink('Step sensor', 'OK'); // rebuilds the Vitals tile
      },
      cancelOnError: false,
    );
    return true;
  }
}
