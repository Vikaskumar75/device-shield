import 'package:flutter_shield/src/config/default_configuration_manager.dart';
import 'package:flutter_shield/src/config/flutter_shield_config_validator.dart';
import 'package:flutter_shield/src/models/flutter_shield_config.dart';
import 'package:flutter_shield/src/models/flutter_shield_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlutterShieldConfigValidator', () {
    final validator = FlutterShieldConfigValidator();

    test('returns the config unchanged when every bound is satisfied', () {
      const config = FlutterShieldConfig();
      expect(validator.validate(config), same(config));
    });

    test('rejects periodicCheckInterval below 5000ms', () {
      expect(
        () => validator.validate(
            const FlutterShieldConfig(periodicCheckInterval: 100)),
        throwsA(isA<ConfigurationException>()
            .having((e) => e.code, 'code', 'INVALID_INTERVAL')),
      );
    });

    test('rejects maxRetryAttempts outside 0-10', () {
      expect(
        () => validator
            .validate(const FlutterShieldConfig(maxRetryAttempts: 11)),
        throwsA(isA<ConfigurationException>()
            .having((e) => e.code, 'code', 'INVALID_RETRY')),
      );
    });

    test('rejects retryDelay outside 500-10000ms', () {
      expect(
        () => validator.validate(const FlutterShieldConfig(retryDelay: 100)),
        throwsA(isA<ConfigurationException>()
            .having((e) => e.code, 'code', 'INVALID_RETRY_DELAY')),
      );
    });

    test('rejects checkTimeout outside 1000-30000ms', () {
      expect(
        () =>
            validator.validate(const FlutterShieldConfig(checkTimeout: 500)),
        throwsA(isA<ConfigurationException>()
            .having((e) => e.code, 'code', 'INVALID_TIMEOUT')),
      );
    });
  });

  group('Architecture Correction 2 — ConfigurationManager no longer validates', () {
    test('DefaultConfigurationManager accepts an out-of-bounds config '
        'without throwing — validation is not its job', () {
      const outOfBounds = FlutterShieldConfig(periodicCheckInterval: 1);

      expect(() => DefaultConfigurationManager(outOfBounds),
          returnsNormally);
      final manager = DefaultConfigurationManager(outOfBounds);
      expect(manager.current.periodicCheckInterval, 1);
    });

    test('updateConfig accepts an out-of-bounds config without throwing',
        () async {
      final manager = DefaultConfigurationManager(const FlutterShieldConfig());

      await manager.updateConfig(
          const FlutterShieldConfig(periodicCheckInterval: 1));

      expect(manager.current.periodicCheckInterval, 1);
    });
  });
}
