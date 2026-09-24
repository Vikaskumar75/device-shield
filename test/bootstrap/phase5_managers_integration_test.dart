import 'package:flutter_shield/src/bootstrap/plugin_initializer.dart';
import 'package:flutter_shield/src/bootstrap/service_container.dart';
import 'package:flutter_shield/src/bridge/native_bridge.dart';
import 'package:flutter_shield/src/config/configuration_manager.dart';
import 'package:flutter_shield/src/core/logger.dart';
import 'package:flutter_shield/src/events/default_event_manager.dart';
import 'package:flutter_shield/src/events/event_manager.dart';
import 'package:flutter_shield/src/managers/default_detection_manager.dart';
import 'package:flutter_shield/src/managers/default_policy_manager.dart';
import 'package:flutter_shield/src/managers/default_security_manager.dart';
import 'package:flutter_shield/src/managers/detection_manager.dart';
import 'package:flutter_shield/src/managers/security_manager.dart';
import 'package:flutter_shield/src/models/detection_result.dart';
import 'package:flutter_shield/src/models/flutter_shield_config.dart';
import 'package:flutter_shield/src/models/sdk_state.dart';
import 'package:flutter_shield/src/registry/detector.dart';
import 'package:flutter_shield/src/registry/detector_registry.dart';
import 'package:flutter_shield/src/state/default_lifecycle_manager.dart';
import 'package:flutter_shield/src/state/lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proves the Phase 5 managers and the Phase 6 registry wire correctly
/// into the Phase 4 `PluginInitializer` sequence, alongside the real
/// Phase 7 `DefaultNativeBridge` — auto-registered by `PluginInitializer`
/// (this correction pass), not a test-only fake. Safe to use for real
/// here: nothing in this test ever invokes a channel method, only
/// registers/disposes the bridge, so no actual native call is attempted.
class _FakeDetector implements Detector {
  @override
  final String type = 'phase6-probe';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'PluginInitializer (unmodified boot order) reaches running with the '
      'real Phase 5 managers and the Phase 6 DetectorRegistry composed '
      'together via constructor injection', () async {
    final container = ServiceContainer();
    // NativeBridge is intentionally left unregistered — Step 3 now
    // auto-registers the real DefaultNativeBridge (this correction pass).

    final eventManager = DefaultEventManager();
    container.registerSingleton<EventManager>(eventManager);

    container.registerSingleton<LifecycleManager>(DefaultLifecycleManager());

    // Captured so assertions after initialize() can reach the same
    // instance the lazy factory below constructs.
    late final DetectionManager detectionManager;

    // Deferred: PluginInitializer default-registers Logger/
    // ConfigurationManager/Lifecycle/DetectorRegistry during its own
    // steps 1-5, *before* step 6 resolves SecurityManager. A lazy
    // singleton defers construction until resolve<SecurityManager>()
    // actually runs, by which point all four already exist in the
    // container — this is exactly how DetectorRegistry reaches
    // DetectionManager via constructor injection rather than
    // DetectionManager constructing one itself.
    container.registerLazySingleton<SecurityManager>(() {
      detectionManager = DefaultDetectionManager(
        logger: container.resolve<Logger>(),
        registry: container.resolve<DetectorRegistry>(),
      );
      final policyManager =
          DefaultPolicyManager(logger: container.resolve<Logger>());
      return DefaultSecurityManager(
        detectionManager: detectionManager,
        policyManager: policyManager,
        eventManager: eventManager,
        configurationManager: container.resolve<ConfigurationManager>(),
        lifecycle: container.resolve<Lifecycle>(),
        logger: container.resolve<Logger>(),
        nativeBridge: container.resolve<NativeBridge>(),
      );
    });

    final initializer = PluginInitializer(container: container);

    await initializer.initialize(const FlutterShieldConfig());

    expect(container.resolve<Lifecycle>().current, SDKState.running);
    expect(container.resolve<SecurityManager>().status, SDKState.running);
    expect(container.isRegistered<DetectorRegistry>(), isTrue,
        reason:
            'Step 5 must register a DetectorRegistry, per the Phase 6 '
            'clarification');

    // Prove the registry DetectionManager received is genuinely usable
    // end to end, through the same container-resolved instance.
    final probe = _FakeDetector();
    await detectionManager.registerDetector(probe);
    await detectionManager.runAllChecks();
    expect(probe.checked, isTrue);
    expect(container.resolve<DetectorRegistry>().contains('phase6-probe'),
        isTrue);

    await initializer.shutdown();
    expect(container.resolve<Lifecycle>().current, SDKState.stopped);
  });
}
