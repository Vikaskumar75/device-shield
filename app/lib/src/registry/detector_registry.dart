import 'detector.dart';
import 'registry.dart';

/// Decouples "what detectors exist" from "how `DetectionManager` runs
/// them" — the FR-18 extension mechanism itself. See
/// ARCHITECTURE_CONTRACTS.md Group E.
///
/// Builds on the generic [Registry] base (register/unregister/find/list)
/// and adds the `Detector`-specific accessors this phase requires:
/// `contains`, `clear`, `getAll` (priority-ordered), `getById`. Detectors
/// are keyed by `Detector.type` — `getAll()` is an alias for [list] with
/// domain-specific naming; both return the same priority-ordered,
/// immutable view.
///
/// Owner (creates it): `PluginInitializer`, registered into
/// `ServiceContainer` (Phase 4's dependency-injection pattern — this class
/// is never manually constructed inside `DetectionManager`).
///
/// Dependents: `DetectionManager` exclusively — nothing else is meant to
/// hold a reference to this.
///
/// Public/Internal: internal — private to the framework, not part of the
/// public API surface.
///
/// Pure storage only: depends on nothing but the [Detector] contract and
/// the generic [Registry] base. No manager, no `NativeBridge`, no
/// platform code, no knowledge of policies or events.
abstract class DetectorRegistry implements Registry<Detector> {
  /// Adds [entry] to the registry.
  ///
  /// Throws [ArgumentError] if a detector with the same [Detector.type]
  /// is already registered — this is the duplicate-registration
  /// prevention this component exists to enforce.
  @override
  void register(Detector entry);

  /// Whether a detector identified by [type] is currently registered.
  bool contains(String type);

  /// Removes every registered detector.
  void clear();

  /// Every registered detector, ordered by [Detector.priority] ascending
  /// (registration order preserved as the tiebreak for equal priorities).
  /// An unmodifiable view — callers cannot mutate the registry through it.
  List<Detector> getAll();

  /// The detector registered for [type], or `null` if none is.
  Detector? getById(String type);
}
