/// Ordinal severity for a [SecurityEvent] — ascending, matching the SRS's
/// frozen ordering (debug < info < warning < high < critical) exactly.
/// Compare via `.index` (lower is less severe); no operator overloads
/// added, to keep this a plain, dependency-free enum.
enum EventSeverity { debug, info, warning, high, critical }

/// Shared model — one event broadcast through `EventManager`.
///
/// Immutable value object. `type` is deliberately a [String], matching
/// `DetectionResult.type` and `Detector.type`'s open-identifier design —
/// system-level events (`initialized`, `stopped`, `error`) and any future
/// detector/protection-specific event fit the same field without a closed
/// enum needing a framework change to add one.
///
/// No `matches(filter)` method is defined here — Phase 2 already expressed
/// event filtering as the `SecurityEventFilter` predicate typedef
/// (`bool Function(SecurityEvent)`) on `EventManager`; a class-level
/// `matches` method would duplicate, not extend, that frozen decision.
///
/// Equality / serialization: same approach and trade-offs as
/// `DetectionResult` — `data` compares by reference, not deep content.
class SecurityEvent {
  final String type;
  final DateTime timestamp;
  final Map<String, dynamic> data;
  final EventSeverity severity;
  final String? source;

  const SecurityEvent({
    required this.type,
    required this.timestamp,
    required this.severity,
    this.data = const {},
    this.source,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'timestamp': timestamp.toIso8601String(),
        'data': data,
        'severity': severity.name,
        'source': source,
      };

  factory SecurityEvent.fromJson(Map<String, dynamic> json) {
    return SecurityEvent(
      type: json['type'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      severity: EventSeverity.values.byName(json['severity'] as String),
      data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      source: json['source'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecurityEvent &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          timestamp == other.timestamp &&
          data == other.data &&
          severity == other.severity &&
          source == other.source;

  @override
  int get hashCode => Object.hash(type, timestamp, data, severity, source);

  @override
  String toString() =>
      'SecurityEvent(type: $type, severity: $severity, source: $source)';
}
