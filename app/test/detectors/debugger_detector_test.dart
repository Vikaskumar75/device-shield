import 'package:device_shield/src/bridge/method_codes.dart';
import 'package:device_shield/src/bridge/native_bridge.dart';
import 'package:device_shield/src/detectors/debugger_detector.dart';
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
  group('DebuggerDetector — identity', () {
    test('type is the registered typeId', () {
      final detector = DebuggerDetector(
        nativeBridge: _FakeNativeBridge((_) async => {}),
      );
      expect(detector.type, 'debugger');
      expect(detector.type, DebuggerDetector.typeId);
    });
  });

  group('DebuggerDetector — check() success path', () {
    test('calls the bridge with MethodCodes.checkDebugger', () async {
      final bridge = _FakeNativeBridge(
        (_) async => {
          'detected': false,
          'confidence': 0.0,
          'signals': <String>[],
        },
      );
      final detector = DebuggerDetector(nativeBridge: bridge);

      await detector.check();

      expect(bridge.lastMethod, MethodCodes.checkDebugger);
    });

    test('maps a detected=true native response to a matching '
        'DetectionResult', () async {
      final bridge = _FakeNativeBridge(
        (_) async => {
          'detected': true,
          'confidence': 1.0,
          'signals': ['debugger_connected'],
        },
      );
      final detector = DebuggerDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.type, 'debugger');
      expect(result.detected, isTrue);
      expect(result.confidence, 1.0);
      expect(result.status, DetectionStatus.completed);
      expect(result.evidence['signals'], ['debugger_connected']);
    });

    test('maps a detected=false native response to a matching '
        'DetectionResult', () async {
      final bridge = _FakeNativeBridge(
        (_) async => {
          'detected': false,
          'confidence': 0.0,
          'signals': <String>[],
        },
      );
      final detector = DebuggerDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.detected, isFalse);
      expect(result.confidence, 0.0);
    });

    test('a partial-confidence response (some but not all Android signals '
        'firing) is passed through unchanged', () async {
      final bridge = _FakeNativeBridge(
        (_) async => {
          'detected': true,
          'confidence': 1 / 3,
          'signals': ['debuggable_flag'],
        },
      );
      final detector = DebuggerDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.detected, isTrue);
      expect(result.confidence, closeTo(1 / 3, 0.0001));
    });

    test('missing keys in the native response default safely rather '
        'than throwing', () async {
      final bridge = _FakeNativeBridge((_) async => <Object?, Object?>{});
      final detector = DebuggerDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.detected, isFalse);
      expect(result.confidence, 0.0);
      expect(result.status, DetectionStatus.completed);
    });
  });

  group('DebuggerDetector — check() failure path (per the frozen Detector '
      'contract: reported as failed, never thrown)', () {
    test('a NativeBridgeException results in DetectionStatus.failed', () async {
      final bridge = _FakeNativeBridge(
        (_) async => throw const NativeBridgeException(
          method: MethodCodes.checkDebugger,
          nativeError: 'boom',
          code: 'BRIDGE_UNAVAILABLE',
          message: 'no native handler',
        ),
      );
      final detector = DebuggerDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.status, DetectionStatus.failed);
      expect(result.detected, isFalse);
      expect(result.confidence, 0.0);
    });

    test('a malformed (non-Map) native response results in '
        'DetectionStatus.failed', () async {
      final bridge = _FakeNativeBridge((_) async => 'not a map');
      final detector = DebuggerDetector(nativeBridge: bridge);

      final result = await detector.check();

      expect(result.status, DetectionStatus.failed);
    });
  });

  group('DebuggerDetector — initialize/dispose', () {
    test('both complete without doing anything observable', () async {
      final detector = DebuggerDetector(
        nativeBridge: _FakeNativeBridge((_) async => {}),
      );

      await expectLater(detector.initialize(), completes);
      await expectLater(detector.dispose(), completes);
    });
  });
}
