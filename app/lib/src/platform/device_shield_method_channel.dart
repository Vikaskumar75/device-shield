import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_shield_platform_interface.dart';

/// An implementation of [FlutterShieldPlatform] that uses method channels.
class MethodChannelFlutterShield extends FlutterShieldPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_shield');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
