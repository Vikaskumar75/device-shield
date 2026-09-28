import '../models/detection_result.dart';
import '../models/security_action.dart';

/// Contract every policy rule implements.
///
/// A [Rule] decides whether it applies to a given [DetectionResult] and, if
/// so, which [SecurityAction] should follow. This contract knows nothing
/// about any specific rule's condition — see ARCHITECTURE_CONTRACTS.md
/// Group E.
///
/// Public/Internal: public — `CustomRule` (FR-17) implements this directly,
/// so it must be importable outside the SDK.
///
/// Extension point: yes — this is the FR-17 mechanism; new rules register
/// via `PolicyManager.addRule` without ever touching `PolicyManager`'s own
/// implementation.
abstract class Rule {
  /// Unique identifier — required so a rule can later be removed by
  /// `PolicyManager.removeRule(id)`.
  String get id;

  /// Whether this rule applies to [result].
  ///
  /// A rule that throws is treated as "no match" by `PolicyManager` — a
  /// broken rule must never block evaluation of other rules.
  bool matches(DetectionResult result);

  /// The action to execute when [matches] returns `true`.
  SecurityAction get action;

  /// Evaluation priority. Lower is evaluated first; `PolicyManager` stops
  /// at the first matching rule.
  int get priority;
}
