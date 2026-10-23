import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/calendar_api.dart';
import '../app/fmt.dart';
import '../vigil/vigil.dart';
import 'models.dart';
import 'sleep_analyzer.dart';

enum Persona { tactical, butler, quiet }

enum Verbosity { terse, standard, detailed }

/// Single in-memory source of truth, persisted to SharedPreferences.
/// Engines (readiness, sleep recommender, capture parser) are plain functions
/// over this state, as described in the architecture spec. The store only uses
/// `foundation` and SharedPreferences, so the home-screen widget callback can
/// load it in a background isolate.
class VigilStore extends ChangeNotifier {
  VigilStore(this._prefs);

  final SharedPreferences _prefs;
  int _seq = 0;

  /// Set by the app: pushes widget data and re-arms reminders after a change.
  VoidCallback? afterChange;

  // ---- settings ---------------------------------------------------------
  bool booted = false;
  String fullName = 'Abhishek';
  String callsign = 'Batman';
  int wakeMin = 6 * 60 + 30;
  int bedMin = 23 * 60;
  int accentIndex = 0;
  Persona persona = Persona.tactical;

  /// In-app sound effect volume: 0 low, 1 medium, 2 high.
  int sfxLevel = 1;
  Verbosity verbosity = Verbosity.terse;
  Set<String> modules = <String>{..._allModules};
  static const List<String> _allModules = <String>['OBJECTIVES', 'TIMELINE', 'PROTOCOLS', 'VITALS', 'DEEP OPS', 'FIELD LOG', 'LEDGER'];
  static const Map<String, bool> _defaultToggles = <String, bool>{
    'spoken': true,
    'dawn': true,
    'debrief': true,
    'vaultLock': true,
    'cloudAi': false,
    'drive': false,
    'ramp': true,
    'windDown': true,
    'autoFirstOp': true,
    'notifyOps': true,
    'notifyProtocols': true,
    'sfx': true,
  };
  final Map<String, bool> toggles = <String, bool>{..._defaultToggles};
  static const List<String> linkKeys = <String>['Calendar link', 'Health Connect', 'Notifications', 'Step sensor', 'Usage access', 'Exact alarms', 'Voice uplink'];
  final Map<String, String> linkStatus = <String, String>{for (final String k in linkKeys) k: 'ASK'};

  Color get accent => VigilPalette.signalOptions[accentIndex];

  // ---- objectives & timeline ---------------------------------------------
  late List<Objective> objectives;
  late List<Block> blocks;
  bool justResolved = false;
  int selectedDayIndex = DateTime.now().weekday - 1;
  final Map<String, String> carry = <String, String>{}; // id -> moved|dropped
  String? tomorrowFirstId;

  // ---- protocols ----------------------------------------------------------
  late List<Protocol> protocols;

  // ---- vitals -----------------------------------------------------------
  int waterMl = 0;
  final int waterTargetMl = 3000;

  /// Steps today from the phone's step-counter sensor; null until it reports.
  int? steps;
  final int stepTarget = 8000;
  /// Body data from Health Connect or manual entries (newest last).
  List<WeightPoint> weights = <WeightPoint>[];
  int? restingHr;

  /// When Health Connect was last read, and whether the last read failed.
  DateTime? healthSyncedAt;

  // ---- sleep ------------------------------------------------------------
  int needMin = 435;
  final int latencyMin = 15;
  bool armedTonight = false;
  bool insightApplied = false;
  late List<ScheduleRow> schedule;
  /// Every stored night (health + manual), unsorted. See [nights] for the display view.
  List<SleepNight> _sleep = <SleepNight>[];

  /// Health Connect nights the user deleted; they stay hidden after the next sync.
  Set<String> _hiddenNights = <String>{};

  // ---- screen -----------------------------------------------------------
  bool nightShieldArmed = false;

  // ---- ledger -----------------------------------------------------------
  /// Set by the user; 0 means no budget yet.
  int monthBudgetPaise = 0;
  late List<Bill> bills;
  late List<Txn> txns;

  // ---- field log --------------------------------------------------------
  late List<Note> notes;
  int logStreak = 0;
  String? sealedAt;
  int sealedMood = 2;
  String logDraft = '';
  int logMood = 2;

  // ---- deep ops ---------------------------------------------------------
  int focusTodayMin = 0;
  final int focusTargetMin = 240;
  int deepSessionsDone = 0;
  bool shieldSilence = true;
  bool shieldBlock = true;
  bool shieldRain = false;

  // ---- assistant --------------------------------------------------------
  final List<ChatMsg> chat = <ChatMsg>[];

  SharedPreferences get prefs => _prefs;

  String nextId() => '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  // =========================================================================
  // Load / save
  // =========================================================================
  static Future<VigilStore> load() async {
    final VigilStore s = VigilStore(await SharedPreferences.getInstance());
    s._seed();
    s._restore();
    return s;
  }

  /// Re-read what a background isolate (home-screen widget) wrote.
  Future<void> reloadFromDisk() async {
    await _prefs.reload();
    _seed();
    _restore();
    notifyListeners();
  }

  /// Every list starts empty: the app shows only what the user logs, the calendar returns, or a sensor reports.
  void _seed() {
    objectives = <Objective>[];
    blocks = <Block>[];
    protocols = <Protocol>[];
    schedule = <ScheduleRow>[
      ScheduleRow(night: 'MON → TUE', bed: 23 * 60, wake: 6 * 60 + 30),
      ScheduleRow(night: 'TUE → WED', bed: 23 * 60, wake: 6 * 60 + 30),
      ScheduleRow(night: 'WED → THU', bed: 23 * 60 + 30, wake: 6 * 60 + 30),
      ScheduleRow(night: 'THU → FRI', bed: 23 * 60, wake: 6 * 60 + 30),
      ScheduleRow(night: 'FRI → SAT', bed: 24 * 60, wake: 8 * 60),
      ScheduleRow(night: 'SAT → SUN', bed: 24 * 60 + 15, wake: 8 * 60 + 30),
      ScheduleRow(night: 'SUN → MON', bed: 23 * 60, wake: 6 * 60 + 30),
    ];
    _sleep = <SleepNight>[];
    weights = <WeightPoint>[];
    restingHr = null;
    healthSyncedAt = null;
    bills = <Bill>[];
    txns = <Txn>[];
    notes = <Note>[];
  }

  static String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  void _restore() {
    final DateTime now = DateTime.now();
    final String today = dayKey(now);
    booted = _prefs.getBool('booted') ?? false;
    fullName = _prefs.getString('fullName') ?? fullName;
    callsign = _prefs.getString('callsign') ?? callsign;
    wakeMin = _prefs.getInt('wakeMin') ?? wakeMin;
    bedMin = _prefs.getInt('bedMin') ?? bedMin;
    accentIndex = _prefs.getInt('accent') ?? 0;
    persona = Persona.values[_prefs.getInt('persona') ?? 0];
    verbosity = Verbosity.values[_prefs.getInt('verbosity') ?? 0];
    needMin = _prefs.getInt('needMin') ?? needMin;
    sfxLevel = (_prefs.getInt('sfxLevel') ?? 1).clamp(0, 2);
    final List<String>? mods = _prefs.getStringList('modules');
    if (mods != null) modules = mods.toSet();
    final String? tg = _prefs.getString('toggles');
    if (tg != null) {
      (jsonDecode(tg) as Map<String, dynamic>).forEach((String k, dynamic v) => toggles[k] = v as bool);
    }
    final String? ls = _prefs.getString('links');
    if (ls != null) {
      (jsonDecode(ls) as Map<String, dynamic>).forEach((String k, dynamic v) => linkStatus[k] = v as String);
    }
    logStreak = _prefs.getInt('logStreak') ?? logStreak;
    monthBudgetPaise = _prefs.getInt('budget') ?? 0;
    final String? bj = _prefs.getString('bills');
    if (bj != null) bills = (jsonDecode(bj) as List<dynamic>).map((dynamic e) => Bill.fromJson(e as Map<String, dynamic>)).toList();
    final String? ob = _prefs.getString('objectives');
    if (ob != null) {
      objectives = (jsonDecode(ob) as List<dynamic>).map((dynamic e) => Objective.fromJson(e as Map<String, dynamic>)).toList();
    }
    final String? nt = _prefs.getString('notes');
    if (nt != null) notes = (jsonDecode(nt) as List<dynamic>).map((dynamic e) => Note.fromJson(e as Map<String, dynamic>)).toList();
    final String? tx = _prefs.getString('txns');
    if (tx != null) txns = (jsonDecode(tx) as List<dynamic>).map((dynamic e) => Txn.fromJson(e as Map<String, dynamic>)).toList();
    final String? sc = _prefs.getString('schedule');
    if (sc != null) {
      final List<dynamic> l = jsonDecode(sc) as List<dynamic>;
      for (int i = 0; i < schedule.length && i < l.length; i++) {
        schedule[i].bed = (l[i] as List<dynamic>)[0] as int;
        schedule[i].wake = (l[i] as List<dynamic>)[1] as int;
      }
    }
    tomorrowFirstId = _prefs.getString('tomorrowFirst');
    final DateTime cutoff = now.subtract(const Duration(days: 45));
    final String? sl = _prefs.getString('sleepLog');
    if (sl != null) {
      _sleep = (jsonDecode(sl) as List<dynamic>).map((dynamic e) => SleepNight.fromJson(e as Map<String, dynamic>)).where((SleepNight n) => n.nightOf.isAfter(cutoff)).toList();
    }
    final String? wl = _prefs.getString('weights');
    if (wl != null) {
      weights = (jsonDecode(wl) as List<dynamic>).map((dynamic e) => WeightPoint.fromJson(e as Map<String, dynamic>)).where((WeightPoint w) => w.at.isAfter(now.subtract(const Duration(days: 120)))).toList();
    }
    restingHr = _prefs.getInt('rhr');
    _hiddenNights = (_prefs.getStringList('sleepHidden') ?? <String>[]).toSet();
    final int? hs = _prefs.getInt('hcSync');
    healthSyncedAt = hs == null ? null : DateTime.fromMillisecondsSinceEpoch(hs);

    // ---- state that belongs to one calendar day -----------------------
    final String lastDay = _prefs.getString('day') ?? today;
    final bool sameDay = lastDay == today;
    final String? pr = _prefs.getString('protocols');
    if (pr != null) {
      // Older builds saved only the state of built-in protocols (no name); those were sample data.
      protocols = <Protocol>[
        for (final dynamic e in jsonDecode(pr) as List<dynamic>)
          if ((e as Map<String, dynamic>).containsKey('name')) Protocol.fromJson(e),
      ];
    }
    final String? bl = _prefs.getString('blocks');
    if (bl != null) {
      blocks = (jsonDecode(bl) as List<dynamic>).map((dynamic e) => Block.fromJson(e as Map<String, dynamic>)).toList();
    }
    if (sameDay) {
      waterMl = _prefs.getInt('water') ?? 0;
      focusTodayMin = _prefs.getInt('focusToday') ?? focusTodayMin;
      deepSessionsDone = _prefs.getInt('deepSessions') ?? 0;
      armedTonight = _prefs.getBool('armedTonight') ?? false;
      insightApplied = _prefs.getBool('insightApplied') ?? false;
      justResolved = _prefs.getBool('justResolved') ?? false;
      if (_prefs.getString('sealDay') == today) {
        sealedAt = _prefs.getString('sealedAt');
        sealedMood = _prefs.getInt('sealedMood') ?? 2;
      }
      steps = _prefs.getString('stepsDay') == today ? _prefs.getInt('stepsToday') : null;
    } else {
      waterMl = 0;
      focusTodayMin = 0;
      deepSessionsDone = 0;
      final DateTime? last = _parseDayKey(lastDay);
      final int gap = last == null ? 1 : math.max(1, DateTime(now.year, now.month, now.day).difference(last).inDays);
      for (final Protocol p in protocols) {
        p.rollOver(gap);
      }
      objectives.removeWhere((Objective o) => o.dropped || (o.done && !o.recurring && !o.clearedToday(now)));
      for (final Objective o in objectives) {
        if (o.recurring && o.done) {
          o.done = false;
          o.doneAt = null;
        }
      }
      // A new day: keep only blocks that are still ahead.
      blocks = blocks.where((Block b) => b.dayKey != null && _keyAtOrAfter(b.dayKey!, now)).toList();
      steps = null;
    }
    nightShieldArmed = _prefs.getBool('nightShield') ?? false;

    // Builds up to v1.3 seeded sample objectives, notes, spend, blocks and streaks. Drop what is left of them once.
    if (!(_prefs.getBool('realData1') ?? false)) {
      objectives.removeWhere((Objective o) => RegExp(r'^[oc]\d$').hasMatch(o.id));
      notes.removeWhere((Note n) => RegExp(r'^n\d$').hasMatch(n.id));
      txns.removeWhere((Txn t) => RegExp(r'^t\d$').hasMatch(t.id));
      blocks.removeWhere((Block b) => RegExp(r'^(b\d+|x\d+-\d+)$').hasMatch(b.id));
      logStreak = 0;
      focusTodayMin = 0;
      _prefs.setBool('realData1', true);
      _save();
    }
  }

  static DateTime? _parseDayKey(String k) {
    final List<String> p = k.split('-');
    if (p.length != 3) return null;
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  static bool _keyAtOrAfter(String k, DateTime now) {
    final DateTime? d = _parseDayKey(k);
    return d != null && !d.isBefore(DateTime(now.year, now.month, now.day));
  }

  void _save() {
    final String today = dayKey(DateTime.now());
    _prefs
      ..setBool('booted', booted)
      ..setString('fullName', fullName)
      ..setString('callsign', callsign)
      ..setInt('wakeMin', wakeMin)
      ..setInt('bedMin', bedMin)
      ..setInt('accent', accentIndex)
      ..setInt('persona', persona.index)
      ..setInt('verbosity', verbosity.index)
      ..setInt('needMin', needMin)
      ..setInt('sfxLevel', sfxLevel)
      ..setStringList('modules', modules.toList())
      ..setString('toggles', jsonEncode(toggles))
      ..setString('links', jsonEncode(linkStatus))
      ..setInt('logStreak', logStreak)
      ..setString('bills', jsonEncode(bills.map((Bill b) => b.toJson()).toList()))
      ..setInt('budget', monthBudgetPaise)
      ..setString('objectives', jsonEncode(objectives.map((Objective o) => o.toJson()).toList()))
      ..setString('notes', jsonEncode(notes.map((Note n) => n.toJson()).toList()))
      ..setString('txns', jsonEncode(txns.map((Txn t) => t.toJson()).toList()))
      ..setString('protocols', jsonEncode(protocols.map((Protocol p) => p.toJson()).toList()))
      ..setString('blocks', jsonEncode(blocks.map((Block b) => b.toJson()).toList()))
      ..setString('schedule', jsonEncode(schedule.map((ScheduleRow r) => <int>[r.bed, r.wake]).toList()))
      ..setBool('nightShield', nightShieldArmed)
      ..setInt('water', waterMl)
      ..setInt('focusToday', focusTodayMin)
      ..setInt('deepSessions', deepSessionsDone)
      ..setBool('armedTonight', armedTonight)
      ..setBool('insightApplied', insightApplied)
      ..setBool('justResolved', justResolved)
      ..setString('day', today);
    if (tomorrowFirstId != null) _prefs.setString('tomorrowFirst', tomorrowFirstId!);
    _prefs
      ..setString('sleepLog', jsonEncode(_sleep.map((SleepNight n) => n.toJson()).toList()))
      ..setString('weights', jsonEncode(weights.map((WeightPoint w) => w.toJson()).toList()));
    if (restingHr != null) _prefs.setInt('rhr', restingHr!);
    _prefs.setStringList('sleepHidden', _hiddenNights.toList());
    if (healthSyncedAt != null) _prefs.setInt('hcSync', healthSyncedAt!.millisecondsSinceEpoch);
    if (steps != null) {
      _prefs
        ..setInt('stepsToday', steps!)
        ..setString('stepsDay', today);
    }
    if (sealedAt != null) {
      _prefs
        ..setString('sealedAt', sealedAt!)
        ..setInt('sealedMood', sealedMood)
        ..setString('sealDay', today);
    }
  }

  void changed() {
    _save();
    notifyListeners();
    afterChange?.call();
  }

  // =========================================================================
  // Boot / settings
  // =========================================================================
  void completeBoot({required String name, required String call, required int wake, required int bed, required Set<String> armed}) {
    if (name.trim().isNotEmpty) fullName = name.trim();
    if (call.trim().isNotEmpty) callsign = call.trim();
    wakeMin = wake;
    // The picker returns 00:00-23:59; anything before 06:00 is after midnight.
    bedMin = bed < 360 ? bed + 1440 : bed;
    modules = armed;
    // Boot asks for weekdays: Mon-Thu nights and Sunday night. Fri/Sat keep their weekend defaults.
    for (final int i in <int>[0, 1, 2, 3, 6]) {
      schedule[i].bed = bedMin;
      schedule[i].wake = wake;
    }
    booted = true;
    changed();
  }

  void setLink(String key, String status) {
    linkStatus[key] = status;
    changed();
  }

  void setToggle(String key, bool v) {
    toggles[key] = v;
    changed();
  }

  void setAccent(int i) {
    accentIndex = i;
    changed();
  }

  void setPersona(Persona p) {
    persona = p;
    changed();
  }

  void setSfxLevel(int i) {
    sfxLevel = i.clamp(0, 2);
    changed();
  }

  void setVerbosity(Verbosity v) {
    verbosity = v;
    changed();
  }

  Future<void> eraseAll() async {
    await _prefs.clear();
    _seed();
    booted = false;
    fullName = 'Abhishek';
    callsign = 'Batman';
    wakeMin = 6 * 60 + 30;
    bedMin = 23 * 60;
    modules = <String>{..._allModules};
    toggles
      ..clear()
      ..addAll(_defaultToggles);
    linkStatus
      ..clear()
      ..addAll(<String, String>{for (final String k in linkKeys) k: 'ASK'});
    waterMl = 0;
    steps = null;
    accentIndex = 0;
    persona = Persona.tactical;
    verbosity = Verbosity.terse;
    needMin = 435;
    sfxLevel = 1;
    armedTonight = false;
    insightApplied = false;
    nightShieldArmed = false;
    justResolved = false;
    focusTodayMin = 0;
    deepSessionsDone = 0;
    logStreak = 0;
    monthBudgetPaise = 0;
    sealedAt = null;
    sealedMood = 2;
    logDraft = '';
    logMood = 2;
    tomorrowFirstId = null;
    carry.clear();
    chat.clear();
    notifyListeners();
    afterChange?.call();
  }

  // =========================================================================
  // Objectives / timeline
  // =========================================================================
  List<Objective> get open => objectives.where((Objective o) => !o.done && !o.dropped).toList();

  List<Objective> get cleared {
    final DateTime now = DateTime.now();
    return objectives.where((Objective o) => o.clearedToday(now)).toList();
  }

  /// Today's total for progress bars: open plus cleared today.
  int get objectivesToday => open.length + cleared.length;

  int get overdueCount {
    final DateTime now = DateTime.now();
    return open.where((Objective o) => o.isOverdue(now)).length;
  }

  int get critCount => open.where((Objective o) => o.threat == Threat.crit).length;

  void toggleObjective(String id, [bool? value]) {
    final Objective o = objectives.firstWhere((Objective e) => e.id == id);
    o.done = value ?? !o.done;
    o.doneAt = o.done ? DateTime.now().millisecondsSinceEpoch : null;
    changed();
  }

  void rescheduleObjective(String id, String label) {
    final Objective o = objectives.firstWhere((Objective e) => e.id == id);
    o.dueMin = null;
    o.dueLabel = label;
    changed();
  }

  void dropObjective(String id) {
    objectives.firstWhere((Objective e) => e.id == id).dropped = true;
    changed();
  }

  Objective addObjective(String title, {Threat threat = Threat.routine, int? dueMin, String? dueLabel, String tag = 'WORK', bool recurring = false}) {
    final Objective o = Objective(id: nextId(), title: title, threat: threat, dueMin: dueMin, dueLabel: dueLabel, tag: tag, recurring: recurring);
    objectives.insert(0, o);
    changed();
    return o;
  }

  void removeObjective(String id) {
    objectives.removeWhere((Objective o) => o.id == id);
    changed();
  }

  List<Block> get todayBlocks {
    final String k = dayKey(DateTime.now());
    return blocks.where((Block b) => b.dayKey == null || b.dayKey == k).toList();
  }

  List<Block> blocksFor(DateTime day) {
    final DateTime t = DateTime.now();
    if (day.year == t.year && day.month == t.month && day.day == t.day) return todayBlocks;
    return blocks.where((Block b) => b.dayKey == dayKey(day)).toList();
  }

  /// First overlapping pair of events today, or null.
  (Block, Block)? get conflict {
    final List<Block> ev = todayBlocks.where((Block b) => b.kind == BlockKind.event).toList()..sort((Block a, Block b) => a.startMin.compareTo(b.startMin));
    for (int i = 0; i < ev.length - 1; i++) {
      if (ev[i].overlaps(ev[i + 1])) return (ev[i], ev[i + 1]);
    }
    return null;
  }

  void selectDay(int i) {
    selectedDayIndex = i.clamp(0, 6);
    notifyListeners();
  }

  void resolveConflict() {
    final (Block, Block)? c = conflict;
    if (c == null) return;
    final int len = c.$2.endMin - c.$2.startMin;
    c.$2.startMin = c.$1.endMin;
    c.$2.endMin = c.$1.endMin + len;
    justResolved = true;
    changed();
  }

  Block? nextBlock(DateTime now) {
    final int m = now.hour * 60 + now.minute;
    final List<Block> l = todayBlocks.where((Block b) => b.kind == BlockKind.event && b.startMin > m).toList()..sort((Block a, Block b) => a.startMin.compareTo(b.startMin));
    return l.isEmpty ? null : l.first;
  }

  int get focusMinPlanned => todayBlocks.where((Block b) => b.kind == BlockKind.focus).fold(0, (int a, Block b) => a + b.endMin - b.startMin);

  /// Replace today's Google Calendar events with a fresh pull. A source in [failedSources] (its label)
  /// could not be reached this time, so what it showed before stays, unless the new pull already has it.
  void mergeRemoteEvents(List<RemoteEvent> events, {Set<String> failedSources = const <String>{}, DateTime? now}) {
    final DateTime t = now ?? DateTime.now();
    final String today = dayKey(t);
    int mins(DateTime d) => d.hour * 60 + d.minute;
    final List<({String title, int start, int end, String? src})> rows = <({String title, int start, int end, String? src})>[];
    for (final RemoteEvent e in events) {
      if (e.start.year != t.year || e.start.month != t.month || e.start.day != t.day) continue;
      rows.add((title: e.title, start: mins(e.start), end: math.max(mins(e.end), mins(e.start) + 15), src: e.account));
    }
    for (final Block b in blocks) {
      if (!b.id.startsWith('g:') || b.dayKey != today) continue;
      final bool fromFailed = (b.src ?? '').split('+').any(failedSources.contains);
      final bool inNewPull = rows.any((r) => r.title == b.title && r.start == b.startMin && r.end == b.endMin);
      if (fromFailed && !inNewPull) rows.add((title: b.title, start: b.startMin, end: b.endMin, src: b.src));
    }
    blocks.removeWhere((Block b) => b.id.startsWith('g:'));
    int i = 0;
    for (final r in rows) {
      blocks.add(Block(id: 'g:${i++}', kind: BlockKind.event, title: r.title, startMin: r.start, endMin: r.end, dayKey: today, src: r.src));
    }
    changed();
  }

  void removeBlock(String id) {
    blocks.removeWhere((Block b) => b.id == id);
    changed();
  }

  // =========================================================================
  // Protocols
  // =========================================================================
  void toggleProtocol(String id) {
    final Protocol p = protocols.firstWhere((Protocol e) => e.id == id);
    p.doneToday = !p.doneToday;
    if (p.doneToday) p.missedDays = 0;
    p.week = <bool>[...p.week.sublist(0, 6), p.doneToday];
    changed();
  }

  int get protocolsDone => protocols.where((Protocol p) => p.doneToday).length;

  /// The last 7 days (oldest first) as levels 0-4: the share of protocols done that day. Empty with no protocols.
  List<int> get weekLevels {
    if (protocols.isEmpty) return const <int>[];
    return List<int>.generate(7, (int d) {
      final int done = protocols.where((Protocol p) => p.week[d]).length;
      return done == 0 ? 0 : (done * 4 / protocols.length).ceil().clamp(1, 4);
    });
  }

  void addProtocol(String name) {
    final String n = name.trim();
    if (n.isEmpty) return;
    protocols.add(Protocol(id: nextId(), name: n, streak: 0, week: List<bool>.filled(7, false)));
    changed();
  }

  void removeProtocol(String id) {
    protocols.removeWhere((Protocol p) => p.id == id);
    changed();
  }

  // =========================================================================
  // Vitals
  // =========================================================================
  void logWater(int ml) {
    waterMl = math.max(0, waterMl + ml);
    changed();
  }

  // ---- steps (phone step-counter sensor) -----------------------------
  /// [counter] is the cumulative count since boot reported by the sensor.
  /// We keep a per-day baseline so "today" survives restarts and reboots.
  void onStepCounter(int counter) {
    final String today = dayKey(DateTime.now());
    int? base = _prefs.getInt('stepBase');
    int carryOver = _prefs.getInt('stepCarry') ?? 0;
    final String? baseDay = _prefs.getString('stepBaseDay');
    final int? last = _prefs.getInt('stepLast');
    if (baseDay != today) {
      base = (last != null && last <= counter) ? last : counter;
      carryOver = 0;
    } else if (base == null) {
      base = counter;
    } else if (counter < base) {
      // The phone rebooted and the sensor restarted from zero.
      carryOver += math.max(0, (last ?? base) - base);
      base = 0;
    }
    final int total = carryOver + counter - base;
    _prefs
      ..setInt('stepBase', base)
      ..setInt('stepCarry', carryOver)
      ..setString('stepBaseDay', today)
      ..setInt('stepLast', counter);
    if (steps != total) {
      steps = total;
      // Not a full _save(): this runs in the background and must not overwrite
      // what the home-screen widget wrote to the same preferences.
      _prefs
        ..setInt('stepsToday', total)
        ..setString('stepsDay', today);
      notifyListeners();
      afterChange?.call();
    }
  }

  // =========================================================================
  // Sleep
  // =========================================================================
  /// The last seven recorded nights within two weeks, newest first, each with
  /// the schedule's plan for that weekday. Empty until sleep data exists.
  List<SleepNight> get nights {
    final DateTime now = DateTime.now();
    final DateTime from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 14));
    final List<SleepNight> l = _sleep.where((SleepNight n) => !n.nightOf.isBefore(from)).toList()..sort((SleepNight a, SleepNight b) => b.nightOf.compareTo(a.nightOf));
    return l.take(7).map((SleepNight n) {
      final ScheduleRow r = schedule[n.nightOf.weekday - 1];
      return n.withPlan(r.bed, 1440 + r.wake);
    }).toList();
  }

  /// Last night's record: the newest night, but only if it is last night or the night before.
  /// An older record is not "last night", so it is not shown as such.
  SleepNight? get lastNight {
    final List<SleepNight> n = nights;
    if (n.isEmpty) return null;
    final DateTime now = DateTime.now();
    final DateTime yesterday = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    return n.first.nightOf.isBefore(yesterday) ? null : n.first;
  }

  /// A stored night by date (any of the last 45 days, not only the newest seven).
  SleepNight? sleepFor(DateTime nightOf) {
    final String k = '${nightOf.year}-${nightOf.month}-${nightOf.day}';
    return _sleep.where((SleepNight n) => n.key == k).firstOrNull;
  }

  /// Needs three nights before averages and debt mean anything (handoff 13a).
  bool get hasSleepStats => nights.length >= 3;

  int get debtMin {
    final List<SleepNight> n = nights;
    if (n.length < 3) return 0;
    return math.max(0, needMin * n.length - n.fold<int>(0, (int a, SleepNight x) => a + x.asleep));
  }

  int get avgSleep {
    final List<SleepNight> n = nights;
    return n.isEmpty ? 0 : n.fold<int>(0, (int a, SleepNight x) => a + x.asleep) ~/ n.length;
  }

  int get bedtimeVariance {
    final List<int> b = nights.map((SleepNight n) => n.bed).toList()..sort();
    return b.length < 2 ? 0 : b.last - b.first;
  }

  /// A night the user logged by hand (replaces any other entry for the same night).
  void logSleep(DateTime nightOf, int bed, int wake) {
    final DateTime d = DateTime(nightOf.year, nightOf.month, nightOf.day);
    _sleep.removeWhere((SleepNight n) => n.key == '${d.year}-${d.month}-${d.day}');
    _sleep.add(SleepNight(nightOf: d, bed: bed, wake: wake, source: 'manual'));
    _hiddenNights.remove('${d.year}-${d.month}-${d.day}');
    changed();
  }

  void removeSleep(DateTime nightOf) {
    final String k = '${nightOf.year}-${nightOf.month}-${nightOf.day}';
    if (_sleep.any((SleepNight n) => n.key == k && n.source == 'health')) _hiddenNights.add(k);
    _sleep.removeWhere((SleepNight n) => n.key == k);
    changed();
  }

  /// Replace what came from Health Connect inside the window it read ([since] onward);
  /// older Health nights are kept. Manual entries win for the same night, and nights
  /// the user deleted stay hidden.
  void setHealthSleep(List<SleepNight> fromHealth, {DateTime? since}) {
    final Set<String> manual = _sleep.where((SleepNight n) => n.source == 'manual').map((SleepNight n) => n.key).toSet();
    _sleep = <SleepNight>[
      ..._sleep.where((SleepNight n) => n.source == 'manual'),
      if (since != null) ..._sleep.where((SleepNight n) => n.source == 'health' && n.nightOf.isBefore(since)),
      ...fromHealth.where((SleepNight n) => !manual.contains(n.key) && !_hiddenNights.contains(n.key)),
    ];
    healthSyncedAt = DateTime.now();
    changed();
  }

  // ---- body -------------------------------------------------------------
  double? get weightKg => weights.isEmpty ? null : (List<WeightPoint>.of(weights)..sort((WeightPoint a, WeightPoint b) => a.at.compareTo(b.at))).last.kg;

  /// Change over the last 30 days, or null with fewer than two readings.
  double? get weightDelta {
    final DateTime from = DateTime.now().subtract(const Duration(days: 30));
    final List<WeightPoint> w = weights.where((WeightPoint p) => p.at.isAfter(from)).toList()..sort((WeightPoint a, WeightPoint b) => a.at.compareTo(b.at));
    return w.length < 2 ? null : w.last.kg - w.first.kg;
  }

  /// Up to 12 averaged points over the last 30 days for the sparkline.
  List<double> get weightSeries {
    final DateTime from = DateTime.now().subtract(const Duration(days: 30));
    final List<WeightPoint> w = weights.where((WeightPoint p) => p.at.isAfter(from)).toList()..sort((WeightPoint a, WeightPoint b) => a.at.compareTo(b.at));
    return SleepAnalyzer.bucket(w.map((WeightPoint p) => p.kg).toList(), 12);
  }

  void logWeight(double kg) {
    weights = <WeightPoint>[...weights, WeightPoint(DateTime.now(), double.parse(kg.toStringAsFixed(1)))];
    changed();
  }

  /// Replace Health Connect readings inside the window it read ([since] onward); manual
  /// readings and older Health readings are kept.
  void setHealthBody(List<WeightPoint> fromHealth, int? rhr, {DateTime? since}) {
    weights = <WeightPoint>[
      ...weights.where((WeightPoint w) => w.source == 'manual' || (since != null && w.at.isBefore(since))),
      ...fromHealth,
    ];
    if (rhr != null) restingHr = rhr;
    healthSyncedAt = DateTime.now();
    changed();
  }

  ScheduleRow get tonightRow => schedule[(DateTime.now().weekday - 1) % 7];

  /// Spec 8.2: wake - (need + latency), pulled earlier to repay debt, rounded
  /// to 5 min and clamped to [plan - 45, plan + 30].
  int get recommendedBed {
    final ScheduleRow r = tonightRow;
    final int shift = math.min(20, ((debtMin / 6) / 5).round() * 5);
    final int raw = 1440 + r.wake - (needMin + latencyMin) - shift;
    final int rounded = (raw / 5).round() * 5;
    return rounded.clamp(r.bed - 45, r.bed + 30);
  }

  int get windDownAt => recommendedBed - 30;

  // =========================================================================
  // Capture
  // =========================================================================
  /// Commit a draft. Returns an undo closure, or null if nothing was written.
  VoidCallback? commitCapture(CaptureDraft d, Threat threat) {
    final String raw = d.raw.trim();
    if (raw.isEmpty) return null;
    final DateTime now = DateTime.now();
    final String? label = d.whenLabel;
    final bool today = label == null || label == 'TODAY' || label == 'TONIGHT';
    switch (d.type) {
      case CaptureType.obj:
      case CaptureType.habit:
        final bool habit = d.type == CaptureType.habit;
        final Objective o = addObjective(
          raw,
          threat: threat,
          dueMin: today ? d.when : null,
          dueLabel: today ? null : (d.when != null ? '$label ${Fmt.hm(d.when!)}' : label),
          tag: d.tag ?? 'WORK',
          recurring: habit,
        );
        return () => removeObjective(o.id);
      case CaptureType.event:
        final int s = d.when ?? math.min(23 * 60, (now.hour + 1) * 60);
        final Block b = Block(id: 'u:${nextId()}', kind: BlockKind.event, title: raw, startMin: s, endMin: math.min(s + 30, 24 * 60), dayKey: dayKey(dateForLabel(label, now)));
        blocks.add(b);
        changed();
        return () {
          blocks.removeWhere((Block e) => e.id == b.id);
          changed();
        };
      case CaptureType.note:
        final Note n = Note(id: nextId(), title: raw.length > 40 ? '${raw.substring(0, 40)}…' : raw, body: raw, at: now);
        notes.insert(0, n);
        changed();
        return () {
          notes.removeWhere((Note e) => e.id == n.id);
          changed();
        };
      case CaptureType.spend:
        if (d.paise == null || d.paise! <= 0) return null;
        final Txn t = Txn(id: nextId(), title: d.title.isEmpty ? raw : d.title, category: (d.tag ?? 'OTHER').toUpperCase(), paise: d.paise!, at: now);
        txns.insert(0, t);
        changed();
        return () {
          txns.removeWhere((Txn e) => e.id == t.id);
          changed();
        };
    }
  }

  /// Next calendar date for a day label (TODAY, TOMORROW, MON..SUN).
  static DateTime dateForLabel(String? label, DateTime now) {
    final DateTime base = DateTime(now.year, now.month, now.day);
    switch (label) {
      case null:
      case 'TODAY':
      case 'TONIGHT':
        return base;
      case 'TOMORROW':
        return base.add(const Duration(days: 1));
    }
    const List<String> days = <String>['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final int idx = days.indexOf(label);
    if (idx < 0) return base;
    int add = (idx + 1) - base.weekday;
    if (add <= 0) add += 7;
    return base.add(Duration(days: add));
  }

  // ---- ledger -----------------------------------------------------------
  /// This month's spend only.
  List<Txn> get monthTxns {
    final DateTime n = DateTime.now();
    return txns.where((Txn t) => t.at.year == n.year && t.at.month == n.month).toList();
  }

  int get monthSpentPaise => monthTxns.fold(0, (int a, Txn t) => a + t.paise);

  Map<String, int> get categorySpend {
    final Map<String, int> m = <String, int>{};
    for (final Txn t in monthTxns) {
      m[t.category] = (m[t.category] ?? 0) + t.paise;
    }
    return m;
  }

  /// Whole percent of the month's budget spent, or null while no budget is set.
  int? get monthSpentPercent => monthBudgetPaise <= 0 ? null : (monthSpentPaise * 100 / monthBudgetPaise).round();

  void setBudget(int paise) {
    monthBudgetPaise = math.max(0, paise);
    changed();
  }

  void addBill(String name, int paise, DateTime due) {
    bills.add(Bill(id: nextId(), name: name.trim(), dueAt: due, paise: paise));
    bills.sort((Bill a, Bill b) => a.dueAt.compareTo(b.dueAt));
    changed();
  }

  void removeBill(String id) {
    bills.removeWhere((Bill b) => b.id == id);
    changed();
  }

  int get safeToSpendPaise {
    final DateTime now = DateTime.now();
    final int daysLeft = DateUtils2.daysInMonth(now) - now.day + 1;
    return monthBudgetPaise <= 0 ? 0 : math.max(0, (monthBudgetPaise - monthSpentPaise) ~/ daysLeft);
  }

  int yesterdaySpendPaise(DateTime now) {
    final DateTime y = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    return txns.where((Txn t) => t.at.year == y.year && t.at.month == y.month && t.at.day == y.day).fold(0, (int a, Txn t) => a + t.paise);
  }

  // ---- field log / deep ops ----------------------------------------------
  void logFocus(int minutes) {
    focusTodayMin += minutes;
    deepSessionsDone++;
    changed();
  }

  void sealLog(String text, int mood) {
    final DateTime now = DateTime.now();
    notes.insert(0, Note(id: nextId(), title: 'Night log · ${Fmt.dayStamp(now)}', body: text, at: now));
    sealedAt = Fmt.time(now);
    sealedMood = mood;
    logStreak++;
    logDraft = '';
    changed();
  }

  // =========================================================================
  // Readiness / intel
  // =========================================================================
  int get readiness {
    final int total = objectivesToday;
    final double obj = total == 0 ? 0 : cleared.length / total;
    final double prot = protocols.isEmpty ? 0 : protocolsDone / protocols.length;
    final double focus = (focusTodayMin / focusTargetMin).clamp(0, 1).toDouble();
    final double water = (waterMl / waterTargetMl).clamp(0, 1).toDouble();
    // Sleep only counts once there is data; otherwise the other parts carry the full weight.
    final SleepNight? ln = lastNight;
    final double sleepW = ln == null ? 0 : 0.2;
    final double sleep = ln == null ? 0 : (ln.asleep / needMin).clamp(0, 1).toDouble();
    final double wsum = 0.25 + 0.25 + 0.15 + 0.15 + sleepW;
    return (100 * (0.25 * obj + 0.25 * prot + 0.15 * focus + 0.15 * water + sleepW * sleep) / wsum).round();
  }

  /// Water expected by now, linear 07:00 -> 21:00.
  int expectedWater(DateTime now) {
    final double f = ((now.hour + now.minute / 60) - 7) / 14;
    return (waterTargetMl * f.clamp(0, 1)).round();
  }

  bool hydrationBehind(DateTime now) => waterMl + 250 < expectedWater(now);

  /// Open objectives, most urgent first: threat, then due time, then newest.
  List<Objective> prioritised() {
    final List<Objective> l = open;
    int rank(Threat t) => t == Threat.crit ? 0 : (t == Threat.high ? 1 : 2);
    l.sort((Objective a, Objective b) {
      if (a.id == tomorrowFirstId) return -1;
      if (b.id == tomorrowFirstId) return 1;
      final int r = rank(a.threat).compareTo(rank(b.threat));
      if (r != 0) return r;
      return (a.dueMin ?? 9999).compareTo(b.dueMin ?? 9999);
    });
    return l;
  }

  /// Compact situation report for the assistant (spec section 6).
  String sitrep(DateTime now) {
    final Block? nb = nextBlock(now);
    final (Block, Block)? c = conflict;
    return jsonEncode(<String, dynamic>{
      'now': now.toIso8601String(),
      'callsign': callsign,
      'objectives_open': open.map((Objective o) => <String, dynamic>{'t': o.title, 'threat': o.threat.name, 'due': o.dueMin != null ? Fmt.hm(o.dueMin!) : o.dueLabel, 'overdue': o.isOverdue(now)}).toList(),
      'cleared_today': cleared.length,
      'next_op': nb == null ? null : <String, dynamic>{'t': nb.title, 'start': Fmt.hm(nb.startMin)},
      'conflict': c == null ? null : '${c.$1.title} vs ${c.$2.title}',
      'protocols': <String, dynamic>{'done': protocolsDone, 'total': protocols.length, 'at_risk': protocols.where((Protocol p) => p.atRisk).map((Protocol p) => p.name).toList()},
      'water_ml': waterMl,
      'water_target': waterTargetMl,
      'steps': steps,
      'sleep': <String, dynamic>{'last_asleep_min': lastNight?.asleep, 'debt_min': hasSleepStats ? debtMin : null, 'tonight_bed': Fmt.hm(recommendedBed), 'wake': Fmt.hm(tonightRow.wake)},
      'ledger': <String, dynamic>{'spent_paise': monthSpentPaise, 'budget_paise': monthBudgetPaise == 0 ? null : monthBudgetPaise},
      'persona': persona.name,
      'verbosity': verbosity.name,
    });
  }
}

/// Small helper so the store does not depend on Flutter's material library.
abstract final class DateUtils2 {
  static int daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;
}
