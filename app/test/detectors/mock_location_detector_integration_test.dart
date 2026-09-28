import 'package:device_shield/src/bridge/method_codes.dart';
import 'package:device_shield/src/bridge/native_bridge.dart';
import 'package:device_shield/src/core/console_logger.dart';
import 'package:device_shield/src/detectors/mock_location_detector.dart';
import 'package:device_shield/src/managers/default_detection_manager.dart';
import 'package:device_shield/src/models/detection_result.dart';
import 'package:device_shield/src/registry/default_detector_registry.dart';
import 'package:device_shield/src/registry/detector_factory.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors `root_jailbreak_detector_integration_test.dart`'s own pattern
/// — the "all built-in detectors together" test lives in
/// `screenshot_recording_detector_integration_test.dart` (updated for
/// this new type, not duplicated here); this file covers
/// `MockLocationDetector`'s own individual `DetectorFactory`/
/// `DefaultDetectionManager` integration only.
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
  test('DetectorFactory-constructed MockLocationDetector registers and '
      'runs through DefaultDetectionManager, correctly invoking '
      'MethodCodes.checkMockLocation', () async {
    final bridge = _FakeNativeBridge({
      MethodCodes.checkMockLocation: {
        'detected': true,
        'confidence': 0.4,
        'signals': ['mock_provider_flag', 'fake_gps_app_installed'],
        'applicable': true,
        'permissionGranted': true,
        'locationAvailable': true,
      },
    });
    final factory = DetectorFactory(nativeBridge: bridge);
    final manager = DefaultDetectionManager(
      logger: ConsoleLogger(),
      registry: DefaultDetectorRegistry(),
    );

    await manager.registerDetector(factory.create(MockLocationDetector.typeId));

    final results = await manager.runAllChecks();

    expect(results, hasLength(1));
    expect(results.single.type, MockLocationDetector.typeId);
    expect(results.single.detected, isTrue);
    expect(results.single.confidence, 0.4);
    expect(results.single.status, DetectionStatus.completed);
    expect(bridge.invokedMethods, [MethodCodes.checkMockLocation]);
  });

  test('a permission-denied response completes normally with the honest '
      'capability gap carried through, never a failed/thrown result', () async {
    final bridge = _FakeNativeBridge({
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

    await manager.registerDetector(factory.create(MockLocationDetector.typeId));

    final results = await manager.runAllChecks();

    expect(results.single.status, DetectionStatus.completed);
    expect(results.single.evidence['applicable'], isTrue);
    expect(results.single.evidence['permissionGranted'], isFalse);
    expect(results.single.evidence['locationAvailable'], isFalse);
  });
}
