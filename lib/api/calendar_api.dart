import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app/env.dart';
import 'api_error.dart';

/// One calendar event. [account] names where it came from (a linked account's label, or PUBLIC for the
/// API-key calendar); after [dedupeEvents] it can list several, joined by `+`.
class RemoteEvent {
  const RemoteEvent(this.title, this.start, this.end, {this.uid, this.account});

  final String title;
  final DateTime start;
  final DateTime end;

  /// The event's iCalUID: the same meeting has the same uid in every account it was sent to.
  final String? uid;
  final String? account;

  RemoteEvent from(String source) => RemoteEvent(title, start, end, uid: uid, account: source);
}

class CalendarApiException implements Exception {
  const CalendarApiException(this.status, this.message);

  final int? status;
  final String message;

  @override
  String toString() => message;
}

/// Timed events from a Calendar API `events.list` body. All-day events are left out, and so are
/// cancelled events and ones the user declined, so they never show up as conflicts.
List<RemoteEvent> parseCalendarEvents(String body, {String? account}) {
  final List<dynamic> items = (jsonDecode(body) as Map<String, dynamic>)['items'] as List<dynamic>? ?? <dynamic>[];
  final List<RemoteEvent> out = <RemoteEvent>[];
  for (final dynamic raw in items) {
    final Map<String, dynamic> e = raw as Map<String, dynamic>;
    final String? start = (e['start'] as Map<String, dynamic>?)?['dateTime'] as String?;
    final String? end = (e['end'] as Map<String, dynamic>?)?['dateTime'] as String?;
    if (start == null || end == null || e['status'] == 'cancelled') continue;
    final List<dynamic> attendees = e['attendees'] as List<dynamic>? ?? <dynamic>[];
    final bool declined = attendees.any((dynamic a) => a is Map<String, dynamic> && a['self'] == true && a['responseStatus'] == 'declined');
    if (declined) continue;
    out.add(RemoteEvent(
      (e['summary'] as String?) ?? 'Event',
      DateTime.parse(start).toLocal(),
      DateTime.parse(end).toLocal(),
      uid: e['iCalUID'] as String?,
      account: account,
    ));
  }
  return out;
}

/// One entry per meeting: the same event in two accounts (matching uid, or title and times when there is
/// none) is kept once and tagged with both accounts, so it never reads as a conflict with itself.
List<RemoteEvent> dedupeEvents(List<RemoteEvent> events) {
  final Map<String, RemoteEvent> seen = <String, RemoteEvent>{};
  for (final RemoteEvent e in events) {
    final String key = e.uid ?? '${e.title}|${e.start.toIso8601String()}|${e.end.toIso8601String()}';
    final RemoteEvent? prior = seen[key];
    if (prior == null) {
      seen[key] = e;
      continue;
    }
    final List<String> accounts = <String>{...?prior.account?.split('+'), ...?e.account?.split('+')}.toList();
    seen[key] = RemoteEvent(prior.title, prior.start, prior.end, uid: prior.uid, account: accounts.isEmpty ? null : accounts.join('+'));
  }
  return seen.values.toList()..sort((RemoteEvent a, RemoteEvent b) => a.start.compareTo(b.start));
}

Map<String, String> _bearer(String token) => <String, String>{'authorization': 'Bearer $token', 'accept': 'application/json'};

/// Events on [day] (local) from the primary calendar of the account that [token] belongs to.
Future<List<RemoteEvent>> fetchAccountEvents(String token, DateTime day, {String? account, http.Client? client}) async {
  final DateTime start = DateTime(day.year, day.month, day.day);
  final Uri uri = Uri.https('www.googleapis.com', '/calendar/v3/calendars/primary/events', <String, String>{
    'singleEvents': 'true',
    'orderBy': 'startTime',
    'maxResults': '100',
    'timeMin': start.toUtc().toIso8601String(),
    'timeMax': DateTime(start.year, start.month, start.day + 1).toUtc().toIso8601String(),
  });
  final http.Client c = client ?? http.Client();
  try {
    final http.Response r = await c.get(uri, headers: _bearer(token)).timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) throw CalendarApiException(r.statusCode, 'HTTP ${r.statusCode}: ${apiErrorMessage(r.body)}');
    return parseCalendarEvents(r.body, account: account);
  } on CalendarApiException {
    rethrow;
  } on TimeoutException {
    throw const CalendarApiException(null, 'Timed out after 12 seconds.');
  } catch (e) {
    throw CalendarApiException(null, 'Could not reach Google: ${e.toString().split('\n').first}');
  } finally {
    if (client == null) c.close();
  }
}

/// Adds a timed event to the primary calendar of the account that [token] belongs to. Returns its id.
Future<String> createCalendarEvent(String token, {required String title, required DateTime start, required DateTime end, http.Client? client}) async {
  final Uri uri = Uri.https('www.googleapis.com', '/calendar/v3/calendars/primary/events');
  final http.Client c = client ?? http.Client();
  try {
    final http.Response r = await c
        .post(
          uri,
          headers: <String, String>{..._bearer(token), 'content-type': 'application/json'},
          body: jsonEncode(<String, dynamic>{
            'summary': title,
            'start': <String, String>{'dateTime': start.toUtc().toIso8601String()},
            'end': <String, String>{'dateTime': end.toUtc().toIso8601String()},
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) throw CalendarApiException(r.statusCode, 'HTTP ${r.statusCode}: ${apiErrorMessage(r.body)}');
    return (jsonDecode(r.body) as Map<String, dynamic>)['id'] as String? ?? '';
  } on CalendarApiException {
    rethrow;
  } on TimeoutException {
    throw const CalendarApiException(null, 'Timed out after 12 seconds.');
  } catch (e) {
    throw CalendarApiException(null, 'Could not reach Google: ${e.toString().split('\n').first}');
  } finally {
    if (client == null) c.close();
  }
}

/// Reads today's events from the Google Calendar REST API using the API key
/// and calendar id in `.env`. An API key only works for public calendars;
/// private calendars come in through linked Google accounts (Loadout).
Future<List<RemoteEvent>?> fetchTodayEvents({http.Client? client}) async {
  if (!Env.hasCalendar) return null;
  final DateTime now = DateTime.now();
  final DateTime start = DateTime(now.year, now.month, now.day);
  final Uri uri = Uri.https(
    'www.googleapis.com',
    '/calendar/v3/calendars/${Uri.encodeComponent(Env.googleCalendarId)}/events',
    <String, String>{
      'key': Env.googleCalendarApiKey,
      'singleEvents': 'true',
      'orderBy': 'startTime',
      'timeMin': start.toUtc().toIso8601String(),
      'timeMax': DateTime(start.year, start.month, start.day + 1).toUtc().toIso8601String(),
    },
  );
  final http.Client c = client ?? http.Client();
  try {
    final http.Response r = await c.get(uri).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    return parseCalendarEvents(r.body);
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}
