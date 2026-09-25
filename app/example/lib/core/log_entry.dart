/// Severity of an [AppLogEntry] — deliberately separate from the SDK's own
/// `EventSeverity`, since this log captures the *example app's* actions
/// (see `AppLogEntry`'s own doc comment for why the SDK's real internal
/// logger cannot be captured here).
enum AppLogLevel { debug, info, warning, error }

/// One entry in the example app's own action log.
///
/// IMPORTANT, documented SDK limitation (see MANUAL_TEST_PLAN.md and the
/// About screen): `FlutterShield` never exposes the SDK's internal
/// `Logger`/`LogSink` extension point publicly — there is no supported way
/// for a host app to intercept the SDK's own `ConsoleLogger` output (it
/// only ever reaches the system console via `print`). This log therefore
/// records what the *example app* does — every SDK call it makes, and the
/// result — not the SDK's own internal debug trace. This is the most
/// faithful "SDK logging" surface actually reachable from host-app code
/// today.
class AppLogEntry {
  AppLogEntry({
    required this.level,
    required this.tag,
    required this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final AppLogLevel level;
  final String tag;
  final String message;
  final DateTime timestamp;

  String get formatted =>
      '[${timestamp.toIso8601String()}] ${level.name.toUpperCase()} '
      '($tag): $message';
}
