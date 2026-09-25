import XCTest
import UIKit
@testable import flutter_shield

/// `ScreenCaptureProtection`'s layer re-parenting, tested against a
/// manually-constructed view attached to a real `UIWindow` (so
/// `view.layer.superlayer` is non-nil deterministically, independent of
/// whatever windows the ambient XCTest host process happens to have) —
/// not against real screenshot pixel content, which XCTest cannot
/// inspect; that is covered by live Simulator verification instead (see
/// MANUAL_TEST_PLAN.md protect-9/protect-10).
final class ScreenCaptureProtectionTests: XCTestCase {
  override func tearDown() {
    ScreenCaptureProtection.disable()
    super.tearDown()
  }

  private func makeAttachedView() -> UIView {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    let container = UIView(frame: window.bounds)
    window.addSubview(container)
    window.isHidden = false
    return container
  }

  func testEnable_withAnAttachedView_returnsTrueAndSetsIsEnabled() {
    let view = makeAttachedView()

    let applied = ScreenCaptureProtection.enable(protecting: view)

    XCTAssertTrue(applied)
    XCTAssertTrue(ScreenCaptureProtection.isEnabled)
  }

  func testEnable_reparentsTheViewsLayerAwayFromItsOriginalSuperlayer() {
    let view = makeAttachedView()
    let originalSuperlayer = view.layer.superlayer

    ScreenCaptureProtection.enable(protecting: view)

    XCTAssertNotEqual(view.layer.superlayer, originalSuperlayer)
  }

  func testDisable_restoresTheOriginalSuperlayerExactly() {
    let view = makeAttachedView()
    let originalSuperlayer = view.layer.superlayer
    ScreenCaptureProtection.enable(protecting: view)

    ScreenCaptureProtection.disable()

    XCTAssertEqual(view.layer.superlayer, originalSuperlayer)
    XCTAssertFalse(ScreenCaptureProtection.isEnabled)
  }

  func testEnable_withNoSuperlayer_returnsFalseAndDoesNotEnable() {
    // Never added to any window/superview — no superlayer to re-parent
    // from, mirroring ScreenCaptureProtection.kt's own "no Activity
    // attached yet" honest-false path on Android.
    let view = UIView()

    let applied = ScreenCaptureProtection.enable(protecting: view)

    XCTAssertFalse(applied)
    XCTAssertFalse(ScreenCaptureProtection.isEnabled)
  }

  func testEnable_calledTwiceForTheSameView_isIdempotentAndStillReportsTrue() {
    let view = makeAttachedView()
    ScreenCaptureProtection.enable(protecting: view)
    let layerAfterFirstEnable = view.layer.superlayer

    let secondApplied = ScreenCaptureProtection.enable(protecting: view)

    XCTAssertTrue(secondApplied)
    XCTAssertEqual(view.layer.superlayer, layerAfterFirstEnable)
  }

  func testEnable_calledForADifferentView_restoresTheFirstViewBeforeProtectingTheSecond() {
    let firstView = makeAttachedView()
    let firstOriginalSuperlayer = firstView.layer.superlayer
    let secondView = makeAttachedView()
    ScreenCaptureProtection.enable(protecting: firstView)

    ScreenCaptureProtection.enable(protecting: secondView)

    XCTAssertEqual(firstView.layer.superlayer, firstOriginalSuperlayer)
    XCTAssertTrue(ScreenCaptureProtection.isEnabled)
  }

  func testDisable_whenNeverEnabled_isSafeAndDoesNotCrash() {
    ScreenCaptureProtection.disable()

    XCTAssertFalse(ScreenCaptureProtection.isEnabled)
  }

  func testDisable_calledTwiceInARow_isSafeAndDoesNotCrash() {
    let view = makeAttachedView()
    ScreenCaptureProtection.enable(protecting: view)

    ScreenCaptureProtection.disable()
    ScreenCaptureProtection.disable()

    XCTAssertFalse(ScreenCaptureProtection.isEnabled)
  }

  func testCurrentRootView_neverThrowsRegardlessOfWhetherAWindowExists() {
    XCTAssertNoThrow(ScreenCaptureProtection.currentRootView())
  }
}
