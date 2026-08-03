/// Shared model — base of the SDK's exception hierarchy (SRS §8.1).
///
/// Not serialized — exceptions are surfaced to callers and logs, never
/// persisted or transmitted as data, so no toJson/fromJson is defined here
/// (a deliberate decision, not an oversight).
///
/// Equality: intentionally NOT value-equality — two exceptions are
/// distinct occurrences even if their fields match; default identity
/// equality is correct here and is left un-overridden.
///
/// Subtypes below are limited to the generic, non-detector-specific
/// categories already named in ARCHITECTURE_CONTRACTS.md's failure-behavior
/// column for `NativeBridge`, `ConfigurationManager`, and
/// `PermissionManager`. Detector-specific exception subtypes (e.g. a
/// `RootDetectionException`) are out of scope until that detector exists.
class FlutterShieldException implements Exception {
  final String code;
  final String message;
  final dynamic details;
  final StackTrace? stackTrace;

  const FlutterShieldException({
    required this.code,
    required this.message,
    this.details,
    this.stackTrace,
  });

  @override
  String toString() => 'FlutterShieldException($code): $message'
      '${details != null ? '\nDetails: $details' : ''}';
}

/// Thrown by `ConfigurationManager` when a replacement config fails
/// validation. The previous config is retained on this failure.
class ConfigurationException extends FlutterShieldException {
  const ConfigurationException({
    required super.code,
    required super.message,
    super.details,
    super.stackTrace,
  });
}

/// Thrown by `PermissionManager` when a required permission is denied.
class PermissionException extends FlutterShieldException {
  final List<String> missingPermissions;

  const PermissionException({
    required super.code,
    required super.message,
    required this.missingPermissions,
    super.details,
    super.stackTrace,
  });
}

/// Thrown when SDK boot fails for a reason not covered by a more specific
/// exception type below.
class InitializationException extends FlutterShieldException {
  const InitializationException({
    required super.code,
    required super.message,
    super.details,
    super.stackTrace,
  });
}

/// Thrown by `NativeBridge` when a native call is unreachable or exceeds
/// its timeout.
class NativeBridgeException extends FlutterShieldException {
  final String method;
  final dynamic nativeError;

  const NativeBridgeException({
    required this.method,
    required this.nativeError,
    required super.code,
    required super.message,
    super.details,
  });
}

/// Thrown by `PolicyManager` when action execution fails (e.g. no handler
/// registered for the resolved `SecurityAction`).
class PolicyException extends FlutterShieldException {
  const PolicyException({
    required super.code,
    required super.message,
    super.details,
    super.stackTrace,
  });
}

/// Thrown by a `Detector` implementation for an unrecoverable failure.
/// `type` mirrors `Detector.type`'s open identifier — never a closed enum.
class DetectionException extends FlutterShieldException {
  final String? type;

  const DetectionException({
    this.type,
    required super.code,
    required super.message,
    super.details,
    super.stackTrace,
  });
}
