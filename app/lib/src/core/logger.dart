/// Severity of a single log entry. Intrinsic to [Logger]'s own contract —
/// not a Phase 3 model, since it has no meaning outside logging.
enum LogLevel { debug, info, warning, error, exception }

/// A registrable log destination — the extension point named in
/// ARCHITECTURE_CONTRACTS.md ("Logger accepts an optional list of `LogSink`
/// implementations... so forwarding to a third-party service is a
/// registered sink, not a Logger code change").
abstract class LogSink {
  void write(LogLevel level, String message, {Map<String, dynamic>? data});
}

/// The SDK's only sanctioned output path.
///
/// See ARCHITECTURE_CONTRACTS.md Group C. Must never throw — a logging
/// failure is not permitted to crash boot or any other operation.
///
/// Public/Internal: internal.
///
/// Extension point: yes — [LogSink] registration.
abstract class Logger {
  void debug(String message, {Map<String, dynamic>? data});

  void info(String message, {Map<String, dynamic>? data});

  void warning(String message, {Map<String, dynamic>? data, Object? error});

  void error(
    String message, {
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  });

  void exception(String message, {Object? error, StackTrace? stackTrace});

  /// Registers [sink] to additionally receive every log entry from this
  /// point forward.
  void addSink(LogSink sink);

  /// Removes a previously registered sink.
  void removeSink(LogSink sink);
}
