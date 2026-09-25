import 'permission_manager.dart';

/// Real implementation of [PermissionManager].
///
/// [requiredPermissions] is fixed at construction — the same "supplied at
/// build time, not through `initialize()`" pattern `ConfigurationManager`
/// already uses (see [PermissionManager]'s own doc comment for why).
///
/// Today's only reachable input through the public API is an empty set:
/// no `SecurityProfile` is yet threaded through `DeviceShield.initialize()`,
/// and no built-in detector/protection exists yet to require a real OS
/// permission. [initialize] therefore trivially succeeds for the empty
/// case.
///
/// A non-empty [requiredPermissions] set is intentionally **not** silently
/// auto-granted — doing so would misrepresent permissions this class never
/// actually checked against the OS. Requesting a real, non-empty
/// permission set requires the sole native-access path (`NativeBridge` —
/// see ARCHITECTURE_CONTRACTS.md Group F) to expose a permission-request
/// method, which doesn't exist on either platform yet. [requestPermissions]
/// throws [UnimplementedError] for that case rather than fabricating a
/// result — the same "defer the dependency until it's genuinely needed
/// rather than stub one in" choice `DetectionManager` already makes for
/// its own `NativeBridge` dependency.
class DefaultPermissionManager implements PermissionManager {
  DefaultPermissionManager({this.requiredPermissions = const {}});

  /// The permissions [initialize] requests. Fixed at construction.
  final Set<String> requiredPermissions;

  final Set<String> _granted = {};

  @override
  Future<void> initialize() => requestPermissions(requiredPermissions);

  @override
  Future<void> dispose() async {
    _granted.clear();
  }

  @override
  Future<void> requestPermissions(Set<String> permissions) async {
    if (permissions.isEmpty) return;
    throw UnimplementedError(
      'DefaultPermissionManager cannot request real OS permissions yet — '
      'no native permission channel exists until a detector or protection '
      'requiring one is implemented (see ARCHITECTURE_CONTRACTS.md Group C).',
    );
  }

  @override
  bool isGranted(String permission) => _granted.contains(permission);

  @override
  Set<String> get grantedPermissions => Set.unmodifiable(_granted);
}
