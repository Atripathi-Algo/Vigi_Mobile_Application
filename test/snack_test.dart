import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/app/common.dart';
import 'package:vigil/vigil/theme/vigil_theme.dart';

void main() {
  testWidgets('a snackbar with an Undo action goes away by itself', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildVigilTheme(Brightness.light),
      home: Scaffold(body: Builder(builder: (BuildContext context) => TextButton(onPressed: () => showVigilSnack(context, 'Logged 200 rupees for lunch.', action: 'Undo', onAction: () {}), child: const Text('go')))),
    ));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Logged 200 rupees for lunch.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Logged 200 rupees for lunch.'), findsNothing);
  });
}
