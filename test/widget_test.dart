import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:momir/app/theme.dart';

void main() {
  testWidgets('theme builds a MaterialApp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMomirTheme(),
        home: const Scaffold(body: Text('Momir')),
      ),
    );
    expect(find.text('Momir'), findsOneWidget);
  });
}
