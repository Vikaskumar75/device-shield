import '../models/sdk_state.dart';

/// Single source of truth for SDK status. See ARCHITECTURE_CONTRACTS.md
/// Group G and Part 3's Initialization Matrix for the full transition
/// table.
///
/// Holds the current [SDKState]; validates and performs every transition;
/// broadcasts changes. Transition-guard logic (which states may reach
/// which) is not implemented here — Phase 5 owns it.
///
/// Public/Internal: write access is internal only — nothing but the
/// concrete state machine calls [transitionTo]. Read access
/// (`current`/`stateStream`) is exposed publicly via `DeviceShield.status`.
///
/// Extension point: no.
abstract class Lifecycle {
  SDKState get current;

  Stream<SDKState> get stateStream;

  /// Attempts to move to [next]. Throws `StateError` synchronously if the
  /// transition isn't in the frozen table — the current state is never
  /// left corrupted by a rejected request.
  void transitionTo(SDKState next);
}

/// The narrow callback contract `LifecycleManager` depends on instead of a
/// direct reference to `SecurityManager`.
///
/// This resolves the circular dependency identified in
/// ARCHITECTURE_CONTRACTS.md §Circular Dependency Verification:
/// `SecurityManager` owns `LifecycleManager`, so `LifecycleManager` cannot
/// also hold a concrete reference back to `SecurityManager` without
/// creating a two-node cycle. `SecurityManager` implements this contract
/// and passes itself as the handler; `LifecycleManager` only ever depends
/// on this four-method shape, never on `SecurityManager` concretely — the
/// same pattern it already uses on its `WidgetsBinding` side.
///
/// Architecture Correction 3: implementers of this contract (i.e.
/// `SecurityManager`) may emit a `SecurityEvent` in response to a
/// lifecycle callback — that is legitimate, since `SecurityManager`
/// already owns `EventManager` in the frozen dependency graph. What must
/// never happen is `LifecycleManager` itself constructing or emitting a
/// `SecurityEvent`, or holding any reference to `EventManager` — its only
/// job is translating `WidgetsBinding` callbacks into calls on whatever
/// [SecurityLifecycleHandler] is attached. Event emission is entirely the
/// attached handler's business, several layers away from
/// `LifecycleManager`.
abstract class SecurityLifecycleHandler {
  Future<void> onResume();

  Future<void> onInactive();

  Future<void> onPause();

  Future<void> onDetached();
}

/// The only component listening to Flutter's own app lifecycle. See
/// ARCHITECTURE_CONTRACTS.md Group G.
///
/// Architecture Correction 3: must never depend on, reference, or emit
/// through `EventManager` — see [SecurityLifecycleHandler]'s documentation
/// above for the full reasoning and the correct flow
/// (`LifecycleManager` → `SecurityLifecycleHandler` implementer →
/// `EventManager` → `SecurityEvent`).
///
/// Public/Internal: internal.
///
/// Extension point: no.
abstract class LifecycleManager {
  /// Begins observing `WidgetsBinding` and forwarding lifecycle changes to
  /// [handler].
  void attach(SecurityLifecycleHandler handler);

  /// Stops observing `WidgetsBinding`.
  void detach();
}
