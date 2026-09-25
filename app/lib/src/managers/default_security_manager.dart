import 'dart:async';

import '../bridge/native_bridge.dart';
import '../config/configuration_manager.dart';
import '../core/logger.dart';
import '../events/event_manager.dart';
import '../models/detection_result.dart';
import '../models/sdk_state.dart';
import '../models/security_event.dart';
import '../state/lifecycle.dart';
import 'detection_manager.dart';
import 'policy_manager.dart';
import 'screen_capture_controller.dart';
import 'security_manager.dart';

/// Real implementation of [SecurityManager] — the SDK's runtime
/// orchestrator. Coordinates [DetectionManager], [PolicyManager], and
/// [EventManager] only; implements no detection, policy, or native logic
/// of its own.
///
/// Deliberately **retains no `NativeBridge` field** — even though the
/// frozen dependency matrix lists it as an allowed dependency, this class
/// itself has no legitimate use for one (all native communication happens
/// inside `DetectionManager`, via the detectors it hosts, and now inside
/// [screenCaptureController], the one collaborator that genuinely needs
/// direct native access — see docs/features/
/// SCREENSHOT_SCREEN_RECORDING_PROTECTION.md §8.3). A `NativeBridge` is
/// accepted as a constructor *parameter* solely to hand off to
/// [screenCaptureController]'s own construction; it is never stored as a
/// field on this class.
///
/// State-transition ownership is unchanged from the already-frozen rules
/// (ARCHITECTURE_CONTRACTS.md Part 3's "who changes state" table):
/// [pause]/[resume] transition `running ⇄ paused` themselves, exactly as
/// frozen. [shutdown] does **not** transition to `stopped` — that
/// transition belongs to `PluginInitializer`/`ShutdownSequence`, per the
/// same frozen table, so this class only stops its own periodic timer
/// and leaves the state machine alone.
class DefaultSecurityManager implements SecurityManager, SecurityLifecycleHandler {
  DefaultSecurityManager({
    required this.detectionManager,
    required this.policyManager,
    required this.eventManager,
    required this.configurationManager,
    required this.lifecycle,
    required this.logger,
    required NativeBridge nativeBridge,
  }) {
    // Constructed in the constructor *body*, not the initializer list —
    // `processResult` is an instance-method tear-off, and `this` isn't
    // available for that until the body runs. Mirrors the same
    // narrow-callback pattern that already resolves the
    // LifecycleManager<->SecurityManager cycle (SecurityLifecycleHandler),
    // just narrower still — a bare function, not even an interface.
    screenCaptureController = ScreenCaptureController(
      nativeBridge: nativeBridge,
      onResult: processResult,
    );
  }

  final DetectionManager detectionManager;
  final PolicyManager policyManager;
  final EventManager eventManager;
  final ConfigurationManager configurationManager;
  final Lifecycle lifecycle;
  final Logger logger;

  /// Owned exactly like [detectionManager]/[policyManager] — constructed
  /// here, never independently `ServiceContainer`-registered (Step 8's
  /// Architecture Verification Report §4).
  late final ScreenCaptureController screenCaptureController;

  Timer? _timer;

  @override
  SDKState get status => lifecycle.current;

  @override
  Future<void> initialize() async {
    await detectionManager.initialize();
    await policyManager.initialize();
    await screenCaptureController.initialize(configurationManager.current);
    _startPeriodicChecks();
  }

  @override
  Future<void> dispose() async {
    _stopPeriodicChecks();
    await screenCaptureController.dispose();
    await detectionManager.dispose();
    await policyManager.dispose();
  }

  /// Idempotent: a redundant call while already [SDKState.paused] is a
  /// no-op rather than a thrown [StateError]. `paused -> paused` is
  /// deliberately absent from `DefaultSecurityStateManager`'s frozen
  /// transition table (it isn't a real state *change*), but [pause] can
  /// legitimately be invoked twice in a row — both by a host app calling
  /// it defensively, and internally via [onPause], which
  /// `DefaultLifecycleManager` fires on every `AppLifecycleState.paused`
  /// Flutter reports, including ones that occur while already paused.
  /// Calling [pause] from any *other* non-adjacent state (e.g. before
  /// [initialize]) still throws, unchanged — only the same-state case is
  /// special-cased.
  @override
  Future<void> pause() async {
    if (lifecycle.current == SDKState.paused) {
      logger.info('SecurityManager: pause() while already paused — no-op');
      return;
    }
    _stopPeriodicChecks();
    lifecycle.transitionTo(SDKState.paused);
    logger.info('SecurityManager: paused');
  }

  /// Idempotent, symmetric to [pause]: a redundant call while already
  /// [SDKState.running] is a no-op. This is the fix for a real, confirmed
  /// bug — [onResume] is fired by `DefaultLifecycleManager` on every
  /// `AppLifecycleState.resumed` Flutter reports, which includes
  /// transient inactive-then-resumed blips (notification shade, app
  /// switcher, an incoming call) that occur while the SDK never actually
  /// left `running`. Before this fix, that second [resume] call threw an
  /// uncaught `StateError` from `transitionTo(running)`, since
  /// `running -> running` is correctly absent from the frozen transition
  /// table (it isn't a real state change) — observed live via a real
  /// screenshot/notification interaction during Android example-app
  /// testing. See `default_security_manager_test.dart`'s regression tests
  /// for both this callback path and the direct double-call case.
  @override
  Future<void> resume() async {
    if (lifecycle.current == SDKState.running) {
      logger.info('SecurityManager: resume() while already running — no-op');
      return;
    }
    lifecycle.transitionTo(SDKState.running);
    _startPeriodicChecks();
    logger.info('SecurityManager: resumed');
  }

  @override
  Future<void> shutdown() async {
    // Stops this manager's own coordination loop only. The SDK-level
    // `running/paused -> stopped` transition belongs to
    // PluginInitializer/ShutdownSequence (frozen, Phase 4) — not
    // duplicated here.
    _stopPeriodicChecks();
    logger.info('SecurityManager: internal shutdown (timer stopped)');
  }

  @override
  Future<void> checkNow() async {
    final results = await detectionManager.runAllChecks();
    for (final result in results) {
      await processResult(result);
    }
  }

  /// Extracted verbatim from [checkNow]'s own per-result loop body (Step
  /// 8's Architecture Verification Report §7 — zero duplicated logic:
  /// [checkNow] now only calls this once per batched result, and
  /// [screenCaptureController]'s push-driven results reach the exact same
  /// pipeline immediately, without waiting for the next periodic tick.
  /// No confidence gate exists here, same as before this method existed
  /// — every result reaches [PolicyManager] unconditionally (§8 of that
  /// same report: a pre-existing gap, not something this method changes).
  @override
  Future<void> processResult(DetectionResult result) async {
    final action = await policyManager.evaluate(result);
    await policyManager.executeAction(action, result);
    await eventManager.emit(SecurityEvent(
      type: result.type,
      timestamp: DateTime.now(),
      // Deliberately constant — assigning severity based on the result
      // would be a policy-adjacent decision; that content is out of
      // scope for this phase, same as PolicyManager's placeholder
      // action resolution.
      severity: EventSeverity.info,
      source: 'SecurityManager',
      data: {'action': action.name, 'confidence': result.confidence},
    ));
  }

  @override
  Future<bool> enableScreenshotProtection() => screenCaptureController.enable();

  @override
  Future<bool> disableScreenshotProtection() => screenCaptureController.disable();

  @override
  bool get isScreenshotProtectionEnabled => screenCaptureController.isEnabled;

  @override
  Future<bool> enableAppSwitcherProtection() =>
      screenCaptureController.enableAppSwitcherProtection();

  @override
  Future<bool> disableAppSwitcherProtection() =>
      screenCaptureController.disableAppSwitcherProtection();

  @override
  bool get isAppSwitcherProtectionEnabled =>
      screenCaptureController.isAppSwitcherProtectionEnabled;

  // SecurityLifecycleHandler — invoked by whatever LifecycleManager this
  // instance is attached to. Never called directly by this class.

  @override
  Future<void> onResume() => resume();

  @override
  Future<void> onInactive() async {
    // "Limited background protections" (per the original architecture
    // narrative) has no concrete protections to apply yet — no-op until
    // Protections exist.
  }

  @override
  Future<void> onPause() => pause();

  @override
  Future<void> onDetached() => shutdown();

  void _startPeriodicChecks() {
    _stopPeriodicChecks();
    final interval =
        Duration(milliseconds: configurationManager.current.periodicCheckInterval);
    _timer = Timer.periodic(interval, (_) => checkNow());
  }

  void _stopPeriodicChecks() {
    _timer?.cancel();
    _timer = null;
  }
}
