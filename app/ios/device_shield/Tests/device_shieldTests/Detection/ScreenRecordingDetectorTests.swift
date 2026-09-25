import UIKit
import XCTest

@testable import device_shield

/// `ScreenRecordingDetector.evaluate(isCaptured:)` (pure logic) is
/// exercised with synthetic inputs, mirroring `DebuggerDetectorTests`'
/// own split. `start`/`stop` post the real `capturedDidChangeNotification`
/// — a real Simulator process can do this, unlike Android's plain-JVM
/// equivalent, which could only assert the unsupported/no-op path.
final class ScreenRecordingDetectorTests: XCTestCase {
  override func tearDown() {
    ScreenRecordingDetector.stop()
    super.tearDown()
  }

  func testEvaluateNotCaptured_reportsSupportedAndNotCaptured() {
    let result = ScreenRecordingDetector.evaluate(isCaptured: false)

    XCTAssertEqual(result["isCaptured"] as? Bool, false)
    XCTAssertEqual(result["supported"] as? Bool, true)
  }

  func testEvaluateCaptured_reportsSupportedAndCaptured() {
    let result = ScreenRecordingDetector.evaluate(isCaptured: true)

    XCTAssertEqual(result["isCaptured"] as? Bool, true)
    XCTAssertEqual(result["supported"] as? Bool, true)
  }

  func testCheck_alwaysReportsSupportedOnIOS() {
    // Unlike Android, iOS always reports supported:true — there is a real
    // signal here (design doc §1.5's capability table), regardless of the
    // actual isCaptured value in this test environment.
    let result = ScreenRecordingDetector.check()

    XCTAssertEqual(result["supported"] as? Bool, true)
    XCTAssertNotNil(result["isCaptured"])
  }

  func testStart_firesCallbackWithCurrentStateWhenTheRealNotificationIsPosted() {
    var received: Bool?
    ScreenRecordingDetector.start { isCaptured in received = isCaptured }

    NotificationCenter.default.post(name: UIScreen.capturedDidChangeNotification, object: nil)

    XCTAssertEqual(received, UIScreen.main.isCaptured)
  }

  func testStop_stopsRoutingAfterBeingCalled() {
    var callCount = 0
    ScreenRecordingDetector.start { _ in callCount += 1 }
    ScreenRecordingDetector.stop()

    NotificationCenter.default.post(name: UIScreen.capturedDidChangeNotification, object: nil)

    XCTAssertEqual(callCount, 0)
  }

  func testStop_whenNeverStarted_isSafeAndDoesNotCrash() {
    ScreenRecordingDetector.stop()
  }
}
