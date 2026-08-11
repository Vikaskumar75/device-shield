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

  /// Screenshot/Screen Recording Protection — Dart→native command.
  /// `{'enabled': bool}` argument; returns `{'applied': bool}`. Android:
  /// sets/clears `FLAG_SECURE`. iOS: re-parents the Flutter root view's
  /// layer under a `UITextField.isSecureTextEntry` field's secure
  /// rendering layer — **not** a supported Apple API, an undocumented-
  /// internals technique accepted with that risk explicit (see
  /// `ScreenCaptureProtection.swift`'s own top-of-file warning). See
  /// `docs/features/SCREENSHOT_SCREEN_RECORDING_PROTECTION.md` §9.4/§7/§18.5.
  static const String setScreenshotProtection = 'setScreenshotProtection';

  /// Screenshot/Screen Recording Protection — Dart→native poll. No
  /// arguments; returns `{'isCaptured': bool}` on iOS, or an explicit
  /// unsupported marker on Android (§7.1: no reliable discrete Android
  /// signal exists). See
  /// `docs/features/SCREENSHOT_SCREEN_RECORDING_PROTECTION.md` §9.4/§7.
  static const String isScreenCaptureActive = 'isScreenCaptureActive';

  /// App-switcher/background-snapshot redaction — Dart→native command.
  /// `{'enabled': bool}` argument; returns `{'applied': bool}`. Android:
  /// delegates to the same `FLAG_SECURE` toggle as [setScreenshotProtection]
  /// — it is genuinely the same native mechanism there, not a separate one.
  /// iOS: a real, independent mechanism — a blur overlay shown immediately
  /// before the OS captures the app-switcher snapshot, removed when the app
  /// becomes active again. See
  /// `docs/features/SCREENSHOT_SCREEN_RECORDING_PROTECTION.md` §17.
  static const String setAppSwitcherProtection = 'setAppSwitcherProtection';
}
