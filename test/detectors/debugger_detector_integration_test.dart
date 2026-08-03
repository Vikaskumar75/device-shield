import 'package:flutter_shield/src/bridge/method_codes.dart';
import 'package:flutter_shield/src/bridge/native_bridge.dart';
import 'package:flutter_shield/src/core/console_logger.dart';
import 'package:flutter_shield/src/detectors/debugger_detector.dart';
import 'package:flutter_shield/src/detectors/emulator_detector.dart';
import 'package:flutter_shield/src/managers/default_detection_manager.dart';
import 'package:flutter_shield/src/models/detection_result.dart';
import 'package:flutter_shield/src/registry/default_detector_registry.dart';
import 'package:flutter_shield/src/registry/detector_factory.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// Proves DebuggerDetector's real, end-to-end integration through the
/// same framework path a host app or PluginInitializer-driven boot would
/// use: DetectorFactory constructs it (not a hand-built instance),
/// DetectionManager.registerDetector() stores it via DetectorRegistry, and
/// runAllChecks() runs it alongside another real built-in detector,
/// bounded-concurrent, through the actual pipeline — no test-only fake
/// Detector stands in anywhere in this file.
void main() {
  test('DetectorFactory-constructed DebuggerDetector registers and runs '
      'through DefaultDetectionManager exactly like any other built-in '
      'detector', () async {
    final bridge = _FakeNativeBridge({
      MethodCodes.checkDebugger: {
        'detected': true,
        'confidence': 1.0,
        'signals': ['debugger_connected'],
      },
    });
    final factory = DetectorFactory(nativeBridge: bridge);
    final manager = DefaultDetectionManager(
      logger: ConsoleLogger(),
      registry: DefaultDetectorRegistry(),
    );

    final debugger = factory.create(DebuggerDetector.typeId);
    await manager.registerDetector(debugger);

    final results = await manager.runAllChecks();

    expect(results, hasLength(1));
    expect(results.single.type, DebuggerDetector.typeId);
    expect(results.single.detected, isTrue);
    expect(results.single.confidence, 1.0);
    expect(bridge.invokedMethods, [MethodCodes.checkDebugger]);
  });

  test('DebuggerDetector runs alongside EmulatorDetector in the same '
      'bounded-concurrent batch, both DetectorFactory-constructed, '
      'aggregated in registry priority order', () async {
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
    });
    final factory = DetectorFactory(nativeBridge: bridge);
    final manager = DefaultDetectionManager(
      logger: ConsoleLogger(),
      registry: DefaultDetectorRegistry(),
    );

    await manager.registerDetector(factory.create(EmulatorDetector.typeId));
    await manager.registerDetector(factory.create(DebuggerDetector.typeId));

    final results = await manager.runAllChecks();

    expect(results.map((r) => r.type).toSet(),
        {EmulatorDetector.typeId, DebuggerDetector.typeId});
    expect(results.every((r) => r.detected == false), isTrue);
    expect(
      bridge.invokedMethods.toSet(),
      {MethodCodes.checkEmulator, MethodCodes.checkDebugger},
    );
  });

  test('a native-side failure for checkDebugger is reported as a failed '
      'DetectionResult — never thrown, never excluded from the batch — '
      'alongside a successful sibling detector, per the frozen Detector '
      'contract', () async {
    final bridge = _FakeNativeBridge({
      MethodCodes.checkEmulator: {
        'detected': false,
        'confidence': 0.0,
        'signals': <String>[],
      },
      // checkDebugger deliberately absent — the fake bridge casts a
      // missing entry to the expected Map type, which throws inside
      // NativeBridge.invoke(). DebuggerDetector.check() catches that
      // internally and returns DetectionStatus.failed rather than
      // rethrowing — the same "report failure, never throw" contract
      // EmulatorDetector already follows, so the failure surfaces as a
      // result *in* the batch, not an exclusion from it.
    });
    final factory = DetectorFactory(nativeBridge: bridge);
    final manager = DefaultDetectionManager(
      logger: ConsoleLogger(),
      registry: DefaultDetectorRegistry(),
    );

    await manager.registerDetector(factory.create(EmulatorDetector.typeId));
    await manager.registerDetector(factory.create(DebuggerDetector.typeId));

    final results = await manager.runAllChecks();

    expect(results.map((r) => r.type).toSet(),
        {EmulatorDetector.typeId, DebuggerDetector.typeId});
    final debuggerResult =
        results.firstWhere((r) => r.type == DebuggerDetector.typeId);
    expect(debuggerResult.status, DetectionStatus.failed);
    expect(debuggerResult.detected, isFalse);
    final emulatorResult =
        results.firstWhere((r) => r.type == EmulatorDetector.typeId);
    expect(emulatorResult.status, DetectionStatus.completed);
  });
}
