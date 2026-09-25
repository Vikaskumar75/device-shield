// Basic smoke test for the DeviceShield reference example app: verifies
// the app boots into its navigation shell without crashing.

import 'package:device_shield_example/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App boots and shows the Home screen', (tester) async {
    await tester.pumpWidget(const DeviceShieldExampleApp());
    await tester.pump();

    expect(find.text('Home'), findsWidgets);
  });
}
