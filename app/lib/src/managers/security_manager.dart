import '../models/detection_result.dart';
import '../models/sdk_state.dart';
import 'manager.dart';

/// Runtime orchestrator — the one component every public call actually
/// reaches. See ARCHITECTURE_CONTRACTS.md Group D.
///
/// Owns references to `DetectionManager`, `PolicyManager`, `EventManager`,
/// `NativeBridge`, `ConfigurationManager`, `PermissionManager`, `Logger`,
/// and the state machine; drives the periodic check timer; runs the
/// confidence-gate → Policy → Event pipeline. None of that pipeline logic
/// is implemented here — Phase 5 owns it. This file defines only the shape.
///
/// Public/Internal: internal — fully wrapped by the `DeviceShield` public
/// facade.
///
/// Extension point: no — this marks `SecurityManager` as not swappable by
/// a host-supplied implementation (unlike `NativeBridge`/`Detector`/`Rule`,
/// which are). It does not mean this contract can never grow a method as
/// the SDK's own built-in features do — `NativeBridge` itself already
/// gained `dispose()` this same way, per an earlier approved architecture
/// correction. [processResult] (added for Screenshot & Screen Recording
/// Protection — see docs/features/SCREENSHOT_SCREEN_RECORDING_PROTECTION.md
/// §8.3) is the same kind of additive, non-breaking change, verified
/// explicitly against this exact question during that feature's Step 8
/// Architecture Verification Report.
abstract class SecurityManager implements Manager {
  /// Current SDK status. Delegates to the state machine
  /// (`Lifecycle`/`SecurityStateManager`) rather than tracking its own copy.
  SDKState get status;

  Future<void> pause();

  Future<void> resume();

  Future<void> shutdown();

  /// Runs one check cycle on demand, outside the periodic timer.
  Future<void> checkNow();

  /// Runs a single, already-obtained [result] through the same
  /// evaluate→executeAction→emit pipeline [checkNow]'s poll path runs per
  /// result — extracted so a push-driven result (from
  /// `ScreenCaptureController`, arriving the instant a native event fires)
  /// reaches Policy/Event immediately, without waiting for the next
  /// periodic timer tick. Contains no logic of its own beyond what
  /// [checkNow] already ran per result before this method existed — see
  /// this feature's own Step 8 report for the exact before/after diff.
  Future<void> processResult(DetectionResult result);

  /// The imperative, proactive protection command (design doc §11.1) —
  /// independent of detection/policy entirely. Pure delegation to the
  /// owned `ScreenCaptureController`'s own `enable()` — this is the only
  /// reachable path to it, since it is a private collaborator with no
  /// other public exposure (Step 10's Architecture Verification Report
  /// §5). Returns the native "applied" answer honestly — `true` on iOS
  /// when a root view exists to protect (via an undocumented-internals
  /// technique, not a supported Apple API — design doc §18.5). This
  /// `true` proves only that the technique's re-parenting call executed
  /// — **not** that a black-screenshot effect actually occurs; live
  /// Simulator verification found it did not, and it remains unconfirmed
  /// on real hardware. `false` only if called too early.
  Future<bool> enableScreenshotProtection();

  /// The imperative disable — symmetric to [enableScreenshotProtection].
  Future<bool> disableScreenshotProtection();

  /// Last-known local state — mirrors [status]'s own synchronous,
  /// always-answerable read pattern (design doc §3), not a fresh native
  /// round-trip.
  bool get isScreenshotProtectionEnabled;

  /// App-switcher/background-snapshot redaction (design doc §17) — the
  /// same imperative shape as [enableScreenshotProtection], delegating to
  /// the same owned `ScreenCaptureController`. Android: a documented alias
  /// for [enableScreenshotProtection] (same `FLAG_SECURE` flag). iOS: a
  /// real, independent mechanism — see `ScreenCaptureController
  /// .enableAppSwitcherProtection`'s own doc comment.
  Future<bool> enableAppSwitcherProtection();

  /// The imperative disable — symmetric to [enableAppSwitcherProtection].
  Future<bool> disableAppSwitcherProtection();

  /// Last-known local state for app-switcher protection — same shape as
  /// [isScreenshotProtectionEnabled].
  bool get isAppSwitcherProtectionEnabled;
}
