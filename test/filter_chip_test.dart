import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil/theme/vigil_theme.dart';
import 'package:vigil/vigil/vigil.dart';

void main() {
  testWidgets('filter chips in a Wrap are as wide as their text, not the whole row', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildVigilTheme(Brightness.light),
      home: Scaffold(
        body: Wrap(spacing: 8, children: <Widget>[
          VigilFilterChip(label: 'All', selected: true, onTap: () {}),
          VigilFilterChip(label: 'Work', selected: false, onTap: () {}),
        ]),
      ),
    ));
    final Size a = tester.getSize(find.byType(VigilFilterChip).first);
    expect(a.width, lessThan(120));
    expect(a.height, 48, reason: 'a 32 dp chip inside a 48 dp hit area');
    expect(tester.getTopLeft(find.byType(VigilFilterChip).last).dy, tester.getTopLeft(find.byType(VigilFilterChip).first).dy, reason: 'both fit on one line');
  });
}
