import 'dart:io';

import 'package:device_shield/device_shield.dart';
import 'package:device_shield/src/signal_strengths.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every signal id the native detection code can emit, read from the Kotlin
/// and Swift sources so this test fails when a native signal is added
/// without a strength.
Set<String> nativeSignalIds() {
  final pattern = RegExp(
    r'''(?:add|append)\("([a-z_]+)"\)|[:?]\s*\["([a-z_]+)"\]''',
  );
  final dirs = [
    'android/src/main/kotlin/com/geekyants/device_shield/detection',
    'ios/device_shield/Sources/device_shield/Detection',
  ];
  return {
    for (final dir in dirs)
      for (final file in Directory(dir).listSync().whereType<File>())
        for (final match in pattern.allMatches(file.readAsStringSync()))
          (match.group(1) ?? match.group(2))!,
  };
}

List<Signal> signals(List<String> ids) => [
  for (final id in ids) Signal(id, strengthOf(id)),
];

void main() {
  test('every native signal has an explicit strength', () {
    final ids = nativeSignalIds();
    expect(ids, isNotEmpty);
    expect(ids.difference(signalStrengths.keys.toSet()), isEmpty);
  });

  test('the table lists no signal the native code never emits', () {
    expect(signalStrengths.keys.toSet().difference(nativeSignalIds()), isEmpty);
  });

  test('unknown signals are weak, so they can never detect alone', () {
    expect(strengthOf('something_new'), SignalStrength.weak);
  });

  group('detection rule', () {
    test('one strong signal is enough', () {
      expect(statusFor(signals(['su_binary_path'])), CheckStatus.detected);
    });

    test('one medium signal is not enough', () {
      expect(
        statusFor(signals(['superuser_apps_installed'])),
        CheckStatus.clear,
      );
    });

    test('two medium signals are enough', () {
      expect(statusFor(signals(['hardware', 'product'])), CheckStatus.detected);
    });

    test('weak signals never decide, however many fire', () {
      expect(
        statusFor(
          signals([
            'busybox_present',
            'build_tags_test_keys',
            'dangerous_system_props',
          ]),
        ),
        CheckStatus.clear,
      );
    });

    test('no signals is clear', () {
      expect(statusFor(const []), CheckStatus.clear);
    });
  });

  group('known false positives are no longer detections', () {
    test('a stock emulator is not rooted', () {
      final result = CheckResult.fromSignalIds(CheckType.root, [
        'dangerous_system_props',
        'build_tags_test_keys',
      ]);
      expect(result.status, CheckStatus.clear);
      expect(result.signals, hasLength(2));
    });

    test('a debug build without a debugger is not being debugged', () {
      final result = CheckResult.fromSignalIds(CheckType.debugger, [
        'debuggable_flag',
      ]);
      expect(result.detected, isFalse);
    });

    test('an installed fake-GPS app alone is not a mocked location', () {
      final result = CheckResult.fromSignalIds(CheckType.mockLocation, [
        'fake_gps_app_installed',
      ]);
      expect(result.detected, isFalse);
    });

    test('a stock Android emulator is still detected as an emulator', () {
      final result = CheckResult.fromSignalIds(CheckType.emulator, [
        'fingerprint',
        'hardware',
        'product',
      ]);
      expect(result.detected, isTrue);
    });
  });
}
