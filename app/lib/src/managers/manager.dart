/// Shared lifecycle shape implemented by `SecurityManager`,
/// `DetectionManager`, `PolicyManager`, `EventManager`, and
/// `ConfigurationManager` — the five components whose boot/shutdown steps
/// are individually numbered in ARCHITECTURE_CONTRACTS.md Part 3.
///
/// `Logger` and `LifecycleManager` are named as their own distinct
/// contracts per the approved component list and are intentionally not
/// implementations of this interface — their initialize/dispose shapes
/// differ (Logger boots with a default before reconfiguring; LifecycleManager
/// uses attach/detach against `WidgetsBinding`, not a symmetric pair).
///
/// Public/Internal: internal.
abstract class Manager {
  Future<void> initialize();

  Future<void> dispose();
}
