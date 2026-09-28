import UIKit

/// Screenshot & Screen Recording Protection — iOS.
///
/// ⚠️ UNSUPPORTED TECHNIQUE, AND ITS EFFECT IS UNCONFIRMED — READ BEFORE
/// TOUCHING THIS FILE. ⚠️
///
/// docs/features/SCREENSHOT_SCREEN_RECORDING_PROTECTION.md §1.6/§7.2/§18.3
/// investigated this exact mechanism and initially rejected it, for
/// reasons that are all still true and are recorded here, not hidden,
/// because a later engineer (including future us) needs them to make an
/// informed call about touching this file:
///
/// - There is **no Apple-documented, public API** to block a screenshot
///   or recording on iOS, on any version, ever. That platform fact is
///   unchanged and is not what this file claims to solve.
/// - What this file *attempts* — re-parent a view's `CALayer` underneath
///   a `UITextField.isSecureTextEntry` field's internal secure-rendering
///   layer — is reported to work in production apps and published
///   Flutter plugins (`screen_protector`) that use the same mechanism.
///   **It does NOT confirm to work here.** Live verification on a real
///   booted iOS Simulator (design doc §18.5) showed `enable()` genuinely
///   re-parenting the layer (a real, observed layout side effect) but a
///   ground-truth `simctl io screenshot` with protection enabled still
///   captured full, real content — not black. Root cause unconfirmed:
///   most likely the Simulator's compositor doesn't honor this
///   exclusion the way real hardware's does, but a real implementation
///   bug has not been ruled out either. **Do not treat `enable()`
///   returning `true` as proof this works — it only proves the
///   re-parenting call executed.** Verify on physical hardware before
///   relying on this for anything.
/// - It relies on `UITextField`'s **undocumented internal layer
///   structure** (`layer.sublayers.last` being the secure layer) — not a
///   contracted Apple API. Apple has reshuffled `UITextField` internals
///   across iOS releases before; even if this does work on real
///   hardware, it can silently stop working on a future iOS version with
///   **no compile error, no runtime error, no warning** — the app would
///   believe it is protected when it is not. **Re-verify this manually
///   (§7.2's manual test protocol) against every new iOS major version,
///   and on physical hardware, before shipping.**
/// - Approved for implementation by explicit host-app decision, with
///   this risk accepted, for iOS parity with production payment apps —
///   not a claim that this is now an Apple-sanctioned mechanism, and not
///   yet a confirmed-working mechanism either.
///
/// Protects a whole view (in practice: the Flutter root view, for
/// SDK-wide "current sensitive screen" protection, matching Android
/// `FLAG_SECURE`'s own whole-`Window` scope — not per-widget, since
/// Flutter renders one surface, not one native view per widget).
enum ScreenCaptureProtection {
  private static var secureField: UITextField?
  private static weak var protectedView: UIView?
  private static weak var originalSuperlayer: CALayer?

  /// Re-parents [view]'s layer under a secure text field's rendering
  /// layer. Returns `true` only if the re-parenting actually happened —
  /// an honest answer if, for example, [view] has no superlayer yet
  /// (not yet attached to a window), mirroring `ScreenCaptureProtection
  /// .kt`'s own "no Activity attached yet → not applied" honesty on
  /// Android. A no-op (returns `true`) if already enabled for this view.
  ///
  /// [secureField] is kept as a **permanent** (invisible, non-
  /// interactive) subview of [view] for the entire time protection is
  /// enabled — not added-then-immediately-removed. This matters:
  /// `UIView.removeFromSuperview()` also tears the view's `.layer` out
  /// of whatever `CALayer` currently parents it, so calling it right
  /// after the manual re-parenting below would immediately undo that
  /// re-parenting. [secureField] is only ever removed in [disable],
  /// which is exactly the point its layer should come back out.
  @discardableResult
  static func enable(protecting view: UIView) -> Bool {
    if secureField != nil, protectedView === view { return true }
    if secureField != nil { disable() }

    guard let superlayer = view.layer.superlayer else { return false }

    let field = UITextField()
    field.isSecureTextEntry = true
    field.isUserInteractionEnabled = false
    field.isAccessibilityElement = false
    field.borderStyle = .none
    field.backgroundColor = .clear
    field.frame = view.frame
    view.addSubview(field)

    guard let secureLayer = field.layer.sublayers?.last else {
      field.removeFromSuperview()
      return false
    }

    superlayer.addSublayer(field.layer)
    secureLayer.addSublayer(view.layer)

    secureField = field
    protectedView = view
    originalSuperlayer = superlayer
    return true
  }

  /// Restores [view]'s layer to its original superlayer and tears down
  /// [secureField] (see [enable]'s doc comment for why removal is safe
  /// only here, not earlier). Safe to call even if [enable] was never
  /// called, or already disabled.
  static func disable() {
    if let view = protectedView, let superlayer = originalSuperlayer {
      superlayer.addSublayer(view.layer)
    }
    secureField?.removeFromSuperview()
    secureField = nil
    protectedView = nil
    originalSuperlayer = nil
  }

  static var isEnabled: Bool { secureField != nil }

  /// The view this SDK protects when no specific view is supplied by the
  /// caller — the app's key window's root view, matching Android
  /// `FLAG_SECURE`'s whole-`Window` scope. `nil` if no key window exists
  /// yet (e.g. called before Flutter has attached a window) — callers
  /// must treat that as an honest "not applied," not retry silently.
  static func currentRootView() -> UIView? {
    let scenes = UIApplication.shared.connectedScenes
    let windowScene =
      (scenes.first { $0.activationState == .foregroundActive }
      ?? scenes.first) as? UIWindowScene
    let window = windowScene?.windows.first { $0.isKeyWindow } ?? windowScene?.windows.first
    return window?.rootViewController?.view
  }
}
