import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_shield_platform_interface.dart';

/// An implementation of [DeviceShieldPlatform] that uses method channels.
class MethodChannelDeviceShield extends DeviceShieldPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('device_shield');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
