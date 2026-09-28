import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'device_shield_method_channel.dart';

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
abstract class DeviceShieldPlatform extends PlatformInterface {
  /// Constructs a DeviceShieldPlatform.
  DeviceShieldPlatform() : super(token: _token);

  static final Object _token = Object();

  static DeviceShieldPlatform _instance = MethodChannelDeviceShield();

  /// The default instance of [DeviceShieldPlatform] to use.
  ///
  /// Defaults to [MethodChannelDeviceShield].
  static DeviceShieldPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [DeviceShieldPlatform] when
  /// they register themselves.
  static set instance(DeviceShieldPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
