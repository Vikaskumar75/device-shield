import UIKit

/// Screenshot & Screen Recording Protection —
/// doc/features/SCREENSHOT_SCREEN_RECORDING_PROTECTION.md §7.2/§9.6.
///
/// Push-only: unlike `EmulatorDetector`/`DebuggerDetector`, there is no
/// meaningful request/response "check" for this — a screenshot is a
/// discrete past event, not a stable state to poll. No MethodCode exists
/// for one (confirmed absent from Step 4's `method_codes.dart`), matching
/// `ScreenshotDetector.kt`'s own Android-side reasoning exactly.
///
/// `UIApplication.userDidTakeScreenshotNotification` fires *after* the
/// screenshot has already been captured and saved to Photos — purely
/// informational, no way to intercept or cancel it (design doc §1.6/§7.2).
/// Available since iOS 7.0, trivially within this package's iOS 18.0 floor
/// — no version gating needed, unlike the Android API-34 requirement.
enum ScreenshotDetector {
  private static var observer: NSObjectProtocol?

  /// Begins observing for screenshots. A no-op if already observing —
  /// matches `ScreenRecordingDetector.start`'s own idempotent shape.
  static func start(onScreenshotTaken: @escaping () -> Void) {
    guard observer == nil else { return }
    observer = NotificationCenter.default.addObserver(
      forName: UIApplication.userDidTakeScreenshotNotification,
      object: nil,
      queue: .main
    ) { _ in onScreenshotTaken() }
  }

  /// Stops observing. Safe to call even if `start` was never called, or
  /// already stopped.
  static func stop() {
    guard let observer else { return }
    NotificationCenter.default.removeObserver(observer)
    self.observer = nil
  }
}
