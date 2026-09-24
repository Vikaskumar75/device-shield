/// Shared model — SDK-wide configuration (SRS §7.1, generic fields only).
///
/// Deliberately does NOT include detection/protection sub-configs (e.g. a
/// `detectionConfig`/`protectionConfig` pair aggregating per-detector
/// settings) — every such sub-config is inherently detector/protection-
/// specific (root, jailbreak, SSL pinning, ...), out of scope for every
/// phase up to and including this one. Those fields are added additively
/// once detector/protection work begins; this model already existing and
/// being in use makes that a non-breaking extension, not a rework.
///
/// Also deliberately has no `validate()` method — validation is
/// `ConfigurationManager`'s behavior (a manager concern, §7.4), not the
/// model's; keeping it here would mix data shape with business logic.
///
/// Serialization: [toJson]/[fromJson] — backs `ConfigurationPersistence`
/// (SharedPreferences-based save/load, §7.6, a later phase).
///
/// [enableScreenshotDetection], [enableScreenRecordingDetection],
/// [enableScreenshotProtection], [screenshotRecordingRiskScoreWeight], and
/// [allowRecordingDetectionInDebug] are exactly the fields this class's own
/// doc comment above predicted — the first detector/protection-adjacent
/// fields added since that prediction was written. See
/// `docs/features/SCREENSHOT_SCREEN_RECORDING_PROTECTION.md` §4 for the
/// full design and §4.4 for why these live here rather than on
/// `SecurityProfile`/`ProtectionConfig` (not yet threaded through
/// `initialize()`). All five default to the least-invasive option, matching
/// every existing field's own default philosophy — no existing detector is
/// auto-registered at boot without the host app opting in either.
class FlutterShieldConfig {
  final bool debugLogging;
  final bool runOnUIThread;
  final int periodicCheckInterval;
  final int maxRetryAttempts;
  final int retryDelay;
  final int checkTimeout;

  /// Whether `ScreenshotDetector`'s native push listener is registered at
  /// boot. Off by default — see design doc §4.2.
  final bool enableScreenshotDetection;

  /// Whether `ScreenRecordingDetector` (poll + push) is registered at boot.
  /// Accepted on Android too, but the resulting detector always reports
  /// "unsupported on this platform" there rather than silently doing
  /// nothing — see design doc §7.1. Off by default.
  final bool enableScreenRecordingDetection;

  /// Whether `FLAG_SECURE` (Android only) is applied automatically,
  /// SDK-wide, at boot. Deliberately off by default — see design doc §4.1:
  /// forcing every screen to block screenshots by default would be a
  /// surprising, breaking, opinionated default inconsistent with every
  /// other field above. Most host apps will instead call
  /// `FlutterShield.enableScreenshotProtection()` imperatively for one
  /// specific sensitive screen.
  final bool enableScreenshotProtection;

  /// Whether app-switcher/background-snapshot redaction is applied
  /// automatically at boot. Android: redundant with
  /// [enableScreenshotProtection] — `FLAG_SECURE` already redacts the
  /// Recents thumbnail as a side effect, so this flag simply also toggles
  /// the same native flag there. iOS: the one genuinely new mechanism this
  /// flag controls — a blur overlay covers the window immediately before
  /// the OS captures the app-switcher snapshot, and is removed when the
  /// app becomes active again. Off by default, matching every other
  /// protection flag's own least-invasive default.
  final bool enableAppSwitcherProtection;

  /// Weight applied to `DetectionResult.confidence` for events from this
  /// feature, so `PolicyManager.calculateRiskScore()` weighs them
  /// consistently with other detectors — see design doc §4.1. Clamped to
  /// 0.0–1.0, matching the confidence/risk-score convention already used
  /// everywhere else in this codebase (`DetectionResult.confidence`,
  /// `PolicyManager.calculateRiskScore()`).
  final double screenshotRecordingRiskScoreWeight;

  /// Whether recording-state events fire during a debug build. On by
  /// default — matches every other detector's behavior today, none of
  /// which special-case debug builds; see design doc §4.1.
  final bool allowRecordingDetectionInDebug;

  const FlutterShieldConfig({
    this.debugLogging = false,
    this.runOnUIThread = false,
    this.periodicCheckInterval = 30000,
    this.maxRetryAttempts = 3,
    this.retryDelay = 1000,
    this.checkTimeout = 5000,
    this.enableScreenshotDetection = false,
    this.enableScreenRecordingDetection = false,
    this.enableScreenshotProtection = false,
    this.enableAppSwitcherProtection = false,
    this.screenshotRecordingRiskScoreWeight = 1.0,
    this.allowRecordingDetectionInDebug = true,
  });

  FlutterShieldConfig copyWith({
    bool? debugLogging,
    bool? runOnUIThread,
    int? periodicCheckInterval,
    int? maxRetryAttempts,
    int? retryDelay,
    int? checkTimeout,
    bool? enableScreenshotDetection,
    bool? enableScreenRecordingDetection,
    bool? enableScreenshotProtection,
    bool? enableAppSwitcherProtection,
    double? screenshotRecordingRiskScoreWeight,
    bool? allowRecordingDetectionInDebug,
  }) {
    return FlutterShieldConfig(
      debugLogging: debugLogging ?? this.debugLogging,
      runOnUIThread: runOnUIThread ?? this.runOnUIThread,
      periodicCheckInterval:
          periodicCheckInterval ?? this.periodicCheckInterval,
      maxRetryAttempts: maxRetryAttempts ?? this.maxRetryAttempts,
      retryDelay: retryDelay ?? this.retryDelay,
      checkTimeout: checkTimeout ?? this.checkTimeout,
      enableScreenshotDetection:
          enableScreenshotDetection ?? this.enableScreenshotDetection,
      enableScreenRecordingDetection: enableScreenRecordingDetection ??
          this.enableScreenRecordingDetection,
      enableScreenshotProtection:
          enableScreenshotProtection ?? this.enableScreenshotProtection,
      enableAppSwitcherProtection:
          enableAppSwitcherProtection ?? this.enableAppSwitcherProtection,
      screenshotRecordingRiskScoreWeight: screenshotRecordingRiskScoreWeight ??
          this.screenshotRecordingRiskScoreWeight,
      allowRecordingDetectionInDebug: allowRecordingDetectionInDebug ??
          this.allowRecordingDetectionInDebug,
    );
  }

  Map<String, dynamic> toJson() => {
        'debugLogging': debugLogging,
        'runOnUIThread': runOnUIThread,
        'periodicCheckInterval': periodicCheckInterval,
        'maxRetryAttempts': maxRetryAttempts,
        'retryDelay': retryDelay,
        'checkTimeout': checkTimeout,
        'enableScreenshotDetection': enableScreenshotDetection,
        'enableScreenRecordingDetection': enableScreenRecordingDetection,
        'enableScreenshotProtection': enableScreenshotProtection,
        'enableAppSwitcherProtection': enableAppSwitcherProtection,
        'screenshotRecordingRiskScoreWeight':
            screenshotRecordingRiskScoreWeight,
        'allowRecordingDetectionInDebug': allowRecordingDetectionInDebug,
      };

  factory FlutterShieldConfig.fromJson(Map<String, dynamic> json) {
    return FlutterShieldConfig(
      debugLogging: json['debugLogging'] as bool? ?? false,
      runOnUIThread: json['runOnUIThread'] as bool? ?? false,
      periodicCheckInterval: json['periodicCheckInterval'] as int? ?? 30000,
      maxRetryAttempts: json['maxRetryAttempts'] as int? ?? 3,
      retryDelay: json['retryDelay'] as int? ?? 1000,
      checkTimeout: json['checkTimeout'] as int? ?? 5000,
      enableScreenshotDetection:
          json['enableScreenshotDetection'] as bool? ?? false,
      enableScreenRecordingDetection:
          json['enableScreenRecordingDetection'] as bool? ?? false,
      enableScreenshotProtection:
          json['enableScreenshotProtection'] as bool? ?? false,
      enableAppSwitcherProtection:
          json['enableAppSwitcherProtection'] as bool? ?? false,
      screenshotRecordingRiskScoreWeight:
          (json['screenshotRecordingRiskScoreWeight'] as num?)?.toDouble() ??
              1.0,
      allowRecordingDetectionInDebug:
          json['allowRecordingDetectionInDebug'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlutterShieldConfig &&
          runtimeType == other.runtimeType &&
          debugLogging == other.debugLogging &&
          runOnUIThread == other.runOnUIThread &&
          periodicCheckInterval == other.periodicCheckInterval &&
          maxRetryAttempts == other.maxRetryAttempts &&
          retryDelay == other.retryDelay &&
          checkTimeout == other.checkTimeout &&
          enableScreenshotDetection == other.enableScreenshotDetection &&
          enableScreenRecordingDetection ==
              other.enableScreenRecordingDetection &&
          enableScreenshotProtection == other.enableScreenshotProtection &&
          enableAppSwitcherProtection == other.enableAppSwitcherProtection &&
          screenshotRecordingRiskScoreWeight ==
              other.screenshotRecordingRiskScoreWeight &&
          allowRecordingDetectionInDebug ==
              other.allowRecordingDetectionInDebug;

  @override
  int get hashCode => Object.hash(
        debugLogging,
        runOnUIThread,
        periodicCheckInterval,
        maxRetryAttempts,
        retryDelay,
        checkTimeout,
        enableScreenshotDetection,
        enableScreenRecordingDetection,
        enableScreenshotProtection,
        enableAppSwitcherProtection,
        screenshotRecordingRiskScoreWeight,
        allowRecordingDetectionInDebug,
      );

  @override
  String toString() => 'FlutterShieldConfig(periodicCheckInterval: '
      '$periodicCheckInterval, maxRetryAttempts: $maxRetryAttempts)';
}
