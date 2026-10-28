import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:home_widget/home_widget.dart';

import 'app/env.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'data/store.dart';
import 'screens/capture_sheet.dart';
import 'screens/drive_sheet.dart';
import 'services/calendar_sync.dart';
import 'services/drive_sync.dart';
import 'services/google_accounts.dart';
import 'services/haptics.dart';
import 'services/health.dart';
import 'services/local_brain.dart';
import 'services/home_widgets.dart';
import 'services/notifications.dart';
import 'services/output_sync.dart';
import 'services/push.dart';
import 'services/sfx.dart';
import 'services/steps.dart';
import 'vigil/vigil.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: VigilPalette.navBar,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await Env.load();
  final VigilStore store = await VigilStore.load();
  void applySensory() {
    SfxService.configure(on: store.toggles['sfx'] ?? true, level: store.sfxLevel);
    Haptics.enabled = store.toggles['haptics'] ?? true;
    ThunderFx.enabled = store.toggles['effects'] ?? true;
  }

  applySensory();
  store.addListener(applySensory);
  SfxService.init(); // loads the effects in the background; the first frame does not wait for it
  runApp(ProviderScope(
    overrides: <Override>[storeProvider.overrideWith((Ref ref) => store)],
    child: VigilApp(store: store),
  ));
}

class VigilApp extends ConsumerStatefulWidget {
  const VigilApp({super.key, required this.store});

  final VigilStore store;

  @override
  ConsumerState<VigilApp> createState() => _VigilAppState();
}

class _VigilAppState extends ConsumerState<VigilApp> with WidgetsBindingObserver {
  late final GoRouter _router = buildRouter(widget.store);
  late final OutputSync _sync = OutputSync(widget.store);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The on-device model is released shortly after the app leaves the screen, so it costs nothing in the background.
    if (state == AppLifecycleState.resumed) {
      LocalBrain.instance.onForeground();
      DriveSync.instance.syncNow(); // picks up newer data from another phone
    } else {
      LocalBrain.instance.onBackground();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _conflictShown = false;

  /// When this phone and Drive both changed, ask once per run which to keep (the status chip can ask again).
  void _askAboutConflict() {
    final DriveSync d = DriveSync.instance;
    if (d.state != SyncState.conflict) {
      _conflictShown = false;
      return;
    }
    if (_conflictShown) return;
    _conflictShown = true;
    final BuildContext? ctx = rootNavKey.currentContext;
    if (ctx != null) showDriveConflict(ctx, d);
  }

  /// Opens a route or action from a notification, push message or widget tap.
  void _open(String? target) {
    if (target == null || target.isEmpty) return;
    if (target == 'capture') {
      _router.go('/');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final BuildContext? ctx = rootNavKey.currentContext;
        if (ctx != null) showCaptureSheet(ctx);
      });
      return;
    }
    if (target.startsWith('/')) _router.go(target);
  }

  void _openWidgetUri(Uri? uri) {
    switch (uri?.host) {
      case 'capture':
        _open('capture');
      case 'ops':
        _open('/ops/objectives');
      case 'open':
        _open('/');
    }
  }

  Future<void> _bootstrap() async {
    final VigilStore s = widget.store;
    ref.read(outputSyncProvider.notifier).state = _sync;
    s.notify = (String title, String body) => NotificationService.show(title, body, channel: 'ledger', payload: '/vault/ledger');
    // Home-screen widget taps: interactive controls run in the background; the rest open the app.
    await HomeWidget.registerInteractivityCallback(vigilWidgetCallback);
    HomeWidget.widgetClicked.listen(_openWidgetUri);
    _openWidgetUri(await HomeWidget.initiallyLaunchedFromHomeWidget());

    // Local notifications, then optional Firebase push.
    await NotificationService.init(onTap: _open);
    final String? launch = await NotificationService.launchPayload();
    if (launch != null) _open(launch);
    PushService.init(onOpen: _open);

    // Step counter, if the user already allowed it.
    if (await StepService.start(s)) s.setLink('Step sensor', 'OK');
    if (await NotificationService.enabled()) s.setLink('Notifications', 'OK');

    // Health Connect (sleep, weight, resting heart rate), if already allowed.
    await HealthService.sync(s);

    // Calendars (linked Google accounts and the public API-key calendar), then push widgets and reminders.
    await GoogleAccounts.instance.load();
    DriveSync.instance
      ..attach(s)
      ..addListener(_askAboutConflict)
      ..syncNow();
    await LocalBrain.instance.init();
    await syncCalendars(s);
    await _sync.run();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = buildVigilTheme();
    return MaterialApp.router(
      title: 'K',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      routerConfig: _router,
    );
  }
}
