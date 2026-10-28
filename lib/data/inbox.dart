import 'dart:convert';

import '../app/fmt.dart';
import '../vigil/vigil.dart';
import 'models.dart';
import 'store.dart';

enum InboxKind { overdue, streak, briefing, debrief, bill, backup, clash }

/// One line in the notifications inbox.
class InboxItem {
  const InboxItem({required this.id, required this.kind, required this.title, required this.body, required this.at, this.route, this.threat, this.objectiveId});

  /// Stable, so reading or dismissing it is remembered ("overdue" plus the objective id, "dawn" plus the day).
  final String id;
  final InboxKind kind;
  final String title;
  final String body;
  final DateTime at;

  /// Where tapping it goes.
  final String? route;
  final Threat? threat;
  final String? objectiveId;

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'kind': kind.name, 'title': title, 'body': body, 'at': at.millisecondsSinceEpoch, if (route != null) 'route': route};

  static InboxItem? fromJson(Map<String, dynamic> j) {
    final InboxKind? k = InboxKind.values.where((InboxKind e) => e.name == j['kind']).firstOrNull;
    if (k == null || j['id'] is! String || j['at'] is! int) return null;
    return InboxItem(id: j['id'] as String, kind: k, title: (j['title'] as String?) ?? '', body: (j['body'] as String?) ?? '', at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int), route: j['route'] as String?);
  }
}

/// How long a notification is kept.
const int kInboxKeepDays = 14;

const String _kInfo = 'inboxInfo';
const String _kRead = 'inboxRead';
const String _kGone = 'inboxDismissed';

/// What the inbox shows now, newest first. Things that are still true are worked out live (an overdue objective, an
/// unpaid bill) and vanish when fixed; briefings and backups are remembered for [kInboxKeepDays] days. Anything the
/// user dismissed stays hidden.
List<InboxItem> loadInbox(VigilStore s, DateTime now, {DateTime? lastBackup}) {
  final DateTime day0 = DateTime(now.year, now.month, now.day);
  final String key = VigilStore.dayKey(now);
  final List<InboxItem> live = <InboxItem>[];

  for (final Objective o in s.open) {
    if (!o.isOverdue(now)) continue;
    final DateTime due = day0.add(Duration(minutes: o.dueMin!));
    live.add(InboxItem(
      id: 'overdue:${o.id}',
      kind: InboxKind.overdue,
      title: 'Overdue — ${o.title}',
      body: 'Due ${Fmt.hm(o.dueMin!)} · ${Fmt.dur(now.difference(due).inMinutes)} overdue',
      at: due,
      route: '/ops/objectives',
      threat: o.threat,
      objectiveId: o.id,
    ));
  }
  if (now.hour >= 19) {
    for (final Protocol p in s.protocols.where((Protocol p) => p.atRisk)) {
      live.add(InboxItem(id: 'risk:${p.id}:$key', kind: InboxKind.streak, title: 'Streak at risk — ${p.name}', body: '${p.missedDays} days missed · not done today', at: day0.add(const Duration(hours: 19, minutes: 30)), route: '/protocols/habits'));
    }
  }
  for (final Bill b in s.bills.where((Bill b) => !b.paid && b.dueAt.isBefore(day0))) {
    live.add(InboxItem(id: 'bill:${b.id}', kind: InboxKind.bill, title: 'Bill overdue — ${b.name} ${Fmt.money(b.paise)}', body: 'Was due ${Fmt.dayStamp(b.dueAt)} · Vault › Bills', at: DateTime(b.dueAt.year, b.dueAt.month, b.dueAt.day, 9), route: '/vault/ledger'));
  }
  final (Block, Block)? clash = s.conflict;
  if (clash != null) {
    live.add(InboxItem(id: 'clash:${clash.$1.id}:${clash.$2.id}:$key', kind: InboxKind.clash, title: 'Calendar clash', body: '${clash.$1.title} × ${clash.$2.title}', at: now, route: '/ops/timeline'));
  }

  // Remembered items: today's candidates are added or refreshed, old ones expire.
  final Map<String, InboxItem> info = <String, InboxItem>{};
  try {
    final String? raw = s.prefs.getString(_kInfo);
    if (raw != null) {
      for (final dynamic e in jsonDecode(raw) as List<dynamic>) {
        final InboxItem? it = InboxItem.fromJson(e as Map<String, dynamic>);
        if (it != null) info[it.id] = it;
      }
    }
  } catch (_) {
    // an unreadable log starts again
  }
  final DateTime wake = day0.add(Duration(minutes: s.wakeMin % 1440));
  if (!wake.isAfter(now)) {
    info['dawn:$key'] = InboxItem(id: 'dawn:$key', kind: InboxKind.briefing, title: 'Dawn briefing ready', body: '${s.open.length} objectives open, ${s.critCount} critical', at: wake, route: '/briefing');
  }
  final DateTime debrief = day0.add(Duration(minutes: s.bedMin - 30));
  if (!debrief.isAfter(now)) {
    info['debrief:$key'] = InboxItem(id: 'debrief:$key', kind: InboxKind.debrief, title: 'Night debrief', body: 'Review the day and stand down', at: debrief, route: '/debrief');
  }
  if (lastBackup != null) {
    final String bk = 'backup:${VigilStore.dayKey(lastBackup)}';
    info[bk] = InboxItem(id: bk, kind: InboxKind.backup, title: 'Backup complete', body: 'Google Drive · everything up to ${Fmt.time(lastBackup)}', at: lastBackup);
  }
  final DateTime cutoff = day0.subtract(const Duration(days: kInboxKeepDays));
  info.removeWhere((String _, InboxItem it) => it.at.isBefore(cutoff));
  final String encoded = jsonEncode(<Map<String, dynamic>>[for (final InboxItem it in info.values) it.toJson()]);
  if (s.prefs.getString(_kInfo) != encoded) s.prefs.setString(_kInfo, encoded);

  final Set<String> gone = (s.prefs.getStringList(_kGone) ?? <String>[]).toSet();
  final List<InboxItem> all = <InboxItem>[...live, ...info.values].where((InboxItem it) => !gone.contains(it.id)).toList()..sort((InboxItem a, InboxItem b) => b.at.compareTo(a.at));
  return all;
}

/// The ids the user has read.
Set<String> inboxRead(VigilStore s) => (s.prefs.getStringList(_kRead) ?? <String>[]).toSet();

int unreadCount(VigilStore s, DateTime now, {DateTime? lastBackup}) {
  final Set<String> read = inboxRead(s);
  return loadInbox(s, now, lastBackup: lastBackup).where((InboxItem it) => !read.contains(it.id)).length;
}

List<String> _capped(Iterable<String> ids) {
  final List<String> l = ids.toList();
  return l.length > 400 ? l.sublist(l.length - 400) : l;
}

void markInboxRead(VigilStore s, Iterable<String> ids) {
  final Set<String> read = inboxRead(s)..addAll(ids);
  s.prefs.setStringList(_kRead, _capped(read));
  s.changed();
}

void dismissInbox(VigilStore s, String id) {
  final Set<String> gone = (s.prefs.getStringList(_kGone) ?? <String>[]).toSet()..add(id);
  s.prefs.setStringList(_kGone, _capped(gone));
  s.changed();
}

/// "Today", "Yesterday" or "Earlier this week" / "Earlier".
String inboxGroup(DateTime at, DateTime now) {
  final DateTime d0 = DateTime(now.year, now.month, now.day);
  final DateTime a0 = DateTime(at.year, at.month, at.day);
  final int days = d0.difference(a0).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  return 'Earlier';
}
