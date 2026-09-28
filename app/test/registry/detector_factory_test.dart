import 'package:device_shield/src/bridge/native_bridge.dart';
import 'package:device_shield/src/detectors/debugger_detector.dart';
import 'package:device_shield/src/detectors/emulator_detector.dart';
import 'package:device_shield/src/detectors/jailbreak_detector.dart';
import 'package:device_shield/src/detectors/mock_location_detector.dart';
import 'package:device_shield/src/detectors/root_detector.dart';
import 'package:device_shield/src/detectors/screen_recording_detector.dart';
import 'package:device_shield/src/detectors/screenshot_detector.dart';
import 'package:device_shield/src/models/device_shield_exception.dart';
import 'package:device_shield/src/registry/detector_factory.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeNativeBridge implements NativeBridge {
  @override
  Future<T> invoke<T>({
    required String method,
    Map<String, dynamic>? arguments,
    Duration timeout = const Duration(seconds: 5),
  }) async => throw UnimplementedError();

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
  group('DetectorFactory — availableTypes', () {
    test('lists every built-in detector this factory can construct', () {
      final factory = DetectorFactory(nativeBridge: _FakeNativeBridge());

      expect(factory.availableTypes, contains(EmulatorDetector.typeId));
      expect(factory.availableTypes, contains(DebuggerDetector.typeId));
      expect(factory.availableTypes, contains(ScreenshotDetector.typeId));
      expect(factory.availableTypes, contains(ScreenRecordingDetector.typeId));
      expect(factory.availableTypes, contains(RootDetector.typeId));
      expect(factory.availableTypes, contains(JailbreakDetector.typeId));
      expect(factory.availableTypes, contains(MockLocationDetector.typeId));
      expect(factory.availableTypes, hasLength(7));
    });
  });

  group('DetectorFactory — create', () {
    test('constructs a fresh EmulatorDetector wired to the same '
        'NativeBridge for a known built-in type', () {
      final bridge = _FakeNativeBridge();
      final factory = DetectorFactory(nativeBridge: bridge);

      final detector = factory.create(EmulatorDetector.typeId);

      expect(detector, isA<EmulatorDetector>());
      expect((detector as EmulatorDetector).nativeBridge, same(bridge));
    });

    test('constructs a fresh DebuggerDetector wired to the same '
        'NativeBridge for a known built-in type', () {
      final bridge = _FakeNativeBridge();
      final factory = DetectorFactory(nativeBridge: bridge);

      final detector = factory.create(DebuggerDetector.typeId);

      expect(detector, isA<DebuggerDetector>());
      expect((detector as DebuggerDetector).nativeBridge, same(bridge));
    });

    test('constructs a fresh ScreenshotDetector wired to the same '
        'NativeBridge for a known built-in type', () {
      final bridge = _FakeNativeBridge();
      final factory = DetectorFactory(nativeBridge: bridge);

      final detector = factory.create(ScreenshotDetector.typeId);

      expect(detector, isA<ScreenshotDetector>());
      expect((detector as ScreenshotDetector).nativeBridge, same(bridge));
    });

    test('constructs a fresh ScreenRecordingDetector wired to the same '
        'NativeBridge for a known built-in type', () {
      final bridge = _FakeNativeBridge();
      final factory = DetectorFactory(nativeBridge: bridge);

      final detector = factory.create(ScreenRecordingDetector.typeId);

      expect(detector, isA<ScreenRecordingDetector>());
      expect((detector as ScreenRecordingDetector).nativeBridge, same(bridge));
    });

    test('constructs a fresh RootDetector wired to the same NativeBridge '
        'for a known built-in type', () {
      final bridge = _FakeNativeBridge();
      final factory = DetectorFactory(nativeBridge: bridge);

      final detector = factory.create(RootDetector.typeId);

      expect(detector, isA<RootDetector>());
      expect((detector as RootDetector).nativeBridge, same(bridge));
    });

    test('constructs a fresh JailbreakDetector wired to the same '
        'NativeBridge for a known built-in type', () {
      final bridge = _FakeNativeBridge();
      final factory = DetectorFactory(nativeBridge: bridge);

      final detector = factory.create(JailbreakDetector.typeId);

      expect(detector, isA<JailbreakDetector>());
      expect((detector as JailbreakDetector).nativeBridge, same(bridge));
    });

    test('constructs a fresh MockLocationDetector wired to the same '
        'NativeBridge for a known built-in type', () {
      final bridge = _FakeNativeBridge();
      final factory = DetectorFactory(nativeBridge: bridge);

      final detector = factory.create(MockLocationDetector.typeId);

      expect(detector, isA<MockLocationDetector>());
      expect((detector as MockLocationDetector).nativeBridge, same(bridge));
    });

    test('each call returns a distinct instance, not a cached singleton', () {
      final factory = DetectorFactory(nativeBridge: _FakeNativeBridge());

      final first = factory.create(EmulatorDetector.typeId);
      final second = factory.create(EmulatorDetector.typeId);

      expect(identical(first, second), isFalse);
    });

    test(
      'an unknown type throws DetectionException(DETECTOR_TYPE_UNKNOWN)',
      () {
        final factory = DetectorFactory(nativeBridge: _FakeNativeBridge());

        expect(
          () => factory.create('nonexistent_type'),
          throwsA(
            isA<DetectionException>()
                .having((e) => e.code, 'code', 'DETECTOR_TYPE_UNKNOWN')
                .having((e) => e.type, 'type', 'nonexistent_type'),
          ),
        );
      },
    );

    test('a custom (host-app) type is never constructible through this '
        'factory', () {
      final factory = DetectorFactory(nativeBridge: _FakeNativeBridge());

      expect(
        () => factory.create('my_custom_detector'),
        throwsA(isA<DetectionException>()),
      );
    });
  });
}
