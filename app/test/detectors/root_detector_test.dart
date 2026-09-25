import 'package:flutter_shield/src/bridge/method_codes.dart';
import 'package:flutter_shield/src/bridge/native_bridge.dart';
import 'package:flutter_shield/src/detectors/root_detector.dart';
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
  group('RootDetector — identity', () {
    test('type is the registered typeId', () {
      final detector = RootDetector(
        nativeBridge: _FakeNativeBridge((_) async => {}),
      );
      expect(detector.type, 'root');
      expect(detector.type, RootDetector.typeId);
    });

    test('priority matches the other built-in detectors', () {
      final detector = RootDetector(
        nativeBridge: _FakeNativeBridge((_) async => {}),
      );
      expect(detector.priority, 0);
    });
  });

  group('RootDetector — check() success path (Android-shaped response)', () {
    test('calls the bridge with MethodCodes.checkRoot', () async {
      final bridge = _FakeNativeBridge((_) async => {
            'detected': false,
            'confidence': 0.0,
            'signals': <String>[],
            'applicable': true,
          });
      final detector = RootDetector(nativeBridge: bridge);

      await detector.check();

      expect(bridge.lastMethod, MethodCodes.checkRoot);
    });

    test('maps a detected=true native response to a matching '
        'DetectionResult', () async {
      final bridge = _FakeNativeBridge((_) async => {
            'detected': true,
            'confidence': 0.67,
            'signals': ['su_binary_path', 'magisk_artifacts'],
            'applicable': true,
          });
      final detector = RootDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.type, 'root');
      expect(result.detected, isTrue);
      expect(result.confidence, 0.67);
      expect(result.status, DetectionStatus.completed);
      expect(
        result.evidence['signals'],
        ['su_binary_path', 'magisk_artifacts'],
      );
      expect(result.evidence['applicable'], isTrue);
    });

    test('maps a detected=false native response to a matching '
        'DetectionResult', () async {
      final bridge = _FakeNativeBridge((_) async => {
            'detected': false,
            'confidence': 0.0,
            'signals': <String>[],
            'applicable': true,
          });
      final detector = RootDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.detected, isFalse);
      expect(result.confidence, 0.0);
    });

    test('missing keys in the native response default safely rather '
        'than throwing', () async {
      final bridge = _FakeNativeBridge((_) async => <Object?, Object?>{});
      final detector = RootDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.detected, isFalse);
      expect(result.confidence, 0.0);
      expect(result.status, DetectionStatus.completed);
      // Missing 'applicable' defaults to true, not a false "not
      // applicable" — the honest-unsupported shape must be explicit,
      // never inferred from an absent key.
      expect(result.evidence['applicable'], isTrue);
    });
  });

  group('RootDetector — check() not-applicable response (iOS-shaped)', () {
    test('an explicit applicable:false is carried into evidence, never '
        'silently dropped', () async {
      final bridge = _FakeNativeBridge((_) async => {
            'detected': false,
            'confidence': 0.0,
            'signals': <String>[],
            'applicable': false,
          });
      final detector = RootDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.detected, isFalse);
      expect(result.evidence['applicable'], isFalse);
    });
  });

  group('RootDetector — check() failure path (per the frozen Detector '
      'contract: reported as failed, never thrown)', () {
    test('a NativeBridgeException results in DetectionStatus.failed',
        () async {
      final bridge = _FakeNativeBridge((_) async => throw NativeBridgeException(
            method: MethodCodes.checkRoot,
            nativeError: 'boom',
            code: 'BRIDGE_UNAVAILABLE',
            message: 'no native handler',
          ));
      final detector = RootDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.status, DetectionStatus.failed);
      expect(result.detected, isFalse);
      expect(result.confidence, 0.0);
    });

    test('a malformed (non-Map) native response results in '
        'DetectionStatus.failed', () async {
      final bridge = _FakeNativeBridge((_) async => 'not a map');
      final detector = RootDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.status, DetectionStatus.failed);
    });
  });

  group('RootDetector — initialize/dispose', () {
    test('both complete without doing anything observable', () async {
      final detector = RootDetector(
        nativeBridge: _FakeNativeBridge((_) async => {}),
      );

      await expectLater(detector.initialize(), completes);
      await expectLater(detector.dispose(), completes);
    });
  });
}
