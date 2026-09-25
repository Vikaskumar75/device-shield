import '../models/flutter_shield_config.dart';
import 'configuration_manager.dart';

/// Real, complete implementation of [ConfigurationManager].
///
/// Architecture Correction 2: this class performs no validation — it only
/// stores, exposes, and updates whatever [FlutterShieldConfig] it is given.
/// Validation is [FlutterShieldConfigValidator]'s responsibility, run
/// *before* a config ever reaches this class (see
/// `PluginInitializer`'s Configuration step). Passing an out-of-bounds
/// config directly to this class's constructor or [updateConfig] will not
/// throw — that's intentional; this class trusts its caller.
class DefaultConfigurationManager implements ConfigurationManager {
  DefaultConfigurationManager(FlutterShieldConfig initial)
      : _current = initial;

  FlutterShieldConfig _current;

  @override
  FlutterShieldConfig get current => _current;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> updateConfig(FlutterShieldConfig config) async {
    _current = config;
  }
}
