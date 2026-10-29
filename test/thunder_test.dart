import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigil/data/store.dart';
import 'package:vigil/services/haptics.dart';
import 'package:vigil/vigil/vigil.dart';

void main() {
  setUp(() {
    ThunderFx.level = ThunderFx.full;
    Haptics.level = 2;
  });

  Widget host({required Widget Function(BuildContext) body, bool reduceMotion = false}) => MaterialApp(
        home: Builder(
          builder: (BuildContext context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
            child: Scaffold(body: Builder(builder: body)),
          ),
        ),
      );

  group('strike', () {
    testWidgets('flashes and then removes itself, and never blocks a tap', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(host(body: (BuildContext context) => Center(child: ElevatedButton(onPressed: () {
            taps++;
            if (taps == 1) ThunderFx.strike(context);
          }, child: const Text('go')))));
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.byType(StrikeFlash), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(StrikeFlash), findsOneWidget, reason: 'mid-flash');
      await tester.tap(find.text('go'), warnIfMissed: false);
      expect(taps, 2, reason: 'the overlay lets taps through');
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(StrikeFlash), findsNothing);
    });

    testWidgets('is skipped when the user switched thunder effects off', (WidgetTester tester) async {
      ThunderFx.level = ThunderFx.subtle;
      await tester.pumpWidget(host(body: (BuildContext context) => Center(child: ElevatedButton(onPressed: () => ThunderFx.strike(context), child: const Text('go')))));
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.byType(StrikeFlash), findsNothing);
    });

    testWidgets('is skipped when the system asks for reduced motion', (WidgetTester tester) async {
      await tester.pumpWidget(host(reduceMotion: true, body: (BuildContext context) => Center(child: ElevatedButton(onPressed: () => ThunderFx.strike(context), child: const Text('go')))));
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.byType(StrikeFlash), findsNothing);
    });
  });

  group('storm flicker', () {
    Widget flicker({Duration gap = const Duration(seconds: 1)}) => Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(data: const MediaQueryData(), child: StormFlicker(minGap: gap, maxGap: gap, child: const SizedBox.expand())),
        );

    testWidgets('lights the top of the screen now and then, then goes dark again', (WidgetTester tester) async {
      await tester.pumpWidget(flicker());
      expect(find.byType(DecoratedBox), findsNothing, reason: 'dark at first');
      await tester.pump(const Duration(milliseconds: 1050));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(DecoratedBox), findsOneWidget, reason: 'mid-flicker');
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(DecoratedBox), findsNothing, reason: 'dark again');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('stays dark when effects are off, and never takes a tap', (WidgetTester tester) async {
      ThunderFx.level = ThunderFx.subtle;
      await tester.pumpWidget(flicker());
      await tester.pump(const Duration(milliseconds: 1050));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(DecoratedBox), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('haptics', () {
    late List<String> buzzes;

    setUp(() {
      buzzes = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
        if (call.method == 'HapticFeedback.vibrate') buzzes.add('${call.arguments}');
        return null;
      });
    });

    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    testWidgets('tick, tap and rumble are one buzz each, strike is two', (WidgetTester tester) async {
      Haptics.tick();
      Haptics.tap();
      Haptics.rumble();
      expect(buzzes, <String>['HapticFeedbackType.selectionClick', 'HapticFeedbackType.mediumImpact', 'HapticFeedbackType.heavyImpact']);
      buzzes.clear();
      Haptics.strike();
      await tester.pump(const Duration(milliseconds: 200));
      expect(buzzes, <String>['HapticFeedbackType.mediumImpact', 'HapticFeedbackType.mediumImpact']);
    });

    testWidgets('nothing buzzes when haptics are switched off', (WidgetTester tester) async {
      Haptics.level = 0;
      Haptics.tick();
      Haptics.tap();
      Haptics.strike();
      Haptics.rumble();
      await tester.pump(const Duration(milliseconds: 200));
      expect(buzzes, isEmpty);
    });
  });

  test('effects are full by default, and the level is saved', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final VigilStore s = await VigilStore.load();
    expect(s.effectsLevel, 2);
    s.setEffects(1);
    await s.reloadFromDisk();
    expect(s.effectsLevel, 1);
  });

  test('older switches carry over: thunder off means Off, haptics off means Subtle', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'toggles': '{"effects":false,"haptics":true}'});
    expect((await VigilStore.load()).effectsLevel, 0);
    SharedPreferences.setMockInitialValues(<String, Object>{'toggles': '{"effects":true,"haptics":false}'});
    expect((await VigilStore.load()).effectsLevel, 1);
  });
}
