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
import 'services/calendar_sync.dart';
import 'services/home_widgets.dart';
import 'services/notifications.dart';
import 'services/output_sync.dart';
import 'services/push.dart';
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

class _VigilAppState extends ConsumerState<VigilApp> {
  late final GoRouter _router = buildRouter(widget.store);
  late final OutputSync _sync = OutputSync(widget.store);

  @override
  void initState() {
    super.initState();
    _bootstrap();
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

    // Calendar (public calendar via API key), then push widgets and reminders.
    if (Env.hasCalendar) await pullCalendar(s);
    await _sync.run();
  }

  @override
  Widget build(BuildContext context) {
    final VigilStore s = ref.watch(storeProvider);
    final ThemeData theme = buildVigilTheme(signal: s.accent);
    return MaterialApp.router(
      title: 'VIGIL',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      routerConfig: _router,
    );
  }
}
