import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/brand.dart';
import '../app/common.dart';
import '../app/fmt.dart';
import '../app/providers.dart';
import '../data/garage.dart';
import '../data/store.dart';
import '../vigil/vigil.dart';
import 'data_sheets.dart';

const List<String> _months = <String>['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

String _date(DateTime d) => '${d.day} ${_months[d.month - 1]}';
String _dateYear(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
String _km(int v) => kmText(v);
String _l(double v) => v.toStringAsFixed(1);
String _rs(num paise) => Fmt.money(paise.round());

Color _levelColor(BuildContext context, DueLevel l) => switch (l) {
      DueLevel.overdue => context.vigil.critical,
      DueLevel.soon => VigilPalette.warning,
      DueLevel.ok => context.vigil.textMuted,
    };

int? _int(String s) => int.tryParse(s.trim().replaceAll(',', ''));
double? _double(String s) => double.tryParse(s.trim().replaceAll(',', ''));

// =============================================================================================== the list (inside Ops)

/// The Garage tab: the bikes, the month's fuel, and a way to add a bike or a fill-up.
class GarageView extends ConsumerWidget {
  const GarageView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vigil;
    final t = context.vtype;
    final VigilStore s = ref.watch(storeProvider);
    if (s.bikes.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text('GARAGE EMPTY', style: t.micro.copyWith(color: c.signal)),
            const SizedBox(height: 6),
            Text('No bikes in the garage.', style: t.h2),
            const SizedBox(height: 8),
            Text('Add a bike to track fuel, mileage, service and papers. Up to ${VigilStore.kMaxBikes} bikes.', style: t.body.copyWith(color: c.textMuted), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            VigilButton(label: 'Add bike', icon: VigilIcons.plus, onPressed: () => showAddBikeSheet(context, s)),
            const SizedBox(height: 16),
            Text('Later, just tell me: "Filled 10 litres in the Meteor for ₹1,050 at 9,412." I\'ll log it as an expense and update the mileage.', style: t.caption.copyWith(color: c.textFaint), textAlign: TextAlign.center),
          ]),
        ),
      );
    }
    final DateTime now = DateTime.now();
    int overdue = 0;
    int soon = 0;
    for (final Bike b in s.bikes) {
      for (final Reminder r in b.reminders) {
        final DueLevel l = dueStatus(r, b.odometer, now).level;
        if (l == DueLevel.overdue) overdue++;
        if (l == DueLevel.soon) soon++;
      }
    }
    final ({double litres, int paise}) fuel = s.fuelThisMonth(now);
    const List<String> longMonths = <String>['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return ListView(padding: EdgeInsets.only(bottom: tabBottomPad(context)), children: <Widget>[
      Row(children: <Widget>[
        Expanded(
          child: Text.rich(TextSpan(style: t.caption.copyWith(color: c.textMuted), children: <InlineSpan>[
            TextSpan(text: '${s.bikes.length} ${s.bikes.length == 1 ? 'bike' : 'bikes'}', style: TextStyle(color: c.text)),
            if (overdue > 0) TextSpan(text: ' · $overdue overdue', style: TextStyle(color: c.critical)),
            if (soon > 0) TextSpan(text: ' · $soon due soon'),
          ])),
        ),
      ]),
      const SizedBox(height: 10),
      for (final Bike b in s.bikes) ...<Widget>[
        _BikeCard(bike: b),
        const SizedBox(height: 10),
      ],
      VigilCard(
        child: Row(children: <Widget>[
          Icon(Icons.local_gas_station_outlined, size: 22, color: c.signal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('${longMonths[now.month - 1].toUpperCase()} FUEL · ${s.bikes.length == 1 ? s.bikes.first.name.toUpperCase() : 'BOTH BIKES'}', style: t.micro.copyWith(color: c.textFaint)),
              const SizedBox(height: 2),
              Text(fuel.litres == 0 ? 'No fill-ups yet this month' : '${_l(fuel.litres)} L · ${_rs(fuel.paise)} · counted in Vault › Transport', style: t.caption.copyWith(color: c.textMuted)),
            ]),
          ),
          VigilButton(label: 'Fill-up', icon: VigilIcons.plus, onPressed: () => showFillUpSheet(context, s)),
        ]),
      ),
      if (s.bikes.length < VigilStore.kMaxBikes) ...<Widget>[
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerLeft, child: VigilButton(label: 'Add bike', variant: VigilButtonVariant.secondary, icon: VigilIcons.plus, onPressed: () => showAddBikeSheet(context, s))),
      ],
    ]);
  }
}

class _BikeCard extends ConsumerWidget {
  const _BikeCard({required this.bike});

  final Bike bike;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vigil;
    final t = context.vtype;
    final VigilStore s = ref.watch(storeProvider);
    final DateTime now = DateTime.now();
    final BikeStats st = BikeStats.of(bike, s.fillups);
    final List<({Reminder r, DueStatus d})> due = <({Reminder r, DueStatus d})>[for (final Reminder r in bike.reminders) (r: r, d: dueStatus(r, bike.odometer, now))]..sort((a, b) => b.d.fraction.compareTo(a.d.fraction));
    final bool anyOverdue = due.any((x) => x.d.level == DueLevel.overdue);
    final List<MileagePoint> pts = st.points.length > 8 ? st.points.sublist(st.points.length - 8) : st.points;
    Widget stat(String label, String value, String unit) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(label.toUpperCase(), style: t.micro.copyWith(color: c.textFaint, fontSize: 9.5)),
            const SizedBox(height: 3),
            Text.rich(TextSpan(style: t.title.copyWith(color: c.steel), children: <InlineSpan>[TextSpan(text: value), TextSpan(text: ' $unit', style: t.micro.copyWith(color: c.textMuted))])),
          ]),
        );
    return VigilCard(
      brackets: !anyOverdue,
      borderColor: anyOverdue ? c.critical : null,
      onTap: () => context.push('/garage/${bike.id}'),
      semanticLabel: '${bike.name}, ${bike.odometer} kilometres${st.avgKmPerLitre == null ? '' : ', average ${st.avgKmPerLitre!.toStringAsFixed(1)} kilometres per litre'}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Row(children: <Widget>[
          Icon(Icons.two_wheeler, size: 22, color: c.signal),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(bike.name, style: t.title),
              Text('${bike.make.isEmpty ? '' : '${bike.make} · '}${bike.tankL.toStringAsFixed(bike.tankL == bike.tankL.roundToDouble() ? 0 : 1)} L tank', style: t.caption.copyWith(color: c.textFaint)),
            ]),
          ),
          if (pts.length > 1) SizedBox(width: 70, child: MiniBars(values: <double>[for (final MileagePoint p in pts) p.kmPerLitre], colors: <Color>[for (int i = 0; i < pts.length; i++) i == pts.length - 1 ? c.signal : c.lineStrong], height: 28, gap: 3)),
        ]),
        const SizedBox(height: 10),
        Divider(color: c.line, height: 1),
        const SizedBox(height: 10),
        Row(children: <Widget>[
          stat('Odometer', _km(bike.odometer), 'km'),
          stat('Mileage', st.avgKmPerLitre == null ? '—' : _l(st.avgKmPerLitre!), 'km/l'),
          stat('Cost', st.paisePerKm == null ? '—' : rupees2(st.paisePerKm!), '/km'),
        ]),
        if (anyOverdue) ...<Widget>[
          const SizedBox(height: 8),
          Text('${due.firstWhere((x) => x.d.level == DueLevel.overdue).r.title} overdue'.toUpperCase(), style: t.micro.copyWith(color: c.critical)),
        ],
        if (due.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
            for (final x in due.take(3))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(border: Border.all(color: x.d.level == DueLevel.ok ? c.lineStrong : _levelColor(context, x.d.level).withValues(alpha: 0.6))),
                child: Text('${x.r.title.split(' ').first} · ${dueText(x.d)}'.toUpperCase(), style: t.micro.copyWith(color: _levelColor(context, x.d.level), fontSize: 9.5)),
              ),
          ]),
        ],
      ]),
    );
  }
}

// =============================================================================================== one bike

/// A bike's page: odometer, mileage chart, reminders and fill-ups.
class BikeScreen extends ConsumerWidget {
  const BikeScreen({super.key, required this.bikeId});

  final String bikeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.vigil;
    final t = context.vtype;
    final VigilStore s = ref.watch(storeProvider);
    final Bike? bike = s.bikeById(bikeId);
    if (bike == null) {
      return VigilScaffold(
        title: 'Garage',
        leading: VigilIconButton(icon: VigilIcons.chevronLeft, semanticLabel: 'Back', onPressed: () => context.pop()),
        body: Center(child: Text('This bike is not in the garage any more.', style: t.body.copyWith(color: c.textMuted))),
      );
    }
    final DateTime now = DateTime.now();
    final BikeStats st = BikeStats.of(bike, s.fillups);
    final List<FillUp> fills = s.fillups.where((FillUp f) => f.bikeId == bike.id).toList()..sort((FillUp a, FillUp b) => b.odometer.compareTo(a.odometer));
    final List<MileagePoint> pts = st.points.length > 8 ? st.points.sublist(st.points.length - 8) : st.points;
    final List<({Reminder r, DueStatus d})> rows = <({Reminder r, DueStatus d})>[for (final Reminder r in bike.reminders) (r: r, d: dueStatus(r, bike.odometer, now))];
    final ({Reminder r, DueStatus d})? overdue = rows.where((x) => x.d.level == DueLevel.overdue).firstOrNull;

    Widget stat(String label, String value, String unit) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(label.toUpperCase(), style: t.micro.copyWith(color: c.textFaint, fontSize: 9.5)),
            const SizedBox(height: 3),
            Text.rich(TextSpan(style: t.title.copyWith(color: c.steel), children: <InlineSpan>[TextSpan(text: value), TextSpan(text: ' $unit', style: t.micro.copyWith(color: c.textMuted))])),
          ]),
        );

    return VigilScaffold(
      title: bike.name,
      leading: VigilIconButton(icon: VigilIcons.chevronLeft, semanticLabel: 'Back', onPressed: () => context.pop()),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Expanded(
          child: ListView(padding: const EdgeInsets.only(bottom: 12), children: <Widget>[
            InkWell(
              onTap: () => showOdometerSheet(context, s, bike),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(bike.make.isEmpty ? 'ODOMETER' : '${bike.make} · ODOMETER'.toUpperCase(), style: t.micro.copyWith(color: c.textFaint)),
                    const SizedBox(height: 4),
                    Text.rich(TextSpan(style: t.hero.copyWith(fontSize: 34), children: <InlineSpan>[TextSpan(text: _km(bike.odometer)), TextSpan(text: ' km', style: t.body.copyWith(color: c.textMuted))])),
                  ]),
                ),
                Text(
                  '${bike.tankL.toStringAsFixed(bike.tankL == bike.tankL.roundToDouble() ? 0 : 1)} L tank${st.litresLeft == null ? '' : ' · ≈${_l(st.litresLeft!)} L left'}\n${st.sinceLastFillKm == null ? 'No fill-ups yet' : '${st.sinceLastFillKm} km since last fill'}',
                  style: t.caption.copyWith(color: c.textFaint),
                  textAlign: TextAlign.right,
                ),
              ]),
            ),
            const SizedBox(height: 10),
            if (overdue != null) ...<Widget>[
              VigilCard(
                borderColor: c.critical,
                color: c.critical.withValues(alpha: 0.05),
                child: Row(children: <Widget>[
                  Icon(Icons.warning_amber_rounded, size: 22, color: c.critical),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text('${overdue.r.title} overdue', style: t.rowTitle), Text('It is in Ops as a critical objective', style: t.caption.copyWith(color: c.textFaint))])),
                  VigilButton(label: overdue.r.kind.isPaper ? 'Renew' : 'Done', variant: VigilButtonVariant.critical, onPressed: () => overdue.r.kind.isPaper ? showReminderSheet(context, s, bike, reminder: overdue.r) : s.markReminderDone(bike.id, overdue.r.id)),
                ]),
              ),
              const SizedBox(height: 10),
            ],
            VigilCard(
              child: Row(children: <Widget>[
                stat('Average', st.avgKmPerLitre == null ? '—' : _l(st.avgKmPerLitre!), 'km/l'),
                stat('Cost', st.paisePerKm == null ? '—' : rupees2(st.paisePerKm!), '/km'),
                stat('Range left', st.rangeKm == null ? '—' : '≈${st.rangeKm}', 'km'),
              ]),
            ),
            const SizedBox(height: 10),
            VigilCard(
              brackets: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                const SectionLabel('Mileage · last 8 full tanks', trailing: 'km/l'),
                const SizedBox(height: 12),
                if (pts.isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Text('Fill the tank to full twice and mileage shows here. It is measured between full tanks.', style: t.caption.copyWith(color: c.textMuted)))
                else ...<Widget>[
                  MiniBars(
                    // Always eight slots, so one or two measured tanks do not become one huge bar.
                    values: <double>[for (int i = pts.length; i < 8; i++) 0, for (final MileagePoint p in pts) p.kmPerLitre],
                    colors: <Color>[for (int i = pts.length; i < 8; i++) c.lineStrong, for (int i = 0; i < pts.length; i++) i == pts.length - 1 ? c.signal : c.lineStrong],
                    height: 110,
                    gap: 6,
                    refLine: st.avgKmPerLitre,
                    semanticLabel: '${bike.name} mileage, last ${pts.length} full tanks, average ${st.avgKmPerLitre!.toStringAsFixed(1)} kilometres per litre',
                  ),
                  const SizedBox(height: 6),
                  Row(children: <Widget>[for (int i = pts.length; i < 8; i++) const Expanded(child: SizedBox()), for (final MileagePoint p in pts) Expanded(child: Text(_date(p.fill.day), style: t.micro.copyWith(color: c.textFaint, fontSize: 8.5), textAlign: TextAlign.center))]),
                  const SizedBox(height: 4),
                  Text('Average ${_l(st.avgKmPerLitre!)} km/l · latest ${_l(pts.last.kmPerLitre)}', style: t.caption.copyWith(color: c.textMuted)),
                ],
              ]),
            ),
            const SizedBox(height: 10),
            VigilCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                Row(children: <Widget>[
                  Expanded(child: Text('REMINDERS', style: t.label.copyWith(color: c.textFaint))),
                  Text('BY KM OR DATE', style: t.micro.copyWith(color: c.textFaint, fontSize: 9.5)),
                ]),
                const SizedBox(height: 6),
                if (rows.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('No reminders. Add one for service, oil, tyres, insurance or anything else.', style: t.caption.copyWith(color: c.textMuted))),
                for (final x in rows)
                  InkWell(
                    onTap: () => showReminderSheet(context, s, bike, reminder: x.r),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                        Row(children: <Widget>[
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                              Text(x.r.title, style: t.rowTitle),
                              Text(_reminderSub(x.r), style: t.caption.copyWith(color: c.textFaint)),
                            ]),
                          ),
                          Text(dueText(x.d).toUpperCase(), style: t.meta.copyWith(color: _levelColor(context, x.d.level))),
                        ]),
                        const SizedBox(height: 6),
                        ClipRect(child: LinearProgressIndicator(value: x.d.fraction.clamp(0.0, 1.0), minHeight: 3, color: x.d.level == DueLevel.ok ? c.signal : _levelColor(context, x.d.level), backgroundColor: c.line)),
                      ]),
                    ),
                  ),
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerLeft, child: VigilButton(label: 'Add reminder', variant: VigilButtonVariant.ghost, icon: VigilIcons.plus, onPressed: () => showReminderSheet(context, s, bike))),
              ]),
            ),
            const SizedBox(height: 10),
            VigilCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                Row(children: <Widget>[
                  Expanded(child: Text('FILL-UPS', style: t.label.copyWith(color: c.textFaint))),
                  if (fills.isNotEmpty) Text('${rupees2(fills.first.pricePerLitrePaise)} / L', style: t.micro.copyWith(color: c.textFaint, fontSize: 9.5)),
                ]),
                const SizedBox(height: 4),
                if (fills.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('No fill-ups yet. Log one, or tell K: "Filled 10 litres for ₹1,050 at ${bike.odometer + 300}".', style: t.caption.copyWith(color: c.textMuted))),
                for (final FillUp f in fills.take(8))
                  InkWell(
                    onLongPress: () async {
                      if (await confirmDelete(context, title: 'DELETE FILL-UP?', message: 'Removes this fill-up and its ₹ from Vault › Transport.')) s.removeFillUp(f.id);
                    },
                    child: SizedBox(
                      height: 44,
                      child: Row(children: <Widget>[
                        Expanded(child: Text('${_date(f.day)} · ${_l(f.litres)} L${f.full ? '' : ' (partial)'}', style: t.body.copyWith(fontSize: 13))),
                        Text(_rs(f.totalPaise), style: t.meta.copyWith(color: c.textMuted)),
                        SizedBox(
                          width: 74,
                          child: Text(
                            () {
                              final MileagePoint? p = st.points.where((MileagePoint x) => x.fill.id == f.id).firstOrNull;
                              return p == null ? '' : '${_l(p.kmPerLitre)} km/l';
                            }(),
                            style: t.meta.copyWith(color: c.steel),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ]),
                    ),
                  ),
                if (fills.isNotEmpty) Text('Press and hold a fill-up to delete it.', style: t.micro.copyWith(color: c.textFaint, fontSize: 9.5)),
              ]),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: VigilButton(
                label: 'Delete this bike',
                variant: VigilButtonVariant.ghost,
                onPressed: () async {
                  if (!await confirmDelete(context, title: 'DELETE ${bike.name.toUpperCase()}?', message: 'Removes the bike, its reminders and its fill-ups, including their ₹ in Vault › Transport. This cannot be undone.')) return;
                  s.removeBike(bike.id);
                  if (context.mounted) context.pop();
                },
              ),
            ),
          ]),
        ),
        Container(
          padding: EdgeInsets.only(top: 10, bottom: 10 + MediaQuery.paddingOf(context).bottom),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
          child: Row(children: <Widget>[
            VigilButton(label: 'Ask $kAssistantName', variant: VigilButtonVariant.secondary, icon: VigilIcons.voice, onPressed: () => context.go('/vigil')),
            const SizedBox(width: 10),
            Expanded(child: VigilButton(label: 'Log fill-up', expand: true, onPressed: () => showFillUpSheet(context, s, bike: bike))),
          ]),
        ),
      ]),
    );
  }

  static String _reminderSub(Reminder r) {
    final List<String> p = <String>[];
    if (r.kind.isPaper && r.dueDate != null) {
      p.add('Valid till ${_dateYear(r.dueDate!)}');
    } else {
      if (r.mode != ReminderMode.date && r.everyKm != null) p.add('Every ${_km(r.everyKm!)} km');
      if (r.mode != ReminderMode.km && r.everyDays != null) p.add('every ${r.everyDays} days');
      if (r.lastKm != null && r.mode != ReminderMode.date) p.add('last at ${_km(r.lastKm!)}');
    }
    return p.isEmpty ? '' : p.join(' · ');
  }
}

// =============================================================================================== sheets

Future<void> _sheet(BuildContext context, Widget child) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (BuildContext ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.viewInsetsOf(ctx).bottom + MediaQuery.paddingOf(ctx).bottom + 20),
        child: SingleChildScrollView(child: child),
      ),
    );

Future<DateTime?> _pickDate(BuildContext context, DateTime? initial) => showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

Future<void> showAddBikeSheet(BuildContext context, VigilStore s) => _sheet(context, _AddBike(store: s));
Future<void> showFillUpSheet(BuildContext context, VigilStore s, {Bike? bike}) => _sheet(context, _FillUp(store: s, bike: bike));
Future<void> showReminderSheet(BuildContext context, VigilStore s, Bike bike, {Reminder? reminder}) => _sheet(context, _ReminderSheet(store: s, bike: bike, reminder: reminder));
Future<void> showOdometerSheet(BuildContext context, VigilStore s, Bike bike) => _sheet(context, _OdometerSheet(store: s, bike: bike));

Widget _dateButton(BuildContext context, String label, DateTime? value, VoidCallback onTap) {
  final c = context.vigil;
  final t = context.vtype;
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
    Text(label.toUpperCase(), style: t.label.copyWith(color: c.textFaint)),
    const SizedBox(height: 6),
    InkWell(
      onTap: onTap,
      child: Container(
        height: VigilSize.input,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.lineStrong)),
        child: Row(children: <Widget>[Expanded(child: Text(value == null ? 'Not set' : _dateYear(value), style: t.body.copyWith(color: value == null ? c.textFaint : c.text))), Icon(Icons.event, size: 18, color: c.textMuted)]),
      ),
    ),
  ]);
}

class _AddBike extends StatefulWidget {
  const _AddBike({required this.store});

  final VigilStore store;

  @override
  State<_AddBike> createState() => _AddBikeState();
}

class _AddBikeState extends State<_AddBike> {
  final TextEditingController _make = TextEditingController();
  final TextEditingController _model = TextEditingController();
  final TextEditingController _tank = TextEditingController();
  final TextEditingController _odo = TextEditingController();
  DateTime? _insurance;
  DateTime? _puc;
  int _service = 5000;

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _tank.dispose();
    _odo.dispose();
    super.dispose();
  }

  bool get _ok => (_make.text.trim().isNotEmpty || _model.text.trim().isNotEmpty) && (_double(_tank.text) ?? 0) > 0;

  void _save() {
    if (!_ok) return;
    final Bike? b = widget.store.addBike(make: _make.text, model: _model.text, tankL: _double(_tank.text)!, odometer: _int(_odo.text) ?? 0, serviceEveryKm: _service, insuranceUntil: _insurance, pucUntil: _puc);
    if (b == null) {
      showVigilSnack(context, 'The garage keeps up to ${VigilStore.kMaxBikes} bikes');
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('ADD BIKE', style: t.h2),
      const SizedBox(height: 4),
      Text('${widget.store.bikes.length + 1} of ${VigilStore.kMaxBikes} bikes', style: t.micro.copyWith(color: c.textFaint)),
      const SizedBox(height: 14),
      Row(children: <Widget>[
        Expanded(child: VigilField(controller: _make, label: 'Make', hint: 'Royal Enfield', onChanged: (_) => setState(() {}))),
        const SizedBox(width: 10),
        Expanded(child: VigilField(controller: _model, label: 'Model', hint: 'Meteor 350', onChanged: (_) => setState(() {}))),
      ]),
      const SizedBox(height: 12),
      Row(children: <Widget>[
        Expanded(child: VigilField(controller: _tank, label: 'Tank (litres)', hint: '15', keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
        const SizedBox(width: 10),
        Expanded(child: VigilField(controller: _odo, label: 'Odometer (km)', hint: '9412', keyboardType: TextInputType.number)),
      ]),
      const SizedBox(height: 12),
      _dateButton(context, 'Insurance valid till', _insurance, () async {
        final DateTime? d = await _pickDate(context, _insurance);
        if (d != null) setState(() => _insurance = d);
      }),
      const SizedBox(height: 12),
      _dateButton(context, 'PUC valid till', _puc, () async {
        final DateTime? d = await _pickDate(context, _puc);
        if (d != null) setState(() => _puc = d);
      }),
      const SizedBox(height: 12),
      Text('SERVICE EVERY', style: t.label.copyWith(color: c.textFaint)),
      const SizedBox(height: 6),
      VigilSegmented<int>(segments: const <(int, String)>[(3000, '3,000 KM'), (5000, '5,000 KM'), (10000, '10,000 KM')], selected: _service, onSelected: (int v) => setState(() => _service = v)),
      const SizedBox(height: 8),
      Text('$kAssistantName adds chain, tyre and service reminders with sensible defaults; edit any of them later.', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 14),
      VigilButton(label: 'Add bike', size: VigilButtonSize.large, expand: true, onPressed: _ok ? _save : null),
    ]);
  }
}

class _FillUp extends StatefulWidget {
  const _FillUp({required this.store, this.bike});

  final VigilStore store;
  final Bike? bike;

  @override
  State<_FillUp> createState() => _FillUpState();
}

class _FillUpState extends State<_FillUp> {
  late Bike _bike = widget.bike ?? widget.store.bikes.first;
  late final TextEditingController _odo = TextEditingController(text: '${_bike.odometer}');
  final TextEditingController _litres = TextEditingController();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _total = TextEditingController();
  bool _full = true;

  @override
  void dispose() {
    _odo.dispose();
    _litres.dispose();
    _price.dispose();
    _total.dispose();
    super.dispose();
  }

  /// The total paid: typed, or litres times the price per litre when only that was typed.
  int? get _paise {
    final int? typed = parseRupees(_total.text);
    if (typed != null) return typed;
    final double? l = _double(_litres.text);
    final double? p = _double(_price.text);
    if (l == null || p == null || l <= 0 || p <= 0) return null;
    return (l * p * 100).round();
  }

  bool get _ok => (_int(_odo.text) ?? -1) >= 0 && (_double(_litres.text) ?? 0) > 0 && (_paise ?? 0) > 0;

  void _save() {
    final int? odo = _int(_odo.text);
    final double? litres = _double(_litres.text);
    final int? paise = _paise;
    if (odo == null || litres == null || paise == null) return;
    final undo = widget.store.addFillUp(bikeId: _bike.id, odometer: odo, litres: litres, totalPaise: paise, full: _full);
    if (undo == null) {
      showVigilSnack(context, 'That does not look right: check the litres (the tank holds ${_bike.tankL.toStringAsFixed(0)} L) and the amount');
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final List<FillUp> mine = widget.store.fillups.where((FillUp f) => f.bikeId == _bike.id).toList();
    final ({double kmPerLitre, int km, double? vsAveragePercent})? prev = (_int(_odo.text) == null || _double(_litres.text) == null) ? null : previewMileage(_bike, mine, odometer: _int(_odo.text)!, litres: _double(_litres.text)!, full: _full);
    final int? paise = _paise;
    final int budget = widget.store.effectiveBudgetPaise;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('LOG FILL-UP', style: t.h2),
      const SizedBox(height: 12),
      if (widget.store.bikes.length > 1) ...<Widget>[
        VigilSegmented<String>(
          segments: <(String, String)>[for (final Bike b in widget.store.bikes) (b.id, b.name.toUpperCase())],
          selected: _bike.id,
          onSelected: (String id) => setState(() {
            _bike = widget.store.bikeById(id)!;
            _odo.text = '${_bike.odometer}';
          }),
        ),
        const SizedBox(height: 12),
      ],
      Row(children: <Widget>[
        Expanded(child: VigilField(controller: _odo, label: 'Odometer (km)', hint: 'last ${_km(_bike.odometer)}', keyboardType: TextInputType.number, onChanged: (_) => setState(() {}))),
        const SizedBox(width: 10),
        Expanded(child: VigilField(controller: _litres, label: 'Litres', hint: 'tank ${_bike.tankL.toStringAsFixed(0)} L', keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), autofocus: true)),
      ]),
      const SizedBox(height: 10),
      Row(children: <Widget>[
        Expanded(child: VigilField(controller: _price, label: 'Price / L', hint: '104.90', keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
        const SizedBox(width: 10),
        Expanded(child: VigilField(controller: _total, label: 'Total (₹)', hint: paise == null ? '1,050' : (paise / 100).toStringAsFixed(0), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
      ]),
      const SizedBox(height: 10),
      Row(children: <Widget>[
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text('Full tank', style: t.rowTitle), Text('Mileage is measured between full tanks', style: t.caption.copyWith(color: c.textFaint))])),
        VigilSwitch(value: _full, onChanged: (bool v) => setState(() => _full = v), semanticLabel: 'Full tank'),
      ]),
      const SizedBox(height: 10),
      if (prev != null)
        VigilCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('THIS TANK', style: t.micro.copyWith(color: c.textFaint)),
            const SizedBox(height: 2),
            Text('${_l(prev.kmPerLitre)} km/l', style: t.title.copyWith(color: c.steel)),
            Text(
              '${prev.km} km since the last full tank${prev.vsAveragePercent == null ? '' : ' · ${prev.vsAveragePercent! < 0 ? 'below' : 'above'} your average ${prev.vsAveragePercent! < 0 ? '−' : '+'}${prev.vsAveragePercent!.abs().round()} %'}',
              style: t.caption.copyWith(color: c.textMuted),
            ),
          ]),
        ),
      if (paise != null) ...<Widget>[
        const SizedBox(height: 8),
        Text('Adds ${_rs(paise)} to Vault › Transport${budget > 0 ? ' · budget ${(((widget.store.monthSpentPaise + paise) / budget) * 100).round()} %' : ''}', style: t.caption.copyWith(color: c.textMuted)),
      ],
      const SizedBox(height: 14),
      VigilButton(label: 'Save fill-up', size: VigilButtonSize.large, expand: true, onPressed: _ok ? _save : null),
    ]);
  }
}

class _ReminderSheet extends StatefulWidget {
  const _ReminderSheet({required this.store, required this.bike, this.reminder});

  final VigilStore store;
  final Bike bike;
  final Reminder? reminder;

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  late ReminderKind _kind = widget.reminder?.kind ?? ReminderKind.service;
  late ReminderMode _mode = widget.reminder?.mode ?? ReminderMode.km;
  late final TextEditingController _label = TextEditingController(text: widget.reminder?.label ?? '');
  late final TextEditingController _everyKm = TextEditingController(text: widget.reminder?.everyKm?.toString() ?? '');
  late final TextEditingController _everyDays = TextEditingController(text: widget.reminder?.everyDays?.toString() ?? '');
  late DateTime? _dueDate = widget.reminder?.dueDate;
  late int _headsUp = widget.reminder?.headsUpKm ?? 300;

  @override
  void dispose() {
    _label.dispose();
    _everyKm.dispose();
    _everyDays.dispose();
    super.dispose();
  }

  bool get _paper => _kind.isPaper;

  bool get _ok {
    if (_kind == ReminderKind.custom && _label.text.trim().isEmpty) return false;
    if (_paper) return _dueDate != null;
    final bool km = _mode != ReminderMode.date;
    final bool days = _mode != ReminderMode.km;
    return (!km || (_int(_everyKm.text) ?? 0) > 0) && (!days || (_int(_everyDays.text) ?? 0) > 0);
  }

  void _save() {
    if (!_ok) return;
    final Bike b = widget.bike;
    final Reminder r = widget.reminder ?? Reminder(id: widget.store.nextId(), kind: _kind, lastKm: b.odometer, lastDate: dateOnly(DateTime.now()));
    r
      ..kind = _kind
      ..label = _kind == ReminderKind.custom ? _label.text.trim() : null
      ..headsUpKm = _headsUp;
    if (_paper) {
      r
        ..mode = ReminderMode.date
        ..dueDate = _dueDate
        ..everyKm = null
        ..everyDays = null;
    } else {
      r
        ..mode = _mode
        ..dueDate = null
        ..everyKm = _mode == ReminderMode.date ? null : _int(_everyKm.text)
        ..everyDays = _mode == ReminderMode.km ? null : _int(_everyDays.text);
    }
    if (widget.reminder == null) b.reminders.add(r);
    widget.store.bikeEdited();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vigil;
    final t = context.vtype;
    final Reminder? old = widget.reminder;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text(old == null ? 'NEW REMINDER' : 'EDIT REMINDER', style: t.h2),
      const SizedBox(height: 4),
      Text(widget.bike.name, style: t.micro.copyWith(color: c.textFaint)),
      const SizedBox(height: 12),
      Text('TYPE', style: t.label.copyWith(color: c.textFaint)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: <Widget>[for (final ReminderKind k in ReminderKind.values) SizedBox(width: (MediaQuery.sizeOf(context).width - 40 - 8) / 2, child: VigilFilterChip(label: k.label, selected: _kind == k, onTap: () => setState(() => _kind = k)))]),
      if (_kind == ReminderKind.custom) ...<Widget>[
        const SizedBox(height: 12),
        VigilField(controller: _label, label: 'Name', hint: 'Brake pads', onChanged: (_) => setState(() {})),
      ],
      const SizedBox(height: 12),
      if (_paper)
        _dateButton(context, 'Valid till', _dueDate, () async {
          final DateTime? d = await _pickDate(context, _dueDate);
          if (d != null) setState(() => _dueDate = d);
        })
      else ...<Widget>[
        Text('REMIND ME', style: t.label.copyWith(color: c.textFaint)),
        const SizedBox(height: 6),
        VigilSegmented<ReminderMode>(segments: const <(ReminderMode, String)>[(ReminderMode.km, 'BY KM'), (ReminderMode.date, 'BY DATE'), (ReminderMode.both, 'FIRST OF BOTH')], selected: _mode, onSelected: (ReminderMode m) => setState(() => _mode = m)),
        const SizedBox(height: 12),
        Row(children: <Widget>[
          if (_mode != ReminderMode.date) Expanded(child: VigilField(controller: _everyKm, label: 'Every (km)', hint: '5000', keyboardType: TextInputType.number, onChanged: (_) => setState(() {}))),
          if (_mode == ReminderMode.both) const SizedBox(width: 10),
          if (_mode != ReminderMode.km) Expanded(child: VigilField(controller: _everyDays, label: 'Every (days)', hint: '365', keyboardType: TextInputType.number, onChanged: (_) => setState(() {}))),
        ]),
        if (old != null && (old.lastKm != null || old.lastDate != null)) ...<Widget>[
          const SizedBox(height: 8),
          Text('Last done${old.lastKm == null ? '' : ' · ${_km(old.lastKm!)} km'}${old.lastDate == null ? '' : ' · ${_dateYear(old.lastDate!)}'}', style: t.caption.copyWith(color: c.textFaint)),
        ],
      ],
      if (_mode != ReminderMode.date || _paper == false) ...<Widget>[
        const SizedBox(height: 12),
        Text('HEADS-UP', style: t.label.copyWith(color: c.textFaint)),
        const SizedBox(height: 6),
        VigilSegmented<int>(segments: const <(int, String)>[(100, '100 KM'), (300, '300 KM'), (500, '500 KM')], selected: _headsUp, onSelected: (int v) => setState(() => _headsUp = v)),
      ],
      const SizedBox(height: 8),
      Text('When it is due it lands in Ops as an objective, and clearing it there marks the job done.', style: t.caption.copyWith(color: c.textMuted)),
      const SizedBox(height: 14),
      Row(children: <Widget>[
        if (old != null && !_paper) VigilButton(label: 'Mark done', variant: VigilButtonVariant.secondary, onPressed: () {
              widget.store.markReminderDone(widget.bike.id, old.id);
              Navigator.pop(context);
            }),
        if (old != null && !_paper) const SizedBox(width: 8),
        if (old != null) VigilButton(label: 'Delete', variant: VigilButtonVariant.ghost, onPressed: () {
              widget.bike.reminders.removeWhere((Reminder r) => r.id == old.id);
              widget.store.bikeEdited();
              Navigator.pop(context);
            }),
        const Spacer(),
        VigilButton(label: 'Save reminder', onPressed: _ok ? _save : null),
      ]),
    ]);
  }
}

class _OdometerSheet extends StatefulWidget {
  const _OdometerSheet({required this.store, required this.bike});

  final VigilStore store;
  final Bike bike;

  @override
  State<_OdometerSheet> createState() => _OdometerSheetState();
}

class _OdometerSheetState extends State<_OdometerSheet> {
  late final TextEditingController _odo = TextEditingController(text: '${widget.bike.odometer}');

  @override
  void dispose() {
    _odo.dispose();
    super.dispose();
  }

  void _save() {
    final int? v = _int(_odo.text);
    if (v == null || v < 0) return;
    widget.store.setOdometer(widget.bike.id, v);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vtype;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('ODOMETER', style: t.h2),
      const SizedBox(height: 4),
      Text(widget.bike.name, style: t.micro.copyWith(color: context.vigil.textFaint)),
      const SizedBox(height: 12),
      VigilField(controller: _odo, label: 'Kilometres', keyboardType: TextInputType.number, autofocus: true, onSubmitted: (_) => _save()),
      const SizedBox(height: 14),
      VigilButton(label: 'Save', size: VigilButtonSize.large, expand: true, onPressed: _save),
    ]);
  }
}
