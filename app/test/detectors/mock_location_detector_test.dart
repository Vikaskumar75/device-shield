import 'package:flutter_shield/src/bridge/method_codes.dart';
import 'package:flutter_shield/src/bridge/native_bridge.dart';
import 'package:flutter_shield/src/detectors/mock_location_detector.dart';
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
  group('MockLocationDetector — identity', () {
    test('type is the registered typeId', () {
      final detector = MockLocationDetector(
        nativeBridge: _FakeNativeBridge((_) async => {}),
      );
      expect(detector.type, 'mock_location');
      expect(detector.type, MockLocationDetector.typeId);
    });

    test('priority matches the other built-in detectors', () {
      final detector = MockLocationDetector(
        nativeBridge: _FakeNativeBridge((_) async => {}),
      );
      expect(detector.priority, 0);
    });
  });

  group('MockLocationDetector — check() success path', () {
    test('calls the bridge with MethodCodes.checkMockLocation', () async {
      final bridge = _FakeNativeBridge((_) async => {
            'detected': false,
            'confidence': 0.0,
            'signals': <String>[],
            'applicable': true,
            'permissionGranted': false,
            'locationAvailable': false,
          });
      final detector = MockLocationDetector(nativeBridge: bridge);

      await detector.check();

      expect(bridge.lastMethod, MethodCodes.checkMockLocation);
    });

    test('maps a detected=true native response to a matching '
        'DetectionResult', () async {
      final bridge = _FakeNativeBridge((_) async => {
            'detected': true,
            'confidence': 0.4,
            'signals': ['mock_provider_flag', 'fake_gps_app_installed'],
            'applicable': true,
            'permissionGranted': true,
            'locationAvailable': true,
          });
      final detector = MockLocationDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.type, 'mock_location');
      expect(result.detected, isTrue);
      expect(result.confidence, 0.4);
      expect(result.status, DetectionStatus.completed);
      expect(
        result.evidence['signals'],
        ['mock_provider_flag', 'fake_gps_app_installed'],
      );
      expect(result.evidence['applicable'], isTrue);
      expect(result.evidence['permissionGranted'], isTrue);
      expect(result.evidence['locationAvailable'], isTrue);
    });

    test('maps a detected=false native response to a matching '
        'DetectionResult', () async {
      final bridge = _FakeNativeBridge((_) async => {
            'detected': false,
            'confidence': 0.0,
            'signals': <String>[],
            'applicable': true,
            'permissionGranted': true,
            'locationAvailable': true,
          });
      final detector = MockLocationDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.detected, isFalse);
      expect(result.confidence, 0.0);
    });

    test('a permission-denied response is carried into evidence — an '
        'honest capability gap, not a confident "not detected"', () async {
      final bridge = _FakeNativeBridge((_) async => {
            'detected': false,
            'confidence': 0.0,
            'signals': <String>[],
            'applicable': true,
            'permissionGranted': false,
            'locationAvailable': false,
          });
      final detector = MockLocationDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.evidence['permissionGranted'], isFalse);
      expect(result.evidence['locationAvailable'], isFalse);
      // Still reports applicable:true — unlike root/jailbreak, mock
      // location detection is a real concept on both platforms; a
      // missing permission is a capability gap, not non-applicability.
      expect(result.evidence['applicable'], isTrue);
    });

    test('missing keys in the native response default safely rather '
        'than throwing', () async {
      final bridge = _FakeNativeBridge((_) async => <Object?, Object?>{});
      final detector = MockLocationDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.detected, isFalse);
      expect(result.confidence, 0.0);
      expect(result.status, DetectionStatus.completed);
      expect(result.evidence['applicable'], isTrue);
      expect(result.evidence['permissionGranted'], isFalse);
      expect(result.evidence['locationAvailable'], isFalse);
    });
  });

  group('MockLocationDetector — check() failure path (per the frozen '
      'Detector contract: reported as failed, never thrown)', () {
    test('a NativeBridgeException results in DetectionStatus.failed',
        () async {
      final bridge = _FakeNativeBridge((_) async => throw NativeBridgeException(
            method: MethodCodes.checkMockLocation,
            nativeError: 'boom',
            code: 'BRIDGE_UNAVAILABLE',
            message: 'no native handler',
          ));
      final detector = MockLocationDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.status, DetectionStatus.failed);
      expect(result.detected, isFalse);
      expect(result.confidence, 0.0);
    });

    test('a malformed (non-Map) native response results in '
        'DetectionStatus.failed', () async {
      final bridge = _FakeNativeBridge((_) async => 'not a map');
      final detector = MockLocationDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.status, DetectionStatus.failed);
    });
  });

  group('MockLocationDetector — initialize/dispose', () {
    test('both complete without doing anything observable', () async {
      final detector = MockLocationDetector(
        nativeBridge: _FakeNativeBridge((_) async => {}),
      );

      await expectLater(detector.initialize(), completes);
      await expectLater(detector.dispose(), completes);
    });
  });
}
