import 'package:flutter_shield/src/bridge/method_codes.dart';
import 'package:flutter_shield/src/bridge/native_bridge.dart';
import 'package:flutter_shield/src/core/console_logger.dart';
import 'package:flutter_shield/src/detectors/screen_recording_detector.dart';
import 'package:flutter_shield/src/detectors/screenshot_detector.dart';
import 'package:flutter_shield/src/managers/default_detection_manager.dart';
import 'package:flutter_shield/src/models/detection_result.dart';
import 'package:flutter_shield/src/registry/default_detector_registry.dart';
import 'package:flutter_shield/src/registry/detector_factory.dart';
import 'package:flutter_test/flutter_test.dart';

/// Step 11 coverage-gap closure: mirrors
/// `debugger_detector_integration_test.dart`'s own pattern exactly — no
/// equivalent existed for `ScreenshotDetector`/`ScreenRecordingDetector`
/// running through the *real* `DetectorFactory`/`DefaultDetectionManager`
/// pipeline (bounded concurrency, registry ordering), only isolated unit
/// tests against a hand-built instance. This file closes that specific,
/// verified gap — nothing here duplicates `screenshot_detector_test.dart`/
/// `screen_recording_detector_test.dart`'s own unit-level coverage.
class _FakeNativeBridge implements NativeBridge {
  _FakeNativeBridge(this._responses);

  final Map<String, Map<Object?, Object?>> _responses;
  final List<String> invokedMethods = [];

  @override
  Future<T> invoke<T>({
    required String method,
    Map<String, dynamic>? arguments,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    invokedMethods.add(method);
    return _responses[method] as T;
  }

  @override
  void invokeAsync({required String method, Map<String, dynamic>? arguments}) {}

  @override
  void registerCallback(String name, void Function(dynamic data) callback) {}

  @override
  void unregisterCallback(String name) {}

  @override
  Future<void> dispose() async {}
}

void main() {
  test('DetectorFactory-constructed ScreenshotDetector registers and runs '
      'through DefaultDetectionManager exactly like any other built-in '
      'detector', () async {
    final bridge = _FakeNativeBridge(const {});
    final factory = DetectorFactory(nativeBridge: bridge);
    final manager = DefaultDetectionManager(
      logger: ConsoleLogger(),
      registry: DefaultDetectorRegistry(),
    );

    await manager.registerDetector(factory.create(ScreenshotDetector.typeId));

    final results = await manager.runAllChecks();

    expect(results, hasLength(1));
    expect(results.single.type, ScreenshotDetector.typeId);
    expect(results.single.detected, isFalse);
    expect(results.single.status, DetectionStatus.completed);
    // Confirms, at the integration level, the Step 7 finding that no
    // native call ever happens for this detector's poll path.
    expect(bridge.invokedMethods, isEmpty);
  });

  test('DetectorFactory-constructed ScreenRecordingDetector registers and '
      'runs through DefaultDetectionManager, correctly invoking '
      'MethodCodes.isScreenCaptureActive', () async {
    final bridge = _FakeNativeBridge({
      MethodCodes.isScreenCaptureActive: {'isCaptured': true, 'supported': true},
    });
    final factory = DetectorFactory(nativeBridge: bridge);
    final manager = DefaultDetectionManager(
      logger: ConsoleLogger(),
      registry: DefaultDetectorRegistry(),
    );

    await manager
        .registerDetector(factory.create(ScreenRecordingDetector.typeId));

    final results = await manager.runAllChecks();

    expect(results, hasLength(1));
    expect(results.single.type, ScreenRecordingDetector.typeId);
    expect(results.single.detected, isTrue);
    expect(results.single.confidence, 1.0);
    expect(bridge.invokedMethods, [MethodCodes.isScreenCaptureActive]);
  });

  test('all seven built-in detectors run together in the same '
      'bounded-concurrent batch, all DetectorFactory-constructed, '
      'aggregated correctly with no cross-contamination', () async {
    // Kept as the one place that iterates every `factory.availableTypes`
    // together — updated here, not duplicated in
    // root_jailbreak_detector_integration_test.dart, each time a new
    // built-in detector is added.
    final bridge = _FakeNativeBridge({
      MethodCodes.checkEmulator: {
        'detected': false,
        'confidence': 0.0,
        'signals': <String>[],
      },
      MethodCodes.checkDebugger: {
        'detected': false,
        'confidence': 0.0,
        'signals': <String>[],
      },
      MethodCodes.isScreenCaptureActive: {
        'isCaptured': false,
        'supported': false,
      },
      MethodCodes.checkRoot: {
        'detected': false,
        'confidence': 0.0,
        'signals': <String>[],
        'applicable': true,
      },
      MethodCodes.checkJailbreak: {
        'detected': false,
        'confidence': 0.0,
        'signals': <String>[],
        'applicable': false,
      },
      MethodCodes.checkMockLocation: {
        'detected': false,
        'confidence': 0.0,
        'signals': <String>[],
        'applicable': true,
        'permissionGranted': false,
        'locationAvailable': false,
      },
    });
    final factory = DetectorFactory(nativeBridge: bridge);
    final manager = DefaultDetectionManager(
      logger: ConsoleLogger(),
      registry: DefaultDetectorRegistry(),
    );

    for (final type in factory.availableTypes) {
      await manager.registerDetector(factory.create(type));
    }

    final results = await manager.runAllChecks();

    expect(results, hasLength(7));
    expect(
      results.map((r) => r.type).toSet(),
      {
        'emulator',
        'debugger',
        ScreenshotDetector.typeId,
        ScreenRecordingDetector.typeId,
        'root',
        'jailbreak',
        'mock_location',
      },
    );
    // The Android-unsupported shape must never fabricate a false positive,
    // even sitting in a mixed batch with other detectors.
    final recording = results
        .firstWhere((r) => r.type == ScreenRecordingDetector.typeId);
    expect(recording.detected, isFalse);
    expect(recording.evidence['supported'], isFalse);
    // Same honesty requirement for the new not-applicable-on-this-
    // platform shape.
    final jailbreak = results.firstWhere((r) => r.type == 'jailbreak');
    expect(jailbreak.detected, isFalse);
    expect(jailbreak.evidence['applicable'], isFalse);
  });
}
