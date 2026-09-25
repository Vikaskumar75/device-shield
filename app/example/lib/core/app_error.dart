/// One captured error surfaced to the user — every async SDK call in this
/// app is wrapped so nothing fails silently (see `ShieldController`).
class AppError {
  AppError({
    required this.operation,
    required this.error,
    required this.stackTrace,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String operation;
  final Object error;
  final StackTrace stackTrace;
  final DateTime timestamp;

  String get summary => '$operation failed: $error';
}
