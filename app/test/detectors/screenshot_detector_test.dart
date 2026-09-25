import 'package:flutter_shield/src/bridge/native_bridge.dart';
import 'package:flutter_shield/src/detectors/screenshot_detector.dart';
import 'package:flutter_shield/src/models/detection_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// A bridge that throws if [invoke] is ever called — used to assert
/// [ScreenshotDetector.check] never calls native at all (Step 7's
/// architecture review finding: no MethodCode for polling screenshot
/// state exists anywhere in the bridge; a screenshot is a discrete past
/// event, not a stable state to poll — see the class's own doc comment).
class _NeverInvokedNativeBridge implements NativeBridge {
  bool invokeWasCalled = false;

  @override
  Future<T> invoke<T>({
    required String method,
    Map<String, dynamic>? arguments,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    invokeWasCalled = true;
    throw StateError('ScreenshotDetector.check() must never call invoke()');
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
  group('ScreenshotDetector — constructor', () {
    test('stores the provided NativeBridge', () {
      final bridge = _NeverInvokedNativeBridge();
      final detector = ScreenshotDetector(nativeBridge: bridge);

      expect(detector.nativeBridge, same(bridge));
    });
  });

  group('ScreenshotDetector — identity/metadata', () {
    test('type is the registered typeId', () {
      final detector = ScreenshotDetector(
        nativeBridge: _NeverInvokedNativeBridge(),
      );

      expect(detector.type, 'screenshot');
      expect(detector.type, ScreenshotDetector.typeId);
    });

    test('priority matches the other built-in detectors', () {
      final detector = ScreenshotDetector(
        nativeBridge: _NeverInvokedNativeBridge(),
      );

      expect(detector.priority, 0);
    });
  });

  group('ScreenshotDetector — check()', () {
    test('never calls NativeBridge.invoke() — no poll mechanism exists '
        'for screenshots, by design', () async {
      final bridge = _NeverInvokedNativeBridge();
      final detector = ScreenshotDetector(nativeBridge: bridge);

      await detector.check();

      expect(bridge.invokeWasCalled, isFalse);
    });

    test('always returns a constant, honest not-detected result', () async {
      final detector = ScreenshotDetector(
        nativeBridge: _NeverInvokedNativeBridge(),
      );

      final result = await detector.check();

      expect(result.type, 'screenshot');
      expect(result.detected, isFalse);
      expect(result.confidence, 0.0);
      expect(result.status, DetectionStatus.completed);
      expect(result.evidence['signals'], isEmpty);
    });

    test('never throws, since there is no native call that could fail',
        () async {
      final detector = ScreenshotDetector(
        nativeBridge: _NeverInvokedNativeBridge(),
      );

      await expectLater(detector.check(), completes);
    });
  });

  group('ScreenshotDetector — initialize/dispose', () {
    test('both complete without doing anything observable', () async {
      final detector = ScreenshotDetector(
        nativeBridge: _NeverInvokedNativeBridge(),
      );

      await expectLater(detector.initialize(), completes);
      await expectLater(detector.dispose(), completes);
    });
  });
}
