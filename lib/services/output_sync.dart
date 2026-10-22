import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/store.dart';
import 'health.dart';
import 'home_widgets.dart';
import 'notifications.dart';

/// Keeps the outside world in step with the store: home-screen widgets and
/// scheduled reminders. Debounced, and reloads from disk first when the app is
/// in the background so it never pushes stale values over a widget action.
class OutputSync with WidgetsBindingObserver {
  OutputSync(this.store) {
    WidgetsBinding.instance.addObserver(this);
    store.afterChange = schedule;
  }

  final VigilStore store;
  Timer? _timer;

  void schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1500), run);
  }

  Future<void> run() async {
    if (WidgetsBinding.instance.lifecycleState != null && WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      await store.reloadFromDisk();
    }
    await HomeWidgets.push(store);
    await NotificationService.syncReminders(store);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back in the foreground: pick up anything a widget tap changed meanwhile.
    if (state == AppLifecycleState.resumed) {
      store.reloadFromDisk().then((_) async {
        await HealthService.sync(store); // throttled to every 10 minutes
        await run();
      });
    }
  }
}
