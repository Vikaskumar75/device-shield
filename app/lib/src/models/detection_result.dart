/// Shared model — the result of one `Detector.check` invocation.
///
/// Immutable value object. `type` is deliberately a [String], matching
/// `Detector.type`'s open-identifier design (registry/detector.dart) — not
/// a closed enum, so a custom detector never requires a framework change to
/// report a result.
///
/// Equality: value equality across every field. `evidence` compares by
/// reference, not deep content — deep map equality would require the
/// `collection` package, intentionally not added as a dependency at this
/// stage. Two results built from equivalent-but-distinct evidence maps will
/// not be `==`; documented trade-off, not an oversight.
///
/// Serialization: hand-written [toJson]/[fromJson], no code-gen dependency.
class DetectionResult {
  final String type;
  final bool detected;
  final double confidence;
  final DateTime timestamp;
  final Map<String, dynamic> evidence;
  final DetectionStatus status;

  const DetectionResult({
    required this.type,
    required this.detected,
    required this.confidence,
    required this.timestamp,
    this.evidence = const {},
    this.status = DetectionStatus.completed,
  });

  /// Confidence weighted by whether anything was actually detected — a
  /// clean miss always scores 0.0 regardless of confidence.
  double get riskScore => confidence * (detected ? 1.0 : 0.0);

  /// Commonly-used threshold check: detected with high confidence.
  bool get isCritical => detected && confidence > 0.8;

  Map<String, dynamic> toJson() => {
    'type': type,
    'detected': detected,
    'confidence': confidence,
    'timestamp': timestamp.toIso8601String(),
    'evidence': evidence,
    'status': status.name,
  };

  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    return DetectionResult(
      type: json['type'] as String,
      detected: json['detected'] as bool,
      confidence: (json['confidence'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      evidence: (json['evidence'] as Map?)?.cast<String, dynamic>() ?? const {},
      status: DetectionStatus.values.byName(json['status'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DetectionResult &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          detected == other.detected &&
          confidence == other.confidence &&
          timestamp == other.timestamp &&
          evidence == other.evidence &&
          status == other.status;

  @override
  int get hashCode =>
      Object.hash(type, detected, confidence, timestamp, evidence, status);

  @override
  String toString() =>
      'DetectionResult(type: $type, detected: $detected, '
      'confidence: $confidence, status: $status)';
}

/// Whether a `Detector.check` call completed normally or failed.
///
/// A detector that hits an expected failure mode (native timeout,
/// permission denial) must return `failed` here rather than throw — see
/// `Detector`'s failure-behavior contract.
enum DetectionStatus { completed, failed }
