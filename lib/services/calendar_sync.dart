import '../api/calendar_api.dart';
import '../data/store.dart';

/// Pull today's events into the Timeline. Returns false if no key is set or
/// the request failed (the Timeline then keeps what it had).
Future<bool> pullCalendar(VigilStore s) async {
  final List<RemoteEvent>? ev = await fetchTodayEvents();
  if (ev == null) return false;
  s.mergeRemoteEvents(ev);
  s.setLink('Calendar link', 'OK');
  return true;
}
