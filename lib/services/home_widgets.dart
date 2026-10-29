import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../app/fmt.dart';
import '../data/garage.dart';
import '../data/models.dart';
import '../data/store.dart';

/// Home-screen widgets (Android). The app writes display strings; the native
/// providers in android/.../VigilWidgets.kt draw them. Taps on the water
/// button and on an objective run [vigilWidgetCallback] in the background.
abstract final class HomeWidgets {
  static const String _pkg = 'com.algoanalytics.vigil';
  static const List<String> _providers = <String>['VigilObjectivesWidget', 'VigilSmallWidget', 'VigilWaterWidget', 'VigilNextOpWidget', 'VigilAskWidget', 'VigilSpendWidget', 'VigilGarageWidget'];

  static String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static Future<void> push(VigilStore s) async {
    try {
      final DateTime now = DateTime.now();
      final Block? nb = s.nextBlock(now);
      final List<Objective> top = s.prioritised().take(3).toList();
      final String steps = s.steps == null ? 'STEPS --' : 'STEPS ${_grouped(s.steps!)}';
      final String water = 'WATER ${Fmt.litres(s.waterMl)}/${Fmt.litres(s.waterTargetMl)} L';
      final Map<String, String> data = <String, String>{
        'accent': _hex(s.accent),
        'ready': '${s.readiness}',
        'next': nb == null ? (top.isEmpty ? 'All clear' : 'Next: ${top.first.title}') : '${Fmt.hm(nb.startMin)} ${nb.title} · T–${nb.startMin - (now.hour * 60 + now.minute)} MIN',
        'stats': '$steps · $water',
        'stats_small': '$steps\n$water',
      };
      data.addAll(<String, String>{
        'water_amount': '${Fmt.litres(s.waterMl)} / ${Fmt.litres(s.waterTargetMl)} L',
        'next_title': nb?.title ?? 'Nothing next',
        'next_when': nb == null ? 'All clear' : '${Fmt.hm(nb.startMin)} · in ${nb.startMin - (now.hour * 60 + now.minute)} min',
        ...HomeWidgets.spendData(s),
        ...HomeWidgets.garageData(s, now),
      });
      for (int i = 0; i < 3; i++) {
        final Objective? o = i < top.length ? top[i] : null;
        data['o${i + 1}_t'] = o?.title ?? '';
        data['o${i + 1}_id'] = o?.id ?? '';
        data['o${i + 1}_done'] = '0';
      }
      for (final MapEntry<String, String> e in data.entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }
      for (final String p in _providers) {
        await HomeWidget.updateWidget(qualifiedAndroidName: '$_pkg.$p');
      }
    } catch (e) {
      debugPrint('Widget update failed: $e');
    }
  }

  /// The Spend widget stays masked until "Show amounts on the Spend widget" is on in Settings.
  @visibleForTesting
  static Map<String, String> spendData(VigilStore s) {
    if (s.toggles['widgetSpend'] != true) return <String, String>{'spend_amount': '₹ ••••', 'spend_of': 'Tap to open'};
    return <String, String>{
      'spend_amount': Fmt.money(s.monthSpentPaise),
      'spend_of': s.effectiveBudgetPaise > 0 ? 'of ${Fmt.money(s.effectiveBudgetPaise)}' : 'no budget set',
    };
  }

  /// The first bike: odometer, mileage and running cost, and the reminder that is closest to due.
  @visibleForTesting
  static Map<String, String> garageData(VigilStore s, DateTime now) {
    if (s.bikes.isEmpty) return <String, String>{'garage_name': 'Garage', 'garage_odo': 'No bike yet', 'garage_stats': 'Add one in Plan, Garage', 'garage_next': ''};
    final Bike b = s.bikes.first;
    final BikeStats st = BikeStats.of(b, s.fillups);
    Reminder? next;
    DueStatus? nextStatus;
    for (final Reminder r in b.reminders) {
      final DueStatus ds = dueStatus(r, b.odometer, now);
      if (nextStatus == null || ds.fraction > nextStatus.fraction) {
        next = r;
        nextStatus = ds;
      }
    }
    return <String, String>{
      'garage_name': b.name,
      'garage_odo': '${_grouped(b.odometer)} km',
      'garage_stats': <String>[if (st.avgKmPerLitre != null) '${st.avgKmPerLitre!.toStringAsFixed(1)} km/l', if (st.paisePerKm != null) '${rupees2(st.paisePerKm!)}/km', if (st.rangeKm != null) 'range ${st.rangeKm} km'].join(' · '),
      'garage_next': next == null || nextStatus == null ? '' : '${next.title}: ${dueText(nextStatus).toLowerCase()}',
    };
  }

  static String _grouped(int n) => n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (Match m) => '${m[1]},');
}

/// Runs in a background isolate when the user taps a widget control.
@pragma('vm:entry-point')
Future<void> vigilWidgetCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  final VigilStore s = await VigilStore.load();
  switch (uri?.host) {
    case 'water':
      s.logWater(int.tryParse(uri?.queryParameters['ml'] ?? '') ?? 250);
    case 'toggle':
      final String? id = uri?.queryParameters['id'];
      if (id != null && s.objectives.any((Objective o) => o.id == id)) s.toggleObjective(id);
  }
  await HomeWidgets.push(s);
}
