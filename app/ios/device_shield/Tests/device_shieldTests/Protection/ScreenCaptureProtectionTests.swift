import UIKit
import XCTest

@testable import device_shield

/// These tests cover the bookkeeping only. Whether captures are actually
/// blocked can only be checked on a physical device with a real screenshot
/// and screen recording (see docs/MANUAL_TEST_PLAN.md).
final class ScreenCaptureProtectionTests: XCTestCase {
  override func tearDown() {
    ScreenCaptureProtection.disable()
    super.tearDown()
  }

  func testEnable_forAWindowThatIsNotOnScreen_returnsFalseAndStaysDisabled() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))

    XCTAssertFalse(ScreenCaptureProtection.enable(protecting: window))
    XCTAssertFalse(ScreenCaptureProtection.isEnabled)
  }

  func testDisable_whenNotEnabled_isANoOp() {
    ScreenCaptureProtection.disable()

    XCTAssertFalse(ScreenCaptureProtection.isEnabled)
  }

  /// Fails first if Apple changes the secure field's internals, before users
  /// notice protection silently stopped working.
  func testSecureCanvasLayer_existsForASecureTextField() {
    let field = UITextField()
    field.isSecureTextEntry = true
    field.layoutIfNeeded()

    XCTAssertNotNil(ScreenCaptureProtection.secureCanvasLayer(of: field))
  }

  func testSecureCanvasLayer_isAbsentForAPlainView() {
    let field = UITextField()
    for subview in field.subviews { subview.removeFromSuperview() }

    XCTAssertNil(ScreenCaptureProtection.secureCanvasLayer(of: field))
  }
}
