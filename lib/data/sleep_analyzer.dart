import 'models.dart';

/// One sleep session as reported by a source (Health Connect, or a manual entry).
class RawSleepSession {
  const RawSleepSession(this.start, this.end, {this.asleepMin});

  final DateTime start;
  final DateTime end;

  /// Minutes actually asleep, if the source reports it (otherwise the whole span counts).
  final int? asleepMin;
}

/// Pure functions that turn raw sessions into per-night records. No I/O, so
/// they are unit-tested directly (test/sleep_analyzer_test.dart).
abstract final class SleepAnalyzer {
  /// The calendar date of the evening a night started. A session beginning at
  /// 23:48 on Wed and one beginning at 00:30 on Thu both belong to Wed's night.
  static DateTime nightOf(DateTime start) {
    final DateTime d = start.subtract(const Duration(hours: 12));
    return DateTime(d.year, d.month, d.day);
  }

  /// Minutes of [t] on the clock of [nightOf]'s midnight: 23:00 is 1380, 01:00 next day is 1500.
  /// Calendar arithmetic, so it stays right across a daylight-saving change.
  static int wallMinutes(DateTime t, DateTime nightOf) {
    final int days = DateTime.utc(t.year, t.month, t.day).difference(DateTime.utc(nightOf.year, nightOf.month, nightOf.day)).inDays;
    return days * 1440 + t.hour * 60 + t.minute;
  }

  /// Group sessions into nights, newest first. Daytime naps (starting 10:00 to
  /// 17:59) and fragments under 20 minutes are ignored; several sessions in
  /// the same night are merged (earliest start, latest end, summed sleep).
  static List<SleepNight> nightsFromSessions(Iterable<RawSleepSession> sessions, {String source = 'health'}) {
    final Map<DateTime, List<RawSleepSession>> byNight = <DateTime, List<RawSleepSession>>{};
    for (final RawSleepSession s in sessions) {
      final int span = s.end.difference(s.start).inMinutes;
      if (span < 20) continue;
      if (s.start.hour >= 10 && s.start.hour < 18) continue;
      byNight.putIfAbsent(nightOf(s.start), () => <RawSleepSession>[]).add(s);
    }
    final List<SleepNight> out = <SleepNight>[];
    byNight.forEach((DateTime night, List<RawSleepSession> list) {
      DateTime start = list.first.start;
      DateTime end = list.first.end;
      int asleep = 0;
      for (final RawSleepSession s in list) {
        if (s.start.isBefore(start)) start = s.start;
        if (s.end.isAfter(end)) end = s.end;
        asleep += s.asleepMin ?? s.end.difference(s.start).inMinutes;
      }
      final int bed = wallMinutes(start, night);
      final int wake = wallMinutes(end, night);
      out.add(SleepNight(nightOf: night, bed: bed, wake: wake, asleepMin: asleep.clamp(0, wake - bed), source: source));
    });
    out.sort((SleepNight a, SleepNight b) => b.nightOf.compareTo(a.nightOf));
    return out;
  }

  /// Minutes of the span [start, end] covered by [awake] intervals (clipped to
  /// the span, overlaps counted once).
  static int awakeOverlap(DateTime start, DateTime end, Iterable<({DateTime from, DateTime to})> awake) {
    final List<({DateTime from, DateTime to})> clipped = <({DateTime from, DateTime to})>[];
    for (final ({DateTime from, DateTime to}) a in awake) {
      final DateTime f = a.from.isBefore(start) ? start : a.from;
      final DateTime t = a.to.isAfter(end) ? end : a.to;
      if (t.isAfter(f)) clipped.add((from: f, to: t));
    }
    clipped.sort((a, b) => a.from.compareTo(b.from));
    int total = 0;
    DateTime? curFrom;
    DateTime? curTo;
    for (final ({DateTime from, DateTime to}) c in clipped) {
      if (curTo == null || c.from.isAfter(curTo)) {
        if (curFrom != null) total += curTo!.difference(curFrom).inMinutes;
        curFrom = c.from;
        curTo = c.to;
      } else if (c.to.isAfter(curTo)) {
        curTo = c.to;
      }
    }
    if (curFrom != null) total += curTo!.difference(curFrom).inMinutes;
    return total;
  }

  /// Bucket [points] (oldest first) into at most [buckets] averages for a sparkline.
  static List<double> bucket(List<double> points, int buckets) {
    if (points.isEmpty) return const <double>[];
    if (points.length <= buckets) return List<double>.of(points);
    final List<double> out = <double>[];
    for (int i = 0; i < buckets; i++) {
      final int a = (i * points.length / buckets).floor();
      final int b = ((i + 1) * points.length / buckets).floor().clamp(a + 1, points.length);
      final List<double> slice = points.sublist(a, b);
      out.add(slice.reduce((double x, double y) => x + y) / slice.length);
    }
    return out;
  }
}
