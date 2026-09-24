// Basic smoke test for the FlutterShield reference example app: verifies
// the app boots into its navigation shell without crashing.

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_shield_example/app.dart';

void main() {
  testWidgets('App boots and shows the Home screen', (tester) async {
    await tester.pumpWidget(const FlutterShieldExampleApp());
    await tester.pump();

    expect(find.text('Home'), findsWidgets);
  });
}
