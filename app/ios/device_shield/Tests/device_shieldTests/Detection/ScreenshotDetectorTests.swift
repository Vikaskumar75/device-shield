import UIKit
import XCTest

@testable import device_shield

/// Unlike `ScreenshotDetectorTest.kt` (Android), which cannot exercise the
/// real registration path in a plain JVM unit test, XCTest here runs in a
/// real Simulator process with a real `NotificationCenter` — so these
/// tests post the actual `userDidTakeScreenshotNotification` and assert
/// the observer really fires, not just that it no-ops.
///
/// `ScreenshotDetector` holds module-level static state (mirroring
/// `ScreenshotDetector.kt`'s singleton `object` shape), which persists
/// across test methods in the same process — every test calls `stop()` in
/// `tearDown` to avoid leaking a registration into the next test.
final class ScreenshotDetectorTests: XCTestCase {
  override func tearDown() {
    ScreenshotDetector.stop()
    super.tearDown()
  }

  func testStart_firesCallbackWhenTheRealNotificationIsPosted() {
    var callCount = 0
    ScreenshotDetector.start { callCount += 1 }

    NotificationCenter.default.post(
      name: UIApplication.userDidTakeScreenshotNotification, object: nil)

    XCTAssertEqual(callCount, 1)
  }

  func testStop_stopsRoutingAfterBeingCalled() {
    var callCount = 0
    ScreenshotDetector.start { callCount += 1 }
    ScreenshotDetector.stop()

    NotificationCenter.default.post(
      name: UIApplication.userDidTakeScreenshotNotification, object: nil)

    XCTAssertEqual(callCount, 0)
  }

  func testStart_calledTwice_keepsOnlyTheFirstCallback() {
    var firstCallCount = 0
    var secondCallCount = 0
    ScreenshotDetector.start { firstCallCount += 1 }
    ScreenshotDetector.start { secondCallCount += 1 }

    NotificationCenter.default.post(
      name: UIApplication.userDidTakeScreenshotNotification, object: nil)

    XCTAssertEqual(firstCallCount, 1)
    XCTAssertEqual(secondCallCount, 0)
  }

  func testStop_whenNeverStarted_isSafeAndDoesNotCrash() {
    ScreenshotDetector.stop()
  }
}
