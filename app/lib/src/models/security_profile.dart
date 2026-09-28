import 'security_action.dart';

/// Shared model — declarative per-app risk-posture configuration (SRS
/// FR-14, §6.2). Documented as a dependency of `PermissionManager`,
/// `DetectionManager`, and `PolicyManager` in ARCHITECTURE_CONTRACTS.md,
/// but not yet threaded through any frozen method signature —
/// `Manager.initialize()` is deliberately parameterless (Phase 2).
///
/// How this reaches a manager: constructor injection at build time (a
/// later Bootstrap phase), not via `initialize()` — this keeps Phase 2's
/// frozen signature intact rather than requiring it to change now.
///
/// [DetectionConfig]/[PolicyConfig]/[ProtectionConfig] are intentionally
/// generic and open-identifier-based (`type: String`) — never naming a
/// specific detector or protection. The SRS's own per-detector config
/// classes (e.g. `RootDetectionConfig`, `SslPinningConfig`) are out of
/// scope until the corresponding detector/protection is implemented.
class SecurityProfile {
  final String name;
  final String description;
  final List<DetectionConfig> detectionConfigs;
  final List<PolicyConfig> policyConfigs;
  final List<ProtectionConfig> protectionConfigs;

  const SecurityProfile({
    required this.name,
    required this.description,
    this.detectionConfigs = const [],
    this.policyConfigs = const [],
    this.protectionConfigs = const [],
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'detectionConfigs': detectionConfigs.map((e) => e.toJson()).toList(),
    'policyConfigs': policyConfigs.map((e) => e.toJson()).toList(),
    'protectionConfigs': protectionConfigs.map((e) => e.toJson()).toList(),
  };

  factory SecurityProfile.fromJson(Map<String, dynamic> json) {
    return SecurityProfile(
      name: json['name'] as String,
      description: json['description'] as String,
      detectionConfigs: (json['detectionConfigs'] as List? ?? [])
          .map(
            (e) => DetectionConfig.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList(),
      policyConfigs: (json['policyConfigs'] as List? ?? [])
          .map((e) => PolicyConfig.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      protectionConfigs: (json['protectionConfigs'] as List? ?? [])
          .map(
            (e) =>
                ProtectionConfig.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecurityProfile &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          description == other.description &&
          detectionConfigs == other.detectionConfigs &&
          policyConfigs == other.policyConfigs &&
          protectionConfigs == other.protectionConfigs;

  @override
  int get hashCode => Object.hash(
    name,
    description,
    detectionConfigs,
    policyConfigs,
    protectionConfigs,
  );

  @override
  String toString() => 'SecurityProfile(name: $name)';
}

/// Per-detector enablement/threshold — generic across every detector type.
class DetectionConfig {
  final String type;
  final bool enabled;
  final double confidenceThreshold;

  const DetectionConfig({
    required this.type,
    this.enabled = true,
    this.confidenceThreshold = 0.8,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'enabled': enabled,
    'confidenceThreshold': confidenceThreshold,
  };

  factory DetectionConfig.fromJson(Map<String, dynamic> json) =>
      DetectionConfig(
        type: json['type'] as String,
        enabled: json['enabled'] as bool? ?? true,
        confidenceThreshold:
            (json['confidenceThreshold'] as num?)?.toDouble() ?? 0.8,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DetectionConfig &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          enabled == other.enabled &&
          confidenceThreshold == other.confidenceThreshold;

  @override
  int get hashCode => Object.hash(type, enabled, confidenceThreshold);
}

/// Per-detection-type policy wiring — which [SecurityAction] applies above
/// which confidence `threshold`, at what `priority`.
class PolicyConfig {
  final String type;
  final SecurityAction action;
  final double threshold;
  final int priority;

  const PolicyConfig({
    required this.type,
    required this.action,
    this.threshold = 0.8,
    this.priority = 0,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'action': action.name,
    'threshold': threshold,
    'priority': priority,
  };

  factory PolicyConfig.fromJson(Map<String, dynamic> json) => PolicyConfig(
    type: json['type'] as String,
    action: SecurityAction.values.byName(json['action'] as String),
    threshold: (json['threshold'] as num?)?.toDouble() ?? 0.8,
    priority: json['priority'] as int? ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PolicyConfig &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          action == other.action &&
          threshold == other.threshold &&
          priority == other.priority;

  @override
  int get hashCode => Object.hash(type, action, threshold, priority);
}

/// Per-protection enablement — generic across every protection type.
class ProtectionConfig {
  final String type;
  final bool enabled;

  const ProtectionConfig({required this.type, this.enabled = true});

  Map<String, dynamic> toJson() => {'type': type, 'enabled': enabled};

  factory ProtectionConfig.fromJson(Map<String, dynamic> json) =>
      ProtectionConfig(
        type: json['type'] as String,
        enabled: json['enabled'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProtectionConfig &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          enabled == other.enabled;

  @override
  int get hashCode => Object.hash(type, enabled);
}
