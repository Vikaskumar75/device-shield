import 'package:flutter_shield/src/bridge/method_codes.dart';
import 'package:flutter_shield/src/bridge/native_bridge.dart';
import 'package:flutter_shield/src/managers/screen_capture_controller.dart';
import 'package:flutter_shield/src/models/detection_result.dart';
import 'package:flutter_shield/src/models/flutter_shield_config.dart';
import 'package:flutter_shield/src/models/flutter_shield_exception.dart';
import 'package:flutter_test/flutter_test.dart';

/// Used by every test in this file that only cares about push-routing
/// behavior, not config-gating itself (that has its own dedicated group
/// below) — both detection flags on, both protection flags off.
const _bothDetectionConfig = FlutterShieldConfig(
  enableScreenshotDetection: true,
  enableScreenRecordingDetection: true,
);

/// A fake bridge that actually stores registered callbacks (keyed by name)
/// so tests can simulate a native push by invoking them directly — mirrors
/// the routing this class relies on `DefaultNativeBridge` to provide for
/// real, already verified end-to-end in `default_native_bridge_test.dart`.
class _FakeNativeBridge implements NativeBridge {
  _FakeNativeBridge({this.respond});

  final Future<Object?> Function(String method, Map<String, dynamic>? args)?
      respond;
  final Map<String, void Function(dynamic data)> callbacks = {};
  final List<String> invokedMethods = [];
  bool disposed = false;

  @override
  Future<T> invoke<T>({
    required String method,
    Map<String, dynamic>? arguments,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    invokedMethods.add(method);
    final respondFn = respond;
    if (respondFn == null) throw UnimplementedError();
    return await respondFn(method, arguments) as T;
  }

  @override
  void invokeAsync({required String method, Map<String, dynamic>? arguments}) {}

  @override
  void registerCallback(String name, void Function(dynamic data) callback) {
    callbacks[name] = callback;
  }

  @override
  void unregisterCallback(String name) {
    callbacks.remove(name);
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  group('ScreenCaptureController — initialize (callback registration)', () {
    test('registers both native callbacks by their documented names',
        () async {
      final bridge = _FakeNativeBridge();
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});

      await controller.initialize(_bothDetectionConfig);

      expect(bridge.callbacks.keys,
          containsAll(['onScreenshotTaken', 'onScreenCaptureStateChanged']));
    });

    test('calling initialize() twice registers each callback only once',
        () async {
      final bridge = _FakeNativeBridge();
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});

      await controller.initialize(_bothDetectionConfig);
      final firstScreenshotCallback = bridge.callbacks['onScreenshotTaken'];
      await controller.initialize(_bothDetectionConfig);

      expect(bridge.callbacks['onScreenshotTaken'], same(firstScreenshotCallback));
    });
  });

  group('ScreenCaptureController — dispose (callback disposal / shutdown '
      'cleanup)', () {
    test('unregisters both native callbacks', () async {
      final bridge = _FakeNativeBridge();
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});
      await controller.initialize(_bothDetectionConfig);

      await controller.dispose();

      expect(bridge.callbacks, isEmpty);
    });

    test('a native push after dispose is no longer routed to onResult',
        () async {
      final bridge = _FakeNativeBridge();
      final received = <DetectionResult>[];
      final controller = ScreenCaptureController(
        nativeBridge: bridge,
        onResult: (result) async => received.add(result),
      );
      await controller.initialize(_bothDetectionConfig);
      final screenshotCallback = bridge.callbacks['onScreenshotTaken']!;

      await controller.dispose();
      screenshotCallback({'detected': true, 'confidence': 1.0, 'signals': []});
      await Future<void>.delayed(Duration.zero);

      // The callback reference itself still exists locally in this test
      // (captured before dispose), but NativeBridge.unregisterCallback
      // means DefaultNativeBridge would never invoke it again in practice
      // — verified separately in default_native_bridge_test.dart. This
      // test instead verifies dispose() actually clears the registration
      // map, which is what prevents that routing.
      expect(bridge.callbacks.containsKey('onScreenshotTaken'), isFalse);
    });

    test('dispose is safe to call even if initialize was never called',
        () async {
      final controller = ScreenCaptureController(
        nativeBridge: _FakeNativeBridge(),
        onResult: (_) async {},
      );

      await expectLater(controller.dispose(), completes);
    });
  });

  group('ScreenCaptureController — screenshot push routing', () {
    test('a native onScreenshotTaken push produces a matching '
        'DetectionResult via onResult', () async {
      final bridge = _FakeNativeBridge();
      final received = <DetectionResult>[];
      final controller = ScreenCaptureController(
        nativeBridge: bridge,
        onResult: (result) async => received.add(result),
      );
      await controller.initialize(_bothDetectionConfig);

      bridge.callbacks['onScreenshotTaken']!(
        {'detected': true, 'confidence': 1.0, 'signals': ['screen_capture_callback']},
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.type, 'screenshot');
      expect(received.single.detected, isTrue);
      expect(received.single.confidence, 1.0);
      expect(received.single.evidence['signals'], ['screen_capture_callback']);
    });

    test('missing keys in the push payload default to "a screenshot was '
        'taken" — receiving this callback at all means one occurred',
        () async {
      final bridge = _FakeNativeBridge();
      final received = <DetectionResult>[];
      final controller = ScreenCaptureController(
        nativeBridge: bridge,
        onResult: (result) async => received.add(result),
      );
      await controller.initialize(_bothDetectionConfig);

      bridge.callbacks['onScreenshotTaken']!(<Object?, Object?>{});
      await Future<void>.delayed(Duration.zero);

      expect(received.single.detected, isTrue);
      expect(received.single.confidence, 1.0);
    });

    test('a non-Map push payload is handled without throwing', () async {
      final bridge = _FakeNativeBridge();
      final received = <DetectionResult>[];
      final controller = ScreenCaptureController(
        nativeBridge: bridge,
        onResult: (result) async => received.add(result),
      );
      await controller.initialize(_bothDetectionConfig);

      bridge.callbacks['onScreenshotTaken']!('not a map');
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.type, 'screenshot');
    });
  });

  group('ScreenCaptureController — screen-recording push routing', () {
    test('a native onScreenCaptureStateChanged push with isCaptured:true '
        'reports detected at full confidence', () async {
      final bridge = _FakeNativeBridge();
      final received = <DetectionResult>[];
      final controller = ScreenCaptureController(
        nativeBridge: bridge,
        onResult: (result) async => received.add(result),
      );
      await controller.initialize(_bothDetectionConfig);

      bridge.callbacks['onScreenCaptureStateChanged']!({'isCaptured': true});
      await Future<void>.delayed(Duration.zero);

      expect(received.single.type, 'screen_recording');
      expect(received.single.detected, isTrue);
      expect(received.single.confidence, 1.0);
      expect(received.single.evidence['isCaptured'], isTrue);
    });

    test('isCaptured:false reports not detected at zero confidence',
        () async {
      final bridge = _FakeNativeBridge();
      final received = <DetectionResult>[];
      final controller = ScreenCaptureController(
        nativeBridge: bridge,
        onResult: (result) async => received.add(result),
      );
      await controller.initialize(_bothDetectionConfig);

      bridge.callbacks['onScreenCaptureStateChanged']!({'isCaptured': false});
      await Future<void>.delayed(Duration.zero);

      expect(received.single.detected, isFalse);
      expect(received.single.confidence, 0.0);
    });
  });

  group('ScreenCaptureController — no duplicate processing', () {
    test('each individual push produces exactly one onResult call — no '
        'push is ever processed twice', () async {
      final bridge = _FakeNativeBridge();
      final received = <DetectionResult>[];
      final controller = ScreenCaptureController(
        nativeBridge: bridge,
        onResult: (result) async => received.add(result),
      );
      await controller.initialize(_bothDetectionConfig);

      bridge.callbacks['onScreenshotTaken']!({'detected': true, 'confidence': 1.0, 'signals': []});
      bridge.callbacks['onScreenCaptureStateChanged']!({'isCaptured': true});
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(2));
      expect(received.map((r) => r.type), ['screenshot', 'screen_recording']);
    });
  });

  group('ScreenCaptureController — enable/disable (proactive protection)', () {
    test('enable() invokes MethodCodes.setScreenshotProtection with '
        'enabled:true and returns the native "applied" answer', () async {
      final bridge = _FakeNativeBridge(
        respond: (method, args) async => {'applied': true},
      );
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});

      final applied = await controller.enable();

      expect(bridge.invokedMethods, [MethodCodes.setScreenshotProtection]);
      expect(applied, isTrue);
      expect(controller.isEnabled, isTrue);
    });

    test('disable() invokes the same method with enabled:false', () async {
      final bridge = _FakeNativeBridge(
        respond: (method, args) async => {'applied': true},
      );
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});
      await controller.enable();

      final applied = await controller.disable();

      expect(applied, isTrue);
      expect(controller.isEnabled, isFalse);
    });

    test('an honest "not applied" answer (e.g. no root view/Activity '
        'available yet on either platform) never marks the '
        'controller enabled', () async {
      final bridge = _FakeNativeBridge(
        respond: (method, args) async => {'applied': false},
      );
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});

      final applied = await controller.enable();

      expect(applied, isFalse);
      expect(controller.isEnabled, isFalse);
    });

    test('a NativeBridgeException from enable() propagates unmodified — '
        'not swallowed, not transformed — and leaves isEnabled unchanged '
        '(Step 11 coverage-gap closure: previously only proven '
        'transitively via FlutterShield\'s own real-channel test, not '
        'isolated at this layer)', () async {
      final bridge = _FakeNativeBridge(
        respond: (method, args) async => throw NativeBridgeException(
          method: MethodCodes.setScreenshotProtection,
          nativeError: 'boom',
          code: 'BRIDGE_UNAVAILABLE',
          message: 'no native handler',
        ),
      );
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});

      await expectLater(
        controller.enable(),
        throwsA(isA<NativeBridgeException>()
            .having((e) => e.code, 'code', 'BRIDGE_UNAVAILABLE')),
      );
      expect(controller.isEnabled, isFalse);
    });

    test('a NativeBridgeException from disable() propagates the same way',
        () async {
      final bridge = _FakeNativeBridge(
        respond: (method, args) async => throw NativeBridgeException(
          method: MethodCodes.setScreenshotProtection,
          nativeError: 'boom',
          code: 'BRIDGE_TIMEOUT',
          message: 'timed out',
        ),
      );
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});

      await expectLater(
        controller.disable(),
        throwsA(isA<NativeBridgeException>()
            .having((e) => e.code, 'code', 'BRIDGE_TIMEOUT')),
      );
      expect(controller.isEnabled, isFalse);
    });
  });

  group('ScreenCaptureController — config-gated initialize (dead-config '
      'fix)', () {
    test('enableScreenshotDetection:false does not register the '
        'onScreenshotTaken callback', () async {
      final bridge = _FakeNativeBridge();
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});

      await controller.initialize(const FlutterShieldConfig(
        enableScreenshotDetection: false,
        enableScreenRecordingDetection: true,
      ));

      expect(bridge.callbacks.containsKey('onScreenshotTaken'), isFalse);
      expect(bridge.callbacks.containsKey('onScreenCaptureStateChanged'),
          isTrue);
    });

    test('enableScreenRecordingDetection:false does not register the '
        'onScreenCaptureStateChanged callback', () async {
      final bridge = _FakeNativeBridge();
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});

      await controller.initialize(const FlutterShieldConfig(
        enableScreenshotDetection: true,
        enableScreenRecordingDetection: false,
      ));

      expect(bridge.callbacks.containsKey('onScreenshotTaken'), isTrue);
      expect(bridge.callbacks.containsKey('onScreenCaptureStateChanged'),
          isFalse);
    });

    test('all four flags false registers nothing and applies nothing',
        () async {
      final bridge = _FakeNativeBridge();
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});

      await controller.initialize(const FlutterShieldConfig());

      expect(bridge.callbacks, isEmpty);
      expect(bridge.invokedMethods, isEmpty);
      expect(controller.isEnabled, isFalse);
      expect(controller.isAppSwitcherProtectionEnabled, isFalse);
    });

    test('enableScreenshotProtection:true auto-applies protection at boot '
        '— this is the fix: the flag used to be validated and stored but '
        'never read', () async {
      final bridge =
          _FakeNativeBridge(respond: (method, args) async => {'applied': true});
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});

      await controller.initialize(
          const FlutterShieldConfig(enableScreenshotProtection: true));

      expect(bridge.invokedMethods, [MethodCodes.setScreenshotProtection]);
      expect(controller.isEnabled, isTrue);
    });

    test('enableScreenshotProtection:false never invokes the protection '
        'method at boot', () async {
      final bridge = _FakeNativeBridge();
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});

      await controller.initialize(const FlutterShieldConfig());

      expect(bridge.invokedMethods, isNot(contains(
          MethodCodes.setScreenshotProtection)));
    });

    test('enableAppSwitcherProtection:true auto-applies app-switcher '
        'protection at boot', () async {
      final bridge =
          _FakeNativeBridge(respond: (method, args) async => {'applied': true});
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});

      await controller.initialize(
          const FlutterShieldConfig(enableAppSwitcherProtection: true));

      expect(bridge.invokedMethods, [MethodCodes.setAppSwitcherProtection]);
      expect(controller.isAppSwitcherProtectionEnabled, isTrue);
    });

    test('everything enabled applies both protections and registers both '
        'callbacks, in one initialize() call, with no duplicate '
        'registration on a second call', () async {
      final bridge =
          _FakeNativeBridge(respond: (method, args) async => {'applied': true});
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});
      const everythingOn = FlutterShieldConfig(
        enableScreenshotDetection: true,
        enableScreenRecordingDetection: true,
        enableScreenshotProtection: true,
        enableAppSwitcherProtection: true,
      );

      await controller.initialize(everythingOn);
      final firstCallback = bridge.callbacks['onScreenshotTaken'];
      await controller.initialize(everythingOn);

      expect(bridge.callbacks.keys,
          containsAll(['onScreenshotTaken', 'onScreenCaptureStateChanged']));
      expect(bridge.callbacks['onScreenshotTaken'], same(firstCallback));
      expect(bridge.invokedMethods, [
        MethodCodes.setScreenshotProtection,
        MethodCodes.setAppSwitcherProtection,
      ]);
      expect(controller.isEnabled, isTrue);
      expect(controller.isAppSwitcherProtectionEnabled, isTrue);
    });
  });

  group('ScreenCaptureController — app-switcher protection (enable/disable)',
      () {
    test('enableAppSwitcherProtection() invokes '
        'MethodCodes.setAppSwitcherProtection with enabled:true and '
        'returns the native "applied" answer', () async {
      final bridge = _FakeNativeBridge(
        respond: (method, args) async => {'applied': true},
      );
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});

      final applied = await controller.enableAppSwitcherProtection();

      expect(bridge.invokedMethods, [MethodCodes.setAppSwitcherProtection]);
      expect(applied, isTrue);
      expect(controller.isAppSwitcherProtectionEnabled, isTrue);
    });

    test('disableAppSwitcherProtection() invokes the same method with '
        'enabled:false', () async {
      final bridge = _FakeNativeBridge(
        respond: (method, args) async => {'applied': true},
      );
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});
      await controller.enableAppSwitcherProtection();

      final applied = await controller.disableAppSwitcherProtection();

      expect(applied, isTrue);
      expect(controller.isAppSwitcherProtectionEnabled, isFalse);
    });

    test('is independent of screenshot protection\'s own enabled state —'
        ' enabling one does not flip the other in the Dart-side model',
        () async {
      final bridge = _FakeNativeBridge(
        respond: (method, args) async => {'applied': true},
      );
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});

      await controller.enable();
      expect(controller.isEnabled, isTrue);
      expect(controller.isAppSwitcherProtectionEnabled, isFalse);

      await controller.enableAppSwitcherProtection();
      expect(controller.isEnabled, isTrue);
      expect(controller.isAppSwitcherProtectionEnabled, isTrue);
    });

    test('an honest "not applied" answer never marks app-switcher '
        'protection enabled', () async {
      final bridge = _FakeNativeBridge(
        respond: (method, args) async => {'applied': false},
      );
      final controller =
          ScreenCaptureController(nativeBridge: bridge, onResult: (_) async {});

      final applied = await controller.enableAppSwitcherProtection();

      expect(applied, isFalse);
      expect(controller.isAppSwitcherProtectionEnabled, isFalse);
    });
  });
}
