/// Placeholder shell — Phase 3 ("Core Models") owns the complete definition.
///
/// Exists now only so the [Lifecycle] and manager contracts in Phase 2 have
/// a real type instead of `dynamic`. Values match the 8-state machine
/// frozen in ARCHITECTURE_CONTRACTS.md Part 3 exactly — no logic, no
/// transition rules live here; that belongs to the `Lifecycle` contract.
enum SDKState {
  uninitialized,
  initializing,
  initialized,
  running,
  paused,
  stopped,
  failure,
  destroyed,
}
