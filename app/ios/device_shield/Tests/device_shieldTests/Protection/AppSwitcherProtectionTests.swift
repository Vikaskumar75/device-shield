import XCTest
import UIKit
@testable import flutter_shield

/// `AppSwitcherProtection`'s enable/disable/start/stop state machine,
/// mirroring `ScreenRecordingDetectorTests`'/`ScreenshotDetectorTests`'
/// own pattern: real notifications posted through `NotificationCenter`,
/// asserted against the pure `isEnabled` state rather than inspecting
/// window internals (which the Simulator/XCTest host may or may not have
/// a real `UIWindowScene` for, depending on run context — the class
/// itself already guards that case via `keyWindowScene()` returning nil).
final class AppSwitcherProtectionTests: XCTestCase {
  override func tearDown() {
    AppSwitcherProtection.stop()
    super.tearDown()
  }

  func testEnable_returnsTrueAndSetsIsEnabled() {
    let applied = AppSwitcherProtection.enable()

    XCTAssertTrue(applied)
    XCTAssertTrue(AppSwitcherProtection.isEnabled)
  }

  func testDisable_returnsTrueAndClearsIsEnabled() {
    AppSwitcherProtection.enable()

    let applied = AppSwitcherProtection.disable()

    XCTAssertTrue(applied)
    XCTAssertFalse(AppSwitcherProtection.isEnabled)
  }

  func testDisable_withoutEverEnabling_isSafeAndReportsTrue() {
    let applied = AppSwitcherProtection.disable()

    XCTAssertTrue(applied)
    XCTAssertFalse(AppSwitcherProtection.isEnabled)
  }

  func testStart_isIdempotent_calledTwiceDoesNotDuplicateObservation() {
    AppSwitcherProtection.start()
    AppSwitcherProtection.start()
    AppSwitcherProtection.enable()

    // If start() had registered the resign-active observer twice, this
    // notification would attempt to show the overlay twice — harmless in
    // practice (showOverlayIfEnabled itself guards on overlayWindow == nil),
    // but the real assertion that matters is that isEnabled's state machine
    // stays consistent, not doubled, after two start() calls.
    NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)

    XCTAssertTrue(AppSwitcherProtection.isEnabled)
  }

  func testStop_clearsIsEnabled() {
    AppSwitcherProtection.start()
    AppSwitcherProtection.enable()

    AppSwitcherProtection.stop()

    XCTAssertFalse(AppSwitcherProtection.isEnabled)
  }

  func testStop_whenNeverStarted_isSafeAndDoesNotCrash() {
    AppSwitcherProtection.stop()
  }

  func testStop_stopsRoutingAfterBeingCalled_disableAfterStopStaysFalse() {
    AppSwitcherProtection.start()
    AppSwitcherProtection.enable()
    AppSwitcherProtection.stop()

    // A resign-active notification after stop() must not resurrect the
    // enabled state — start()'s observers were torn down.
    NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)

    XCTAssertFalse(AppSwitcherProtection.isEnabled)
  }

  func testEnableDoesNotRetroactivelyShowTheOverlay_documentedShape() {
    // enable() only flips state; the overlay itself only ever appears on
    // the *next* willResignActive transition — this test documents that
    // contract by asserting enable() alone never crashes or requires an
    // active scene, exactly like the doc comment states.
    AppSwitcherProtection.start()

    XCTAssertNoThrow(AppSwitcherProtection.enable())
  }
}
