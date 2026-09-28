import '../models/device_shield_config.dart';
import 'configuration_manager.dart';

/// Real, complete implementation of [ConfigurationManager].
///
/// Architecture Correction 2: this class performs no validation — it only
/// stores, exposes, and updates whatever [DeviceShieldConfig] it is given.
/// Validation is [DeviceShieldConfigValidator]'s responsibility, run
/// *before* a config ever reaches this class (see
/// `PluginInitializer`'s Configuration step). Passing an out-of-bounds
/// config directly to this class's constructor or [updateConfig] will not
/// throw — that's intentional; this class trusts its caller.
class DefaultConfigurationManager implements ConfigurationManager {
  DefaultConfigurationManager(DeviceShieldConfig initial) : _current = initial;

  DeviceShieldConfig _current;

  @override
  DeviceShieldConfig get current => _current;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> updateConfig(DeviceShieldConfig config) async {
    _current = config;
  }
}
