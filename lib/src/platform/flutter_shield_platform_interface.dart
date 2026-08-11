import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_shield_method_channel.dart';

/// This class is `ARCHITECTURE_CONTRACTS.md`'s `PlatformAdapter` entry —
/// **legacy as of the Phase 7 post-review**. It no longer sits in
/// `NativeBridge`'s dependency chain: `MethodChannelService`/
/// `EventChannelService` construct their channels directly rather than
/// obtaining bindings through this class. Kept unchanged and still fully
/// functional — it continues to back the original `getPlatformVersion()`
/// call from Phase 1 exactly as before. The "new platform" extension
/// point is now `NativeBridge` itself, swapped via `ServiceContainer`; see
/// `ARCHITECTURE.md`'s dependency-graph correction note for the full
/// reasoning.
abstract class FlutterShieldPlatform extends PlatformInterface {
  /// Constructs a FlutterShieldPlatform.
  FlutterShieldPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterShieldPlatform _instance = MethodChannelFlutterShield();

  /// The default instance of [FlutterShieldPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterShield].
  static FlutterShieldPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterShieldPlatform] when
  /// they register themselves.
  static set instance(FlutterShieldPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
