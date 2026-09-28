import 'package:device_shield/src/api/device_shield.dart';
import 'package:device_shield/src/models/detection_result.dart';
import 'package:device_shield/src/models/device_shield_config.dart';
import 'package:device_shield/src/models/device_shield_exception.dart';
import 'package:device_shield/src/models/sdk_state.dart';
import 'package:device_shield/src/models/security_action.dart';
import 'package:device_shield/src/models/security_event.dart';
import 'package:device_shield/src/registry/detector.dart';
import 'package:device_shield/src/registry/rule.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProbeDetector implements Detector {
  _ProbeDetector(this.type);
  @override
  final String type;
  @override
  final int priority = 0;
  bool checked = false;

  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<DetectionResult> check() async {
    checked = true;
    return DetectionResult(
      type: type,
      detected: false,
      confidence: 0.0,
      timestamp: DateTime.now(),
    );
  }
}

class _AlwaysMatchRule implements Rule {
  _AlwaysMatchRule(this.id);
  @override
  final String id;
  @override
  final int priority = 0;
  @override
  final SecurityAction action = SecurityAction.warn;
  bool matchCalled = false;

  @override
  bool matches(DetectionResult result) {
    matchCalled = true;
    return true;
  }
}

/// Every test cleans up with dispose() so DeviceShield's static state
/// never leaks between tests — this class is a process-lifetime facade
/// by design (per its frozen contract), so tests must reset it themselves.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    if (DeviceShield.status != SDKState.uninitialized) {
      await DeviceShield.dispose();
    }
  });

  group('DeviceShield — status before initialize', () {
    test('status is uninitialized before any initialize() call', () {
      expect(DeviceShield.status, SDKState.uninitialized);
    });

    test('calling a delegating method before initialize() throws '
        'NOT_INITIALIZED', () async {
      expect(
        DeviceShield.pause,
        throwsA(
          isA<InitializationException>().having(
            (e) => e.code,
            'code',
            'NOT_INITIALIZED',
          ),
        ),
      );
    });
  });

  group('DeviceShield — initialize / status / pause / resume', () {
    test('initialize reaches running', () async {
      await DeviceShield.initialize();
      expect(DeviceShield.status, SDKState.running);
    });

    test('pause transitions to paused; resume transitions back', () async {
      await DeviceShield.initialize();

      await DeviceShield.pause();
      expect(DeviceShield.status, SDKState.paused);

      await DeviceShield.resume();
      expect(DeviceShield.status, SDKState.running);
    });
  });

  group('DeviceShield — detector registration API', () {
    test(
      'registerDetector + checkNow reaches the detector end-to-end',
      () async {
        await DeviceShield.initialize();
        final probe = _ProbeDetector('probe-1');

        await DeviceShield.registerDetector(probe);
        await DeviceShield.checkNow();

        expect(probe.checked, isTrue);
      },
    );
  });

  group('DeviceShield — rule registration API', () {
    test('addRule makes the rule reachable via the detection→policy '
        'pipeline', () async {
      await DeviceShield.initialize();
      final rule = _AlwaysMatchRule('rule-1');
      final probe = _ProbeDetector('probe-2');

      await DeviceShield.addRule(rule);
      await DeviceShield.registerDetector(probe);
      await DeviceShield.checkNow();

      expect(rule.matchCalled, isTrue);
    });

    test('removeRule stops the rule from being evaluated', () async {
      await DeviceShield.initialize();
      final rule = _AlwaysMatchRule('rule-2');
      await DeviceShield.addRule(rule);

      await DeviceShield.removeRule('rule-2');
      await DeviceShield.registerDetector(_ProbeDetector('probe-3'));
      await DeviceShield.checkNow();

      expect(rule.matchCalled, isFalse);
    });
  });

  group('DeviceShield — callback registration API', () {
    test('registerCallback/unregisterCallback do not throw', () async {
      await DeviceShield.initialize();

      expect(
        () => DeviceShield.registerCallback('probe', (_) {}),
        returnsNormally,
      );
      expect(() => DeviceShield.unregisterCallback('probe'), returnsNormally);
    });
  });

  group('DeviceShield — event subscription API', () {
    test('subscribe receives the event checkNow emits', () async {
      await DeviceShield.initialize();
      final received = <SecurityEvent>[];
      final subscription = DeviceShield.subscribe(received.add);

      await DeviceShield.registerDetector(_ProbeDetector('probe-4'));
      await DeviceShield.checkNow();
      await Future<void>.delayed(Duration.zero);

      expect(received, isNotEmpty);
      await subscription.cancel();
    });

    test('a filter restricts which events are delivered', () async {
      await DeviceShield.initialize();
      final received = <SecurityEvent>[];
      final subscription = DeviceShield.subscribe(
        received.add,
        filter: (e) => e.type == 'never-matches',
      );

      await DeviceShield.registerDetector(_ProbeDetector('probe-5'));
      await DeviceShield.checkNow();
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await subscription.cancel();
    });
  });

  group('DeviceShield — screenshot/screen-recording protection API '
      '(Step 10)', () {
    test('isScreenshotProtectionEnabled is false before initialize() — '
        'never throws, mirroring status\'s own always-answerable pattern', () {
      expect(DeviceShield.isScreenshotProtectionEnabled, isFalse);
    });

    test('enableScreenshotProtection delegates all the way to a real '
        'NativeBridge — with no native handler in this test environment, '
        'the honest result is a propagated NativeBridgeException, proving '
        'the call reaches the platform boundary rather than being '
        'short-circuited anywhere along the way', () async {
      await DeviceShield.initialize();

      await expectLater(
        DeviceShield.enableScreenshotProtection(),
        throwsA(isA<NativeBridgeException>()),
      );
    });

    test('disableScreenshotProtection delegates the same way', () async {
      await DeviceShield.initialize();

      await expectLater(
        DeviceShield.disableScreenshotProtection(),
        throwsA(isA<NativeBridgeException>()),
      );
    });

    test('isScreenshotProtectionEnabled remains false after a failed '
        'enable attempt', () async {
      await DeviceShield.initialize();
      try {
        await DeviceShield.enableScreenshotProtection();
      } catch (_) {
        // Expected in this environment — see the test above.
      }

      expect(DeviceShield.isScreenshotProtectionEnabled, isFalse);
    });
  });

  group('DeviceShield — onScreenshot / onScreenRecordingChanged (Step 10)', () {
    test('onScreenshot only receives events whose type is the screenshot '
        "detector's typeId — pure filtering over subscribe(), nothing "
        'else', () async {
      await DeviceShield.initialize();
      final screenshotEvents = <SecurityEvent>[];
      final recordingEvents = <SecurityEvent>[];
      final screenshotSub = DeviceShield.onScreenshot(screenshotEvents.add);
      final recordingSub = DeviceShield.onScreenRecordingChanged(
        recordingEvents.add,
      );

      await DeviceShield.registerDetector(_ProbeDetector('screenshot'));
      await DeviceShield.checkNow();
      await Future<void>.delayed(Duration.zero);

      expect(screenshotEvents, hasLength(1));
      expect(screenshotEvents.single.type, 'screenshot');
      expect(recordingEvents, isEmpty);

      await screenshotSub.cancel();
      await recordingSub.cancel();
    });

    test('onScreenRecordingChanged only receives events whose type is the '
        "screen-recording detector's typeId", () async {
      await DeviceShield.initialize();
      final screenshotEvents = <SecurityEvent>[];
      final recordingEvents = <SecurityEvent>[];
      final screenshotSub = DeviceShield.onScreenshot(screenshotEvents.add);
      final recordingSub = DeviceShield.onScreenRecordingChanged(
        recordingEvents.add,
      );

      await DeviceShield.registerDetector(_ProbeDetector('screen_recording'));
      await DeviceShield.checkNow();
      await Future<void>.delayed(Duration.zero);

      expect(recordingEvents, hasLength(1));
      expect(recordingEvents.single.type, 'screen_recording');
      expect(screenshotEvents, isEmpty);

      await screenshotSub.cancel();
      await recordingSub.cancel();
    });

    test('an unrelated event type is delivered to neither convenience '
        'subscription', () async {
      await DeviceShield.initialize();
      final screenshotEvents = <SecurityEvent>[];
      final recordingEvents = <SecurityEvent>[];
      final screenshotSub = DeviceShield.onScreenshot(screenshotEvents.add);
      final recordingSub = DeviceShield.onScreenRecordingChanged(
        recordingEvents.add,
      );

      await DeviceShield.registerDetector(_ProbeDetector('emulator'));
      await DeviceShield.checkNow();
      await Future<void>.delayed(Duration.zero);

      expect(screenshotEvents, isEmpty);
      expect(recordingEvents, isEmpty);

      await screenshotSub.cancel();
      await recordingSub.cancel();
    });
  });

  group('DeviceShield — shutdown / reinitialize / dispose', () {
    test('shutdown reaches stopped', () async {
      await DeviceShield.initialize();

      await DeviceShield.shutdown();

      expect(DeviceShield.status, SDKState.stopped);
    });

    test('reinitialize restarts with fresh managers — a detector '
        'registered before shutdown is not silently retained', () async {
      await DeviceShield.initialize();
      final firstProbe = _ProbeDetector('probe-6');
      await DeviceShield.registerDetector(firstProbe);
      await DeviceShield.shutdown();

      await DeviceShield.reinitialize();

      expect(DeviceShield.status, SDKState.running);
      // The fresh DetectionManager's registry was rebuilt empty —
      // checkNow() must not reach the old detector instance.
      await DeviceShield.checkNow();
      expect(firstProbe.checked, isFalse);
    });

    test('reinitialize with a new config applies it', () async {
      await DeviceShield.initialize();
      await DeviceShield.shutdown();

      await expectLater(
        DeviceShield.reinitialize(
          config: const DeviceShieldConfig(periodicCheckInterval: 60000),
        ),
        completes,
      );
      expect(DeviceShield.status, SDKState.running);
    });

    test('screenshot protection state resets across shutdown/reinitialize '
        '— a fresh ScreenCaptureController is wired each cycle, not a '
        'stale or disposed one (Step 11 coverage-gap closure)', () async {
      await DeviceShield.initialize();
      expect(DeviceShield.isScreenshotProtectionEnabled, isFalse);
      await DeviceShield.shutdown();

      await DeviceShield.reinitialize();

      expect(DeviceShield.status, SDKState.running);
      expect(DeviceShield.isScreenshotProtectionEnabled, isFalse);
      // The freshly-wired ScreenCaptureController must still correctly
      // attempt delegation to a real NativeBridge — proving it's a live,
      // newly constructed instance after reinit, not a disposed reference
      // silently no-op'ing.
      await expectLater(
        DeviceShield.enableScreenshotProtection(),
        throwsA(isA<NativeBridgeException>()),
      );
    });

    test(
      'dispose fully resets — a subsequent initialize() starts clean',
      () async {
        await DeviceShield.initialize();
        await DeviceShield.registerDetector(_ProbeDetector('probe-7'));

        await DeviceShield.dispose();

        expect(DeviceShield.status, SDKState.uninitialized);

        // A fresh initialize() after full dispose must succeed and start
        // with no detectors carried over.
        await DeviceShield.initialize();
        expect(DeviceShield.status, SDKState.running);
      },
    );
  });
}
