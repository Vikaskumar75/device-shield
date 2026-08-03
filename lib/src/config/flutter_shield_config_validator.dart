import '../models/flutter_shield_config.dart';
import '../models/flutter_shield_exception.dart';

/// Validates a [FlutterShieldConfig] before it ever reaches
/// [ConfigurationManager].
///
/// Architecture Correction 2: a dedicated, single-purpose component so
/// `ConfigurationManager` itself stays a pure store/expose/update service
/// with no validation rules of its own. The flow is:
///
/// `FlutterShield.initialize(config)` → `FlutterShieldConfigValidator`
/// → `ConfigurationManager` (store).
///
/// Bounds match SRS §7.4 exactly — generic SDK-wide settings only, no
/// detector-specific validation of any kind.
///
/// Public/Internal: internal.
class FlutterShieldConfigValidator {
  /// Returns [config] unchanged if every bound is satisfied. Throws
  /// [ConfigurationException] on the first violated bound.
  FlutterShieldConfig validate(FlutterShieldConfig config) {
    if (config.periodicCheckInterval < 5000) {
      throw const ConfigurationException(
        code: 'INVALID_INTERVAL',
        message: 'periodicCheckInterval must be at least 5000ms',
      );
    }
    if (config.maxRetryAttempts < 0 || config.maxRetryAttempts > 10) {
      throw const ConfigurationException(
        code: 'INVALID_RETRY',
        message: 'maxRetryAttempts must be between 0 and 10',
      );
    }
    if (config.retryDelay < 500 || config.retryDelay > 10000) {
      throw const ConfigurationException(
        code: 'INVALID_RETRY_DELAY',
        message: 'retryDelay must be between 500ms and 10000ms',
      );
    }
    if (config.checkTimeout < 1000 || config.checkTimeout > 30000) {
      throw const ConfigurationException(
        code: 'INVALID_TIMEOUT',
        message: 'checkTimeout must be between 1000ms and 30000ms',
      );
    }
    return config;
  }
}
