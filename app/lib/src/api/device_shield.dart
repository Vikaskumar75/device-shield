import 'dart:async';

import '../bootstrap/plugin_initializer.dart';
import '../bootstrap/service_container.dart';
import '../bridge/native_bridge.dart';
import '../events/event_manager.dart';
import '../managers/detection_manager.dart';
import '../managers/policy_manager.dart';
import '../managers/security_manager.dart';
import '../models/device_shield_config.dart';
import '../models/device_shield_exception.dart';
import '../models/sdk_state.dart';
import '../models/security_event.dart';
import '../platform/device_shield_platform_interface.dart';
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
/// break the existing test that constructs `DeviceShield()`.
class DeviceShield {
  Future<String?> getPlatformVersion() {
    return DeviceShieldPlatform.instance.getPlatformVersion();
  }

  static ServiceContainer? _container;
  static PluginInitializer? _initializer;

  static ServiceContainer get _requireContainer {
    final container = _container;
    if (container == null) {
      throw const InitializationException(
        code: 'NOT_INITIALIZED',
        message: 'DeviceShield.initialize() must be called first',
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
    DeviceShieldConfig config = const DeviceShieldConfig(),
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
    DeviceShieldConfig config = const DeviceShieldConfig(),
  }) => _initializer!.reinitialize(config);

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
  ) => _requireContainer.resolve<NativeBridge>().registerCallback(
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
  }) => _requireContainer.resolve<EventManager>().subscribe(
    handler,
    filter: filter,
  );

  /// Screenshot & Screen Recording Protection — the imperative, proactive
  /// protection command (design doc §11.1), independent of detection/
  /// policy entirely. Pure delegation to [SecurityManager
  /// .enableScreenshotProtection] — never reaches `NativeBridge` directly
  /// (Step 10's Architecture Verification Report §7: `SecurityManager` is
  /// the only reachable path to the owned `ScreenCaptureController`).
  /// Returns the native "applied" answer honestly. iOS: `true` when a
  /// root view was available to protect, via an undocumented-internals
  /// technique — not a supported Apple API. **This does not confirm a
  /// black-screenshot effect actually occurs** — only that the
  /// technique's re-parenting call executed; live Simulator testing
  /// found the capture-exclusion did not occur, and it remains
  /// unconfirmed on real hardware (design doc §18.5;
  /// `ScreenCaptureProtection.swift`'s own warning). `false` only if
  /// called before any window exists yet.
  static Future<bool> enableScreenshotProtection() =>
      _requireContainer.resolve<SecurityManager>().enableScreenshotProtection();

  /// The imperative disable — symmetric to [enableScreenshotProtection].
  static Future<bool> disableScreenshotProtection() => _requireContainer
      .resolve<SecurityManager>()
      .disableScreenshotProtection();

  /// Last-known local state, mirroring [status]'s own synchronous,
  /// always-answerable read pattern — `false` before [initialize] has
  /// ever been called, never a throw, since checking this is a reasonable
  /// thing to do at any time (same reasoning [status] itself documents).
  static bool get isScreenshotProtectionEnabled {
    final container = _container;
    if (container == null || !container.isRegistered<SecurityManager>()) {
      return false;
    }
    return container.resolve<SecurityManager>().isScreenshotProtectionEnabled;
  }

  /// Subscribes [handler] to screenshot-detection events only — pure sugar
  /// over [subscribe], introducing no new capability or logic (matching
  /// this facade's own "owns no logic of its own" rule). Filters on the
  /// literal string `'screenshot'`, matching
  /// `ScreenshotDetector.typeId`/`DetectionResult.type` exactly (verified
  /// against the actual implementation, not the design doc's own earlier
  /// illustrative `'screenshot_taken'` text — that string is the native
  /// callback *name*, a different namespace, never the emitted
  /// `SecurityEvent.type`). Deliberately a string literal, not an import
  /// of the concrete `ScreenshotDetector` class — this facade is
  /// forbidden from depending on any concrete `Detector`
  /// (ARCHITECTURE_CONTRACTS.md Part 2).
  static StreamSubscription<SecurityEvent> onScreenshot(
    void Function(SecurityEvent event) handler,
  ) => subscribe(handler, filter: (event) => event.type == 'screenshot');

  /// App-switcher/background-snapshot redaction (design doc §17) — the
  /// same imperative, pure-delegation shape as [enableScreenshotProtection].
  /// Android: a documented alias for [enableScreenshotProtection] (the
  /// same underlying `FLAG_SECURE` flag — see `ScreenCaptureController
  /// .enableAppSwitcherProtection`'s own doc comment for why). iOS: a
  /// real, independent, working protection — a blur overlay covers the
  /// window immediately before the OS captures the app-switcher snapshot,
  /// removed when the app becomes active again. This is the first
  /// protection call in this SDK that can honestly report `applied: true`
  /// on iOS.
  static Future<bool> enableAppSwitcherProtection() => _requireContainer
      .resolve<SecurityManager>()
      .enableAppSwitcherProtection();

  /// The imperative disable — symmetric to [enableAppSwitcherProtection].
  static Future<bool> disableAppSwitcherProtection() => _requireContainer
      .resolve<SecurityManager>()
      .disableAppSwitcherProtection();

  /// Last-known local state, mirroring [isScreenshotProtectionEnabled]'s
  /// own synchronous, always-answerable read pattern.
  static bool get isAppSwitcherProtectionEnabled {
    final container = _container;
    if (container == null || !container.isRegistered<SecurityManager>()) {
      return false;
    }
    return container.resolve<SecurityManager>().isAppSwitcherProtectionEnabled;
  }

  /// Subscribes [handler] to screen-recording-state-change events only —
  /// pure sugar over [subscribe], same reasoning as [onScreenshot].
  /// Filters on `'screen_recording'`, matching
  /// `ScreenRecordingDetector.typeId`/`DetectionResult.type` exactly.
  static StreamSubscription<SecurityEvent> onScreenRecordingChanged(
    void Function(SecurityEvent event) handler,
  ) => subscribe(handler, filter: (event) => event.type == 'screen_recording');
}
