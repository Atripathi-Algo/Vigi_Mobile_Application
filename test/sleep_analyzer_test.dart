import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/data/models.dart';
import 'package:vigil/data/sleep_analyzer.dart';

void main() {
  group('SleepAnalyzer.nightOf', () {
    test('an evening start belongs to that day', () {
      expect(SleepAnalyzer.nightOf(DateTime(2026, 10, 21, 23, 48)), DateTime(2026, 10, 21));
    });
    test('a start after midnight belongs to the previous evening', () {
      expect(SleepAnalyzer.nightOf(DateTime(2026, 10, 22, 0, 30)), DateTime(2026, 10, 21));
      expect(SleepAnalyzer.nightOf(DateTime(2026, 10, 22, 5, 15)), DateTime(2026, 10, 21));
    });
  });

  group('SleepAnalyzer.nightsFromSessions', () {
    test('a night across midnight uses minutes after the evening midnight', () {
      final List<SleepNight> n = SleepAnalyzer.nightsFromSessions(<RawSleepSession>[
        RawSleepSession(DateTime(2026, 10, 21, 23, 48), DateTime(2026, 10, 22, 7, 0)),
      ]);
      expect(n, hasLength(1));
      expect(n.single.nightOf, DateTime(2026, 10, 21));
      expect(n.single.bed, 23 * 60 + 48); // 1428
      expect(n.single.wake, 1440 + 7 * 60); // 1860
      expect(n.single.asleep, 7 * 60 + 12);
      expect(n.single.label, 'WED');
    });

    test('two sessions in one night merge, and awake time is not counted as sleep', () {
      final List<SleepNight> n = SleepAnalyzer.nightsFromSessions(<RawSleepSession>[
        RawSleepSession(DateTime(2026, 10, 21, 23, 0), DateTime(2026, 10, 22, 3, 0)),
        RawSleepSession(DateTime(2026, 10, 22, 4, 0), DateTime(2026, 10, 22, 7, 0)),
      ]);
      expect(n, hasLength(1));
      expect(n.single.bed, 23 * 60);
      expect(n.single.wake, 1440 + 7 * 60);
      expect(n.single.asleep, 7 * 60); // 4h + 3h, the hour awake is excluded
    });

    test('uses the source asleep minutes when given, never more than the span', () {
      final List<SleepNight> n = SleepAnalyzer.nightsFromSessions(<RawSleepSession>[
        RawSleepSession(DateTime(2026, 10, 21, 23, 0), DateTime(2026, 10, 22, 6, 0), asleepMin: 400),
      ]);
      expect(n.single.asleep, 400);
      final List<SleepNight> capped = SleepAnalyzer.nightsFromSessions(<RawSleepSession>[
        RawSleepSession(DateTime(2026, 10, 21, 23, 0), DateTime(2026, 10, 22, 1, 0), asleepMin: 500),
      ]);
      expect(capped.single.asleep, 120);
    });

    test('daytime naps and tiny fragments are ignored', () {
      final List<SleepNight> n = SleepAnalyzer.nightsFromSessions(<RawSleepSession>[
        RawSleepSession(DateTime(2026, 10, 21, 14, 0), DateTime(2026, 10, 21, 15, 30)),
        RawSleepSession(DateTime(2026, 10, 21, 23, 0), DateTime(2026, 10, 21, 23, 10)),
      ]);
      expect(n, isEmpty);
    });

    test('nights come back newest first', () {
      final List<SleepNight> n = SleepAnalyzer.nightsFromSessions(<RawSleepSession>[
        RawSleepSession(DateTime(2026, 10, 19, 23, 0), DateTime(2026, 10, 20, 7, 0)),
        RawSleepSession(DateTime(2026, 10, 21, 23, 0), DateTime(2026, 10, 22, 7, 0)),
        RawSleepSession(DateTime(2026, 10, 20, 23, 30), DateTime(2026, 10, 21, 6, 30)),
      ]);
      expect(n.map((SleepNight x) => x.nightOf.day).toList(), <int>[21, 20, 19]);
    });
  });

  group('SleepNight JSON', () {
    test('survives a round trip', () {
      final SleepNight a = SleepNight(nightOf: DateTime(2026, 10, 21), bed: 1428, wake: 1860, asleepMin: 410, source: 'health');
      final SleepNight b = SleepNight.fromJson(a.toJson());
      expect(b.nightOf, a.nightOf);
      expect(b.bed, 1428);
      expect(b.wake, 1860);
      expect(b.asleep, 410);
      expect(b.source, 'health');
    });
  });

  group('SleepAnalyzer.bucket', () {
    test('keeps short series and averages long ones', () {
      expect(SleepAnalyzer.bucket(<double>[1, 2, 3], 12), <double>[1, 2, 3]);
      final List<double> b = SleepAnalyzer.bucket(List<double>.generate(24, (int i) => i.toDouble()), 12);
      expect(b, hasLength(12));
      expect(b.first, 0.5);
      expect(b.last, 22.5);
    });
    test('handles empty input', () {
      expect(SleepAnalyzer.bucket(<double>[], 12), isEmpty);
    });
  });

  group('SleepAnalyzer.awakeOverlap', () {
    final DateTime start = DateTime(2026, 10, 21, 23, 0);
    final DateTime end = DateTime(2026, 10, 22, 7, 0);

    test('sums awake stages inside the session', () {
      final int m = SleepAnalyzer.awakeOverlap(start, end, <({DateTime from, DateTime to})>[
        (from: DateTime(2026, 10, 22, 2, 0), to: DateTime(2026, 10, 22, 2, 30)),
        (from: DateTime(2026, 10, 22, 4, 0), to: DateTime(2026, 10, 22, 4, 15)),
      ]);
      expect(m, 45);
    });

    test('clips stages that run outside the session and ignores ones entirely outside', () {
      final int m = SleepAnalyzer.awakeOverlap(start, end, <({DateTime from, DateTime to})>[
        (from: DateTime(2026, 10, 21, 22, 30), to: DateTime(2026, 10, 21, 23, 15)), // 15 min inside
        (from: DateTime(2026, 10, 22, 6, 50), to: DateTime(2026, 10, 22, 7, 20)), // 10 min inside
        (from: DateTime(2026, 10, 21, 20, 0), to: DateTime(2026, 10, 21, 21, 0)), // outside
      ]);
      expect(m, 25);
    });

    test('counts overlapping stages once', () {
      final int m = SleepAnalyzer.awakeOverlap(start, end, <({DateTime from, DateTime to})>[
        (from: DateTime(2026, 10, 22, 2, 0), to: DateTime(2026, 10, 22, 2, 40)),
        (from: DateTime(2026, 10, 22, 2, 20), to: DateTime(2026, 10, 22, 3, 0)),
      ]);
      expect(m, 60);
    });

    test('no stages means no awake time', () {
      expect(SleepAnalyzer.awakeOverlap(start, end, <({DateTime from, DateTime to})>[]), 0);
    });
  });
}
