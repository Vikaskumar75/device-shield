import 'package:device_shield/src/models/device_shield_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceShieldConfig — screenshot/screen-recording fields', () {
    test('default to the least-invasive option', () {
      const config = DeviceShieldConfig();
      expect(config.enableScreenshotDetection, isFalse);
      expect(config.enableScreenRecordingDetection, isFalse);
      expect(config.enableScreenshotProtection, isFalse);
      expect(config.enableAppSwitcherProtection, isFalse);
      expect(config.screenshotRecordingRiskScoreWeight, 1.0);
      expect(config.allowRecordingDetectionInDebug, isTrue);
    });

    test('copyWith overrides only the requested field, per field', () {
      const base = DeviceShieldConfig();

      expect(
        base
            .copyWith(enableScreenshotDetection: true)
            .enableScreenshotDetection,
        isTrue,
      );
      expect(
        base
            .copyWith(enableScreenRecordingDetection: true)
            .enableScreenRecordingDetection,
        isTrue,
      );
      expect(
        base
            .copyWith(enableScreenshotProtection: true)
            .enableScreenshotProtection,
        isTrue,
      );
      expect(
        base
            .copyWith(enableAppSwitcherProtection: true)
            .enableAppSwitcherProtection,
        isTrue,
      );
      expect(
        base
            .copyWith(screenshotRecordingRiskScoreWeight: 0.5)
            .screenshotRecordingRiskScoreWeight,
        0.5,
      );
      expect(
        base
            .copyWith(allowRecordingDetectionInDebug: false)
            .allowRecordingDetectionInDebug,
        isFalse,
      );
    });

    test('copyWith leaves every other field untouched', () {
      const base = DeviceShieldConfig(periodicCheckInterval: 10000);

      final updated = base.copyWith(enableScreenshotProtection: true);

      expect(updated.periodicCheckInterval, 10000);
      expect(updated.debugLogging, base.debugLogging);
      expect(updated.enableScreenshotDetection, base.enableScreenshotDetection);
      expect(
        updated.enableScreenRecordingDetection,
        base.enableScreenRecordingDetection,
      );
      expect(
        updated.screenshotRecordingRiskScoreWeight,
        base.screenshotRecordingRiskScoreWeight,
      );
      expect(
        updated.allowRecordingDetectionInDebug,
        base.allowRecordingDetectionInDebug,
      );
    });

    test('toJson/fromJson round-trips every new field', () {
      const config = DeviceShieldConfig(
        enableScreenshotDetection: true,
        enableScreenRecordingDetection: true,
        enableScreenshotProtection: true,
        enableAppSwitcherProtection: true,
        screenshotRecordingRiskScoreWeight: 0.75,
        allowRecordingDetectionInDebug: false,
      );

      final restored = DeviceShieldConfig.fromJson(config.toJson());

      expect(restored, config);
      expect(restored.enableScreenshotDetection, isTrue);
      expect(restored.enableScreenRecordingDetection, isTrue);
      expect(restored.enableScreenshotProtection, isTrue);
      expect(restored.enableAppSwitcherProtection, isTrue);
      expect(restored.screenshotRecordingRiskScoreWeight, 0.75);
      expect(restored.allowRecordingDetectionInDebug, isFalse);
    });

    test('fromJson falls back to defaults when the new keys are absent — '
        'backward compatible with configs persisted before this feature '
        'existed', () {
      const legacyJson = {
        'debugLogging': true,
        'runOnUIThread': false,
        'periodicCheckInterval': 30000,
        'maxRetryAttempts': 3,
        'retryDelay': 1000,
        'checkTimeout': 5000,
      };

      final restored = DeviceShieldConfig.fromJson(legacyJson);

      expect(restored.enableScreenshotDetection, isFalse);
      expect(restored.enableScreenRecordingDetection, isFalse);
      expect(restored.enableScreenshotProtection, isFalse);
      expect(restored.enableAppSwitcherProtection, isFalse);
      expect(restored.screenshotRecordingRiskScoreWeight, 1.0);
      expect(restored.allowRecordingDetectionInDebug, isTrue);
    });

    test('fromJson accepts an int for screenshotRecordingRiskScoreWeight '
        '(JSON numbers without a decimal point decode as int, not double)', () {
      final restored = DeviceShieldConfig.fromJson(const {
        'screenshotRecordingRiskScoreWeight': 1,
      });
      expect(restored.screenshotRecordingRiskScoreWeight, 1.0);
    });

    test('equality and hashCode account for every new field', () {
      const a = DeviceShieldConfig(enableScreenshotDetection: true);
      const b = DeviceShieldConfig(enableScreenshotDetection: true);
      const c = DeviceShieldConfig();

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('two configs differing only in screenshotRecordingRiskScoreWeight '
        'are not equal', () {
      const a = DeviceShieldConfig(screenshotRecordingRiskScoreWeight: 0.5);
      const b = DeviceShieldConfig(screenshotRecordingRiskScoreWeight: 0.6);

      expect(a, isNot(b));
    });
  });
}
