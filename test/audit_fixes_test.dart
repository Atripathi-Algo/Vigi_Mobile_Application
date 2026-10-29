import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigil/data/assistant.dart';
import 'package:vigil/data/models.dart';
import 'package:vigil/data/store.dart';

void main() {
  late VigilStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dotenv.testLoad(fileInput: '');
    store = await VigilStore.load();
  });

  group('habit consistency counts only the days a habit has existed', () {
    test('a habit made today is judged on one day, not seven', () {
      store.addProtocol('Read');
      expect(store.protocols.single.activeDays(DateTime.now()), 1);
      expect(store.consistencyPercent, 0);
      store.toggleProtocol(store.protocols.single.id);
      expect(store.consistencyPercent, 100, reason: 'done on the only day it has existed');
    });

    test('an older habit counts all seven days, and one from an older build has no creation date', () {
      store.addProtocol('Old');
      final Protocol p = store.protocols.single;
      p.createdAt = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
      p.week = <bool>[true, true, true, false, false, false, false];
      expect((p.activeDays(DateTime.now()), store.consistencyPercent), (7, 43));
      p.createdAt = null;
      expect(p.activeDays(DateTime.now()), 7);
    });

    test('the weekly bars ignore habits that did not exist yet', () {
      store.addProtocol('New');
      expect(store.weekLevels.take(6).every((int l) => l == 0), isTrue);
    });

    test('the creation date is saved', () async {
      store.addProtocol('Read');
      final int? made = store.protocols.single.createdAt;
      await store.reloadFromDisk();
      expect(store.protocols.single.createdAt, made);
    });
  });

  group('K tidies what you say', () {
    test('a trailing priority word becomes priority, not part of the title', () async {
      final ChatMsg m = await Assistant(store).reply('remind me to send the quarterly report by 5 pm, important');
      expect(m.diff!.single.$2, 'Send the quarterly report · 17:00');
      expect(store.open.single.threat.name, 'high');
    });

    test('money is written as rupees with grouping, not as a bare number', () async {
      final Assistant a = Assistant(store);
      expect((await a.reply('set my budget to 30000')).text, 'Monthly budget set to ₹30,000.');
      expect((await a.reply('spent 1250 on groceries')).text, 'Logged ₹1,250 for groceries.');
    });
  });
}
