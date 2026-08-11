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

class _FakeNativeBridge implements NativeBridge {
  _FakeNativeBridge({this.respond});

  final Map<String, void Function(dynamic data)> callbacks = {};
  final Future<Object?> Function(String method, Map<String, dynamic>? args)?
      respond;
  final List<String> invokedMethods = [];

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
  NativeBridge? nativeBridge,
  // A very long interval so the periodic timer never fires mid-test. Every
  // other field defaults false, matching FlutterShieldConfig's own
  // least-invasive defaults — callers that need push callbacks registered
  // must opt in explicitly via this parameter, exactly like a real host
  // app must, now that config actually gates registration (see the
  // config-gated boot group below).
  FlutterShieldConfig config = const FlutterShieldConfig(
    periodicCheckInterval: 999999,
  ),
}) {
  return DefaultSecurityManager(
    detectionManager: detectionManager,
    policyManager: policyManager,
    eventManager: eventManager,
    configurationManager: DefaultConfigurationManager(config),
    lifecycle: lifecycle,
    logger: ConsoleLogger(),
    nativeBridge: nativeBridge ?? _FakeNativeBridge(),
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

    test('processResult drives the exact same Policy -> Event pipeline '
        'checkNow uses per result — a push-driven result reaches an '
        'event without waiting for detectionManager.runAllChecks() at '
        'all', () async {
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
      );
      final received = <SecurityEvent>[];
      eventManager.subscribe(received.add);
      await manager.initialize();

      await manager.processResult(DetectionResult(
        type: 'screenshot',
        detected: true,
        confidence: 1.0,
        timestamp: DateTime.now(),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.type, 'screenshot');
      expect(received.single.source, 'SecurityManager');
      expect(received.single.data['confidence'], 1.0);

      await manager.dispose();
      lifecycle.dispose();
    });

    test('checkNow calling processResult once per result produces exactly '
        'the same events as calling processResult directly for each — no '
        'result is ever processed twice', () async {
      final detectionManager = DefaultDetectionManager(
          logger: ConsoleLogger(), registry: DefaultDetectorRegistry());
      await detectionManager.registerDetector(_FakeDetector('a', detected: true));
      await detectionManager.registerDetector(_FakeDetector('b', detected: true));
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

      expect(received, hasLength(2));
      expect(received.map((e) => e.type).toSet(), {'a', 'b'});

      await manager.dispose();
      lifecycle.dispose();
    });

    test('a real native push, routed through the actual '
        'ScreenCaptureController this manager owns, reaches an event — '
        'end-to-end, not just via processResult() called directly',
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
        config: const FlutterShieldConfig(
          periodicCheckInterval: 999999,
          enableScreenshotDetection: true,
        ),
      );
      final received = <SecurityEvent>[];
      eventManager.subscribe(received.add);

      await manager.initialize();
      // Simulates the native side calling sendEvent("onScreenshotTaken",
      // ...) — routed through the real DefaultNativeBridge mechanism in
      // production; here, directly through the fake's stored callback,
      // exactly mirroring default_native_bridge_test.dart's own approach.
      nativeBridge.callbacks['onScreenshotTaken']!(
        {'detected': true, 'confidence': 1.0, 'signals': []},
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.type, 'screenshot');
      expect(received.single.source, 'SecurityManager');

      await manager.dispose();
      // dispose() must have unregistered both callbacks via the owned
      // ScreenCaptureController's own dispose().
      expect(nativeBridge.callbacks, isEmpty);
      lifecycle.dispose();
    });
  });

  group('DefaultSecurityManager — protection commands (Step 10)', () {
    test('enableScreenshotProtection delegates to the owned '
        'ScreenCaptureController and returns the native "applied" answer',
        () async {
      final nativeBridge = _FakeNativeBridge(
        respond: (method, args) async => {'applied': true},
      );
      final manager = _buildManager(
        detectionManager: DefaultDetectionManager(
            logger: ConsoleLogger(), registry: DefaultDetectorRegistry()),
        policyManager: DefaultPolicyManager(logger: ConsoleLogger()),
        eventManager: DefaultEventManager(),
        lifecycle: DefaultSecurityStateManager(),
        nativeBridge: nativeBridge,
      );

      final applied = await manager.enableScreenshotProtection();

      expect(applied, isTrue);
      expect(manager.isScreenshotProtectionEnabled, isTrue);
    });

    test('disableScreenshotProtection delegates and clears the enabled '
        'state', () async {
      final nativeBridge = _FakeNativeBridge(
        respond: (method, args) async => {'applied': true},
      );
      final manager = _buildManager(
        detectionManager: DefaultDetectionManager(
            logger: ConsoleLogger(), registry: DefaultDetectorRegistry()),
        policyManager: DefaultPolicyManager(logger: ConsoleLogger()),
        eventManager: DefaultEventManager(),
        lifecycle: DefaultSecurityStateManager(),
        nativeBridge: nativeBridge,
      );
      await manager.enableScreenshotProtection();

      final applied = await manager.disableScreenshotProtection();

      expect(applied, isTrue);
      expect(manager.isScreenshotProtectionEnabled, isFalse);
    });

    test('an honest "not applied" native answer (e.g. no root view/'
        'Activity available yet) never marks the manager as '
        'protection-enabled', () async {
      final nativeBridge = _FakeNativeBridge(
        respond: (method, args) async => {'applied': false},
      );
      final manager = _buildManager(
        detectionManager: DefaultDetectionManager(
            logger: ConsoleLogger(), registry: DefaultDetectorRegistry()),
        policyManager: DefaultPolicyManager(logger: ConsoleLogger()),
        eventManager: DefaultEventManager(),
        lifecycle: DefaultSecurityStateManager(),
        nativeBridge: nativeBridge,
      );

      final applied = await manager.enableScreenshotProtection();

      expect(applied, isFalse);
      expect(manager.isScreenshotProtectionEnabled, isFalse);
    });

    test('isScreenshotProtectionEnabled defaults to false before any '
        'enable() call', () {
      final manager = _buildManager(
        detectionManager: DefaultDetectionManager(
            logger: ConsoleLogger(), registry: DefaultDetectorRegistry()),
        policyManager: DefaultPolicyManager(logger: ConsoleLogger()),
        eventManager: DefaultEventManager(),
        lifecycle: DefaultSecurityStateManager(),
        nativeBridge: _FakeNativeBridge(),
      );

      expect(manager.isScreenshotProtectionEnabled, isFalse);
    });
  });

  group('DefaultSecurityManager — coordination only (continued)', () {
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

    test(
        'regression: resume() while already running is a no-op, not a '
        'StateError (bug found via AppLifecycleState.resumed firing while '
        'already running, e.g. a transient inactive-then-resumed blip)',
        () async {
      final lifecycle = DefaultSecurityStateManager()
        ..transitionTo(SDKState.initializing)
        ..transitionTo(SDKState.initialized)
        ..transitionTo(SDKState.running);
      final manager = _buildManager(
        detectionManager: DefaultDetectionManager(
            logger: ConsoleLogger(), registry: DefaultDetectorRegistry()),
        policyManager: DefaultPolicyManager(logger: ConsoleLogger()),
        eventManager: DefaultEventManager(),
        lifecycle: lifecycle,
      );
      await manager.initialize();

      // Already running — resume() must not throw and must leave the
      // state unchanged, matching real repeated AppLifecycleState.resumed
      // delivery via onResume() below.
      await expectLater(manager.resume(), completes);
      expect(lifecycle.current, SDKState.running);

      await manager.dispose();
      lifecycle.dispose();
    });

    test(
        'regression: pause() while already paused is a no-op, not a '
        'StateError', () async {
      final lifecycle = DefaultSecurityStateManager()
        ..transitionTo(SDKState.initializing)
        ..transitionTo(SDKState.initialized)
        ..transitionTo(SDKState.running);
      final manager = _buildManager(
        detectionManager: DefaultDetectionManager(
            logger: ConsoleLogger(), registry: DefaultDetectorRegistry()),
        policyManager: DefaultPolicyManager(logger: ConsoleLogger()),
        eventManager: DefaultEventManager(),
        lifecycle: lifecycle,
      );
      await manager.initialize();

      await manager.pause();
      expect(lifecycle.current, SDKState.paused);

      await expectLater(manager.pause(), completes);
      expect(lifecycle.current, SDKState.paused);

      await manager.dispose();
      lifecycle.dispose();
    });

    test(
        'regression: onResume() delivered twice in a row while running '
        '(simulating a real inactive->resumed blip from the OS, e.g. the '
        'notification shade or a screenshot toast) does not throw',
        () async {
      final lifecycle = DefaultSecurityStateManager()
        ..transitionTo(SDKState.initializing)
        ..transitionTo(SDKState.initialized)
        ..transitionTo(SDKState.running);
      final manager = _buildManager(
        detectionManager: DefaultDetectionManager(
            logger: ConsoleLogger(), registry: DefaultDetectorRegistry()),
        policyManager: DefaultPolicyManager(logger: ConsoleLogger()),
        eventManager: DefaultEventManager(),
        lifecycle: lifecycle,
      );
      await manager.initialize();

      // First onResume(): already running (never left it) — this alone
      // used to throw before the fix, with no pause/onPause in between.
      await expectLater(manager.onResume(), completes);
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

  group('DefaultSecurityManager — config-driven boot (dead-config fix, '
      'manager-level)', () {
    test('initialize() reads ConfigurationManager.current and passes it to '
        'the owned ScreenCaptureController — enableScreenshotProtection:'
        'true actually applies protection at boot, with zero imperative '
        'calls from the caller', () async {
      final nativeBridge = _FakeNativeBridge(
        respond: (method, args) async => {'applied': true},
      );
      final manager = _buildManager(
        detectionManager: DefaultDetectionManager(
            logger: ConsoleLogger(), registry: DefaultDetectorRegistry()),
        policyManager: DefaultPolicyManager(logger: ConsoleLogger()),
        eventManager: DefaultEventManager(),
        lifecycle: DefaultSecurityStateManager(),
        nativeBridge: nativeBridge,
        config: const FlutterShieldConfig(
          periodicCheckInterval: 999999,
          enableScreenshotProtection: true,
        ),
      );

      await manager.initialize();

      expect(nativeBridge.invokedMethods, contains('setScreenshotProtection'));
      expect(manager.isScreenshotProtectionEnabled, isTrue);

      await manager.dispose();
    });

    test('the default config (everything false) applies nothing and '
        'registers nothing at boot', () async {
      final nativeBridge = _FakeNativeBridge();
      final manager = _buildManager(
        detectionManager: DefaultDetectionManager(
            logger: ConsoleLogger(), registry: DefaultDetectorRegistry()),
        policyManager: DefaultPolicyManager(logger: ConsoleLogger()),
        eventManager: DefaultEventManager(),
        lifecycle: DefaultSecurityStateManager(),
        nativeBridge: nativeBridge,
      );

      await manager.initialize();

      expect(nativeBridge.invokedMethods, isEmpty);
      expect(nativeBridge.callbacks, isEmpty);
      expect(manager.isScreenshotProtectionEnabled, isFalse);
      expect(manager.isAppSwitcherProtectionEnabled, isFalse);

      await manager.dispose();
    });
  });
}
