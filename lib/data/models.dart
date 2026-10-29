import 'dart:ui' show VoidCallback;

import '../vigil/vigil.dart';

class Objective {
  Objective({
    required this.id,
    required this.title,
    this.threat = Threat.routine,
    this.dueMin,
    this.dueLabel,
    this.tag = 'WORK',
    this.sub,
    this.estimate,
    this.done = false,
    this.doneAt,
    this.dropped = false,
    this.recurring = false,
  });

  final String id;
  String title;
  Threat threat;

  /// Minutes after midnight, if due today.
  int? dueMin;

  /// Label for non-today dues (e.g. `FRI`, `TOMORROW 18:00`).
  String? dueLabel;
  String tag;
  String? sub;
  int? estimate;
  bool done;

  /// Epoch ms of completion; "cleared today" only counts today's.
  int? doneAt;
  bool dropped;
  bool recurring;

  bool get hasDate => dueMin != null || dueLabel != null;

  bool clearedToday(DateTime now) {
    if (!done || doneAt == null) return false;
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(doneAt!);
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  /// Derived from the clock, never stored.
  bool isOverdue(DateTime now) => !done && !dropped && dueMin != null && dueMin! < now.hour * 60 + now.minute;

  String get meta {
    final List<String> p = <String>[
      if (dueMin != null) 'Due ${_hm(dueMin!)}' else if (dueLabel != null) 'Due ${dueLabel!.toLowerCase()}' else 'No date',
      '${tag.isEmpty ? '' : tag[0].toUpperCase()}${tag.length > 1 ? tag.substring(1).toLowerCase() : ''}',
      if (sub != null) sub!,
      if (estimate != null) '~$estimate min',
    ];
    return p.join(' · ');
  }

  static String _hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'threat': threat.name,
        'dueMin': dueMin,
        'dueLabel': dueLabel,
        'tag': tag,
        'sub': sub,
        'estimate': estimate,
        'done': done,
        'doneAt': doneAt,
        'dropped': dropped,
        'recurring': recurring,
      };

  factory Objective.fromJson(Map<String, dynamic> j) => Objective(
        id: j['id'] as String,
        title: j['title'] as String,
        threat: Threat.values.byName(j['threat'] as String),
        dueMin: j['dueMin'] as int?,
        dueLabel: j['dueLabel'] as String?,
        tag: (j['tag'] as String?) ?? 'WORK',
        sub: j['sub'] as String?,
        estimate: j['estimate'] as int?,
        done: (j['done'] as bool?) ?? false,
        doneAt: j['doneAt'] as int?,
        dropped: (j['dropped'] as bool?) ?? false,
        recurring: (j['recurring'] as bool?) ?? false,
      );
}

enum BlockKind { event, focus, personal, task }

class Block {
  Block({
    required this.id,
    required this.kind,
    required this.title,
    required this.startMin,
    required this.endMin,
    this.attendees = 0,
    this.dayKey,
    this.src,
  });

  final String id;
  final BlockKind kind;
  String title;
  int startMin;
  int endMin;
  int attendees;

  /// `yyyy-m-d`. Null means today.
  String? dayKey;

  /// Which calendar a pulled event came from (a linked account's label, or PUBLIC); `A+B` when it is in both.
  final String? src;

  bool overlaps(Block o) => startMin < o.endMin && o.startMin < endMin;

  /// "WORK × PERSONAL" when this block and [o] come from different calendars, else null.
  String? clashWith(Block o) => (src != null && o.src != null && src != o.src) ? '$src × ${o.src}' : null;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind.name,
        'title': title,
        'start': startMin,
        'end': endMin,
        'att': attendees,
        'day': dayKey,
        if (src != null) 'src': src,
      };

  factory Block.fromJson(Map<String, dynamic> j) => Block(
        id: j['id'] as String,
        kind: BlockKind.values.byName(j['kind'] as String),
        title: j['title'] as String,
        startMin: j['start'] as int,
        endMin: j['end'] as int,
        attendees: (j['att'] as int?) ?? 0,
        dayKey: j['day'] as String?,
        src: j['src'] as String?,
      );
}

class Protocol {
  Protocol({
    required this.id,
    required this.name,
    required this.streak,
    required this.week,
    this.doneToday = false,
    this.missedDays = 0,
    this.unit,
    this.target,
    this.remindMin,
    this.createdAt,
    List<int>? days,
  }) : days = days ?? <int>[];

  final String id;
  String name;

  /// Streak through yesterday. Today adds one when checked.
  int streak;

  /// Last 7 days, oldest first; the last entry is today.
  List<bool> week;
  bool doneToday;
  int missedDays;
  String? unit;
  int? target;

  /// Minutes after midnight for a daily reminder, or null for none.
  int? remindMin;

  /// When it was added (ms since epoch). Null for habits from older builds, which count all seven days.
  int? createdAt;

  /// How many of the last seven days (today included) this habit has existed, 1 to 7.
  int activeDays(DateTime now) {
    final int? c = createdAt;
    if (c == null) return 7;
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime made = DateTime.fromMillisecondsSinceEpoch(c);
    return (today.difference(DateTime(made.year, made.month, made.day)).inDays + 1).clamp(1, 7);
  }

  /// Weekdays it applies to (1 = Monday ... 7 = Sunday); empty means every day.
  List<int> days;

  bool dueOn(DateTime d) => days.isEmpty || days.contains(d.weekday);

  int get streakNow => streak + (doneToday ? 1 : 0);
  bool get atRisk => !doneToday && missedDays >= 2;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'streak': streak,
        'done': doneToday,
        'missed': missedDays,
        'week': week,
        'name': name,
        if (unit != null) 'unit': unit,
        if (target != null) 'target': target,
        if (remindMin != null) 'remindMin': remindMin,
        if (createdAt != null) 'created': createdAt,
        if (days.isNotEmpty) 'days': days,
      };

  factory Protocol.fromJson(Map<String, dynamic> j) => Protocol(
        id: j['id'] as String,
        name: j['name'] as String,
        streak: j['streak'] as int,
        week: (j['week'] as List<dynamic>).map((dynamic e) => e as bool).toList(),
        doneToday: j['done'] as bool,
        missedDays: j['missed'] as int,
        unit: j['unit'] as String?,
        target: j['target'] as int?,
        remindMin: (j['remindMin'] as num?)?.toInt(),
        createdAt: (j['created'] as num?)?.toInt(),
        days: <int>[for (final dynamic d in (j['days'] as List<dynamic>? ?? <dynamic>[])) (d as num).toInt()],
      );

  void applyJson(Map<String, dynamic> j) {
    streak = j['streak'] as int;
    doneToday = j['done'] as bool;
    missedDays = j['missed'] as int;
    week = (j['week'] as List<dynamic>).map((dynamic e) => e as bool).toList();
  }

  /// Move forward [days] calendar days (>= 1).
  void rollOver(int days) {
    final bool hit = doneToday;
    for (int i = 0; i < days; i++) {
      final bool d = i == 0 && hit;
      week = <bool>[...week.sublist(1), false];
      if (i == 0) week[5] = d;
      if (d) {
        streak++;
        missedDays = 0;
      } else {
        streak = 0;
        missedDays++;
      }
    }
    doneToday = false;
    week[6] = false;
  }
}

class Txn {
  Txn({required this.id, required this.title, required this.category, required this.paise, required this.at});

  final String id;
  final String title;
  final String category;
  final int paise;
  final DateTime at;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'category': category,
        'paise': paise,
        'at': at.millisecondsSinceEpoch,
      };

  factory Txn.fromJson(Map<String, dynamic> j) => Txn(
        id: j['id'] as String,
        title: j['title'] as String,
        category: j['category'] as String,
        paise: j['paise'] as int,
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
      );
}

class Bill {
  Bill({required this.id, required this.name, required this.dueAt, required this.paise, this.paid = false});

  final String id;
  final String name;
  final DateTime dueAt;
  final int paise;
  bool paid;

  static const List<String> _months = <String>['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  bool get dueToday {
    final DateTime n = DateTime.now();
    return dueAt.year == n.year && dueAt.month == n.month && dueAt.day == n.day;
  }

  /// "TODAY" or "25 OCT".
  String get due => dueToday ? 'TODAY' : '${dueAt.day} ${_months[dueAt.month - 1]}';

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'name': name, 'due': dueAt.millisecondsSinceEpoch, 'paise': paise, 'paid': paid};

  factory Bill.fromJson(Map<String, dynamic> j) => Bill(
        id: j['id'] as String,
        name: j['name'] as String,
        dueAt: DateTime.fromMillisecondsSinceEpoch(j['due'] as int),
        paise: j['paise'] as int,
        paid: (j['paid'] as bool?) ?? false,
      );
}

enum NoteKind { pinned, voice, note }

class Note {
  Note({required this.id, required this.title, required this.body, this.kind = NoteKind.note, required this.at});

  final String id;
  final String title;
  final String body;
  final NoteKind kind;
  final DateTime at;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'body': body,
        'kind': kind.name,
        'at': at.millisecondsSinceEpoch,
      };

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        kind: NoteKind.values.byName(j['kind'] as String),
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
      );
}

/// One night of sleep. Times are minutes after midnight of the evening the
/// night started ([nightOf]), so bed after midnight is >= 1440 and wake is >= 1440.
class SleepNight {
  const SleepNight({
    required this.nightOf,
    required this.bed,
    required this.wake,
    this.asleepMin,
    this.source = 'manual',
    this.planBed = 23 * 60,
    this.planWake = 1440 + 6 * 60 + 30,
  });

  /// Local date of the evening the night started.
  final DateTime nightOf;
  final int bed;
  final int wake;

  /// Minutes actually asleep, when the source reports it; otherwise the whole span.
  final int? asleepMin;

  /// `health` (Health Connect) or `manual`.
  final String source;

  /// The schedule's plan for that night, filled in by the store for display.
  final int planBed;
  final int planWake;

  String get label => const <String>['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][nightOf.weekday - 1];
  int get asleep => asleepMin ?? (wake - bed);
  String get key => '${nightOf.year}-${nightOf.month}-${nightOf.day}';

  SleepNight withPlan(int bed, int wake) => SleepNight(nightOf: nightOf, bed: this.bed, wake: this.wake, asleepMin: asleepMin, source: source, planBed: bed, planWake: wake);

  Map<String, dynamic> toJson() => <String, dynamic>{'n': key, 'bed': bed, 'wake': wake, 'asleep': asleepMin, 'src': source};

  factory SleepNight.fromJson(Map<String, dynamic> j) {
    final List<String> p = (j['n'] as String).split('-');
    return SleepNight(
      nightOf: DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2])),
      bed: j['bed'] as int,
      wake: j['wake'] as int,
      asleepMin: j['asleep'] as int?,
      source: (j['src'] as String?) ?? 'manual',
    );
  }
}

class WeightPoint {
  const WeightPoint(this.at, this.kg, {this.source = 'manual'});

  final DateTime at;
  final double kg;
  final String source;

  Map<String, dynamic> toJson() => <String, dynamic>{'at': at.millisecondsSinceEpoch, 'kg': kg, 'src': source};

  factory WeightPoint.fromJson(Map<String, dynamic> j) => WeightPoint(DateTime.fromMillisecondsSinceEpoch(j['at'] as int), (j['kg'] as num).toDouble(), source: (j['src'] as String?) ?? 'manual');
}

class ScheduleRow {
  ScheduleRow({required this.night, required this.bed, required this.wake});

  /// e.g. `MON → TUE`
  final String night;

  /// Minutes after 00:00 of the night's day; >= 1440 means after midnight.
  int bed;

  /// Minutes after 00:00 of the following day.
  int wake;

  int get inBed => 1440 + wake - bed;
}

enum CaptureType { obj, event, note, spend, habit }

class CaptureDraft {
  CaptureDraft({
    this.type = CaptureType.obj,
    this.raw = '',
    this.title = '',
    this.when,
    this.whenLabel,
    this.paise,
    this.tag,
    this.uncertainType = true,
  });

  CaptureType type;

  /// The user's words, untouched.
  String raw;

  /// Parsed title (amount stripped for spends).
  String title;
  int? when; // minutes after midnight
  String? whenLabel; // TODAY | TONIGHT | TOMORROW | MON..SUN
  int? paise;
  String? tag;
  bool uncertainType;
}

/// Who produced a reply, shown as a tag on it.
enum ReplySource { instant, data, model, cloud }

class ChatMsg {
  ChatMsg({
    required this.fromUser,
    required this.text,
    required this.at,
    this.alert = false,
    this.diff,
    this.chart,
    this.undoable = false,
    this.undone = false,
    this.note,
    this.onUndo,
    this.source,
    this.ms,
    this.route,
  });

  /// A screen this reply opened, shown as an Open button.
  final String? route;

  final bool fromUser;
  final String text;
  final DateTime at;
  final bool alert;

  /// A small line under the reply, for example that another model answered or that the cloud call failed.
  final String? note;

  /// Reverses what this reply wrote.
  final VoidCallback? onUndo;

  /// Diff card rows: label -> text.
  final List<(String, String)>? diff;

  /// Bar chart values for 7 days (Mon..Sun).
  final List<double>? chart;
  bool undoable;
  bool undone;

  /// The reply is a question that waits for Confirm or Cancel (a deletion). Not saved.
  bool confirm = false;

  /// Instant (rules), from your data (router), on-device AI (model) or cloud. Null for system notes.
  ReplySource? source;

  /// How long the reply took to produce.
  int? ms;

  /// Saved with the app's data. A reply read back from disk can no longer be undone.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': '${at.microsecondsSinceEpoch}-${fromUser ? 'u' : 'k'}',
        'fromUser': fromUser,
        'text': text,
        'at': at.millisecondsSinceEpoch,
        if (alert) 'alert': true,
        if (note != null) 'note': note,
        if (source != null) 'source': source!.name,
        if (ms != null) 'ms': ms,
        if (route != null) 'route': route,
        if (diff != null) 'diff': <List<String>>[for (final (String, String) r in diff!) <String>[r.$1, r.$2]],
      };

  static ChatMsg fromJson(Map<String, dynamic> j) => ChatMsg(
        fromUser: (j['fromUser'] as bool?) ?? false,
        text: (j['text'] as String?) ?? '',
        at: DateTime.fromMillisecondsSinceEpoch((j['at'] as int?) ?? 0),
        alert: (j['alert'] as bool?) ?? false,
        note: j['note'] as String?,
        source: ReplySource.values.where((ReplySource e) => e.name == j['source']).firstOrNull,
        ms: j['ms'] as int?,
        route: j['route'] as String?,
        diff: (j['diff'] as List<dynamic>?)?.map((dynamic r) => ((r as List<dynamic>)[0] as String, r[1] as String)).toList(),
      );
}
