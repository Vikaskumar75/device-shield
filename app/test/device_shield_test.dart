import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_shield/flutter_shield.dart';
import 'package:flutter_shield/src/platform/flutter_shield_platform_interface.dart';
import 'package:flutter_shield/src/platform/flutter_shield_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterShieldPlatform
    with MockPlatformInterfaceMixin
    implements FlutterShieldPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterShieldPlatform initialPlatform = FlutterShieldPlatform.instance;

  test('$MethodChannelFlutterShield is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterShield>());
  });

  test('getPlatformVersion', () async {
    FlutterShield flutterShieldPlugin = FlutterShield();
    MockFlutterShieldPlatform fakePlatform = MockFlutterShieldPlatform();
    FlutterShieldPlatform.instance = fakePlatform;

    expect(await flutterShieldPlugin.getPlatformVersion(), '42');
  });
}
