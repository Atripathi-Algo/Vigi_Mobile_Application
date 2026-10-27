import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigil/api/cloud_ai.dart';
import 'package:vigil/data/agent.dart';
import 'package:vigil/data/assistant.dart';
import 'package:vigil/data/brain_eval.dart';
import 'package:vigil/data/brain_prompt.dart';
import 'package:vigil/data/models.dart';
import 'package:vigil/data/store.dart';
import 'package:vigil/services/local_brain.dart';
import 'package:vigil/services/local_llm.dart';
import 'package:vigil/services/model_store.dart';
import 'package:vigil/vigil/vigil.dart';

/// A stand-in for llama.cpp.
class FakeEngine implements LocalLlmEngine {
  FakeEngine({this.reply = '{"actions":[],"say":"ok"}'});

  String reply;
  bool _loaded = false;
  int loads = 0;
  int unloads = 0;
  int cancels = 0;
  int running = 0;
  int maxRunning = 0;
  bool failLoad = false;
  bool hang = false;
  BrainLoad? lastLoad;
  List<BrainTurn>? lastMessages;
  Map<String, dynamic>? lastSchema;
  BrainSampling? lastSampling;

  @override
  bool get loaded => _loaded;

  @override
  Future<void> load(BrainLoad load) async {
    loads++;
    lastLoad = load;
    if (failLoad) throw StateError('cannot load');
    _loaded = true;
  }

  @override
  Stream<String> generate(List<BrainTurn> messages, {Map<String, dynamic>? schema, BrainSampling sampling = const BrainSampling()}) async* {
    lastMessages = messages;
    lastSchema = schema;
    lastSampling = sampling;
    running++;
    if (running > maxRunning) maxRunning = running;
    try {
      if (hang) await Completer<void>().future;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      for (int i = 0; i < reply.length; i += 7) {
        yield reply.substring(i, i + 7 > reply.length ? reply.length : i + 7);
      }
    } finally {
      running--;
    }
  }

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<void> unload() async {
    if (_loaded) unloads++;
    _loaded = false;
  }
}

/// A model file of the right shape: starts with the GGUF magic and is over 1 MB.
Uint8List ggufBytes([int size = 1200000]) {
  final Uint8List b = Uint8List(size);
  b.setAll(0, 'GGUF'.codeUnits);
  return b;
}

MockClient serving(Uint8List data, {bool honourRange = true, List<String?>? ranges}) => MockClient.streaming((http.BaseRequest req, http.ByteStream body) async {
      final String? range = req.headers['range'];
      ranges?.add(range);
      if (range != null && honourRange) {
        final int from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        return http.StreamedResponse(Stream<List<int>>.value(data.sublist(from)), 206, contentLength: data.length - from, headers: <String, String>{'content-range': 'bytes $from-${data.length - 1}/${data.length}'});
      }
      return http.StreamedResponse(Stream<List<int>>.fromIterable(<List<int>>[data.sublist(0, data.length ~/ 2), data.sublist(data.length ~/ 2)]), 200, contentLength: data.length);
    });

void main() {
  late Directory dir;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dotenv.testLoad(fileInput: '');
    dir = Directory.systemTemp.createTempSync('vigil_models');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('prompt', () {
    final BrainFacts facts = BrainFacts(
      now: DateTime(2026, 10, 23, 14, 30),
      callsign: 'Alex',
      objectives: const <String>['Send weekly report · due 17:00 · high'],
      events: const <String>['16:00-17:00 Vendor sync'],
      protocols: const <String>['Read 20 pages'],
      waterMl: 750,
      steps: 4200,
      sleep: 'last night 6h 50m',
      money: 'spent ₹12,400 this month',
    );

    test('objectives and protocols are always in the context; the rest only when asked about', () {
      final String water = brainContext(facts, 'how much water have I had?');
      expect(water, allOf(contains('OPEN OBJECTIVES: 1) Send weekly report'), contains('PROTOCOLS: Read 20 pages'), contains('WATER: 750 of 3000 ml')));
      expect(water, allOf(isNot(contains('SLEEP')), isNot(contains('STEPS')), isNot(contains('MONEY')), isNot(contains('EVENTS'))));
      expect(brainContext(facts, 'how did I sleep'), contains('SLEEP: last night 6h 50m'));
      expect(brainContext(facts, 'what did I spend'), contains('MONEY: spent'));
      expect(brainContext(facts, 'how many steps'), contains('STEPS: 4200 of 8000'));
      expect(brainContext(facts, 'what is on today'), contains('EVENTS TODAY: 16:00-17:00 Vendor sync'));
      expect(brainContext(facts, 'hello'), contains('EVENTS TODAY'), reason: 'an unclear question gets the schedule');
      expect(brainContext(facts, 'hello'), startsWith('NOW: Fri 23/10/2026 14:30'));
    });

    test('a short context means a short prompt', () {
      final String q = brainContext(facts, 'how much water have I had?');
      expect(q.length, lessThan(400));
    });

    test('messages: fixed instructions first, a few clipped turns, then context and the question', () {
      final List<(bool, String)> history = <(bool, String)>[for (int i = 0; i < 8; i++) (i.isEven, 'turn $i ${'x' * 300}')];
      final List<BrainTurn> m = buildBrainMessages(facts, 'log water', history);
      expect(m.first.role, 'system');
      expect(m.first.text, kBrainSystem, reason: 'identical every time, so its cache can be reused');
      expect(m.length, 1 + 4 + 1);
      expect(m[1].text.length, lessThan(220));
      expect(m.last.role, 'user');
      expect(m.last.text, allOf(startsWith('CONTEXT:'), endsWith('User: log water')));
    });

    test('the schema is valid JSON, writes actions before the sentence, and only allows known actions', () {
      final Map<String, dynamic> j = jsonDecode(jsonEncode(kBrainSchema)) as Map<String, dynamic>;
      expect((j['properties'] as Map<String, dynamic>).keys.toList(), <String>['actions', 'say']);
      final Map<String, dynamic> item = (j['properties']['actions']['items'] as Map<String, dynamic>);
      expect(item['properties']['type']['enum'], kBrainActionTypes);
      expect(item['required'], <String>['type']);
      expect(j['properties']['actions']['maxItems'], lessThanOrEqualTo(3));
      for (final String t in kBrainActionTypes) {
        expect(kBrainSystem, contains('$t('), reason: 'the instructions describe $t');
      }
      expect(kBrainSystem.length, lessThan(1700), reason: 'short instructions mean a short cold start');
      expect(j['properties']['actions']['maxItems'], 1);
    });

    test('facts from the store are plain lines', () async {
      final VigilStore s = await VigilStore.load();
      s.addObjective('Call the plumber', threat: Threat.high, dueMin: 17 * 60 + 30);
      s.addProtocol('Read 20 pages');
      s.logWater(500);
      final BrainFacts f = factsFromStore(s, DateTime(2026, 10, 23, 9));
      expect(f.objectives.single, 'Call the plumber · due 17:30 · high');
      expect(f.protocols.single, 'Read 20 pages');
      expect(f.waterMl, 500);
      expect(f.sleep, 'no data');
      expect(f.money, 'no data');
    });
  });

  group('question guard', () {
    test('questions that ask for information are recognised', () {
      for (final String q in <String>['how much water have I had today?', 'what did I spend this month', 'did I call the plumber?', 'when is my next meeting', 'is it late', 'what is the capital of Japan?', 'how did I sleep']) {
        expect(isQuestionOnly(q), isTrue, reason: q);
      }
    });

    test('statements and requests for a change are not', () {
      for (final String q in <String>['I drank a glass of water', 'log a glass of water', 'remind me to call mom', 'can you add a task to buy milk?', 'could you schedule a meeting at 3?', 'spent 250 on lunch', 'the weekly report is done', 'I did my workout', 'note: ask the landlord', 'hello K', 'thanks']) {
        expect(isQuestionOnly(q), isFalse, reason: q);
      }
    });
  });

  group('judge', () {
    AgentPlan plan(String say, [List<Map<String, dynamic>> actions = const <Map<String, dynamic>>[]]) => AgentPlan(say, <AgentAction>[for (final Map<String, dynamic> a in actions) AgentAction(a['type'] as String, a)]);

    test('right action and fields pass; wrong ones say why', () {
      const BrainCase c = BrainCase('x', 'log_water', args: <String, Object>{'ml': 250});
      expect(judge(c, plan('ok', <Map<String, dynamic>>[<String, dynamic>{'type': 'log_water', 'ml': 250}])).ok, isTrue);
      expect(judge(c, plan('ok', <Map<String, dynamic>>[<String, dynamic>{'type': 'log_water', 'ml': 500}])).detail, 'ml was 500, expected 250');
      expect(judge(c, plan('ok')).detail, 'expected log_water, got no action');
      expect(judge(c, plan('ok', <Map<String, dynamic>>[<String, dynamic>{'type': 'add_note', 'text': 'x'}])).ok, isFalse);
    });

    test('strings compare loosely, and an extra action is a miss', () {
      const BrainCase c = BrainCase('x', 'complete_objective', args: <String, Object>{'title': 'Call the plumber'});
      expect(judge(c, plan('ok', <Map<String, dynamic>>[<String, dynamic>{'type': 'complete_objective', 'title': ' call the PLUMBER '}])).ok, isTrue);
      expect(judge(c, plan('ok', <Map<String, dynamic>>[<String, dynamic>{'type': 'complete_objective', 'title': 'Call the plumber'}, <String, dynamic>{'type': 'log_water', 'ml': 250}])).ok, isFalse);
    });

    test('a question must be answered without acting, with the right fact', () {
      const BrainCase c = BrainCase('how much water', null, say: '750');
      expect(judge(c, plan('You have had 750 ml.')).ok, isTrue);
      expect(judge(c, plan('A lot.')).ok, isFalse);
      expect(judge(c, plan('750 ml.', <Map<String, dynamic>>[<String, dynamic>{'type': 'log_water', 'ml': 750}])).ok, isFalse);
    });

    test('the sample set is well formed', () {
      expect(kEvalCases.map((BrainCase c) => c.utterance).toSet().length, kEvalCases.length);
      for (final BrainCase c in kEvalCases) {
        if (c.type != null) expect(kBrainActionTypes, contains(c.type));
      }
      expect(kEvalCases.length, greaterThanOrEqualTo(20));
    });
  });

  group('ModelStore', () {
    test('downloads, checks the GGUF header, and installs', () async {
      final ModelStore store = ModelStore(dir: dir, client: serving(ggufBytes()));
      final List<int> seen = <int>[];
      await store.download(BrainVariant.q4km, onProgress: (int got, int total) => seen.add(got));
      expect(await store.installedPath(BrainVariant.q4km), endsWith('MiniCPM5-1B-Q4_K_M.gguf'));
      expect(seen.last, 1200000);
      expect(File('${dir.path}/MiniCPM5-1B-Q4_K_M.gguf.part').existsSync(), isFalse);
    });

    test('resumes from the partial file with a Range request', () async {
      final Uint8List data = ggufBytes();
      File('${dir.path}/MiniCPM5-1B-Q4_K_M.gguf.part').writeAsBytesSync(data.sublist(0, 500000));
      final List<String?> ranges = <String?>[];
      final ModelStore store = ModelStore(dir: dir, client: serving(data, ranges: ranges));
      expect(await store.partialBytes(BrainVariant.q4km), 500000);
      await store.download(BrainVariant.q4km);
      expect(ranges.single, 'bytes=500000-');
      expect(File('${dir.path}/MiniCPM5-1B-Q4_K_M.gguf').lengthSync(), 1200000);
    });

    test('a server that ignores Range restarts cleanly instead of corrupting the file', () async {
      final Uint8List data = ggufBytes();
      File('${dir.path}/MiniCPM5-1B-Q4_K_M.gguf.part').writeAsBytesSync(data.sublist(0, 400000));
      final ModelStore store = ModelStore(dir: dir, client: serving(data, honourRange: false));
      await store.download(BrainVariant.q4km);
      expect(File('${dir.path}/MiniCPM5-1B-Q4_K_M.gguf').lengthSync(), 1200000);
    });

    test('something that is not a GGUF is refused and removed', () async {
      final Uint8List html = Uint8List(1200000)..setAll(0, '<html>'.codeUnits);
      final ModelStore store = ModelStore(dir: dir, client: serving(html));
      await expectLater(store.download(BrainVariant.q4km), throwsA(isA<ModelDownloadException>().having((ModelDownloadException e) => e.message, 'message', 'The downloaded file is not a GGUF model.')));
      expect(await store.installedPath(BrainVariant.q4km), isNull);
      expect(await store.partialBytes(BrainVariant.q4km), 0);
    });

    test('a cut-off download keeps its partial file so it can resume', () async {
      final Uint8List data = ggufBytes();
      final MockClient cut = MockClient.streaming((http.BaseRequest req, http.ByteStream body) async => http.StreamedResponse(Stream<List<int>>.value(data.sublist(0, 700000)), 200, contentLength: data.length));
      final ModelStore store = ModelStore(dir: dir, client: cut);
      await expectLater(store.download(BrainVariant.q4km), throwsA(isA<ModelDownloadException>().having((ModelDownloadException e) => e.message, 'message', contains('Try again to resume'))));
      expect(await store.partialBytes(BrainVariant.q4km), 700000);
      expect(await store.installedPath(BrainVariant.q4km), isNull);
    });

    test('cancelling pauses without error and keeps the partial file', () async {
      final DownloadControl control = DownloadControl();
      final ModelStore store = ModelStore(dir: dir, client: serving(ggufBytes()));
      await store.download(BrainVariant.q4km, control: control, onProgress: (int got, int total) => control.cancel());
      expect(await store.installedPath(BrainVariant.q4km), isNull);
      expect(await store.partialBytes(BrainVariant.q4km), greaterThan(0));
    });

    test('a server error is explained, and delete removes both files', () async {
      final ModelStore bad = ModelStore(dir: dir, client: MockClient.streaming((http.BaseRequest r, http.ByteStream b) async => http.StreamedResponse(const Stream<List<int>>.empty(), 404)));
      await expectLater(bad.download(BrainVariant.q8), throwsA(isA<ModelDownloadException>().having((ModelDownloadException e) => e.message, 'message', 'The download server answered HTTP 404.')));
      File('${dir.path}/MiniCPM5-1B-Q8_0.gguf').writeAsBytesSync(ggufBytes());
      File('${dir.path}/MiniCPM5-1B-Q8_0.gguf.part').writeAsBytesSync(ggufBytes(10));
      await bad.delete(BrainVariant.q8);
      expect(Directory(dir.path).listSync(), isEmpty);
    });

    test('the model URLs point at OpenBMB\'s own repository', () {
      expect(BrainVariant.q4km.url, 'https://huggingface.co/openbmb/MiniCPM5-1B-GGUF/resolve/main/MiniCPM5-1B-Q4_K_M.gguf');
      expect(BrainVariant.q8.sizeText, '1.15 GB');
      expect(BrainVariant.q4km.sizeText, '688 MB');
    });
  });

  group('LocalBrain', () {
    Future<(LocalBrain, FakeEngine)> installed({String? reply}) async {
      File('${dir.path}/MiniCPM5-1B-Q4_K_M.gguf').writeAsBytesSync(ggufBytes());
      final FakeEngine e = FakeEngine(reply: reply ?? '{"actions":[],"say":"Paris."}');
      final LocalBrain b = LocalBrain(engine: e, store: ModelStore(dir: dir));
      await b.init();
      return (b, e);
    }

    test('nothing is loaded until the first request, and the answer comes back', () async {
      final (LocalBrain b, FakeEngine e) = await installed();
      expect(b.usable, isTrue);
      expect(e.loads, 0, reason: 'idle costs nothing');
      final CloudReply r = await b.run(const <BrainTurn>[BrainTurn('user', 'hi')]);
      expect(r.text, '{"actions":[],"say":"Paris."}');
      expect(r.model, 'MiniCPM5-1B Q4_K_M');
      expect(e.loads, 1);
      expect(e.lastLoad!.threads, 4);
      expect(e.lastLoad!.contextSize, 2048);
      expect(e.lastSchema, kBrainSchema);
      expect(e.lastSampling!.maxTokens, lessThanOrEqualTo(256));
      await b.run(const <BrainTurn>[BrainTurn('user', 'again')]);
      expect(e.loads, 1, reason: 'still loaded, so no second load');
      expect(b.lastLoadMs, isNotNull);
    });

    test('it lets go of the model after the idle time and loads again on demand', () async {
      final (LocalBrain b, FakeEngine e) = await installed();
      b.idleOverride = const Duration(milliseconds: 40);
      await b.run(const <BrainTurn>[BrainTurn('user', 'hi')]);
      expect(e.loaded, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(e.loaded, isFalse);
      expect(e.unloads, 1);
      await b.run(const <BrainTurn>[BrainTurn('user', 'hi')]);
      expect(e.loads, 2);
    });

    test('going to the background releases it after a grace period, and coming back keeps it', () async {
      final (LocalBrain b, FakeEngine e) = await installed();
      await b.run(const <BrainTurn>[BrainTurn('user', 'hi')]);
      b.idleOverride = const Duration(milliseconds: 40);
      b.onBackground();
      b.onForeground();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(e.loaded, isTrue, reason: 'back in time');
      b.onBackground();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(e.loaded, isFalse);
    });

    test('opening the microphone preloads it, so the answer is not delayed', () async {
      final (LocalBrain b, FakeEngine e) = await installed();
      await b.preload();
      expect(e.loaded, isTrue);
      expect(e.loads, 1);
    });

    test('requests run one at a time', () async {
      final (LocalBrain b, FakeEngine e) = await installed();
      await Future.wait(<Future<CloudReply>>[for (int i = 0; i < 4; i++) b.run(const <BrainTurn>[BrainTurn('user', 'q')])]);
      expect(e.maxRunning, 1);
      expect(e.loads, 1);
    });

    test('a model that cannot load fails cleanly and the next try starts fresh', () async {
      final (LocalBrain b, FakeEngine e) = await installed();
      e.failLoad = true;
      final CloudReply r = await b.run(const <BrainTurn>[BrainTurn('user', 'hi')]);
      expect(r.text, isNull);
      expect(r.error, startsWith('K\'s brain failed'));
      e.failLoad = false;
      expect((await b.run(const <BrainTurn>[BrainTurn('user', 'hi')])).text, isNotNull);
    });

    test('a runaway answer is stopped', () async {
      final (LocalBrain b, FakeEngine e) = await installed();
      e.hang = true;
      final CloudReply r = await b.run(const <BrainTurn>[BrainTurn('user', 'hi')], timeout: const Duration(milliseconds: 80));
      expect(r.text, isNull);
      expect(e.cancels, greaterThan(0));
    });

    test('not downloaded and switched off are both explained, without touching the engine', () async {
      final FakeEngine e = FakeEngine();
      final LocalBrain none = LocalBrain(engine: e, store: ModelStore(dir: dir));
      await none.init();
      expect(none.usable, isFalse);
      expect(none.status, BrainStatus.notInstalled);
      expect((await none.run(const <BrainTurn>[BrainTurn('user', 'hi')])).error, contains('not downloaded'));

      final (LocalBrain b, FakeEngine e2) = await installed();
      await b.run(const <BrainTurn>[BrainTurn('user', 'hi')]);
      await b.setEnabled(false);
      expect(e2.loaded, isFalse, reason: 'switching it off frees the memory');
      expect((await b.run(const <BrainTurn>[BrainTurn('user', 'hi')])).error, contains('switched off'));
      expect(e.loads, 0);
    });

    test('settings are remembered, and a thread change reloads', () async {
      final (LocalBrain b, FakeEngine e) = await installed();
      await b.setIdleMinutes(5);
      await b.setThreads(3);
      await b.run(const <BrainTurn>[BrainTurn('user', 'hi')]);
      expect(e.lastLoad!.threads, 3);
      await b.setThreads(2);
      expect(e.loaded, isFalse);
      final LocalBrain again = LocalBrain(engine: FakeEngine(), store: ModelStore(dir: dir));
      await again.init();
      expect((again.idleMinutes, again.threads, again.enabled), (5, 2, true));
    });

    test('downloading through the brain installs it and reports progress', () async {
      final LocalBrain b = LocalBrain(engine: FakeEngine(), store: ModelStore(dir: dir, client: serving(ggufBytes())));
      await b.init();
      expect(b.status, BrainStatus.notInstalled);
      expect(await b.download(), isNull);
      expect(b.progress.value, 1);
      expect(b.status, BrainStatus.ready);
      expect(b.usable, isTrue);
      await b.remove();
      expect(b.status, BrainStatus.notInstalled);
    });
  });

  group('Assistant with K\'s brain', () {
    late VigilStore store;

    setUp(() async {
      store = await VigilStore.load();
    });

    Future<LocalBrain> brainReplying(String reply, FakeEngine engine) async {
      File('${dir.path}/MiniCPM5-1B-Q4_K_M.gguf').writeAsBytesSync(ggufBytes());
      engine.reply = reply;
      final LocalBrain b = LocalBrain(engine: engine, store: ModelStore(dir: dir));
      await b.init();
      return b;
    }

    test('clear commands are done by the rules, without waking the model', () async {
      final FakeEngine e = FakeEngine();
      final Assistant a = Assistant(store, brain: await brainReplying('{"actions":[],"say":"x"}', e));
      final ChatMsg m = await a.reply('remind me to call mom tomorrow at 6 pm');
      expect(m.text, 'Done. Call mom, tomorrow at 18:00.');
      expect(store.objectives.single.title, 'Call mom');
      expect(m.undoable, isTrue);
      expect(e.loads, 0);
      expect(a.lastWasLocal, isFalse, reason: 'rules, not the model');
      m.onUndo!();
      expect(store.objectives, isEmpty);
    });

    test('the model handles other language, and its change can be undone', () async {
      final FakeEngine e = FakeEngine();
      final Assistant a = Assistant(store, brain: await brainReplying('{"actions":[{"type":"add_objective","title":"Water the plants"}],"say":"Done. Water the plants."}', e));
      store.chat.add(ChatMsg(fromUser: true, text: 'put a reminder to water the plants on my list', at: DateTime.now()));
      final ChatMsg m = await a.reply('put a reminder to water the plants on my list');
      expect(m.text, 'Done. Water the plants.');
      expect(store.objectives.single.title, 'Water the plants');
      expect(a.lastWasLocal, isTrue);
      expect(a.lastModel, 'MiniCPM5-1B Q4_K_M');
      expect(e.loads, 1);
      expect(e.lastMessages!.last.text, contains('User: put a reminder to water the plants on my list'));
      m.onUndo!();
      expect(store.objectives, isEmpty);
    });

    test('a general question is answered by the model, with no change', () async {
      final FakeEngine e = FakeEngine();
      final Assistant a = Assistant(store, brain: await brainReplying('{"actions":[],"say":"Tokyo."}', e));
      final ChatMsg m = await a.reply('what is the capital of Japan?');
      expect(m.text, 'Tokyo.');
      expect(m.diff, isNull);
      expect(a.lastWasLocal, isTrue);
    });

    test('an exact amount of water needs no model at all', () async {
      final FakeEngine e = FakeEngine();
      final Assistant a = Assistant(store, brain: await brainReplying('{"actions":[],"say":"x"}', e));
      final ChatMsg m = await a.reply('log 500 ml water');
      expect(store.waterMl, 500);
      expect(m.text, startsWith('Logged 500 ml'));
      expect(e.loads, 0);
    });

    test('questions about the user\'s own data are answered from the store, without the model', () async {
      store.logWater(500);
      final FakeEngine e = FakeEngine();
      final Assistant a = Assistant(store, brain: await brainReplying('{"actions":[],"say":"I have no idea."}', e));
      final ChatMsg m = await a.reply('how much water have I had today?');
      expect(m.text, contains('Hydration 0.5 of 3.0 L'));
      expect(e.loads, 0);
    });

    test('when the model fails, the reason is shown and the on-device router still answers', () async {
      final FakeEngine e = FakeEngine()..failLoad = true;
      final Assistant a = Assistant(store, brain: await brainReplying('{}', e));
      final ChatMsg m = await a.reply('tell me a joke');
      expect(m.text, contains('Local mode'));
      expect(m.note, startsWith('K\'s brain failed'));
      expect(a.lastWasLocal, isFalse);
    });

    test('a change the user did not ask for is ignored, and the model\'s sentence is not shown', () async {
      store.logWater(500);
      final FakeEngine e = FakeEngine();
      final Assistant a = Assistant(store, brain: await brainReplying('{"actions":[{"type":"log_water","ml":750}],"say":"I logged 750 millilitres of water today."}', e));
      final ChatMsg m = await a.reply('what is the capital of France?');
      expect(store.waterMl, 500, reason: 'nothing was logged');
      expect(m.text, isNot(contains('750')));
      expect(m.note, 'K proposed a change that did not match what you said, so it was ignored.');
      expect(m.diff, isNull);
      expect(a.lastWasLocal, isFalse);
    });

    test('without the model downloaded the router answers as before', () async {
      final Assistant a = Assistant(store, brain: LocalBrain(engine: FakeEngine(), store: ModelStore(dir: dir)));
      final ChatMsg m = await a.reply('how much water today');
      expect(m.text, contains('Hydration'));
      expect(m.note, isNull);
    });

    test('Cloud AI, if the user turned it on, still takes precedence', () async {
      dotenv.testLoad(fileInput: 'CLOUD_AI_PROVIDER=gemini\nCLOUD_AI_API_KEY=k\n');
      store.toggles['cloudAi'] = true;
      final FakeEngine e = FakeEngine();
      final MockClient cloud = MockClient((http.Request r) async => http.Response(
            jsonEncode(<String, dynamic>{
              'candidates': <Map<String, dynamic>>[
                <String, dynamic>{
                  'content': <String, dynamic>{
                    'parts': <Map<String, String>>[<String, String>{'text': '{"actions":[],"say":"From the cloud."}'}],
                  },
                },
              ],
            }),
            200,
          ));
      final Assistant a = Assistant(store, client: cloud, brain: await brainReplying('{"actions":[],"say":"x"}', e));
      expect((await a.reply('hello')).text, 'From the cloud.');
      expect(e.loads, 0);
    });
  });
}
