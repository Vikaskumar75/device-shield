import 'package:flutter_shield/src/models/flutter_shield_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlutterShieldConfig — screenshot/screen-recording fields', () {
    test('default to the least-invasive option', () {
      const config = FlutterShieldConfig();
      expect(config.enableScreenshotDetection, isFalse);
      expect(config.enableScreenRecordingDetection, isFalse);
      expect(config.enableScreenshotProtection, isFalse);
      expect(config.enableAppSwitcherProtection, isFalse);
      expect(config.screenshotRecordingRiskScoreWeight, 1.0);
      expect(config.allowRecordingDetectionInDebug, isTrue);
    });

    test('copyWith overrides only the requested field, per field', () {
      const base = FlutterShieldConfig();

      expect(
        base.copyWith(enableScreenshotDetection: true).enableScreenshotDetection,
        isTrue,
      );
      expect(
        base
            .copyWith(enableScreenRecordingDetection: true)
            .enableScreenRecordingDetection,
        isTrue,
      );
      expect(
        base.copyWith(enableScreenshotProtection: true).enableScreenshotProtection,
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
      const base = FlutterShieldConfig(periodicCheckInterval: 10000);

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
      const config = FlutterShieldConfig(
        enableScreenshotDetection: true,
        enableScreenRecordingDetection: true,
        enableScreenshotProtection: true,
        enableAppSwitcherProtection: true,
        screenshotRecordingRiskScoreWeight: 0.75,
        allowRecordingDetectionInDebug: false,
      );

      final restored = FlutterShieldConfig.fromJson(config.toJson());

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

      final restored = FlutterShieldConfig.fromJson(legacyJson);

      expect(restored.enableScreenshotDetection, isFalse);
      expect(restored.enableScreenRecordingDetection, isFalse);
      expect(restored.enableScreenshotProtection, isFalse);
      expect(restored.enableAppSwitcherProtection, isFalse);
      expect(restored.screenshotRecordingRiskScoreWeight, 1.0);
      expect(restored.allowRecordingDetectionInDebug, isTrue);
    });

    test('fromJson accepts an int for screenshotRecordingRiskScoreWeight '
        '(JSON numbers without a decimal point decode as int, not double)',
        () {
      final restored = FlutterShieldConfig.fromJson(
        const {'screenshotRecordingRiskScoreWeight': 1},
      );
      expect(restored.screenshotRecordingRiskScoreWeight, 1.0);
    });

    test('equality and hashCode account for every new field', () {
      const a = FlutterShieldConfig(enableScreenshotDetection: true);
      const b = FlutterShieldConfig(enableScreenshotDetection: true);
      const c = FlutterShieldConfig(enableScreenshotDetection: false);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('two configs differing only in screenshotRecordingRiskScoreWeight '
        'are not equal', () {
      const a = FlutterShieldConfig(screenshotRecordingRiskScoreWeight: 0.5);
      const b = FlutterShieldConfig(screenshotRecordingRiskScoreWeight: 0.6);

      expect(a, isNot(b));
    });
  });
}
