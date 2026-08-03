import 'dart:async';

import '../config/configuration_manager.dart';
import '../core/logger.dart';
import '../events/event_manager.dart';
import '../models/sdk_state.dart';
import '../models/security_event.dart';
import '../state/lifecycle.dart';
import 'detection_manager.dart';
import 'policy_manager.dart';
import 'security_manager.dart';

/// Real implementation of [SecurityManager] — the SDK's runtime
/// orchestrator. Coordinates [DetectionManager], [PolicyManager], and
/// [EventManager] only; implements no detection, policy, or native logic
/// of its own.
///
/// Deliberately holds **no `NativeBridge` reference** — even though the
/// frozen dependency matrix lists it as an allowed dependency, this phase
/// explicitly forbids `SecurityManager` from accessing native APIs
/// directly, and nothing here has any legitimate use for one (all native
/// communication happens inside `DetectionManager`, via the detectors it
/// hosts).
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
  });

  final DetectionManager detectionManager;
  final PolicyManager policyManager;
  final EventManager eventManager;
  final ConfigurationManager configurationManager;
  final Lifecycle lifecycle;
  final Logger logger;

  Timer? _timer;

  @override
  SDKState get status => lifecycle.current;

  @override
  Future<void> initialize() async {
    await detectionManager.initialize();
    await policyManager.initialize();
    _startPeriodicChecks();
  }

  @override
  Future<void> dispose() async {
    _stopPeriodicChecks();
    await detectionManager.dispose();
    await policyManager.dispose();
  }

  @override
  Future<void> pause() async {
    _stopPeriodicChecks();
    lifecycle.transitionTo(SDKState.paused);
    logger.info('SecurityManager: paused');
  }

  @override
  Future<void> resume() async {
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
  }

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
