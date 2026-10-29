import 'garage.dart';
import 'models.dart';
import 'store.dart';

/// The Sunday review: the last seven days at a glance, built from what is on the phone. No model, no network.
class WeeklyReview {
  const WeeklyReview({
    required this.tasksDone,
    required this.tasksOpen,
    required this.consistency,
    required this.bestHabit,
    required this.bestStreak,
    required this.spentPaise,
    required this.spentBeforePaise,
    required this.fuelPaise,
    required this.fuelLitres,
  });

  final int tasksDone;
  final int tasksOpen;

  /// Whole percent of habit-days done over the week (only the days each habit has existed).
  final int consistency;
  final String? bestHabit;
  final int bestStreak;
  final int spentPaise;

  /// The week before, for comparison.
  final int spentBeforePaise;
  final int fuelPaise;
  final double fuelLitres;

  /// Anything worth showing: a week with nothing in it gets no card.
  bool get hasAnything => tasksDone > 0 || spentPaise > 0 || fuelPaise > 0 || bestStreak > 1 || consistency > 0;
}

/// The review for the seven days up to and including [now].
WeeklyReview weeklyReview(VigilStore s, DateTime now) {
  final DateTime end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  final DateTime start = end.subtract(const Duration(days: 7));
  final DateTime before = start.subtract(const Duration(days: 7));
  bool within(DateTime d, DateTime a, DateTime b) => !d.isBefore(a) && d.isBefore(b);

  final int tasksDone = s.objectives.where((Objective o) {
    final int? at = o.doneAt;
    return o.done && at != null && within(DateTime.fromMillisecondsSinceEpoch(at), start, end);
  }).length;

  int spent(DateTime a, DateTime b) => s.txns.where((Txn t) => within(t.at, a, b)).fold(0, (int sum, Txn t) => sum + t.paise);

  Protocol? best;
  for (final Protocol p in s.protocols) {
    if (best == null || p.streakNow > best.streakNow) best = p;
  }

  final List<FillUp> fills = s.fillups.where((FillUp f) => within(f.day, start, end)).toList();
  return WeeklyReview(
    tasksDone: tasksDone,
    tasksOpen: s.open.length,
    consistency: s.consistencyPercent,
    bestHabit: best?.name,
    bestStreak: best?.streakNow ?? 0,
    spentPaise: spent(start, end),
    spentBeforePaise: spent(before, start),
    fuelPaise: fills.fold(0, (int sum, FillUp f) => sum + f.totalPaise),
    fuelLitres: fills.fold(0.0, (double sum, FillUp f) => sum + f.litres),
  );
}
