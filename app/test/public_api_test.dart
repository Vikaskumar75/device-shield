// Imports only the public barrel. If a type a host app needs stops being
// exported, this file stops compiling. Add new public types here.
import 'package:device_shield/device_shield.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the public API is reachable from the barrel alone', () {
    const Object _ = DeviceShield;

    final types = <Object>[
      CheckType.root,
      CheckStatus.detected,
      SignalStrength.strong,
      const Signal('x', SignalStrength.weak),
      const CheckResult(type: CheckType.root, status: CheckStatus.clear),
      const MockLocationResult(status: CheckStatus.clear),
      ProtectionResult.applied,
    ];
    const clear = CheckResult(type: CheckType.root, status: CheckStatus.clear);
    const report = SecurityReport(
      root: clear,
      jailbreak: clear,
      emulator: clear,
      debugger: clear,
      mockLocation: MockLocationResult(status: CheckStatus.clear),
    );

    expect(types, hasLength(7));
    expect(report.anyDetected, isFalse);
  });

  test('DeviceShield exposes the documented entry points', () {
    // Tear-offs fail to compile if a method is renamed or removed.
    final entryPoints = <Object>[
      DeviceShield.check,
      DeviceShield.checkRoot,
      DeviceShield.checkJailbreak,
      DeviceShield.checkEmulator,
      DeviceShield.checkDebugger,
      DeviceShield.checkMockLocation,
      DeviceShield.isScreenRecorded,
      DeviceShield.setScreenshotProtection,
      DeviceShield.setAppSwitcherProtection,
    ];
    expect(entryPoints, hasLength(9));
  });
}
