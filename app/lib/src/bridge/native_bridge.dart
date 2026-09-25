/// The sole path any Dart code takes to reach native code.
///
/// No detector, protection, or manager is permitted to hold a
/// `MethodChannel`/`EventChannel` reference of its own — everything routes
/// through this contract. See ARCHITECTURE_CONTRACTS.md Group F.
///
/// Public/Internal: internal.
///
/// Extension point: yes — `NativeBridge` itself, swapped via
/// `ServiceContainer` (Phase 4's DI pattern). This superseded
/// `PlatformAdapter` as the "new platform" extension point per the
/// Phase 7 post-review correction — see ARCHITECTURE.md/
/// ARCHITECTURE_CONTRACTS.md.
abstract class NativeBridge {
  /// Sends [method] to native code and awaits a typed response.
  ///
  /// Throws a bridge-specific exception (`NativeBridgeException`, defined
  /// in Phase 3) if native code is unreachable or the call exceeds
  /// [timeout]. `RecoveryStrategy` reinitializes the bridge and retries
  /// within a bounded attempt count on failure.
  Future<T> invoke<T>({
    required String method,
    Map<String, dynamic>? arguments,
    Duration timeout = const Duration(seconds: 5),
  });

  /// Sends [method] to native code without awaiting a response.
  void invokeAsync({
    required String method,
    Map<String, dynamic>? arguments,
  });

  /// Registers a handler for a native-originated callback identified by
  /// [name].
  void registerCallback(String name, void Function(dynamic data) callback);

  /// Removes a previously registered callback.
  void unregisterCallback(String name);

  /// Closes both channel services and clears every registered callback.
  ///
  /// Added per the approved architecture correction resolving the
  /// contradiction between this contract (previously no `dispose`) and
  /// ARCHITECTURE_CONTRACTS.md Part 3's shutdown-order table, which
  /// requires `NativeBridge` to be disposed at step 5. A disposed
  /// `NativeBridge` must never be reused — `PluginInitializer.shutdown()`
  /// unregisters it from `ServiceContainer` immediately after calling
  /// this, so `reinitialize()` always resolves a fresh instance.
  Future<void> dispose();
}
