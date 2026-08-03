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
class FlutterShieldConfig {
  final bool debugLogging;
  final bool runOnUIThread;
  final int periodicCheckInterval;
  final int maxRetryAttempts;
  final int retryDelay;
  final int checkTimeout;

  const FlutterShieldConfig({
    this.debugLogging = false,
    this.runOnUIThread = false,
    this.periodicCheckInterval = 30000,
    this.maxRetryAttempts = 3,
    this.retryDelay = 1000,
    this.checkTimeout = 5000,
  });

  FlutterShieldConfig copyWith({
    bool? debugLogging,
    bool? runOnUIThread,
    int? periodicCheckInterval,
    int? maxRetryAttempts,
    int? retryDelay,
    int? checkTimeout,
  }) {
    return FlutterShieldConfig(
      debugLogging: debugLogging ?? this.debugLogging,
      runOnUIThread: runOnUIThread ?? this.runOnUIThread,
      periodicCheckInterval:
          periodicCheckInterval ?? this.periodicCheckInterval,
      maxRetryAttempts: maxRetryAttempts ?? this.maxRetryAttempts,
      retryDelay: retryDelay ?? this.retryDelay,
      checkTimeout: checkTimeout ?? this.checkTimeout,
    );
  }

  Map<String, dynamic> toJson() => {
        'debugLogging': debugLogging,
        'runOnUIThread': runOnUIThread,
        'periodicCheckInterval': periodicCheckInterval,
        'maxRetryAttempts': maxRetryAttempts,
        'retryDelay': retryDelay,
        'checkTimeout': checkTimeout,
      };

  factory FlutterShieldConfig.fromJson(Map<String, dynamic> json) {
    return FlutterShieldConfig(
      debugLogging: json['debugLogging'] as bool? ?? false,
      runOnUIThread: json['runOnUIThread'] as bool? ?? false,
      periodicCheckInterval: json['periodicCheckInterval'] as int? ?? 30000,
      maxRetryAttempts: json['maxRetryAttempts'] as int? ?? 3,
      retryDelay: json['retryDelay'] as int? ?? 1000,
      checkTimeout: json['checkTimeout'] as int? ?? 5000,
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
          checkTimeout == other.checkTimeout;

  @override
  int get hashCode => Object.hash(debugLogging, runOnUIThread,
      periodicCheckInterval, maxRetryAttempts, retryDelay, checkTimeout);

  @override
  String toString() => 'FlutterShieldConfig(periodicCheckInterval: '
      '$periodicCheckInterval, maxRetryAttempts: $maxRetryAttempts)';
}
