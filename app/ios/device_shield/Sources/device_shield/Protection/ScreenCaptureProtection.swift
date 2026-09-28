import UIKit

/// Keeps a window's content out of screenshots, screen recordings and
/// mirroring.
///
/// iOS has no public API for this. The technique relies on undocumented
/// UIKit behaviour: a `UITextField` with `isSecureTextEntry` renders its text
/// in an internal canvas view whose layer iOS leaves out of captures. Moving
/// the window's layer inside that canvas layer extends the exclusion to the
/// whole window.
///
/// How this avoids the problems of the previous implementation:
/// - It works at window level and never touches the Flutter view, so layout
///   isn't affected.
/// - It finds the secure layer by the canvas view that owns it, not by its
///   position in `sublayers`, which differs between iOS versions.
/// - The text field is never added to the view hierarchy, so the view tree
///   and the layer tree can't disagree about where it is.
///
/// Any iOS release may change this behaviour. **The Simulator can't show
/// whether it works**: verify on a physical device with a system screenshot
/// and a screen recording.
enum ScreenCaptureProtection {
  private static var secureField: UITextField?
  private static weak var protectedWindow: UIWindow?
  private static weak var originalSuperlayer: CALayer?
  private static var originalIndex: UInt32 = 0

  static var isEnabled: Bool { secureField != nil }

  /// Protects `window`. Returns `false` if the technique isn't available on
  /// this iOS version or the window isn't on screen yet.
  @discardableResult
  static func enable(protecting window: UIWindow) -> Bool {
    if isEnabled, protectedWindow === window { return true }
    if isEnabled { disable() }

    guard let superlayer = window.layer.superlayer,
      let index = superlayer.sublayers?.firstIndex(of: window.layer)
    else { return false }

    let field = UITextField()
    field.isSecureTextEntry = true
    field.frame = window.bounds
    field.layoutIfNeeded()
    guard let canvasLayer = secureCanvasLayer(of: field) else { return false }

    superlayer.insertSublayer(field.layer, at: UInt32(index))
    canvasLayer.addSublayer(window.layer)

    secureField = field
    protectedWindow = window
    originalSuperlayer = superlayer
    originalIndex = UInt32(index)
    return true
  }

  /// Restores the window's original layering. Safe to call when not enabled.
  static func disable() {
    if let window = protectedWindow, let superlayer = originalSuperlayer {
      let index = min(originalIndex, UInt32(superlayer.sublayers?.count ?? 0))
      superlayer.insertSublayer(window.layer, at: index)
    }
    secureField?.layer.removeFromSuperlayer()
    secureField = nil
    protectedWindow = nil
    originalSuperlayer = nil
  }

  /// The layer iOS excludes from captures: the one belonging to the secure
  /// field's internal canvas view (`_UITextLayoutCanvasView` on current
  /// iOS versions).
  static func secureCanvasLayer(of field: UITextField) -> CALayer? {
    field.subviews.first { String(describing: type(of: $0)).contains("CanvasView") }?.layer
  }

  /// The key window of the foreground scene, if any.
  static func currentWindow() -> UIWindow? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    return scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
  }
}
