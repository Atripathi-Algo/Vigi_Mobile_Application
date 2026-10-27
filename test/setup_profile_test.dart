import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigil/app/fmt.dart';
import 'package:vigil/data/store.dart';

void main() {
  tearDown(() => Fmt.use24h = true);

  test('a fresh install has no name, no nickname and a 24-hour clock', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final VigilStore s = await VigilStore.load();
    expect((s.fullName, s.callsign, s.nickname, s.clock24, s.booted), ('', '', '', true, false));
  });

  test('the greeting name is the nickname, else the first word of the full name', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final VigilStore s = await VigilStore.load();
    s.setProfile(fullName: 'Asha Rao', nickname: '');
    expect(s.nickname, 'Asha');
    s.setProfile(fullName: 'Asha Rao', nickname: ' Ash ');
    expect(s.nickname, 'Ash');
  });

  test('the old default callsign is dropped when an older build\'s data is opened', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'booted': true, 'fullName': 'Abhishek', 'callsign': 'Batman'});
    final VigilStore s = await VigilStore.load();
    expect(s.callsign, '');
    expect(s.nickname, 'Abhishek');
  });

  test('the clock choice changes every time shown and survives a restart', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final VigilStore s = await VigilStore.load();
    expect(Fmt.hm(19 * 60 + 42), '19:42');
    s.setClock24(false);
    expect(Fmt.hm(19 * 60 + 42), '7:42 PM');
    expect(Fmt.hm(0), '12:00 AM');
    expect(Fmt.hm(12 * 60 + 5), '12:05 PM');
    expect(Fmt.time(DateTime(2026, 10, 27, 7, 5)), '7:05 AM');
    final VigilStore again = await VigilStore.load();
    expect(again.clock24, isFalse);
    expect(Fmt.hm(19 * 60 + 42), '7:42 PM');
  });

  test('running setup again changes the profile and nothing else', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final VigilStore s = await VigilStore.load();
    s.completeBoot(name: 'Asha Rao', call: 'Ash', wake: 7 * 60, bed: 22 * 60, armed: <String>{'OBJECTIVES'});
    s.addProtocol('Read');
    s.setProfile(fullName: 'Asha R.', nickname: 'A');
    expect((s.fullName, s.callsign, s.booted, s.wakeMin, s.protocols.length), ('Asha R.', 'A', true, 7 * 60, 1));
  });
}
