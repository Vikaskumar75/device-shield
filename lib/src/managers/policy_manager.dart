import '../models/detection_result.dart';
import '../models/security_action.dart';
import '../registry/rule.dart';
import 'manager.dart';

/// Turns a [DetectionResult] into a [SecurityAction] — no built-in opinion
/// beyond what the active profile configures. See ARCHITECTURE_CONTRACTS.md
/// Group D.
///
/// Holds a prioritized [Rule] list; evaluates results against it; executes
/// the resolved action via a registered handler. None of the rule-matching
/// or action-execution logic is implemented here — Phase 5 owns it.
///
/// Public/Internal: internal. `addRule`/`removeRule` are reachable publicly
/// via `FlutterShield`.
///
/// Extension point: yes — new [Rule] implementations (FR-17) and new action
/// handlers registered against the reserved `SecurityAction.custom` slot.
abstract class PolicyManager implements Manager {
  /// Resolves the action for [result] by matching against the current rule
  /// list in priority order.
  Future<SecurityAction> evaluate(DetectionResult result);

  /// Executes [action] for [result] via its registered handler.
  Future<void> executeAction(SecurityAction action, DetectionResult result);

  /// Adds [rule] at runtime — the FR-17 extension path.
  Future<void> addRule(Rule rule);

  /// Removes a previously added rule by [ruleId].
  Future<void> removeRule(String ruleId);

  /// Weighted risk score across every result in [results], clamped 0.0–1.0.
  double calculateRiskScore(List<DetectionResult> results);
}
