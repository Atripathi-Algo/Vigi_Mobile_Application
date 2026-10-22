import 'package:http/http.dart' as http;

import '../api/calendar_api.dart';
import '../app/env.dart';
import '../data/store.dart';
import 'google_accounts.dart';

/// What one pass over every calendar source found.
class CalendarSyncResult {
  const CalendarSyncResult({required this.sources, required this.errors, required this.events, this.keyOk});

  /// Sources tried: the public API-key calendar (if set) plus each linked account.
  final int sources;

  /// Source label to what went wrong.
  final Map<String, String> errors;

  /// Events merged into today's Timeline.
  final int events;

  /// The API-key calendar: null if not set up, else whether it was read.
  final bool? keyOk;

  bool get anyOk => sources > errors.length;

  String get summary {
    if (sources == 0) return 'No calendar linked.';
    final String ok = 'Merged $events event${events == 1 ? '' : 's'} from ${sources - errors.length} of $sources calendar${sources == 1 ? '' : 's'}.';
    return errors.isEmpty ? ok : '$ok ${errors.entries.map((MapEntry<String, String> e) => '${e.key}: ${e.value}').join(' ')}';
  }
}

/// Pull today's events from every source (the public calendar and both linked accounts), drop the
/// duplicates, and merge them into the Timeline. A source that fails keeps its last known events.
/// Nothing changes when every source fails, so the Timeline keeps what it had.
Future<CalendarSyncResult> syncCalendars(VigilStore s, {GoogleAccounts? accounts, http.Client? client, DateTime? now}) async {
  final GoogleAccounts acc = accounts ?? GoogleAccounts.instance;
  final DateTime n = now ?? DateTime.now();
  final DateTime day = DateTime(n.year, n.month, n.day);
  final List<RemoteEvent> events = <RemoteEvent>[];
  final Map<String, String> errors = <String, String>{};
  int sources = 0;
  bool? keyOk;

  if (Env.hasCalendar) {
    sources++;
    final List<RemoteEvent>? ev = await fetchTodayEvents(client: client);
    keyOk = ev != null;
    if (ev == null) {
      errors['PUBLIC'] = 'Check the calendar key and id.';
    } else {
      events.addAll(ev.map((RemoteEvent e) => e.from('PUBLIC')));
    }
  }

  for (final GoogleAccount a in acc.accounts) {
    sources++;
    final String? token = await acc.token(a);
    if (token == null) {
      errors[a.label] = acc.noteOf(a) ?? 'Could not sign in.';
      continue;
    }
    try {
      events.addAll(await fetchAccountEvents(token, day, account: a.label, client: client));
      acc.markOk(a);
    } on CalendarApiException catch (e) {
      errors[a.label] = e.message;
      acc.markProblem(a, e.message);
    }
  }

  final List<RemoteEvent> merged = dedupeEvents(events);
  if (sources > errors.length) {
    s.mergeRemoteEvents(merged, failedSources: errors.keys.toSet(), now: n);
    s.setLink('Calendar link', 'OK');
  }
  return CalendarSyncResult(sources: sources, errors: errors, events: sources > errors.length ? merged.length : 0, keyOk: keyOk);
}

/// Pull the public API-key calendar. True if it was read; the Timeline also picks up linked accounts.
Future<bool> pullCalendar(VigilStore s) async => (await syncCalendars(s)).keyOk ?? false;
