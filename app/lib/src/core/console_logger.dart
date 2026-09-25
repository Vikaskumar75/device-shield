import 'logger.dart';

/// Real, complete implementation of [Logger] — console output gated by
/// level, plus [LogSink] fan-out. Pure I/O; no security, detection, or
/// policy logic of any kind.
///
/// This is deliberately not a placeholder: logging has no business-logic
/// content to defer to a later phase.
class ConsoleLogger implements Logger {
  ConsoleLogger({this.minLevel = LogLevel.info});

  /// Entries below this level are dropped. SRS §17.1: debug < info <
  /// warning < error < exception.
  LogLevel minLevel;

  final List<LogSink> _sinks = [];

  static const List<LogLevel> _order = [
    LogLevel.debug,
    LogLevel.info,
    LogLevel.warning,
    LogLevel.error,
    LogLevel.exception,
  ];

  bool _shouldLog(LogLevel level) =>
      _order.indexOf(level) >= _order.indexOf(minLevel);

  void _write(LogLevel level, String message, {Map<String, dynamic>? data}) {
    if (!_shouldLog(level)) return;
    final line =
        '[FlutterShield] [${level.name.toUpperCase()}] $message'
        '${data != null && data.isNotEmpty ? ' $data' : ''}';
    // ignore: avoid_print
    print(line);
    for (final sink in _sinks) {
      sink.write(level, message, data: data);
    }
  }

  @override
  void debug(String message, {Map<String, dynamic>? data}) =>
      _write(LogLevel.debug, message, data: data);

  @override
  void info(String message, {Map<String, dynamic>? data}) =>
      _write(LogLevel.info, message, data: data);

  @override
  void warning(String message, {Map<String, dynamic>? data, Object? error}) {
    _write(LogLevel.warning, message, data: {
      ...?data,
      if (error != null) 'error': error.toString(),
    });
  }

  @override
  void error(
    String message, {
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _write(LogLevel.error, message, data: {
      ...?data,
      if (error != null) 'error': error.toString(),
    });
  }

  @override
  void exception(String message, {Object? error, StackTrace? stackTrace}) {
    _write(LogLevel.exception, message,
        data: error != null ? {'error': error.toString()} : null);
    if (stackTrace != null) {
      // ignore: avoid_print
      print('[FlutterShield] [STACK] $stackTrace');
    }
  }

  @override
  void addSink(LogSink sink) => _sinks.add(sink);

  @override
  void removeSink(LogSink sink) => _sinks.remove(sink);
}
