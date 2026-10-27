import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../app/env.dart';
import 'notifications.dart';

FirebaseOptions _options() => FirebaseOptions(
      apiKey: Env.firebaseApiKey,
      appId: Env.firebaseAppId,
      messagingSenderId: Env.firebaseSenderId,
      projectId: Env.firebaseProjectId,
      storageBucket: Env.firebaseStorageBucket.isEmpty ? null : Env.firebaseStorageBucket,
    );

/// Runs in its own isolate when a data-only message arrives while the app is
/// not in the foreground. Messages with a `notification` block are shown by
/// the system without this.
@pragma('vm:entry-point')
Future<void> vigilFirebaseBackgroundHandler(RemoteMessage m) async {
  await Env.load();
  if (!Env.hasFirebase) return;
  await Firebase.initializeApp(options: _options());
  if (m.notification != null) return;
  await NotificationService.init();
  await NotificationService.show(m.data['title'] ?? 'K', m.data['body'] ?? '', channel: m.data['channel'] ?? 'ops', payload: m.data['route']);
}

/// Optional Firebase Cloud Messaging. Active only when the FIREBASE_* keys in
/// `.env` are filled in; otherwise the app relies on local notifications.
abstract final class PushService {
  /// Human-readable state for Loadout.
  static final ValueNotifier<String> status = ValueNotifier<String>(Env.hasFirebase ? 'STARTING' : 'OFF');
  static final ValueNotifier<String?> token = ValueNotifier<String?>(null);

  static String? _startedWith;
  static void Function(String? route)? _onOpen;

  /// Starts Firebase from the keys in effect. Safe to call again after the keys
  /// change: Firebase can only be configured once per run, so a changed
  /// configuration is applied on the next app start.
  static Future<void> init({void Function(String? route)? onOpen}) async {
    if (onOpen != null) _onOpen = onOpen;
    if (!Env.hasFirebase) {
      if (_startedWith == null) status.value = 'OFF';
      return;
    }
    final String sig = '${Env.firebaseApiKey}|${Env.firebaseAppId}|${Env.firebaseSenderId}|${Env.firebaseProjectId}';
    if (_startedWith != null) {
      if (_startedWith != sig) status.value = 'RESTART';
      return;
    }
    _startedWith = sig;
    status.value = 'STARTING';
    try {
      await Firebase.initializeApp(options: _options());
      FirebaseMessaging.onBackgroundMessage(vigilFirebaseBackgroundHandler);
      final FirebaseMessaging m = FirebaseMessaging.instance;
      await m.requestPermission();
      token.value = await m.getToken();
      m.onTokenRefresh.listen((String t) => token.value = t);
      FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
        NotificationService.show(
          msg.notification?.title ?? msg.data['title'] ?? 'K',
          msg.notification?.body ?? msg.data['body'] ?? '',
          channel: msg.data['channel'] ?? 'ops',
          payload: msg.data['route'],
        );
      });
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage msg) => _onOpen?.call(msg.data['route']));
      final RemoteMessage? initial = await m.getInitialMessage();
      if (initial != null) _onOpen?.call(initial.data['route']);
      status.value = token.value == null ? 'NO TOKEN' : 'LINKED';
    } catch (e) {
      debugPrint('Firebase init failed: $e');
      status.value = 'ERROR';
    }
  }
}
