import 'package:flutter/material.dart';

import '../api/calendar_api.dart';
import '../app/common.dart';
import '../app/fmt.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/calendar_sync.dart';
import '../services/google_accounts.dart';
import '../vigil/vigil.dart';

/// A block made in VIGIL (not pulled from a calendar) that can be sent to a linked Google account.
bool canAddToCalendar(Block b) => b.kind == BlockKind.event && b.id.startsWith('u:') && GoogleAccounts.instance.hasAny;

Future<void> showAddToCalendarSheet(BuildContext context, VigilStore store, Block block) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (BuildContext ctx) => _AddToCalendarSheet(store: store, block: block),
    );

DateTime _blockStart(Block b, int minutes) {
  final List<int> d = (b.dayKey ?? '').split('-').map(int.tryParse).whereType<int>().toList();
  final DateTime day = d.length == 3 ? DateTime(d[0], d[1], d[2]) : DateTime.now();
  return DateTime(day.year, day.month, day.day).add(Duration(minutes: minutes));
}

class _AddToCalendarSheet extends StatefulWidget {
  const _AddToCalendarSheet({required this.store, required this.block});

  final VigilStore store;
  final Block block;

  @override
  State<_AddToCalendarSheet> createState() => _AddToCalendarSheetState();
}

class _AddToCalendarSheetState extends State<_AddToCalendarSheet> {
  int? _busySlot;
  String? _error;

  Future<void> _add(GoogleAccount a) async {
    setState(() {
      _busySlot = a.slot;
      _error = null;
    });
    final GoogleAccounts g = GoogleAccounts.instance;
    final Block b = widget.block;
    final String? token = await g.token(a);
    if (token == null) {
      if (mounted) {
        setState(() {
          _busySlot = null;
          _error = g.noteOf(a) ?? 'Could not sign in to ${a.email}.';
        });
      }
      return;
    }
    try {
      await createCalendarEvent(token, title: b.title, start: _blockStart(b, b.startMin), end: _blockStart(b, b.endMin));
    } on CalendarApiException catch (e) {
      if (mounted) {
        setState(() {
          _busySlot = null;
          _error = e.message;
        });
      }
      return;
    }
    // The event now lives in Google; the next pull brings it back, so drop the local copy rather than show it twice.
    widget.store.removeBlock(b.id);
    await syncCalendars(widget.store);
    if (mounted) {
      Navigator.pop(context);
      showVigilSnack(context, 'Added to ${a.label} calendar');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final Block b = widget.block;
    final List<GoogleAccount> accounts = GoogleAccounts.instance.accounts;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.paddingOf(context).bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text('ADD TO CALENDAR', style: t.h2),
        const SizedBox(height: 8),
        Text(b.title, style: t.rowTitle),
        const SizedBox(height: 2),
        Text('${Fmt.hm(b.startMin)}–${Fmt.hm(b.endMin)}', style: t.meta.copyWith(color: c.textMuted)),
        const SizedBox(height: 6),
        Text('Creates the event in that account\'s Google Calendar and replaces this one.', style: t.caption.copyWith(color: c.textMuted)),
        const SizedBox(height: 14),
        for (final GoogleAccount a in accounts) ...<Widget>[
          VigilButton(
            label: _busySlot == a.slot ? 'Adding…' : '${a.label} · ${a.email}',
            variant: VigilButtonVariant.secondary,
            onPressed: _busySlot != null ? null : () => _add(a),
          ),
          const SizedBox(height: 8),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: 4),
          Semantics(liveRegion: true, child: Text(_error!, style: t.meta.copyWith(color: c.critical, fontSize: 12))),
        ],
      ]),
    );
  }
}
