/// Generic registration/lookup contract. `DetectorRegistry` (Phase 6)
/// builds on this base.
///
/// `ManagerRegistry` and `ActionRegistry` are **not** approved
/// architecture components — an earlier version of this comment listed
/// them as planned Phase 6 work, which was inaccurate; neither appears
/// anywhere in ARCHITECTURE.md or ARCHITECTURE_CONTRACTS.md, and neither
/// was built. Similarly, a `RuleRegistry` was deliberately not built as a
/// separate component — `PolicyManager` owns its rule collection directly
/// (see ARCHITECTURE_CONTRACTS.md Group D), an intentional asymmetry with
/// `DetectorRegistry`, not an oversight.
///
/// This is the base shape only — a concrete registry adds whatever
/// domain-specific enable/priority/ordering logic it needs on top. Kept
/// generic so a future registry never has to re-derive register/find/list
/// semantics from scratch.
///
/// Public/Internal: internal — no registry is meant to be constructed or
/// swapped by a host app directly; extension happens through the
/// components a registry holds (e.g. [Detector], `Rule`), not the registry
/// mechanism itself.
abstract class Registry<T> {
  /// Adds [entry] to the registry.
  void register(T entry);

  /// Removes [entry] from the registry, if present.
  void unregister(T entry);

  /// Returns the first entry matching [predicate], or `null` if none does.
  T? find(bool Function(T entry) predicate);

  /// Returns every currently registered entry.
  List<T> list();
}
