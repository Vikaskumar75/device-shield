/// Single source of truth for `NativeBridge` method-name constants —
/// ROADMAP.md's M3 exit criterion, called out explicitly as mattering
/// "once 15+ detectors share the channel": every method name below is a
/// constant referenced by exactly one Dart-side caller and one native-side
/// handler, never a raw string literal duplicated in both places.
///
/// Generic bridge transport only — this file knows nothing about what any
/// method *does*, only what it's *called*. Detector-specific business
/// logic lives in each detector's own class, never here.
class MethodCodes {
  const MethodCodes._();

  /// FR-03 (SRS §5.3): emulator/simulator detection.
  static const String checkEmulator = 'checkEmulator';

  /// FR-04 (SRS §5.4): debugger detection.
  static const String checkDebugger = 'checkDebugger';
}
