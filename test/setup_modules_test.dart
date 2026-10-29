import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigil/data/store.dart';

void main() {
  test('both optional modules are on by default', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final VigilStore s = await VigilStore.load();
    expect((s.healthOn, s.garageOn), (true, true));
  });

  test('setup saves which modules are on, and they survive a reload', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final VigilStore s = await VigilStore.load();
    s.completeBoot(name: '', call: 'Ash', wake: 390, bed: 1380, armed: <String>{kModuleGarage});
    expect((s.healthOn, s.garageOn), (false, true));
    await s.reloadFromDisk();
    expect((s.healthOn, s.garageOn), (false, true));
    s.setModules(<String>{});
    await s.reloadFromDisk();
    expect((s.healthOn, s.garageOn), (false, false), reason: 'switching both off is remembered');
  });

  test('module names saved by older builds mean everything is on', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'modules': <String>['OBJECTIVES', 'TIMELINE', 'LEDGER']});
    final VigilStore s = await VigilStore.load();
    expect((s.healthOn, s.garageOn), (true, true));
  });

  test('names that are not modules are ignored', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final VigilStore s = await VigilStore.load();
    s.setModules(<String>{kModuleHealth, 'bogus'});
    expect(s.modules, <String>{kModuleHealth});
  });
}
