import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/common.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/inbox.dart';
import '../data/store.dart';
import '../services/drive_sync.dart';
import '../vigil/vigil.dart';
import '../services/haptics.dart';

/// The last time a backup finished, when Drive is set up.
DateTime? lastBackupForInbox() => DriveSync.instance.configured ? DriveSync.instance.lastSync : null;

/// Reminders, briefings and nudges, kept for [kInboxKeepDays] days. Swipe one away to dismiss it.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  IconData _icon(InboxKind k) => switch (k) {
        InboxKind.overdue => Icons.warning_amber_rounded,
        InboxKind.streak => Icons.local_fire_department_outlined,
        InboxKind.briefing => Icons.wb_twilight,
        InboxKind.debrief => Icons.nights_stay_outlined,
        InboxKind.bill => Icons.receipt_long_outlined,
        InboxKind.backup => Icons.cloud_done_outlined,
        InboxKind.clash => Icons.event_busy_outlined,
      };

  void _open(BuildContext context, VigilStore s, InboxItem it) {
    markInboxRead(s, <String>[it.id]);
    final String? r = it.route;
    if (r == null) return;
    if (r == '/briefing' || r == '/debrief') {
      context.push(r);
    } else {
      context.go(r);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vigil;
    final t = context.vtype;
    final VigilStore s = ref.watch(storeProvider);
    final DateTime now = DateTime.now();
    final List<InboxItem> items = loadInbox(s, now, lastBackup: lastBackupForInbox());
    final Set<String> read = inboxRead(s);
    final int unread = items.where((InboxItem it) => !read.contains(it.id)).length;

    Widget row(InboxItem it) {
      final bool isRead = read.contains(it.id);
      final bool crit = it.threat == Threat.crit;
      return Dismissible(
        key: ValueKey<String>('inbox-${it.id}'),
        direction: DismissDirection.endToStart,
        background: Container(color: c.critical.withValues(alpha: 0.15), alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 18), child: Icon(Icons.delete_outline, color: c.critical)),
        onDismissed: (_) {
          Haptics.tick();
          dismissInbox(s, it.id);
        },
        child: InkWell(
          onTap: () => _open(context, s, it),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Container(width: 36, height: 36, decoration: BoxDecoration(border: Border.all(color: crit ? c.critical : c.lineStrong)), child: Icon(_icon(it.kind), size: 18, color: crit ? c.critical : c.textMuted)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Row(children: <Widget>[
                      if (!isRead) Container(width: 7, height: 7, margin: const EdgeInsets.only(right: 7), decoration: BoxDecoration(shape: BoxShape.circle, color: c.signal)),
                      Expanded(child: Text(it.title, style: t.rowTitle.copyWith(color: isRead ? c.textMuted : c.text))),
                    ]),
                    const SizedBox(height: 2),
                    Text(it.body, style: t.caption.copyWith(color: c.textFaint)),
                  ]),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                  Text(Fmt.time(it.at), style: t.meta.copyWith(color: c.textFaint)),
                  if (it.threat != null && it.threat != Threat.routine) ...<Widget>[const SizedBox(height: 4), ThreatTag(it.threat!)],
                ]),
              ]),
              if (it.kind == InboxKind.overdue && it.objectiveId != null) ...<Widget>[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Row(children: <Widget>[
                    VigilButton(
                      label: 'Complete',
                      onPressed: () {
                        markInboxRead(s, <String>[it.id]);
                        s.toggleObjective(it.objectiveId!, true);
                      },
                    ),
                    const SizedBox(width: 8),
                    VigilButton(
                      label: 'Snooze 1 h',
                      variant: VigilButtonVariant.secondary,
                      onPressed: () {
                        markInboxRead(s, <String>[it.id]);
                        s.snoozeObjective(it.objectiveId!, 60);
                      },
                    ),
                  ]),
                ),
              ],
            ]),
          ),
        ),
      );
    }

    final List<Widget> children = <Widget>[];
    String? group;
    final List<InboxItem> bucket = <InboxItem>[];
    void flush() {
      if (bucket.isEmpty) return;
      final int groupUnread = bucket.where((InboxItem it) => !read.contains(it.id)).length;
      children
        ..add(Padding(padding: const EdgeInsets.only(top: 14, bottom: 8), child: SectionLabel(group!, trailing: groupUnread > 0 ? '$groupUnread unread' : null)))
        ..add(RowList(children: <Widget>[for (final InboxItem it in bucket) row(it)]));
      bucket.clear();
    }

    for (final InboxItem it in items) {
      final String g = inboxGroup(it.at, now);
      if (g != group) {
        flush();
        group = g;
      }
      bucket.add(it);
    }
    flush();

    return VigilScaffold(
      title: 'Notifications',
      subtitle: items.isEmpty ? 'ALL CLEAR' : (unread == 0 ? 'ALL READ' : '$unread UNREAD'),
      leading: VigilIconButton(icon: VigilIcons.chevronLeft, semanticLabel: 'Back', onPressed: () => context.canPop() ? context.pop() : context.go('/')),
      body: items.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                const VigilEmblem(size: 40, semanticLabel: ''),
                const SizedBox(height: 14),
                Text('No notifications.', style: t.body.copyWith(color: c.textMuted)),
                const SizedBox(height: 6),
                Text('Reminders, briefings and nudges show here for $kInboxKeepDays days.', style: t.caption.copyWith(color: c.textFaint), textAlign: TextAlign.center),
              ]),
            )
          : ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24), children: <Widget>[
              if (unread > 0)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => markInboxRead(s, items.map((InboxItem it) => it.id)), child: Text('MARK ALL READ', style: t.button.copyWith(fontSize: 11, color: c.signal))),
                ),
              ...children,
              const SizedBox(height: 16),
              Center(child: Text('Swipe a notification to dismiss · kept $kInboxKeepDays days', style: t.micro.copyWith(color: c.textFaint))),
            ]),
    );
  }
}
