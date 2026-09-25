import 'package:device_shield/src/bridge/method_codes.dart';
import 'package:device_shield/src/bridge/native_bridge.dart';
import 'package:device_shield/src/detectors/screen_recording_detector.dart';
import 'package:device_shield/src/models/detection_result.dart';
import 'package:device_shield/src/models/device_shield_exception.dart';
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
  group('ScreenRecordingDetector — identity/metadata', () {
    test('type is the registered typeId', () {
      final detector = ScreenRecordingDetector(
        nativeBridge: _FakeNativeBridge((_) async => {}),
      );
      expect(detector.type, 'screen_recording');
      expect(detector.type, ScreenRecordingDetector.typeId);
    });

    test('priority matches the other built-in detectors', () {
      final detector = ScreenRecordingDetector(
        nativeBridge: _FakeNativeBridge((_) async => {}),
      );
      expect(detector.priority, 0);
    });
  });

  group('ScreenRecordingDetector — check() success path', () {
    test('calls the bridge with MethodCodes.isScreenCaptureActive', () async {
      final bridge = _FakeNativeBridge(
        (_) async => {'isCaptured': false, 'supported': true},
      );
      final detector = ScreenRecordingDetector(nativeBridge: bridge);

      await detector.check();

      expect(bridge.lastMethod, MethodCodes.isScreenCaptureActive);
    });

    test('iOS-shaped captured response reports detected at full '
        'confidence', () async {
      final bridge = _FakeNativeBridge(
        (_) async => {'isCaptured': true, 'supported': true},
      );
      final detector = ScreenRecordingDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.type, 'screen_recording');
      expect(result.detected, isTrue);
      expect(result.confidence, 1.0);
      expect(result.status, DetectionStatus.completed);
      expect(result.evidence['isCaptured'], isTrue);
      expect(result.evidence['supported'], isTrue);
    });

    test('iOS-shaped not-captured response reports not detected at zero '
        'confidence', () async {
      final bridge = _FakeNativeBridge(
        (_) async => {'isCaptured': false, 'supported': true},
      );
      final detector = ScreenRecordingDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.detected, isFalse);
      expect(result.confidence, 0.0);
      expect(result.evidence['supported'], isTrue);
    });

    test('Android-shaped unsupported response never reports a false, '
        'confident detection', () async {
      final bridge = _FakeNativeBridge(
        (_) async => {
          'isCaptured': false,
          'supported': false,
          'reason': 'No reliable screen-recording signal exists on Android.',
        },
      );
      final detector = ScreenRecordingDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.detected, isFalse);
      expect(result.confidence, 0.0);
      expect(result.status, DetectionStatus.completed);
      expect(result.evidence['supported'], isFalse);
    });

    test('confidence is always exactly 0.0 or 1.0 — a single authoritative '
        'signal, never a weighted heuristic', () async {
      final captured = await ScreenRecordingDetector(
        nativeBridge: _FakeNativeBridge(
          (_) async => {'isCaptured': true, 'supported': true},
        ),
      ).check();
      final notCaptured = await ScreenRecordingDetector(
        nativeBridge: _FakeNativeBridge(
          (_) async => {'isCaptured': false, 'supported': true},
        ),
      ).check();

      expect(captured.confidence, 1.0);
      expect(notCaptured.confidence, 0.0);
    });

    test('missing keys in the native response default safely rather than '
        'throwing', () async {
      final bridge = _FakeNativeBridge((_) async => <Object?, Object?>{});
      final detector = ScreenRecordingDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.detected, isFalse);
      expect(result.confidence, 0.0);
      expect(result.evidence['supported'], isFalse);
      expect(result.status, DetectionStatus.completed);
    });
  });

  group('ScreenRecordingDetector — check() failure path (per the frozen '
      'Detector contract: reported as failed, never thrown)', () {
    test('a NativeBridgeException results in DetectionStatus.failed', () async {
      final bridge = _FakeNativeBridge(
        (_) async => throw const NativeBridgeException(
          method: MethodCodes.isScreenCaptureActive,
          nativeError: 'boom',
          code: 'BRIDGE_UNAVAILABLE',
          message: 'no native handler',
        ),
      );
      final detector = ScreenRecordingDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.status, DetectionStatus.failed);
      expect(result.detected, isFalse);
      expect(result.confidence, 0.0);
    });

    test('a malformed (non-Map) native response results in '
        'DetectionStatus.failed', () async {
      final bridge = _FakeNativeBridge((_) async => 'not a map');
      final detector = ScreenRecordingDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.status, DetectionStatus.failed);
    });
  });

  group('ScreenRecordingDetector — initialize/dispose', () {
    test('both complete without doing anything observable', () async {
      final detector = ScreenRecordingDetector(
        nativeBridge: _FakeNativeBridge((_) async => {}),
      );

      await expectLater(detector.initialize(), completes);
      await expectLater(detector.dispose(), completes);
    });
  });
}
