import 'dart:async';

import '../bootstrap/plugin_initializer.dart';
import '../bootstrap/service_container.dart';
import '../bridge/native_bridge.dart';
import '../events/event_manager.dart';
import '../managers/detection_manager.dart';
import '../managers/policy_manager.dart';
import '../managers/security_manager.dart';
import '../models/flutter_shield_config.dart';
import '../models/flutter_shield_exception.dart';
import '../models/sdk_state.dart';
import '../models/security_event.dart';
import '../platform/flutter_shield_platform_interface.dart';
import '../registry/detector.dart';
import '../registry/rule.dart';
import '../state/lifecycle.dart';

/// The SDK's single public entry point. See ARCHITECTURE_CONTRACTS.md
/// Group A: "the only symbol a host app ever imports," delegating every
/// call 1:1 to the layers beneath it, owning no logic of its own.
///
/// [getPlatformVersion] is the pre-existing Phase 1 instance method, kept
/// exactly as-is for backward compatibility. Every method below it is the
/// new Phase 8 surface — static, per the frozen contract's own "static
/// class, never instantiated" description of this component. Both shapes
/// coexist deliberately: changing `getPlatformVersion` to static would
/// break the existing test that constructs `FlutterShield()`.
class FlutterShield {
  Future<String?> getPlatformVersion() {
    return FlutterShieldPlatform.instance.getPlatformVersion();
  }

  static ServiceContainer? _container;
  static PluginInitializer? _initializer;

  static ServiceContainer get _requireContainer {
    final container = _container;
    if (container == null) {
      throw const InitializationException(
        code: 'NOT_INITIALIZED',
        message: 'FlutterShield.initialize() must be called first',
      );
    }
    return container;
  }

  /// Boots the SDK: validates and stores [config], wires the native
  /// bridge, event system, and manager composition, and starts
  /// monitoring. Delegates entirely to [PluginInitializer] — see its own
  /// documentation for the full 9-step sequence. `PluginInitializer` now
  /// constructs every service itself (including `DetectionManager`,
  /// `PolicyManager`, `SecurityManager`, and `LifecycleManager`) when the
  /// caller hasn't already registered one — this class no longer holds
  /// any construction responsibility of its own.
  static Future<void> initialize({
    FlutterShieldConfig config = const FlutterShieldConfig(),
  }) async {
    final container = _container ??= ServiceContainer();
    final initializer = _initializer ??= PluginInitializer(
      container: container,
    );
    await initializer.initialize(config);
  }

  /// Current SDK status. `uninitialized` if [initialize] has never been
  /// called — this is the one query that must not throw before boot,
  /// since checking status is a reasonable thing to do at any time.
  static SDKState get status {
    final container = _container;
    if (container == null || !container.isRegistered<Lifecycle>()) {
      return SDKState.uninitialized;
    }
    return container.resolve<Lifecycle>().current;
  }

  static Future<void> pause() =>
      _requireContainer.resolve<SecurityManager>().pause();

  static Future<void> resume() =>
      _requireContainer.resolve<SecurityManager>().resume();

  /// Runs one check cycle on demand, outside the periodic timer.
  static Future<void> checkNow() =>
      _requireContainer.resolve<SecurityManager>().checkNow();

  /// Pauses monitoring and tears down every service `PluginInitializer`
  /// started, in reverse order (`DetectionManager`/`PolicyManager`
  /// included — `PluginInitializer.shutdown()` now owns unregistering
  /// them, since it's the class that constructed them). Leaves the SDK
  /// `stopped` — resumable via [initialize] or [reinitialize].
  static Future<void> shutdown() => _initializer!.shutdown();

  /// Re-runs the boot sequence after [shutdown] (or a prior failure).
  /// Rebuilds every disposed service through the same
  /// [ServiceContainer] registration flow used by [initialize] — nothing
  /// disposed is ever revived.
  static Future<void> reinitialize({
    FlutterShieldConfig config = const FlutterShieldConfig(),
  }) =>
      _initializer!.reinitialize(config);

  /// Full teardown: shuts down if still running, then clears every
  /// registration. Safe to call [initialize] again afterward — a fresh
  /// [ServiceContainer] and [PluginInitializer] are created on the next
  /// call, since [dispose] discards this class's static references to
  /// both.
  static Future<void> dispose() async {
    await _initializer?.dispose();
    _container = null;
    _initializer = null;
  }

  /// Registers [detector] at runtime — the FR-18 extension path. Pure
  /// delegation to [DetectionManager.registerDetector]; this class knows
  /// nothing about what [detector] checks for.
  static Future<void> registerDetector(Detector detector) =>
      _requireContainer.resolve<DetectionManager>().registerDetector(detector);

  /// Adds [rule] at runtime — the FR-17 extension path. Pure delegation
  /// to [PolicyManager.addRule].
  static Future<void> addRule(Rule rule) =>
      _requireContainer.resolve<PolicyManager>().addRule(rule);

  /// Removes a previously added rule by [ruleId].
  static Future<void> removeRule(String ruleId) =>
      _requireContainer.resolve<PolicyManager>().removeRule(ruleId);

  /// Registers [callback] for native-pushed events named [name]. Pure
  /// delegation to [NativeBridge.registerCallback].
  static void registerCallback(
    String name,
    void Function(dynamic data) callback,
  ) =>
      _requireContainer.resolve<NativeBridge>().registerCallback(
            name,
            callback,
          );

  static void unregisterCallback(String name) =>
      _requireContainer.resolve<NativeBridge>().unregisterCallback(name);

  /// Subscribes [handler] to security events matching [filter] (or every
  /// event, if omitted). Pure delegation to [EventManager.subscribe] —
  /// matches that contract's exact shape rather than introducing a new
  /// `Stream`-returning surface `EventManager` doesn't itself expose.
  static StreamSubscription<SecurityEvent> subscribe(
    SecurityEventHandler handler, {
    SecurityEventFilter? filter,
  }) =>
      _requireContainer
          .resolve<EventManager>()
          .subscribe(handler, filter: filter);
}
