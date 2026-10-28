// The Garage: up to two bikes, their fill-ups, mileage, cost and service reminders. Pure logic with no storage, so it
// can be tested on its own; VigilStore keeps the lists and saves them.

enum ReminderKind { service, oil, chain, tyres, insurance, puc, battery, custom }

extension ReminderKindText on ReminderKind {
  String get label => switch (this) {
        ReminderKind.service => 'Service',
        ReminderKind.oil => 'Engine oil',
        ReminderKind.chain => 'Chain lube & clean',
        ReminderKind.tyres => 'Tyre pressure',
        ReminderKind.insurance => 'Insurance',
        ReminderKind.puc => 'PUC certificate',
        ReminderKind.battery => 'Battery check',
        ReminderKind.custom => 'Custom',
      };

  /// Insurance and PUC are papers with a "valid till" date, not something done every N km.
  bool get isPaper => this == ReminderKind.insurance || this == ReminderKind.puc;
}

/// How a reminder falls due: by distance, by date, or whichever comes first.
enum ReminderMode { km, date, both }

enum DueLevel { ok, soon, overdue }

String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime? _parseDay(Object? v) => v is String ? DateTime.tryParse(v) : null;
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class Reminder {
  Reminder({
    required this.id,
    required this.kind,
    this.label,
    this.mode = ReminderMode.km,
    this.everyKm,
    this.everyDays,
    this.lastKm,
    this.lastDate,
    this.dueDate,
    this.headsUpKm = 300,
  });

  final String id;
  ReminderKind kind;

  /// The name of a custom reminder.
  String? label;
  ReminderMode mode;
  int? everyKm;
  int? everyDays;

  /// When and where it was last done.
  int? lastKm;
  DateTime? lastDate;

  /// A fixed date, for papers: "valid till".
  DateTime? dueDate;

  /// How early a distance reminder warns.
  int headsUpKm;

  String get title => kind == ReminderKind.custom ? ((label ?? '').trim().isEmpty ? 'Custom reminder' : label!.trim()) : kind.label;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind.name,
        if (label != null) 'label': label,
        'mode': mode.name,
        if (everyKm != null) 'everyKm': everyKm,
        if (everyDays != null) 'everyDays': everyDays,
        if (lastKm != null) 'lastKm': lastKm,
        if (lastDate != null) 'lastDate': _day(lastDate!),
        if (dueDate != null) 'dueDate': _day(dueDate!),
        'headsUpKm': headsUpKm,
      };

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        id: j['id'] as String,
        kind: ReminderKind.values.firstWhere((ReminderKind k) => k.name == j['kind'], orElse: () => ReminderKind.custom),
        label: j['label'] as String?,
        mode: ReminderMode.values.firstWhere((ReminderMode m) => m.name == j['mode'], orElse: () => ReminderMode.km),
        everyKm: (j['everyKm'] as num?)?.toInt(),
        everyDays: (j['everyDays'] as num?)?.toInt(),
        lastKm: (j['lastKm'] as num?)?.toInt(),
        lastDate: _parseDay(j['lastDate']),
        dueDate: _parseDay(j['dueDate']),
        headsUpKm: (j['headsUpKm'] as num?)?.toInt() ?? 300,
      );
}

/// Where a reminder stands: what is left, and whether it is due.
class DueStatus {
  const DueStatus({required this.level, this.kmLeft, this.daysLeft, required this.fraction});

  final DueLevel level;

  /// Negative when overdue.
  final int? kmLeft;
  final int? daysLeft;

  /// 0 (just done) to 1 (due) and beyond.
  final double fraction;
}

DueStatus dueStatus(Reminder r, int odometer, DateTime today) {
  final DateTime t = dateOnly(today);
  int? kmLeft;
  double kmFraction = 0;
  final bool useKm = r.mode != ReminderMode.date;
  if (useKm && r.everyKm != null && r.everyKm! > 0) {
    final int next = (r.lastKm ?? odometer) + r.everyKm!;
    kmLeft = next - odometer;
    kmFraction = (r.everyKm! - kmLeft) / r.everyKm!;
  }
  int? daysLeft;
  double dayFraction = 0;
  final bool useDate = r.mode != ReminderMode.km || r.kind.isPaper;
  if (useDate) {
    DateTime? next = r.dueDate;
    int span = 365;
    if (next == null && r.lastDate != null && r.everyDays != null && r.everyDays! > 0) {
      next = dateOnly(r.lastDate!).add(Duration(days: r.everyDays!));
      span = r.everyDays!;
    }
    if (next != null) {
      daysLeft = next.difference(t).inDays;
      dayFraction = (span - daysLeft) / span;
    }
  }
  // A reminder that repeats often (every 14 days) warns later than a paper that expires once a year.
  final int soonDays = r.everyDays != null && r.dueDate == null ? (r.everyDays! ~/ 2).clamp(1, 14) : 14;
  final bool overdue = (kmLeft != null && kmLeft < 0) || (daysLeft != null && daysLeft < 0);
  final bool soon = (kmLeft != null && kmLeft <= r.headsUpKm) || (daysLeft != null && daysLeft <= soonDays);
  return DueStatus(
    level: overdue ? DueLevel.overdue : (soon ? DueLevel.soon : DueLevel.ok),
    kmLeft: kmLeft,
    daysLeft: daysLeft,
    fraction: (kmFraction > dayFraction ? kmFraction : dayFraction).clamp(0.0, 1.5),
  );
}

/// 4642 -> 4,642.
String kmText(int v) => v.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (Match m) => '${m[1]},');

/// Paise per km or per litre as rupees with two decimals: 293.4 -> ₹2.93.
String rupees2(double paise) => '₹${(paise / 100).toStringAsFixed(2)}';

/// What the reminder says in a line: "138 km", "13 days", "Overdue".
String dueText(DueStatus s) {
  if (s.level == DueLevel.overdue) return 'Overdue';
  final List<String> p = <String>[
    if (s.kmLeft != null) '${kmText(s.kmLeft!)} km',
    if (s.daysLeft != null) s.daysLeft == 0 ? 'Today' : '${s.daysLeft} days',
  ];
  if (p.isEmpty) return '';
  // When both are known, the nearer one is the one that matters.
  if (p.length == 2) return s.kmLeft! <= (s.daysLeft! * 30) ? p[0] : p[1];
  return p.first;
}

class Bike {
  Bike({required this.id, required this.make, required this.model, required this.tankL, this.odometer = 0, List<Reminder>? reminders}) : reminders = reminders ?? <Reminder>[];

  final String id;
  String make;
  String model;
  double tankL;

  /// The latest reading, in km.
  int odometer;
  List<Reminder> reminders;

  String get name => model.trim().isEmpty ? make : model.trim();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'make': make,
        'model': model,
        'tankL': tankL,
        'odometer': odometer,
        'reminders': <Map<String, dynamic>>[for (final Reminder r in reminders) r.toJson()],
      };

  factory Bike.fromJson(Map<String, dynamic> j) => Bike(
        id: j['id'] as String,
        make: (j['make'] as String?) ?? '',
        model: (j['model'] as String?) ?? '',
        tankL: (j['tankL'] as num?)?.toDouble() ?? 12,
        odometer: (j['odometer'] as num?)?.toInt() ?? 0,
        reminders: <Reminder>[for (final dynamic r in (j['reminders'] as List<dynamic>? ?? <dynamic>[])) Reminder.fromJson(r as Map<String, dynamic>)],
      );

  /// The reminders a new bike starts with: easy to edit, easy to delete.
  static List<Reminder> defaultReminders({required String Function() newId, required int odometer, required int serviceEveryKm, DateTime? insuranceUntil, DateTime? pucUntil, required DateTime today}) => <Reminder>[
        Reminder(id: newId(), kind: ReminderKind.chain, everyKm: 500, lastKm: odometer, headsUpKm: 100),
        Reminder(id: newId(), kind: ReminderKind.service, mode: ReminderMode.both, everyKm: serviceEveryKm, everyDays: 365, lastKm: odometer, lastDate: dateOnly(today)),
        Reminder(id: newId(), kind: ReminderKind.tyres, mode: ReminderMode.date, everyDays: 14, lastDate: dateOnly(today)),
        if (insuranceUntil != null) Reminder(id: newId(), kind: ReminderKind.insurance, mode: ReminderMode.date, dueDate: dateOnly(insuranceUntil)),
        if (pucUntil != null) Reminder(id: newId(), kind: ReminderKind.puc, mode: ReminderMode.date, dueDate: dateOnly(pucUntil)),
      ];
}

class FillUp {
  FillUp({required this.id, required this.bikeId, required this.day, required this.odometer, required this.litres, required this.totalPaise, this.full = true});

  final String id;
  final String bikeId;
  final DateTime day;

  /// The odometer reading at the pump, in km.
  final int odometer;
  final double litres;
  final int totalPaise;

  /// Mileage is measured between full tanks.
  final bool full;

  double get pricePerLitrePaise => litres <= 0 ? 0 : totalPaise / litres;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'bikeId': bikeId,
        'day': _day(day),
        'odometer': odometer,
        'litres': litres,
        'totalPaise': totalPaise,
        'full': full,
      };

  factory FillUp.fromJson(Map<String, dynamic> j) => FillUp(
        id: j['id'] as String,
        bikeId: j['bikeId'] as String,
        day: _parseDay(j['day']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        odometer: (j['odometer'] as num).toInt(),
        litres: (j['litres'] as num).toDouble(),
        totalPaise: (j['totalPaise'] as num).toInt(),
        full: (j['full'] as bool?) ?? true,
      );
}

/// One measured stretch between two full tanks.
class MileagePoint {
  const MileagePoint({required this.fill, required this.km, required this.litres, required this.paise});

  /// The fill-up that closed the stretch.
  final FillUp fill;
  final int km;
  final double litres;
  final int paise;

  double get kmPerLitre => km / litres;
}

class BikeStats {
  const BikeStats({required this.points, required this.avgKmPerLitre, required this.paisePerKm, required this.sinceLastFillKm, required this.litresLeft, required this.rangeKm});

  /// Oldest first.
  final List<MileagePoint> points;
  final double? avgKmPerLitre;
  final double? paisePerKm;
  final int? sinceLastFillKm;
  final double? litresLeft;
  final int? rangeKm;

  MileagePoint? get last => points.isEmpty ? null : points.last;

  /// Mileage is measured from full tank to full tank: the distance between two full fill-ups divided by every litre
  /// put in since the first of them (partial fills in between count), so a partial fill never distorts it.
  static BikeStats of(Bike bike, Iterable<FillUp> fillups) {
    final List<FillUp> fills = fillups.where((FillUp f) => f.bikeId == bike.id).toList()..sort((FillUp a, FillUp b) => a.odometer.compareTo(b.odometer));
    final List<MileagePoint> points = <MileagePoint>[];
    int? prevFull;
    for (int i = 0; i < fills.length; i++) {
      if (!fills[i].full) continue;
      if (prevFull != null) {
        final int km = fills[i].odometer - fills[prevFull].odometer;
        double litres = 0;
        int paise = 0;
        for (int k = prevFull + 1; k <= i; k++) {
          litres += fills[k].litres;
          paise += fills[k].totalPaise;
        }
        if (km > 0 && litres > 0) points.add(MileagePoint(fill: fills[i], km: km, litres: litres, paise: paise));
      }
      prevFull = i;
    }
    final int totalKm = points.fold(0, (int a, MileagePoint p) => a + p.km);
    final double totalLitres = points.fold(0.0, (double a, MileagePoint p) => a + p.litres);
    final int totalPaise = points.fold(0, (int a, MileagePoint p) => a + p.paise);
    final double? avg = totalLitres > 0 ? totalKm / totalLitres : null;
    final int? since = fills.isEmpty ? null : (bike.odometer - fills.last.odometer).clamp(0, 1 << 30);
    double? left;
    int? range;
    if (avg != null && since != null && bike.tankL > 0) {
      left = (bike.tankL - since / avg).clamp(0.0, bike.tankL);
      range = (left * avg).round();
    }
    return BikeStats(points: points, avgKmPerLitre: avg, paisePerKm: totalKm > 0 ? totalPaise / totalKm : null, sinceLastFillKm: since, litresLeft: left, rangeKm: range);
  }
}

/// How a tank that is about to be saved compares: "32.5 km/l, 6 % below your 34.6 average". Null when it cannot be
/// measured (not a full tank, no earlier full tank, or no distance).
({double kmPerLitre, int km, double? vsAveragePercent})? previewMileage(Bike bike, List<FillUp> existing, {required int odometer, required double litres, required bool full}) {
  if (!full || litres <= 0) return null;
  final FillUp probe = FillUp(id: 'preview', bikeId: bike.id, day: DateTime.now(), odometer: odometer, litres: litres, totalPaise: 0, full: true);
  final BikeStats before = BikeStats.of(bike, existing);
  final BikeStats after = BikeStats.of(bike, <FillUp>[...existing, probe]);
  final MileagePoint? p = after.points.where((MileagePoint x) => x.fill.id == 'preview').firstOrNull;
  if (p == null) return null;
  final double? avg = before.avgKmPerLitre;
  return (kmPerLitre: p.kmPerLitre, km: p.km, vsAveragePercent: avg == null ? null : (p.kmPerLitre - avg) / avg * 100);
}
