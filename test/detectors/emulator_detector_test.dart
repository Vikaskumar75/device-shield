import 'package:flutter_shield/src/bridge/method_codes.dart';
import 'package:flutter_shield/src/bridge/native_bridge.dart';
import 'package:flutter_shield/src/detectors/emulator_detector.dart';
import 'package:flutter_shield/src/models/detection_result.dart';
import 'package:flutter_shield/src/models/flutter_shield_exception.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeNativeBridge implements NativeBridge {
  _FakeNativeBridge(this._respond);

  final Future<Object?> Function(String method) _respond;
  String? lastMethod;

  @override
  Future<T> invoke<T>({
    required String method,
    Map<String, dynamic>? arguments,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    lastMethod = method;
    return await _respond(method) as T;
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
  group('EmulatorDetector — identity', () {
    test('type is the registered typeId', () {
      final detector = EmulatorDetector(
        nativeBridge: _FakeNativeBridge((_) async => {}),
      );
      expect(detector.type, 'emulator');
      expect(detector.type, EmulatorDetector.typeId);
    });
  });

  group('EmulatorDetector — check() success path', () {
    test('calls the bridge with MethodCodes.checkEmulator', () async {
      final bridge = _FakeNativeBridge((_) async => {
            'detected': false,
            'confidence': 0.0,
            'signals': <String>[],
          });
      final detector = EmulatorDetector(nativeBridge: bridge);

      await detector.check();

      expect(bridge.lastMethod, MethodCodes.checkEmulator);
    });

    test('maps a detected=true native response to a matching '
        'DetectionResult', () async {
      final bridge = _FakeNativeBridge((_) async => {
            'detected': true,
            'confidence': 0.85,
            'signals': ['fingerprint', 'hardware'],
          });
      final detector = EmulatorDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.type, 'emulator');
      expect(result.detected, isTrue);
      expect(result.confidence, 0.85);
      expect(result.status, DetectionStatus.completed);
      expect(result.evidence['signals'], ['fingerprint', 'hardware']);
    });

    test('maps a detected=false native response to a matching '
        'DetectionResult', () async {
      final bridge = _FakeNativeBridge((_) async => {
            'detected': false,
            'confidence': 0.0,
            'signals': <String>[],
          });
      final detector = EmulatorDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.detected, isFalse);
      expect(result.confidence, 0.0);
    });

    test('missing keys in the native response default safely rather '
        'than throwing', () async {
      final bridge = _FakeNativeBridge((_) async => <Object?, Object?>{});
      final detector = EmulatorDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.detected, isFalse);
      expect(result.confidence, 0.0);
      expect(result.status, DetectionStatus.completed);
    });
  });

  group('EmulatorDetector — check() failure path (per the frozen Detector '
      'contract: reported as failed, never thrown)', () {
    test('a NativeBridgeException results in DetectionStatus.failed',
        () async {
      final bridge = _FakeNativeBridge((_) async => throw NativeBridgeException(
            method: MethodCodes.checkEmulator,
            nativeError: 'boom',
            code: 'BRIDGE_UNAVAILABLE',
            message: 'no native handler',
          ));
      final detector = EmulatorDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.status, DetectionStatus.failed);
      expect(result.detected, isFalse);
      expect(result.confidence, 0.0);
    });

    test('a malformed (non-Map) native response results in '
        'DetectionStatus.failed', () async {
      final bridge = _FakeNativeBridge((_) async => 'not a map');
      final detector = EmulatorDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.status, DetectionStatus.failed);
    });
  });

  group('EmulatorDetector — initialize/dispose', () {
    test('both complete without doing anything observable', () async {
      final detector = EmulatorDetector(
        nativeBridge: _FakeNativeBridge((_) async => {}),
      );

      await expectLater(detector.initialize(), completes);
      await expectLater(detector.dispose(), completes);
    });
  });
}
