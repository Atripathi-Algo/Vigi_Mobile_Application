import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigil/api/cloud_ai.dart';
import 'package:vigil/data/agent.dart';
import 'package:vigil/data/assistant.dart';
import 'package:vigil/data/models.dart';
import 'package:vigil/data/store.dart';
import 'package:vigil/services/voice.dart';
import 'package:vigil/vigil/vigil.dart';

http.Response json(int code, Object body) => http.Response(jsonEncode(body), code, headers: <String, String>{'content-type': 'application/json'});

/// A Gemini success whose text is [text].
http.Response gemini(String text) => json(200, <String, dynamic>{
      'candidates': <Map<String, dynamic>>[
        <String, dynamic>{
          'content': <String, dynamic>{
            'parts': <Map<String, String>>[<String, String>{'text': text}],
          },
        },
      ],
    });

AgentPlan plan(List<Map<String, dynamic>> actions, [String say = 'ok']) => AgentPlan(say, <AgentAction>[for (final Map<String, dynamic> a in actions) AgentAction(a['type'] as String, a)]);

void main() {
  late VigilStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dotenv.testLoad(fileInput: 'CLOUD_AI_PROVIDER=gemini\nCLOUD_AI_API_KEY=k\nCLOUD_AI_MODEL=gemini-3.5-flash-lite\n');
    store = await VigilStore.load();
  });

  group('parseAgentPlan', () {
    test('reads a bare JSON reply', () {
      final AgentPlan p = parseAgentPlan('{"say":"Logged.","actions":[{"type":"log_water","ml":250}]}');
      expect(p.say, 'Logged.');
      expect(p.actions.single.type, 'log_water');
      expect(p.actions.single.args['ml'], 250);
    });

    test('reads JSON inside a code fence or chatter', () {
      expect(parseAgentPlan('```json\n{"say":"Hi","actions":[]}\n```').say, 'Hi');
      expect(parseAgentPlan('Sure! {"say":"Done","actions":[]} Hope that helps.').say, 'Done');
    });

    test('plain text is spoken as it is, with no actions', () {
      final AgentPlan p = parseAgentPlan('The capital of France is Paris.');
      expect(p.say, 'The capital of France is Paris.');
      expect(p.actions, isEmpty);
      expect(parseAgentPlan('{"unrelated": 1}').say, '{"unrelated": 1}');
    });

    test('caps the number of actions and ignores malformed ones', () {
      final String many = jsonEncode(<String, dynamic>{
        'say': 'x',
        'actions': <dynamic>[
          'junk',
          <String, dynamic>{'nope': 1},
          for (int i = 0; i < 9; i++) <String, dynamic>{'type': 'log_water', 'ml': 100},
        ],
      });
      expect(parseAgentPlan(many).actions.length, lessThanOrEqualTo(5));
    });
  });

  group('applyAgentPlan', () {
    test('adds an objective with a due time and threat, and undo removes it', () {
      final AgentResult r = applyAgentPlan(store, plan(<Map<String, dynamic>>[
        <String, dynamic>{'type': 'add_objective', 'title': 'Call the plumber', 'due': '17:30', 'threat': 'high'},
      ]));
      final Objective o = store.objectives.single;
      expect(o.title, 'Call the plumber');
      expect(o.dueMin, 17 * 60 + 30);
      expect(o.threat, Threat.high);
      expect(r.diff.single.$1, 'OBJECTIVE');
      r.undo!();
      expect(store.objectives, isEmpty);
    });

    test('adds an event with its own length, for today or tomorrow', () {
      final DateTime now = DateTime(2026, 10, 23, 9);
      applyAgentPlan(store, plan(<Map<String, dynamic>>[
        <String, dynamic>{'type': 'add_event', 'title': 'Dentist', 'start': '15:00', 'end': '16:15'},
        <String, dynamic>{'type': 'add_event', 'title': 'Review', 'start': '10:00', 'day': 'tomorrow'},
      ]), now: now);
      final Block today = store.blocks.firstWhere((Block b) => b.title == 'Dentist');
      expect((today.startMin, today.endMin), (900, 975));
      expect(today.dayKey, '2026-10-23');
      final Block tomorrow = store.blocks.firstWhere((Block b) => b.title == 'Review');
      expect(tomorrow.endMin - tomorrow.startMin, 30, reason: 'default length');
      expect(tomorrow.dayKey, '2026-10-24');
    });

    test('logs water within limits, and spend in paise', () {
      final AgentResult r = applyAgentPlan(store, plan(<Map<String, dynamic>>[
        <String, dynamic>{'type': 'log_water', 'ml': 500},
        <String, dynamic>{'type': 'log_water', 'ml': 99999},
        <String, dynamic>{'type': 'log_expense', 'title': 'Lunch', 'amount': 250.5, 'category': 'food'},
        <String, dynamic>{'type': 'log_expense', 'title': 'Free', 'amount': 0},
      ]));
      expect(store.waterMl, 500);
      expect(store.txns.single.paise, 25050);
      expect(store.txns.single.category, 'FOOD');
      expect(r.failed.length, 2);
      r.undo!();
      expect(store.waterMl, 0);
      expect(store.txns, isEmpty);
    });

    test('clears an objective only when exactly one open objective matches', () {
      store.addObjective('Send weekly report');
      store.addObjective('Send invoice');
      final AgentResult ambiguous = applyAgentPlan(store, plan(<Map<String, dynamic>>[
        <String, dynamic>{'type': 'complete_objective', 'title': 'send'},
      ]));
      expect(ambiguous.diff, isEmpty);
      expect(ambiguous.failed.single, contains('exactly one'));

      final AgentResult ok = applyAgentPlan(store, plan(<Map<String, dynamic>>[
        <String, dynamic>{'type': 'complete_objective', 'title': 'Send weekly report'},
      ]));
      expect(store.open.map((Objective o) => o.title), <String>['Send invoice']);
      ok.undo!();
      expect(store.open.length, 2);
    });

    test('checks a protocol once and reports a repeat', () {
      store.addProtocol('Read 20 pages');
      applyAgentPlan(store, plan(<Map<String, dynamic>>[
        <String, dynamic>{'type': 'check_protocol', 'name': 'read'},
      ]));
      expect(store.protocols.single.doneToday, isTrue);
      final AgentResult again = applyAgentPlan(store, plan(<Map<String, dynamic>>[
        <String, dynamic>{'type': 'check_protocol', 'name': 'read'},
      ]));
      expect(again.failed.single, contains('already checked'));
      expect(store.protocols.single.doneToday, isTrue);
    });

    test('bad and unknown actions are reported and change nothing', () {
      final AgentResult r = applyAgentPlan(store, plan(<Map<String, dynamic>>[
        <String, dynamic>{'type': 'add_objective'},
        <String, dynamic>{'type': 'add_event', 'title': 'No time'},
        <String, dynamic>{'type': 'add_event', 'title': 'Bad time', 'start': '25:99'},
        <String, dynamic>{'type': 'add_note', 'text': '  '},
        <String, dynamic>{'type': 'delete_everything'},
      ]));
      expect(r.diff, isEmpty);
      expect(r.undo, isNull);
      expect(r.failed.length, 5);
      expect(store.objectives, isEmpty);
      expect(store.blocks, isEmpty);
    });

    test('there is no action that deletes or sends anything', () {
      applyAgentPlan(store, plan(<Map<String, dynamic>>[
        <String, dynamic>{'type': 'remove_objective', 'title': 'x'},
        <String, dynamic>{'type': 'send_email', 'to': 'a@b.c'},
        <String, dynamic>{'type': 'erase_all'},
      ]));
      expect(store.objectives, isEmpty);
    });
  });

  group('Assistant with Cloud AI on', () {
    test('open chat goes to the cloud with no app data, and nothing is changed', () async {
      store.toggles['cloudAi'] = true;
      late Map<String, dynamic> body;
      final MockClient client = MockClient((http.Request r) async {
        body = jsonDecode(r.body) as Map<String, dynamic>;
        return gemini('Paris.');
      });
      store.logWater(500);
      store.chat
        ..add(ChatMsg(fromUser: true, text: 'how much water today?', at: DateTime.now()))
        ..add(ChatMsg(fromUser: false, text: 'Hydration 0.5 of 3.0 L.', at: DateTime.now(), source: ReplySource.data))
        ..add(ChatMsg(fromUser: true, text: 'earlier open question', at: DateTime.now()))
        ..add(ChatMsg(fromUser: false, text: 'earlier open answer', at: DateTime.now(), source: ReplySource.model))
        ..add(ChatMsg(fromUser: true, text: 'what is the capital of France?', at: DateTime.now()));
      final Assistant a = Assistant(store, client: client);
      final ChatMsg m = await a.reply('what is the capital of France?');
      expect(m.text, 'Paris.');
      expect(m.source, ReplySource.cloud);
      expect(m.diff, isNull);
      expect(a.lastWasCloud, isTrue);
      expect(store.waterMl, 500);

      final String sys = body['systemInstruction']['parts'][0]['text'] as String;
      expect(sys, allOf(contains('plain sentences'), isNot(contains('"actions"'))));
      final List<dynamic> contents = body['contents'] as List<dynamic>;
      expect(contents.map((dynamic c) => c['role']), <String>['user', 'model', 'user']);
      expect(jsonEncode(body), allOf(isNot(contains('SITREP')), isNot(contains('Hydration')), isNot(contains('0.5'))));
      expect(contents.last['parts'][0]['text'], 'what is the capital of France?');
      expect(body['generationConfig']?['responseMimeType'], isNull);
    });

    test('a command is done by the rules and never leaves the phone', () async {
      store.toggles['cloudAi'] = true;
      int calls = 0;
      final MockClient client = MockClient((http.Request r) async {
        calls++;
        return gemini('should not be called');
      });
      final ChatMsg m = await Assistant(store, client: client).reply('log a glass of water');
      expect(calls, 0);
      expect(store.waterMl, 250);
      expect(m.source, ReplySource.instant);
      expect(m.undoable, isTrue);
    });

    test('a question about the user\'s data is answered from the store, not the cloud', () async {
      store.toggles['cloudAi'] = true;
      int calls = 0;
      final MockClient client = MockClient((http.Request r) async {
        calls++;
        return gemini('should not be called');
      });
      final ChatMsg m = await Assistant(store, client: client).reply('how much water today');
      expect(calls, 0);
      expect(m.text, contains('Hydration'));
      expect(m.source, ReplySource.data);
    });

    test('when the call fails the reason is shown and the on-device answer still works', () async {
      store.toggles['cloudAi'] = true;
      final MockClient client = MockClient((http.Request r) async => json(401, <String, dynamic>{
            'error': <String, dynamic>{'message': 'API key not valid.'},
          }));
      final ChatMsg m = await Assistant(store, client: client).reply('tell me a joke');
      expect(m.text, contains('Local mode'));
      expect(m.note, allOf(startsWith('Cloud AI failed'), contains('HTTP 401'), contains('aistudio.google.com')));
    });
  });

  group('Gemini fallback', () {
    test('a refused model falls back to a free one and says so', () async {
      final List<String> asked = <String>[];
      final MockClient client = MockClient((http.Request r) async {
        asked.add(r.url.pathSegments.last.split(':').first);
        if (asked.length == 1) {
          return json(402, <String, dynamic>{
            'error': <String, dynamic>{'message': 'Your prepayment credits are depleted.'},
          });
        }
        return gemini('Ready.');
      });
      final CloudReply r = await askCloudDetailed('q', '{}', client: client);
      expect(r.text, 'Ready.');
      expect(asked, <String>['gemini-3.5-flash-lite', 'gemini-flash-latest']);
      expect(r.model, 'gemini-flash-latest');
      expect(r.note, allOf(contains('gemini-3.5-flash-lite was refused'), contains('HTTP 402'), contains('Answered by gemini-flash-latest')));
    });

    test('tries each free model once, never a paid one, then explains', () async {
      final List<String> asked = <String>[];
      final MockClient client = MockClient((http.Request r) async {
        asked.add(r.url.pathSegments.last.split(':').first);
        return json(429, <String, dynamic>{
          'error': <String, dynamic>{'message': 'Quota exceeded'},
        });
      });
      final CloudReply r = await askCloudDetailed('q', '{}', client: client);
      expect(asked, <String>['gemini-3.5-flash-lite', ...kGeminiFreeFallbacks]);
      expect(r.text, isNull);
      expect(r.error, allOf(contains('HTTP 429'), contains('Wait a minute'), contains('Also tried gemini-flash-latest')));
    });

    test('an invalid key is not retried', () async {
      int calls = 0;
      final MockClient client = MockClient((http.Request r) async {
        calls++;
        return json(400, <String, dynamic>{
          'error': <String, dynamic>{'message': 'API key not valid.'},
        });
      });
      final CloudReply r = await askCloudDetailed('q', '{}', client: client);
      expect(calls, 1);
      expect(r.error, 'HTTP 400: API key not valid.');
    });

    test('the 402 message says what it means', () async {
      final MockClient client = MockClient((http.Request r) async => json(402, <String, dynamic>{
            'error': <String, dynamic>{'message': 'Your prepayment credits are depleted.'},
          }));
      dotenv.testLoad(fileInput: 'CLOUD_AI_PROVIDER=gemini\nCLOUD_AI_API_KEY=k\nCLOUD_AI_BASE_URL=https://example.test\n');
      final CloudReply r = await askCloudDetailed('q', '{}', client: client);
      expect(r.error, allOf(contains('HTTP 402'), contains('prepaid billing')));
    });

    test('other providers are not retried on other models', () async {
      dotenv.testLoad(fileInput: 'CLOUD_AI_PROVIDER=openai\nCLOUD_AI_API_KEY=k\nCLOUD_AI_MODEL=gpt-x\n');
      int calls = 0;
      final MockClient client = MockClient((http.Request r) async {
        calls++;
        return json(429, <String, dynamic>{
          'error': <String, dynamic>{'message': 'slow down'},
        });
      });
      await askCloudDetailed('q', '{}', client: client);
      expect(calls, 1);
    });

    test('history is sent as strictly alternating turns starting with the user', () async {
      dotenv.testLoad(fileInput: 'CLOUD_AI_PROVIDER=anthropic\nCLOUD_AI_API_KEY=k\n');
      late Map<String, dynamic> body;
      final MockClient client = MockClient((http.Request r) async {
        body = jsonDecode(r.body) as Map<String, dynamic>;
        return json(200, <String, dynamic>{
          'content': <Map<String, String>>[<String, String>{'type': 'text', 'text': 'ok'}],
        });
      });
      await askCloudDetailed('now', '{}', client: client, history: const <ChatTurn>[
        ChatTurn(false, 'orphan assistant'),
        ChatTurn(true, 'a'),
        ChatTurn(true, 'b'),
        ChatTurn(false, 'c'),
      ]);
      final List<dynamic> msgs = body['messages'] as List<dynamic>;
      expect(msgs.map((dynamic m) => m['role']), <String>['user', 'assistant', 'user']);
      expect(msgs.first['content'], 'a\nb');
    });
  });

  group('speakable', () {
    test('units and symbols are spelled out for the voice', () {
      expect(speakable('Hydration 1.2 of 3.0 L. Recommend 500 ml now.'), 'Hydration 1.2 of 3.0 litres. Recommend 500 millilitres now.');
      expect(speakable('Spent ₹1,250 on lunch'), 'Spent 1250 rupees on lunch');
      expect(speakable('Standup 09:00–09:30 · Vendor sync'), 'Standup 09:00 to 09:30 , Vendor sync');
      expect(speakable('WORK × PERSONAL'), 'WORK versus PERSONAL');
      expect(speakable('**Bold** and `code`'), 'Bold and code');
      expect(speakable('line one\nline two'), 'line one. line two');
    });
  });
}
