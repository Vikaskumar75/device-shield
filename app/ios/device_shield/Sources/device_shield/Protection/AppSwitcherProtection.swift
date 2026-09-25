import UIKit

/// App-Switcher / Background-Snapshot Protection — the iOS-only follow-on
/// design doc §17 named as future work: doc/features/
/// SCREENSHOT_SCREEN_RECORDING_PROTECTION.md. Android needs no equivalent
/// of this file — it already gets Recents-thumbnail redaction for free as
/// a side effect of `FLAG_SECURE`
/// ([com.geekyants.device_shield.protection.ScreenCaptureProtection]).
/// iOS has no such free side effect, and — as with screenshot/recording
/// blocking generally (§1.6) — no API to stop the OS from taking the
/// app-switcher snapshot at all. What iOS *does* allow, entirely through
/// public, documented, App-Store-safe UIKit (`UIWindow` +
/// `UIVisualEffectView`, both ordinary view-layer APIs, not a private or
/// undocumented technique): covering the window's content with an opaque
/// overlay in the brief window between `willResignActiveNotification`
/// (fired *before* the OS captures that snapshot) and the app actually
/// leaving the foreground, then removing it once `didBecomeActiveNotification`
/// confirms the app is interactive again. This is the same
/// technique widely used by production banking apps — not a novel or
/// fragile trick.
///
/// A dedicated top-level `UIWindow`, not a subview inserted into Flutter's
/// own key window — this never touches Flutter's view or hit-test
/// hierarchy at all; showing/hiding the overlay is just this window's own
/// visibility.
///
/// Deliberately its own file/package (`Protection/`, mirroring Android's
/// `protection/`) — same detecting-vs-blocking separation rationale
/// `ScreenCaptureProtection.kt` documents.
enum AppSwitcherProtection {
  private static var overlayWindow: UIWindow?
  private static var resignObserver: NSObjectProtocol?
  private static var activeObserver: NSObjectProtocol?

  /// Pure state check, separated from the real window-manipulating code
  /// below so it can be unit-tested without a full `UIApplication`/scene
  /// runtime — same split `ScreenRecordingDetector.evaluate` already
  /// documents for the same reason.
  private(set) static var isEnabled = false

  /// Begins observing app-active-state transitions. Always safe to call
  /// more than once — a no-op if already observing. Observing itself
  /// costs nothing while [isEnabled] is false; the overlay is only ever
  /// shown after a caller has explicitly opted in via [enable].
  static func start() {
    guard resignObserver == nil else { return }
    resignObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification,
      object: nil,
      queue: .main
    ) { _ in showOverlayIfEnabled() }
    activeObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { _ in hideOverlay() }
  }

  /// Stops observing and tears down any active overlay/state. Safe to
  /// call even if [start] was never called, or already stopped.
  static func stop() {
    if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
    resignObserver = nil
    activeObserver = nil
    hideOverlay()
    isEnabled = false
  }

  /// Opts in. Does not retroactively cover an already-inactive app — the
  /// overlay only ever appears on the *next* `willResignActive`
  /// transition after this call, exactly mirroring
  /// `ScreenCaptureProtection`'s own "applies from here forward" shape.
  /// Always reports `true` — unlike Android `FLAG_SECURE` (which can fail
  /// to apply if no `Activity` is attached yet), there is no equivalent
  /// failure mode here: `UIApplication`/`NotificationCenter` are globally
  /// available the instant this runs.
  @discardableResult
  static func enable() -> Bool {
    isEnabled = true
    return true
  }

  /// The imperative disable — symmetric to [enable]. If the overlay is
  /// currently shown, it is removed immediately rather than waiting for
  /// the next `didBecomeActive`.
  @discardableResult
  static func disable() -> Bool {
    isEnabled = false
    hideOverlay()
    return true
  }

  private static func showOverlayIfEnabled() {
    guard isEnabled, overlayWindow == nil else { return }
    guard let scene = keyWindowScene() else { return }

    let window = UIWindow(windowScene: scene)
    window.windowLevel = .alert + 1
    window.backgroundColor = .clear
    window.isHidden = false

    let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    blur.frame = window.bounds
    blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(blur)

    overlayWindow = window
  }

  private static func hideOverlay() {
    overlayWindow?.isHidden = true
    overlayWindow = nil
  }

  private static func keyWindowScene() -> UIWindowScene? {
    let scenes = UIApplication.shared.connectedScenes
    let active = scenes.first { $0.activationState == .foregroundActive }
    let inactive = scenes.first { $0.activationState == .foregroundInactive }
    return (active ?? inactive ?? scenes.first) as? UIWindowScene
  }
}
