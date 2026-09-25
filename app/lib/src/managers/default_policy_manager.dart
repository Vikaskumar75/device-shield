import '../core/logger.dart';
import '../models/detection_result.dart';
import '../models/security_action.dart';
import '../registry/rule.dart';
import 'policy_manager.dart';

/// Real, coordination-only implementation of [PolicyManager].
///
/// [evaluate] mirrors exactly how `DefaultDetectionManager` coordinates
/// [Detector]s: it invokes whatever [Rule]s have been registered, in
/// priority order, and returns the first match's action — the same
/// "call the registered contract's own method, know nothing about its
/// content" shape used everywhere else in this phase. No rule *content*
/// is implemented here; with zero rules registered (true today, since
/// rule content is out of scope), or when none match, [evaluate] falls
/// through to the placeholder decision [SecurityAction.ignore].
///
/// [executeAction] is a placeholder — no `ActionHandler` registry exists
/// yet (out of scope), so it only logs that coordination reached this
/// point rather than doing anything.
class DefaultPolicyManager implements PolicyManager {
  DefaultPolicyManager({required this.logger});

  final Logger logger;

  final List<Rule> _rules = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {
    _rules.clear();
  }

  @override
  Future<SecurityAction> evaluate(DetectionResult result) async {
    final ordered = List<Rule>.of(_rules)
      ..sort((a, b) => a.priority.compareTo(b.priority));
    for (final rule in ordered) {
      try {
        if (rule.matches(result)) {
          return rule.action;
        }
      } catch (error, stackTrace) {
        // A broken rule is treated as "no match" — per this component's
        // frozen failure behavior, it must never block other rules.
        logger.error(
          'Rule "${rule.id}" threw during evaluation — treated as no match',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    // Placeholder decision: nothing matched (or nothing is registered
    // yet) — rule content is out of scope for this phase.
    return SecurityAction.ignore;
  }

  @override
  Future<void> executeAction(
      SecurityAction action, DetectionResult result) async {
    // Placeholder — no ActionHandler registry exists yet. Coordination
    // reaching this point is logged; nothing else happens.
    logger.info('PolicyManager: action resolved (placeholder execution)',
        data: {'action': action.name, 'type': result.type});
  }

  @override
  Future<void> addRule(Rule rule) async {
    _rules.add(rule);
  }

  @override
  Future<void> removeRule(String ruleId) async {
    _rules.removeWhere((rule) => rule.id == ruleId);
  }

  @override
  double calculateRiskScore(List<DetectionResult> results) {
    final detected = results.where((r) => r.detected);
    if (detected.isEmpty) return 0.0;
    final sum = detected.fold<double>(0.0, (acc, r) => acc + r.confidence);
    return (sum / detected.length).clamp(0.0, 1.0);
  }
}
