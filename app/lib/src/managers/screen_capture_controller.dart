import 'dart:async';

import '../bridge/method_codes.dart';
import '../bridge/native_bridge.dart';
import '../detectors/screen_recording_detector.dart';
import '../detectors/screenshot_detector.dart';
import '../models/detection_result.dart';
import '../models/device_shield_config.dart';

/// Screenshot & Screen Recording Protection —
/// doc/features/SCREENSHOT_SCREEN_RECORDING_PROTECTION.md §9.3/§8.3.
///
/// The feature's real-time mechanism: owns the native push-listener
/// registration and the imperative protection-toggle commands. Owned by
/// [DefaultSecurityManager] exactly like `DetectionManager`/`PolicyManager`
/// are — **not** registered in `ServiceContainer`, since it is a private
/// implementation detail of `SecurityManager`, not a peer service (see
/// Step 8's Architecture Verification Report §4).
///
/// Holds [nativeBridge] directly — the same pattern every leaf `Detector`
/// already uses, not a new one (`ARCHITECTURE_CONTRACTS.md`'s frozen
/// `NativeBridge` row already lists "future `Protection`s" as a dependent).
///
/// Deliberately does **not** hold a `SecurityManager` reference, concrete
/// or otherwise — [onResult] is a plain callback, supplied by whichever
/// `SecurityManager` constructs this instance (its own `processResult`
/// method, torn off), mirroring the narrow-callback pattern that already
/// resolves the `LifecycleManager`↔`SecurityManager` cycle
/// (`SecurityLifecycleHandler`), just narrower still: a bare function
/// type, not even an interface, since there is exactly one callback here.
class ScreenCaptureController {
  ScreenCaptureController({required this.nativeBridge, required this.onResult});

  final NativeBridge nativeBridge;

  /// Invoked with a freshly-constructed [DetectionResult] every time a
  /// native push arrives. Supplied by `SecurityManager` as its own
  /// `processResult` — the same evaluate→executeAction→emit pipeline
  /// `checkNow()`'s poll path already runs, reused rather than duplicated
  /// (Step 8 §7).
  final Future<void> Function(DetectionResult result) onResult;

  static const String _onScreenshotTaken = 'onScreenshotTaken';
  static const String _onScreenCaptureStateChanged =
      'onScreenCaptureStateChanged';

  bool _registered = false;
  bool _enabled = false;
  bool _appSwitcherEnabled = false;

  /// Registers native push callbacks and applies boot-time protection,
  /// **gated by [config]** — this is the fix for a real, confirmed bug:
  /// `enableScreenshotDetection`/`enableScreenRecordingDetection`/
  /// `enableScreenshotProtection`/`enableAppSwitcherProtection` were
  /// previously validated and stored by `DeviceShieldConfig` but never
  /// read anywhere at runtime — the push listeners registered
  /// unconditionally and protection was never auto-applied regardless of
  /// what the config said. See `default_security_manager_test.dart`'s
  /// config-gating regression tests.
  ///
  /// A no-op if already registered — matches every other `initialize()`
  /// in this codebase being safe to call at most meaningfully once per
  /// instance, and keeps a config-gated re-`initialize()` (e.g. after a
  /// `dispose()`/reinitialize cycle) from double-registering a callback.
  Future<void> initialize(DeviceShieldConfig config) async {
    if (_registered) return;
    _registered = true;

    if (config.enableScreenshotDetection) {
      nativeBridge.registerCallback(_onScreenshotTaken, _handleScreenshotTaken);
    }
    if (config.enableScreenRecordingDetection) {
      nativeBridge.registerCallback(
        _onScreenCaptureStateChanged,
        _handleCaptureStateChanged,
      );
    }
    if (config.enableScreenshotProtection) {
      await enable();
    }
    if (config.enableAppSwitcherProtection) {
      await enableAppSwitcherProtection();
    }
  }

  /// Unregisters both push callbacks. Safe to call even if [initialize]
  /// was never called, or already disposed. Does **not** clear
  /// [isEnabled]/[isAppSwitcherProtectionEnabled] — those reflect native
  /// protection state, which persists natively until explicitly disabled;
  /// a disposed controller simply stops listening for new push events,
  /// exactly like [ScreenCaptureProtection]'s own persistence-across-
  /// lifecycle behavior on the native side.
  Future<void> dispose() async {
    nativeBridge.unregisterCallback(_onScreenshotTaken);
    nativeBridge.unregisterCallback(_onScreenCaptureStateChanged);
    _registered = false;
  }

  /// The imperative, proactive protection command (design doc §11.1) —
  /// independent of detection/policy entirely. Android: sets `FLAG_SECURE`.
  /// iOS: re-parents the Flutter root view's layer under a secure text
  /// field's rendering layer, via undocumented `UITextField` internals,
  /// not a supported Apple API (design doc §18.5). **`applied: true`
  /// only proves the re-parenting call executed — it is NOT proof of a
  /// black-screenshot effect.** Live Simulator verification this session
  /// showed the intended capture-exclusion did not occur; unconfirmed on
  /// real hardware (design doc §18.5's own honest write-up). Reports
  /// `false` only if there's no root view yet to protect.
  Future<bool> enable() => _invokeProtection(
    MethodCodes.setScreenshotProtection,
    true,
    (v) => _enabled = v,
  );

  /// The imperative disable — symmetric to [enable].
  Future<bool> disable() => _invokeProtection(
    MethodCodes.setScreenshotProtection,
    false,
    (v) => _enabled = v,
  );

  /// Last-known local state, mirroring `DeviceShield.status`'s own
  /// synchronous, always-answerable read pattern (design doc §3) — not a
  /// fresh native round-trip.
  bool get isEnabled => _enabled;

  /// App-switcher/background-snapshot redaction (design doc §17). Android:
  /// the exact same `FLAG_SECURE` toggle as [enable] — genuinely one
  /// native mechanism, not two; a host app that only wants Recents
  /// redaction on Android should prefer [enable] directly, since this is
  /// a documented alias there. iOS: a real, independent mechanism (a blur
  /// overlay shown just before the OS captures the app-switcher
  /// snapshot) — the first protection call on iOS that can honestly
  /// report `applied: true`.
  Future<bool> enableAppSwitcherProtection() => _invokeProtection(
    MethodCodes.setAppSwitcherProtection,
    true,
    (v) => _appSwitcherEnabled = v,
  );

  /// The imperative disable — symmetric to [enableAppSwitcherProtection].
  Future<bool> disableAppSwitcherProtection() => _invokeProtection(
    MethodCodes.setAppSwitcherProtection,
    false,
    (v) => _appSwitcherEnabled = v,
  );

  /// Last-known local state for app-switcher protection — same
  /// synchronous, cached-read shape as [isEnabled].
  bool get isAppSwitcherProtectionEnabled => _appSwitcherEnabled;

  Future<bool> _invokeProtection(
    String method,
    bool enabled,
    void Function(bool enabled) onApplied,
  ) async {
    final response = await nativeBridge.invoke<Map<Object?, Object?>>(
      method: method,
      arguments: {'enabled': enabled},
    );
    final applied = response['applied'] as bool? ?? false;
    if (applied) onApplied(enabled);
    return applied;
  }

  /// Both platforms send `{'detected': bool, 'confidence': double,
  /// 'signals': [...]}`, matching `MethodCodes.checkEmulator`/
  /// `checkDebugger`'s own established response shape (Steps 5/6). Missing
  /// keys default to "a screenshot was taken" rather than a false negative
  /// — receiving this callback at all means one occurred.
  void _handleScreenshotTaken(dynamic data) {
    final map = data is Map ? data : const <Object?, Object?>{};
    unawaited(
      onResult(
        DetectionResult(
          type: ScreenshotDetector.typeId,
          detected: map['detected'] as bool? ?? true,
          confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
          timestamp: DateTime.now(),
          evidence: {'signals': map['signals'] ?? const <String>[]},
        ),
      ),
    );
  }

  /// iOS sends `{'isCaptured': bool}` only — the notification itself
  /// carries no other payload (design doc §7.2). Android never sends this
  /// callback at all (Step 5's resolution: no reliable Android signal
  /// exists), so this handler is iOS-authoritative in practice; nothing
  /// here assumes a platform, it simply reacts to whatever arrives.
  void _handleCaptureStateChanged(dynamic data) {
    final map = data is Map ? data : const <Object?, Object?>{};
    final isCaptured = map['isCaptured'] as bool? ?? false;
    unawaited(
      onResult(
        DetectionResult(
          type: ScreenRecordingDetector.typeId,
          detected: isCaptured,
          confidence: isCaptured ? 1.0 : 0.0,
          timestamp: DateTime.now(),
          evidence: {'isCaptured': isCaptured},
        ),
      ),
    );
  }
}
