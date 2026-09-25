import UIKit

/// Screenshot & Screen Recording Protection —
/// doc/features/SCREENSHOT_SCREEN_RECORDING_PROTECTION.md §7.2/§9.6.
///
/// Unlike Android (no reliable discrete recording signal exists there at
/// all — see `ScreenRecordingDetector.kt`), iOS has a real, official,
/// reliable signal: `UIScreen.main.isCaptured` (available since iOS 11.0,
/// well within this package's iOS 18.0 floor) is `true` whenever the
/// screen's contents are being captured by *any* mechanism iOS considers
/// "capture" — Control Center screen recording, AirPlay mirroring, an
/// external/CarPlay display, or a connected recording accessory. It
/// cannot distinguish which (design doc §1.6/§14.3) — that ambiguity is a
/// named, permanent platform limitation, not something this class
/// resolves.
///
/// Explicitly **not** ReplayKit — `RPScreenRecorder` is for recording an
/// app's *own* screen and broadcasting/sharing that recording, not for
/// detecting that some other process is capturing the screen. Some of
/// this repository's own planning docs (`SDK_MILESTONE_PLAN.md`,
/// `ROADMAP.md`) describe this as "ReplayKit monitoring" — imprecise; the
/// design doc's own §7.2 already corrects this, and this file implements
/// that correction.
enum ScreenRecordingDetector {
  /// `isCaptureActive` MethodCode's iOS response.
  static func check() -> [String: Any] {
    return evaluate(isCaptured: UIScreen.main.isCaptured)
  }

  /// Pure response-shaping logic, separated from the real `UIScreen.main
  /// .isCaptured` read above so it can be unit-tested with a synthetic
  /// input — mirrors `DebuggerDetector.evaluate(debuggerAttached:)`'s own
  /// split for the same reason.
  static func evaluate(isCaptured: Bool) -> [String: Any] {
    return ["isCaptured": isCaptured, "supported": true]
  }

  private static var observer: NSObjectProtocol?

  /// Begins observing capture-state changes. `capturedDidChangeNotification`
  /// itself carries no payload — just "the value changed" — so this reads
  /// `UIScreen.main.isCaptured` fresh each time it fires, then forwards
  /// that value to [onStateChanged]. A no-op if already observing.
  static func start(onStateChanged: @escaping (Bool) -> Void) {
    guard observer == nil else { return }
    observer = NotificationCenter.default.addObserver(
      forName: UIScreen.capturedDidChangeNotification,
      object: nil,
      queue: .main
    ) { _ in onStateChanged(UIScreen.main.isCaptured) }
  }

  /// Stops observing. Safe to call even if `start` was never called, or
  /// already stopped.
  static func stop() {
    guard let observer else { return }
    NotificationCenter.default.removeObserver(observer)
    self.observer = nil
  }
}
