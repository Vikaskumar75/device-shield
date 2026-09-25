import 'package:device_shield/src/bridge/method_codes.dart';
import 'package:device_shield/src/bridge/native_bridge.dart';
import 'package:device_shield/src/core/console_logger.dart';
import 'package:device_shield/src/detectors/jailbreak_detector.dart';
import 'package:device_shield/src/detectors/root_detector.dart';
import 'package:device_shield/src/managers/default_detection_manager.dart';
import 'package:device_shield/src/models/detection_result.dart';
import 'package:device_shield/src/registry/default_detector_registry.dart';
import 'package:device_shield/src/registry/detector_factory.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors `screenshot_recording_detector_integration_test.dart`'s own
/// pattern — the "all built-in detectors together" test lives there
/// (updated for these two new types, not duplicated here); this file
/// covers `RootDetector`/`JailbreakDetector`'s own individual
/// `DetectorFactory`/`DefaultDetectionManager` integration only.
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
  test('DetectorFactory-constructed RootDetector registers and runs '
      'through DefaultDetectionManager, correctly invoking '
      'MethodCodes.checkRoot', () async {
    final bridge = _FakeNativeBridge({
      MethodCodes.checkRoot: {
        'detected': true,
        'confidence': 0.44,
        'signals': ['su_binary_path', 'busybox_present'],
        'applicable': true,
      },
    });
    final factory = DetectorFactory(nativeBridge: bridge);
    final manager = DefaultDetectionManager(
      logger: ConsoleLogger(),
      registry: DefaultDetectorRegistry(),
    );

    await manager.registerDetector(factory.create(RootDetector.typeId));

    final results = await manager.runAllChecks();

    expect(results, hasLength(1));
    expect(results.single.type, RootDetector.typeId);
    expect(results.single.detected, isTrue);
    expect(results.single.confidence, 0.44);
    expect(bridge.invokedMethods, [MethodCodes.checkRoot]);
  });

  test('DetectorFactory-constructed JailbreakDetector registers and runs '
      'through DefaultDetectionManager, correctly invoking '
      'MethodCodes.checkJailbreak', () async {
    final bridge = _FakeNativeBridge({
      MethodCodes.checkJailbreak: {
        'detected': false,
        'confidence': 0.0,
        'signals': <String>[],
        'applicable': false,
      },
    });
    final factory = DetectorFactory(nativeBridge: bridge);
    final manager = DefaultDetectionManager(
      logger: ConsoleLogger(),
      registry: DefaultDetectorRegistry(),
    );

    await manager.registerDetector(factory.create(JailbreakDetector.typeId));

    final results = await manager.runAllChecks();

    expect(results, hasLength(1));
    expect(results.single.type, JailbreakDetector.typeId);
    expect(results.single.status, DetectionStatus.completed);
    expect(results.single.evidence['applicable'], isFalse);
    expect(bridge.invokedMethods, [MethodCodes.checkJailbreak]);
  });

  test('Root and Jailbreak run alongside each other in the same '
      'bounded-concurrent batch with no cross-contamination', () async {
    final bridge = _FakeNativeBridge({
      MethodCodes.checkRoot: {
        'detected': true,
        'confidence': 0.22,
        'signals': ['build_tags_test_keys'],
        'applicable': true,
      },
      MethodCodes.checkJailbreak: {
        'detected': true,
        'confidence': 0.8,
        'signals': ['jailbreak_app_paths', 'suspicious_system_paths'],
        'applicable': true,
      },
    });
    final factory = DetectorFactory(nativeBridge: bridge);
    final manager = DefaultDetectionManager(
      logger: ConsoleLogger(),
      registry: DefaultDetectorRegistry(),
    );

    await manager.registerDetector(factory.create(RootDetector.typeId));
    await manager.registerDetector(factory.create(JailbreakDetector.typeId));

    final results = await manager.runAllChecks();

    expect(results, hasLength(2));
    final root = results.firstWhere((r) => r.type == RootDetector.typeId);
    final jailbreak = results.firstWhere(
      (r) => r.type == JailbreakDetector.typeId,
    );
    expect(root.confidence, 0.22);
    expect(jailbreak.confidence, 0.8);
    expect(root.evidence['signals'], ['build_tags_test_keys']);
    expect(jailbreak.evidence['signals'], [
      'jailbreak_app_paths',
      'suspicious_system_paths',
    ]);
  });
}
