import 'package:device_shield/device_shield.dart';
import 'package:device_shield/src/platform/device_shield_method_channel.dart';
import 'package:device_shield/src/platform/device_shield_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDeviceShieldPlatform
    with MockPlatformInterfaceMixin
    implements DeviceShieldPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final DeviceShieldPlatform initialPlatform = DeviceShieldPlatform.instance;

  test('$MethodChannelDeviceShield is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelDeviceShield>());
  });

  test('getPlatformVersion', () async {
    final DeviceShield deviceShieldPlugin = DeviceShield();
    final MockDeviceShieldPlatform fakePlatform = MockDeviceShieldPlatform();
    DeviceShieldPlatform.instance = fakePlatform;

    expect(await deviceShieldPlugin.getPlatformVersion(), '42');
  });
}
