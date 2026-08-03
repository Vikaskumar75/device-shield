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
}) {
  return DefaultSecurityManager(
    detectionManager: detectionManager,
    policyManager: policyManager,
    eventManager: eventManager,
    // A very long interval so the periodic timer never fires mid-test.
    configurationManager: DefaultConfigurationManager(
        const FlutterShieldConfig(periodicCheckInterval: 999999)),
    lifecycle: lifecycle,
    logger: ConsoleLogger(),
  );
}

void main() {
  group('DefaultSecurityManager — coordination only', () {
    test('checkNow drives Detection -> Policy -> Event, end to end',
        () async {
      final detectionManager = DefaultDetectionManager(logger: ConsoleLogger(), registry: DefaultDetectorRegistry());
      await detectionManager
          .registerDetector(_FakeDetector('x', detected: true));
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
      );
      final received = <SecurityEvent>[];
      eventManager.subscribe(received.add);

      await manager.initialize();
      await manager.checkNow();
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.type, 'x');
      expect(received.single.source, 'SecurityManager');

      await manager.dispose();
      lifecycle.dispose();
    });

    test('status delegates to Lifecycle.current, never tracks its own copy',
        () async {
      final lifecycle = DefaultSecurityStateManager();
      final manager = _buildManager(
        detectionManager: DefaultDetectionManager(logger: ConsoleLogger(), registry: DefaultDetectorRegistry()),
        policyManager: DefaultPolicyManager(logger: ConsoleLogger()),
        eventManager: DefaultEventManager(),
        lifecycle: lifecycle,
      );

      expect(manager.status, SDKState.uninitialized);
      lifecycle.transitionTo(SDKState.initializing);
      expect(manager.status, SDKState.initializing);

      lifecycle.dispose();
    });

    test('pause transitions running -> paused; resume transitions back',
        () async {
      final lifecycle = DefaultSecurityStateManager()
        ..transitionTo(SDKState.initializing)
        ..transitionTo(SDKState.initialized)
        ..transitionTo(SDKState.running);
      final manager = _buildManager(
        detectionManager: DefaultDetectionManager(logger: ConsoleLogger(), registry: DefaultDetectorRegistry()),
        policyManager: DefaultPolicyManager(logger: ConsoleLogger()),
        eventManager: DefaultEventManager(),
        lifecycle: lifecycle,
      );
      await manager.initialize();

      await manager.pause();
      expect(lifecycle.current, SDKState.paused);

      await manager.resume();
      expect(lifecycle.current, SDKState.running);

      await manager.dispose();
      lifecycle.dispose();
    });

    test('shutdown stops the timer but does not transition Lifecycle state',
        () async {
      final lifecycle = DefaultSecurityStateManager()
        ..transitionTo(SDKState.initializing)
        ..transitionTo(SDKState.initialized)
        ..transitionTo(SDKState.running);
      final manager = _buildManager(
        detectionManager: DefaultDetectionManager(logger: ConsoleLogger(), registry: DefaultDetectorRegistry()),
        policyManager: DefaultPolicyManager(logger: ConsoleLogger()),
        eventManager: DefaultEventManager(),
        lifecycle: lifecycle,
      );
      await manager.initialize();

      await manager.shutdown();

      // State-transition ownership for `-> stopped` belongs to
      // PluginInitializer/ShutdownSequence, not SecurityManager itself.
      expect(lifecycle.current, SDKState.running);

      lifecycle.dispose();
    });

    test('SecurityLifecycleHandler callbacks delegate to resume/pause/shutdown',
        () async {
      final lifecycle = DefaultSecurityStateManager()
        ..transitionTo(SDKState.initializing)
        ..transitionTo(SDKState.initialized)
        ..transitionTo(SDKState.running);
      final manager = _buildManager(
        detectionManager: DefaultDetectionManager(logger: ConsoleLogger(), registry: DefaultDetectorRegistry()),
        policyManager: DefaultPolicyManager(logger: ConsoleLogger()),
        eventManager: DefaultEventManager(),
        lifecycle: lifecycle,
      );
      await manager.initialize();

      await manager.onPause();
      expect(lifecycle.current, SDKState.paused);

      await manager.onResume();
      expect(lifecycle.current, SDKState.running);

      await expectLater(manager.onInactive(), completes);
      await expectLater(manager.onDetached(), completes);

      await manager.dispose();
      lifecycle.dispose();
    });
  });
}
