// Runs the real native checks on a device or emulator:
//   cd app/example && flutter test integration_test
import 'dart:io';

import 'package:device_shield/device_shield.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every check runs on this platform', (tester) async {
    final report = await DeviceShield.check();

    for (final result in report.all) {
      // Printed so a device run records what actually fired.
      // ignore: avoid_print
      print(result);
      expect(result.status, isNot(CheckStatus.failed), reason: '$result');
    }
    if (Platform.isAndroid) {
      expect(report.jailbreak.status, CheckStatus.notApplicable);
      expect(report.root.status, isNot(CheckStatus.notApplicable));
    }
    if (Platform.isIOS) {
      expect(report.root.status, CheckStatus.notApplicable);
      // The Simulator can't be jailbroken, so the check doesn't apply there.
      final onSimulator = report.emulator.detected;
      expect(
        report.jailbreak.status,
        onSimulator
            ? CheckStatus.notApplicable
            : isNot(CheckStatus.notApplicable),
      );
    }
  });

  testWidgets('screen protection can be turned on and off', (tester) async {
    final on = await DeviceShield.setAppSwitcherProtection(true);
    final off = await DeviceShield.setAppSwitcherProtection(false);

    expect(on, ProtectionResult.applied);
    expect(off, ProtectionResult.applied);
  });
}
