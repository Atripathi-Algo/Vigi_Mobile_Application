import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil/theme/vigil_theme.dart';
import 'package:vigil/vigil/vigil.dart';

Widget host(Widget child, {bool reduce = false}) => MaterialApp(
      theme: buildVigilTheme(Brightness.light),
      home: Builder(
        builder: (BuildContext context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );

void main() {
  setUp(() => ThunderFx.level = ThunderFx.full);

  testWidgets('ticking a checkbox throws sparks, which clear themselves, and never block the tap', (WidgetTester tester) async {
    bool done = false;
    await tester.pumpWidget(host(StatefulBuilder(builder: (BuildContext context, StateSetter set) => VigilCheckbox(value: done, semanticLabel: 'x', onChanged: (bool v) => set(() => done = v)))));
    await tester.tap(find.byType(VigilCheckbox));
    await tester.pump();
    expect(done, isTrue);
    expect(find.byType(SparkBurst), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SparkBurst), findsNothing);
  });

  testWidgets('un-ticking does not spark, and neither does Effects off or reduced motion', (WidgetTester tester) async {
    bool done = true;
    await tester.pumpWidget(host(StatefulBuilder(builder: (BuildContext context, StateSetter set) => VigilCheckbox(value: done, semanticLabel: 'x', onChanged: (bool v) => set(() => done = v)))));
    await tester.tap(find.byType(VigilCheckbox));
    await tester.pump();
    expect(find.byType(SparkBurst), findsNothing);
    ThunderFx.level = ThunderFx.off;
    await tester.tap(find.byType(VigilCheckbox));
    await tester.pump();
    expect(find.byType(SparkBurst), findsNothing);
    ThunderFx.level = ThunderFx.full;
    await tester.pumpWidget(host(reduce: true, StatefulBuilder(builder: (BuildContext context, StateSetter set) => VigilCheckbox(value: false, semanticLabel: 'y', onChanged: (bool v) {}))));
    await tester.tap(find.byType(VigilCheckbox));
    await tester.pump();
    expect(find.byType(SparkBurst), findsNothing);
  });

  testWidgets('subtle keeps sparks but drops the lightning strike', (WidgetTester tester) async {
    ThunderFx.level = ThunderFx.subtle;
    await tester.pumpWidget(host(Builder(builder: (BuildContext context) => ElevatedButton(onPressed: () {
          ThunderFx.strike(context);
          ThunderFx.spark(context);
        }, child: const Text('go')))));
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.byType(StrikeFlash), findsNothing);
    expect(find.byType(SparkBurst), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('a rolling number counts up to its value, and shows it at once with Effects off', (WidgetTester tester) async {
    await tester.pumpWidget(host(const RollingNumber(value: 80)));
    expect(find.text('0'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('80'), findsOneWidget);
    ThunderFx.level = ThunderFx.off;
    await tester.pumpWidget(host(const RollingNumber(value: 42)));
    await tester.pump();
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('a pressed button sinks to 98 percent and comes back', (WidgetTester tester) async {
    await tester.pumpWidget(host(VigilButton(label: 'Go', onPressed: () {})));
    final TestGesture g = await tester.startGesture(tester.getCenter(find.text('Go')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale).first).scale, 0.98);
    await g.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale).first).scale, 1);
  });
}
