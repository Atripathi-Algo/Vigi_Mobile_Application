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

  group('quick add (rules only)', () {
    test('a clear command is applied at once, can be undone, and never touches the model', () {
      final Assistant a = Assistant(store);
      final ChatMsg? m = a.quick('log 250 ml water');
      expect(m, isNotNull);
      expect(m!.diff, isNotNull);
      expect(m.source, ReplySource.instant);
      expect(store.waterMl, 250);
      m.onUndo!();
      expect(store.waterMl, 0);
    });

    test('a task, an expense and a note are filed', () {
      final Assistant a = Assistant(store);
      expect(a.quick('remind me to call Mom at 6 pm')!.diff!.single.$1, 'TASK');
      expect(a.quick('spent 200 on lunch')!.diff!.single.$1, 'SPEND');
      expect(a.quick('note that the wifi is on the fridge')!.diff!.single.$1, 'NOTE');
      expect(store.open, hasLength(1));
    });

    test('anything the rules do not recognise is left for K', () {
      final Assistant a = Assistant(store);
      expect(a.quick('what is the capital of France'), isNull);
      expect(a.quick('how much water today?'), isNull, reason: 'a question goes to K, not the quick-add bar');
    });

    test('a deletion needs a Confirm, so quick add hands it to K', () {
      store.addObjective('Old chore');
      expect(Assistant(store).quick('delete the task old chore'), isNull);
      expect(store.open, hasLength(1));
    });
  });

  test('K\'s deletion question is flagged so the chat can show Confirm and Cancel', () async {
    store.addObjective('Old chore');
    final Assistant a = Assistant(store);
    final ChatMsg ask = await a.reply('delete the task old chore');
    expect(ask.confirm, isTrue);
    final ChatMsg done = await a.reply('yes');
    expect(done.confirm, isFalse);
    expect(store.open, isEmpty);
  });
}
