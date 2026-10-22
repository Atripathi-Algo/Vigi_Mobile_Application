import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app/env.dart';

class RemoteEvent {
  const RemoteEvent(this.title, this.start, this.end);

  final String title;
  final DateTime start;
  final DateTime end;
}

/// Reads today's events from the Google Calendar REST API using the API key
/// and calendar id in `.env`. An API key only works for public calendars;
/// for a private calendar swap this for an OAuth bearer token (see README).
Future<List<RemoteEvent>?> fetchTodayEvents() async {
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
      'timeMax': start.add(const Duration(days: 1)).toUtc().toIso8601String(),
    },
  );
  try {
    final http.Response r = await http.get(uri).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    final List<dynamic> items = (jsonDecode(r.body) as Map<String, dynamic>)['items'] as List<dynamic>? ?? <dynamic>[];
    return <RemoteEvent>[
      for (final dynamic e in items)
        if ((e as Map<String, dynamic>)['start']?['dateTime'] != null)
          RemoteEvent(
            (e['summary'] as String?) ?? 'Event',
            DateTime.parse(e['start']['dateTime'] as String).toLocal(),
            DateTime.parse(e['end']['dateTime'] as String).toLocal(),
          ),
    ];
  } catch (_) {
    return null;
  }
}
