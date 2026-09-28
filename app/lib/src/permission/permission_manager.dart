import '../managers/manager.dart';

/// Requests and tracks the OS permissions the active profile's detectors/
/// protections require. See ARCHITECTURE_CONTRACTS.md Group C.
///
/// [initialize] performs the actual request (Part 3 Init Matrix step 2:
/// "requests required permissions") — the permission *set* itself is
/// supplied at construction time, not through [initialize]'s parameterless
/// signature (the frozen `Manager` contract), the same pattern
/// `ConfigurationManager` already uses for its own per-boot input.
///
/// M10's `SecurityProfile` is documented as this component's source for
/// deriving a required-permission set, but nothing yet threads a profile
/// through `DeviceShield.initialize()` — `SecurityProfile` exists only as
/// a data shape today. Until that lands, the required set is whatever the
/// caller supplies directly; an empty set (today's only reachable
/// scenario through the public API) is always satisfied trivially. See
/// `DefaultPermissionManager`'s own doc comment for why a non-empty set is
/// deliberately not silently auto-granted.
///
/// Public/Internal: internal.
///
/// Extension point: no.
abstract class PermissionManager implements Manager {
  /// Requests every permission in [permissions]. [initialize] calls this
  /// once, internally, with whatever set the implementation was
  /// constructed with; it's also exposed directly so a future recovery
  /// path (`RecoveryStrategy` re-requesting after a denial, per this
  /// contract's frozen failure behavior) has something concrete to call.
  ///
  /// Throws `PermissionException` naming every permission that was denied.
  Future<void> requestPermissions(Set<String> permissions);

  /// Whether [permission] is currently known to be granted.
  bool isGranted(String permission);

  /// Every permission currently known to be granted.
  Set<String> get grantedPermissions;
}
