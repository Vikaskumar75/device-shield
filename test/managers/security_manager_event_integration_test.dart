import 'package:flutter_shield/src/bridge/native_bridge.dart';
import 'package:flutter_shield/src/config/default_configuration_manager.dart';
import 'package:flutter_shield/src/core/console_logger.dart';
import 'package:flutter_shield/src/events/default_event_manager.dart';
import 'package:flutter_shield/src/managers/default_detection_manager.dart';
import 'package:flutter_shield/src/managers/default_policy_manager.dart';
import 'package:flutter_shield/src/managers/default_security_manager.dart';
import 'package:flutter_shield/src/models/detection_result.dart';
import 'package:flutter_shield/src/models/flutter_shield_config.dart';
import 'package:flutter_shield/src/models/sdk_state.dart';
import 'package:flutter_shield/src/models/security_event.dart';
import 'package:flutter_shield/src/registry/default_detector_registry.dart';
import 'package:flutter_shield/src/registry/detector.dart';
import 'package:flutter_shield/src/state/security_state_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// Step 9 (Event Integration) — the one genuinely new scenario Steps 7/8's
/// own tests didn't already cover: a poll cycle and a native push occurring
/// together, through the real `DefaultSecurityManager`/
/// `ScreenCaptureController` wiring, verifying ordering and the absence of
/// any accidental duplication between the two paths (see Step 9's
/// Architecture Verification Report §9/§17-18 for why this is the one real
/// gap, not a restatement of Step 8's own coverage).

class _FakeNativeBridge implements NativeBridge {
  final Map<String, void Function(dynamic data)> callbacks = {};

  @override
  Future<T> invoke<T>({
    required String method,
    Map<String, dynamic>? arguments,
    Duration timeout = const Duration(seconds: 5),
  }) async =>
      throw UnimplementedError();

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
  Future<void> dispose() async {}
}

class _FakeDetector implements Detector {
  _FakeDetector(this.type, {this.detected = false});
  @override
  final String type;
  @override
  final int priority = 0;
  final bool detected;

  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<DetectionResult> check() async => DetectionResult(
        type: type,
        detected: detected,
        confidence: detected ? 0.9 : 0.0,
        timestamp: DateTime.now(),
      );
}

DefaultSecurityManager _buildManager({
  required DefaultDetectionManager detectionManager,
  required DefaultPolicyManager policyManager,
  required DefaultEventManager eventManager,
  required DefaultSecurityStateManager lifecycle,
  required NativeBridge nativeBridge,
}) {
  return DefaultSecurityManager(
    detectionManager: detectionManager,
    policyManager: policyManager,
    eventManager: eventManager,
    // Both detection flags on — this file specifically tests native push
    // routing, so it must opt in explicitly now that config actually
    // gates registration (see screen_capture_controller_test.dart's
    // dedicated "config-gated initialize" group for the gating behavior
    // itself).
    configurationManager: DefaultConfigurationManager(
        const FlutterShieldConfig(
          periodicCheckInterval: 999999,
          enableScreenshotDetection: true,
          enableScreenRecordingDetection: true,
        )),
    lifecycle: lifecycle,
    logger: ConsoleLogger(),
    nativeBridge: nativeBridge,
  );
}

void main() {
  group('Event Integration — mixed poll + push', () {
    test('a poll cycle (emulator-style detector) and a native screenshot '
        'push each produce exactly one correctly-typed event, in the '
        'order they actually occurred, with no duplication between the '
        'two paths', () async {
      final nativeBridge = _FakeNativeBridge();
      final detectionManager = DefaultDetectionManager(
          logger: ConsoleLogger(), registry: DefaultDetectorRegistry());
      await detectionManager
          .registerDetector(_FakeDetector('emulator', detected: true));
      final policyManager = DefaultPolicyManager(logger: ConsoleLogger());
      final eventManager = DefaultEventManager();
      final lifecycle = DefaultSecurityStateManager()
        ..transitionTo(SDKState.initializing)
        ..transitionTo(SDKState.initialized)
        ..transitionTo(SDKState.running);
      final manager = _buildManager(
        detectionManager: detectionManager,
        policyManager: policyManager,
        eventManager: eventManager,
        lifecycle: lifecycle,
        nativeBridge: nativeBridge,
      );
      final received = <SecurityEvent>[];
      eventManager.subscribe(received.add);
      await manager.initialize();

      // Poll fires first.
      await manager.checkNow();
      await Future<void>.delayed(Duration.zero);
      // Push fires second, independently, via the real registered callback.
      nativeBridge.callbacks['onScreenshotTaken']!(
        {'detected': true, 'confidence': 1.0, 'signals': []},
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(2));
      expect(received[0].type, 'emulator');
      expect(received[1].type, 'screenshot');

      await manager.dispose();
      lifecycle.dispose();
    });

    test('reversing the order (push before poll) preserves that same '
        'arrival order — dispatch is FIFO regardless of which path fired '
        'first', () async {
      final nativeBridge = _FakeNativeBridge();
      final detectionManager = DefaultDetectionManager(
          logger: ConsoleLogger(), registry: DefaultDetectorRegistry());
      await detectionManager
          .registerDetector(_FakeDetector('debugger', detected: true));
      final policyManager = DefaultPolicyManager(logger: ConsoleLogger());
      final eventManager = DefaultEventManager();
      final lifecycle = DefaultSecurityStateManager()
        ..transitionTo(SDKState.initializing)
        ..transitionTo(SDKState.initialized)
        ..transitionTo(SDKState.running);
      final manager = _buildManager(
        detectionManager: detectionManager,
        policyManager: policyManager,
        eventManager: eventManager,
        lifecycle: lifecycle,
        nativeBridge: nativeBridge,
      );
      final received = <SecurityEvent>[];
      eventManager.subscribe(received.add);
      await manager.initialize();

      nativeBridge.callbacks['onScreenCaptureStateChanged']!(
        {'isCaptured': true},
      );
      await Future<void>.delayed(Duration.zero);
      await manager.checkNow();
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(2));
      expect(received[0].type, 'screen_recording');
      expect(received[1].type, 'debugger');

      await manager.dispose();
      lifecycle.dispose();
    });

    test('multiple pushes for the same native event are never coalesced '
        'or dropped — each is its own distinct SecurityEvent, per the '
        'design doc\'s explicit "no built-in deduplication" decision',
        () async {
      final nativeBridge = _FakeNativeBridge();
      final policyManager = DefaultPolicyManager(logger: ConsoleLogger());
      final eventManager = DefaultEventManager();
      final lifecycle = DefaultSecurityStateManager()
        ..transitionTo(SDKState.initializing)
        ..transitionTo(SDKState.initialized)
        ..transitionTo(SDKState.running);
      final manager = _buildManager(
        detectionManager: DefaultDetectionManager(
            logger: ConsoleLogger(), registry: DefaultDetectorRegistry()),
        policyManager: policyManager,
        eventManager: eventManager,
        lifecycle: lifecycle,
        nativeBridge: nativeBridge,
      );
      final received = <SecurityEvent>[];
      eventManager.subscribe(received.add);
      await manager.initialize();

      final screenshotCallback = nativeBridge.callbacks['onScreenshotTaken']!;
      screenshotCallback({'detected': true, 'confidence': 1.0, 'signals': []});
      screenshotCallback({'detected': true, 'confidence': 1.0, 'signals': []});
      screenshotCallback({'detected': true, 'confidence': 1.0, 'signals': []});
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(3));
      expect(received.every((e) => e.type == 'screenshot'), isTrue);

      await manager.dispose();
      lifecycle.dispose();
    });

    test('backward compatibility: a poll cycle with only pre-existing '
        'detector types (no screenshot/recording involved at all) '
        'behaves exactly as it did before this feature existed', () async {
      final detectionManager = DefaultDetectionManager(
          logger: ConsoleLogger(), registry: DefaultDetectorRegistry());
      await detectionManager
          .registerDetector(_FakeDetector('emulator', detected: true));
      await detectionManager
          .registerDetector(_FakeDetector('debugger', detected: false));
      final policyManager = DefaultPolicyManager(logger: ConsoleLogger());
      final eventManager = DefaultEventManager();
      final lifecycle = DefaultSecurityStateManager()
        ..transitionTo(SDKState.initializing)
        ..transitionTo(SDKState.initialized)
        ..transitionTo(SDKState.running);
      final manager = _buildManager(
        detectionManager: detectionManager,
        policyManager: policyManager,
        eventManager: eventManager,
        lifecycle: lifecycle,
        nativeBridge: _FakeNativeBridge(),
      );
      final received = <SecurityEvent>[];
      eventManager.subscribe(received.add);
      await manager.initialize();

      await manager.checkNow();
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(2));
      expect(received.map((e) => e.type).toSet(), {'emulator', 'debugger'});
      expect(received.every((e) => e.source == 'SecurityManager'), isTrue);

      await manager.dispose();
      lifecycle.dispose();
    });
  });
}
