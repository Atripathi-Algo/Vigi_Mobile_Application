import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../app/fmt.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../vigil/vigil.dart';

/// Local notifications on the seven channels from the handoff (section 6).
/// Reminders are scheduled from the store and re-armed after every change.
/// Works with no backend; Firebase push (push.dart) is an optional extra.
abstract final class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static void Function(String? payload)? _onTap;

  /// One channel per kind of alert, each with its own original sound from
  /// android/app/src/main/res/raw (made by tools/gen_sounds.py). Android fixes a
  /// channel's sound when it is created, so the ids carry a version suffix; the
  /// sound can still be changed per channel in the system settings.
  static const List<_Chan> _channels = <_Chan>[
    _Chan('critical', 'K · Alerts', Importance.high, 'Deadlines and critical conflicts', 'bat_critical'),
    _Chan('ops', 'K · Ops', Importance.defaultImportance, 'Next op and focus reminders', 'bat_ops'),
    _Chan('protocols', 'K · Protocols', Importance.low, 'Streaks at risk', 'bat_soft'),
    _Chan('sleep', 'K · Sleep', Importance.high, 'Wind-down and lights-out', 'bat_sleep'),
    _Chan('screen', 'K · Screen', Importance.low, 'Screen-time limits', 'bat_soft'),
    _Chan('ledger', 'K · Ledger', Importance.defaultImportance, 'Bills due', 'bat_soft'),
    _Chan('briefings', 'K · Briefings', Importance.low, 'Dawn briefing and night debrief', 'bat_brief'),
  ];

  /// Channel ids from before the sounds were added; removed on start so they do not clutter the settings.
  static const List<String> _oldChannelIds = <String>['critical', 'ops', 'protocols', 'sleep', 'screen', 'ledger', 'briefings'];

  static AndroidFlutterLocalNotificationsPlugin? get _android => _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Safe to call more than once and from a background isolate.
  static Future<void> init({void Function(String? payload)? onTap}) async {
    if (onTap != null) _onTap = onTap;
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.UTC); // one-off schedules are absolute instants, so UTC is enough
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_vigil')),
        onDidReceiveNotificationResponse: (NotificationResponse r) => _onTap?.call(r.payload),
      );
      for (final String old in _oldChannelIds) {
        await _android?.deleteNotificationChannel(channelId: old);
      }
      for (final _Chan c in _channels) {
        await _android?.createNotificationChannel(AndroidNotificationChannel(
          c.id,
          c.name,
          description: c.description,
          importance: c.importance,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(c.sound),
        ));
      }
      _ready = true;
    } catch (e) {
      debugPrint('Notifications init failed: $e');
    }
  }

  /// Payload of the notification that cold-started the app, if any.
  static Future<String?> launchPayload() async {
    try {
      final NotificationAppLaunchDetails? d = await _plugin.getNotificationAppLaunchDetails();
      return (d?.didNotificationLaunchApp ?? false) ? d?.notificationResponse?.payload : null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> enabled() async => (await _android?.areNotificationsEnabled()) ?? false;

  /// Asks for the Android 13+ notification permission.
  static Future<bool> requestPermission() async {
    await init();
    return (await _android?.requestNotificationsPermission()) ?? false;
  }

  /// Opens the system "Alarms & reminders" screen on Android 12+.
  static Future<bool> requestExactAlarms() async {
    await init();
    return (await _android?.requestExactAlarmsPermission()) ?? false;
  }

  static Future<bool> canScheduleExact() async => (await _android?.canScheduleExactNotifications()) ?? false;

  static NotificationDetails _details(String channel) {
    final _Chan c = _channels.firstWhere((_Chan e) => e.key == channel, orElse: () => _channels[1]);
    return NotificationDetails(
      android: AndroidNotificationDetails(
        c.id,
        c.name,
        channelDescription: c.description,
        importance: c.importance,
        priority: c.importance == Importance.high ? Priority.high : (c.importance == Importance.low ? Priority.low : Priority.defaultPriority),
        icon: 'ic_stat_vigil',
        color: VigilPalette.signal,
        styleInformation: const BigTextStyleInformation(''),
        playSound: true,
        sound: RawResourceAndroidNotificationSound(c.sound),
      ),
    );
  }

  static Future<void> show(String title, String body, {String channel = 'ops', String? payload, int? id}) async {
    await init();
    try {
      await _plugin.show(id: id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000 + 100000, title: title, body: body, notificationDetails: _details(channel), payload: payload);
    } catch (e) {
      debugPrint('Notification show failed: $e');
    }
  }

  static Future<void> _schedule(int id, DateTime at, String title, String body, String channel, {String? payload, required AndroidScheduleMode mode}) async {
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: tz.TZDateTime.from(at, tz.UTC),
      notificationDetails: _details(channel),
      androidScheduleMode: mode,
      title: title,
      body: body,
      payload: payload,
    );
  }

  /// Re-arm every reminder from the store. At most six proactive nudges a day
  /// (spec 11); sleep and briefing notifications are not part of that budget.
  static Future<void> syncReminders(VigilStore s) async {
    await init();
    if (!_ready || !await enabled()) return;
    try {
      await _plugin.cancelAllPendingNotifications();
      final DateTime now = DateTime.now();
      final DateTime day0 = DateTime(now.year, now.month, now.day);
      final AndroidScheduleMode mode = await canScheduleExact() ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
      DateTime at(int minutes) => day0.add(Duration(minutes: minutes));

      final List<(DateTime, String, String, String, String?)> nudges = <(DateTime, String, String, String, String?)>[];
      if (s.toggles['notifyOps'] ?? true) {
        for (final Objective o in s.open) {
          if (o.dueMin == null || o.threat == Threat.routine) continue;
          nudges.add((at(o.dueMin! - 30), o.threat == Threat.crit ? 'critical' : 'ops', '${o.title} due in 30 min', 'Due ${Fmt.hm(o.dueMin!)}. Open the focus block.', '/ops/objectives'));
        }
        for (final Block b in s.todayBlocks.where((Block b) => b.kind == BlockKind.event)) {
          nudges.add((at(b.startMin - 15), 'ops', 'Next op in 15 min', '${b.title} at ${Fmt.hm(b.startMin)}', '/ops/timeline'));
        }
      }
      if (s.toggles['notifyProtocols'] ?? true) {
        final List<Protocol> risk = s.protocols.where((Protocol p) => p.atRisk).toList();
        if (risk.isNotEmpty) nudges.add((at(20 * 60), 'protocols', 'Streak at risk', '${risk.first.name}: ${risk.first.missedDays} days missed', '/protocols/habits'));
      }
      nudges.sort(((DateTime, String, String, String, String?) a, (DateTime, String, String, String, String?) b) => a.$1.compareTo(b.$1));
      int id = 2000;
      int budget = 6;
      for (final (DateTime, String, String, String, String?) n in nudges) {
        if (budget == 0) break;
        if (!n.$1.isAfter(now)) continue;
        await _schedule(id++, n.$1, n.$3, n.$4, n.$2, payload: n.$5, mode: mode);
        budget--;
      }

      // Sleep: wind-down and lights-out for the coming night.
      if (s.toggles['windDown'] ?? true) {
        final DateTime wd = at(s.windDownAt);
        if (wd.isAfter(now)) await _schedule(10, wd, 'Wind-down', 'Lights out ${Fmt.hm(s.recommendedBed)}. Mute and Night Shield.', 'sleep', payload: '/protocols/vitals/sleep', mode: mode);
        final DateTime lo = at(s.recommendedBed);
        if (s.armedTonight && lo.isAfter(now)) await _schedule(11, lo, 'Lights out', 'Wake ${Fmt.hm(s.tonightRow.wake)}.', 'sleep', payload: '/protocols/vitals/sleep', mode: mode);
      }

      // Briefings: next occurrence of the wake time and the debrief time.
      DateTime next(int minutes) {
        final DateTime t = at(minutes % 1440);
        return t.isAfter(now) ? t : t.add(const Duration(days: 1));
      }

      if (s.toggles['dawn'] ?? true) await _schedule(12, next(s.wakeMin), 'Dawn briefing ready', '${s.open.length} objectives open, ${s.critCount} critical.', 'briefings', payload: '/briefing', mode: mode);
      if (s.toggles['debrief'] ?? true) await _schedule(13, next(s.bedMin - 30), 'Night debrief', 'Review the day and stand down.', 'briefings', payload: '/debrief', mode: mode);
    } catch (e) {
      debugPrint('syncReminders failed: $e');
    }
  }
}

class _Chan {
  const _Chan(this.key, this.name, this.importance, this.description, this.sound);

  /// What the rest of the app calls it (`critical`, `ops`, ...).
  final String key;
  final String name;
  final Importance importance;
  final String description;

  /// Name of the file in res/raw, without the extension.
  final String sound;

  String get id => '${key}_v2';
}
