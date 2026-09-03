import XCTest
import Flutter
@testable import flutter_shield

/// Unit tests for the native plugin foundation added to `FlutterShieldPlugin`:
/// event emission (`sendEvent`), callback/event-channel lifecycle
/// (`onListen`/`onCancel`), and the pre-existing `getPlatformVersion` /
/// `notImplemented` method dispatch. Mirrors
/// `android/src/test/kotlin/.../FlutterShieldPluginTest.kt` test-for-test
/// where the underlying behavior is the same on both platforms.
///
/// Note: `detachFromEngine(for:)` cleanup is exercised only indirectly here
/// (via the same `eventSink = nil` assignment `onCancel` already covers) —
/// constructing a real `FlutterPluginRegistrar` conforming test double is
/// out of scope for this pass, since it requires satisfying a large
/// Objective-C protocol surface unrelated to what changed in this file.
final class FlutterShieldPluginTests: XCTestCase {
  func testGetPlatformVersionReturnsExpectedValue() {
    let plugin = FlutterShieldPlugin()
    let call = FlutterMethodCall(methodName: "getPlatformVersion", arguments: nil)
    let expectation = expectation(description: "result")

    plugin.handle(call) { result in
      XCTAssertEqual(result as? String, "iOS " + UIDevice.current.systemVersion)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
  }

  func testCheckEmulatorReturnsAnEmulatorDetectionMap() {
    let plugin = FlutterShieldPlugin()
    let call = FlutterMethodCall(methodName: "checkEmulator", arguments: nil)
    let expectation = expectation(description: "result")

    plugin.handle(call) { result in
      let response = result as? [String: Any]
      XCTAssertNotNil(response?["detected"])
      XCTAssertNotNil(response?["confidence"])
      XCTAssertNotNil(response?["signals"])
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
  }

  func testCheckDebuggerReturnsADebuggerDetectionMap() {
    let plugin = FlutterShieldPlugin()
    let call = FlutterMethodCall(methodName: "checkDebugger", arguments: nil)
    let expectation = expectation(description: "result")

    plugin.handle(call) { result in
      let response = result as? [String: Any]
      XCTAssertNotNil(response?["detected"])
      XCTAssertNotNil(response?["confidence"])
      XCTAssertNotNil(response?["signals"])
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
  }

  func testCheckJailbreakReturnsAJailbreakDetectionMap() {
    let plugin = FlutterShieldPlugin()
    let call = FlutterMethodCall(methodName: "checkJailbreak", arguments: nil)
    let expectation = expectation(description: "result")

    plugin.handle(call) { result in
      let response = result as? [String: Any]
      XCTAssertNotNil(response?["detected"])
      XCTAssertNotNil(response?["confidence"])
      XCTAssertNotNil(response?["signals"])
      XCTAssertEqual(response?["applicable"] as? Bool, true)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
  }

  func testCheckRootReturnsTheHonestNotApplicableMap() {
    // "Root" is not an iOS concept — never a false "not rooted".
    let plugin = FlutterShieldPlugin()
    let call = FlutterMethodCall(methodName: "checkRoot", arguments: nil)
    let expectation = expectation(description: "result")

    plugin.handle(call) { result in
      let response = result as? [String: Any]
      XCTAssertEqual(response?["detected"] as? Bool, false)
      XCTAssertEqual(response?["confidence"] as? Double, 0.0)
      XCTAssertEqual(response?["applicable"] as? Bool, false)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
  }

  func testCheckMockLocationReturnsAMockLocationDetectionMap() {
    let plugin = FlutterShieldPlugin()
    let call = FlutterMethodCall(methodName: "checkMockLocation", arguments: nil)
    let expectation = expectation(description: "result")

    plugin.handle(call) { result in
      let response = result as? [String: Any]
      XCTAssertNotNil(response?["detected"])
      XCTAssertNotNil(response?["confidence"])
      XCTAssertNotNil(response?["signals"])
      XCTAssertNotNil(response?["permissionGranted"])
      XCTAssertNotNil(response?["locationAvailable"])
      // Unlike checkRoot on iOS, mock location is a real concept on both
      // platforms — never a false "not applicable".
      XCTAssertEqual(response?["applicable"] as? Bool, true)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
  }

  func testSetScreenshotProtectionEnabled_reportsAppliedWhenARootViewExists() {
    // "applied: true" here only proves the re-parenting call executed —
    // NOT that a black-screenshot effect occurs. Live Simulator testing
    // (design doc §18.5) found it does not, on Simulator at least; see
    // ScreenCaptureProtection.swift's own warning. A real XCTest host
    // process has at least one window, so currentRootView() finds one
    // and this call succeeds structurally.
    let plugin = FlutterShieldPlugin()
    let call = FlutterMethodCall(methodName: "setScreenshotProtection", arguments: ["enabled": true])
    let expectation = expectation(description: "result")

    plugin.handle(call) { result in
      XCTAssertEqual((result as? [String: Any])?["applied"] as? Bool, true)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
    ScreenCaptureProtection.disable()
  }

  func testSetScreenshotProtectionDisabled_alwaysReportsApplied() {
    let plugin = FlutterShieldPlugin()
    let call = FlutterMethodCall(methodName: "setScreenshotProtection", arguments: ["enabled": false])
    let expectation = expectation(description: "result")

    plugin.handle(call) { result in
      XCTAssertEqual((result as? [String: Any])?["applied"] as? Bool, true)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
  }

  func testSetAppSwitcherProtectionReportsApplied() {
    // Unlike setScreenshotProtection, this is a real, working mechanism on
    // iOS (AppSwitcherProtection) — the first protection call in this SDK
    // that can honestly report applied:true here.
    let plugin = FlutterShieldPlugin()
    let call = FlutterMethodCall(methodName: "setAppSwitcherProtection", arguments: ["enabled": true])
    let expectation = expectation(description: "result")

    plugin.handle(call) { result in
      XCTAssertEqual((result as? [String: Any])?["applied"] as? Bool, true)
      XCTAssertTrue(AppSwitcherProtection.isEnabled)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
    AppSwitcherProtection.disable()
  }

  func testSetAppSwitcherProtectionDisableReportsApplied() {
    let plugin = FlutterShieldPlugin()
    let call = FlutterMethodCall(methodName: "setAppSwitcherProtection", arguments: ["enabled": false])
    let expectation = expectation(description: "result")

    plugin.handle(call) { result in
      XCTAssertEqual((result as? [String: Any])?["applied"] as? Bool, true)
      XCTAssertFalse(AppSwitcherProtection.isEnabled)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
  }

  func testIsScreenCaptureActiveReturnsTheSupportedCaptureStateMap() {
    let plugin = FlutterShieldPlugin()
    let call = FlutterMethodCall(methodName: "isScreenCaptureActive", arguments: nil)
    let expectation = expectation(description: "result")

    plugin.handle(call) { result in
      let response = result as? [String: Any]
      XCTAssertEqual(response?["supported"] as? Bool, true)
      XCTAssertNotNil(response?["isCaptured"])
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
  }

  func testUnknownBridgeMethodReturnsNotImplemented() {
    let plugin = FlutterShieldPlugin()
    let call = FlutterMethodCall(methodName: "someFutureSecurityCheck", arguments: nil)
    let expectation = expectation(description: "result")

    plugin.handle(call) { result in
      XCTAssertTrue((result as AnyObject) === (FlutterMethodNotImplemented as AnyObject))
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
  }

  func testSendEventWithActiveListenerDeliversTheCallbackDataShape() {
    let plugin = FlutterShieldPlugin()
    var captured: [String: Any]?
    _ = plugin.onListen(withArguments: nil) { event in
      captured = event as? [String: Any]
    }

    plugin.sendEvent(callback: "onSecurityEvent", data: "root_detected")

    XCTAssertEqual(captured?["callback"] as? String, "onSecurityEvent")
    XCTAssertEqual(captured?["data"] as? String, "root_detected")
  }

  func testSendEventWithNilDataForwardsNSNull() {
    let plugin = FlutterShieldPlugin()
    var captured: [String: Any]?
    _ = plugin.onListen(withArguments: nil) { event in
      captured = event as? [String: Any]
    }

    plugin.sendEvent(callback: "probe", data: nil)

    XCTAssertEqual(captured?["callback"] as? String, "probe")
    XCTAssertTrue(captured?["data"] is NSNull)
  }

  func testSendEventWithNoActiveListenerIsANoOpRatherThanCrashing() {
    let plugin = FlutterShieldPlugin()

    // No listener has ever attached — this must simply not crash.
    plugin.sendEvent(callback: "onSecurityEvent", data: "root_detected")
  }

  func testOnCancelStopsRoutingToThePreviousSink() {
    let plugin = FlutterShieldPlugin()
    var callCount = 0
    _ = plugin.onListen(withArguments: nil) { _ in callCount += 1 }

    _ = plugin.onCancel(withArguments: nil)
    plugin.sendEvent(callback: "probe", data: "x")

    XCTAssertEqual(callCount, 0)
  }

  func testOnListenReplacesAnyPreviouslyRegisteredSink() {
    let plugin = FlutterShieldPlugin()
    var firstCallCount = 0
    var secondCaptured: [String: Any]?
    _ = plugin.onListen(withArguments: nil) { _ in firstCallCount += 1 }

    _ = plugin.onListen(withArguments: nil) { event in
      secondCaptured = event as? [String: Any]
    }
    plugin.sendEvent(callback: "probe", data: "x")

    XCTAssertEqual(firstCallCount, 0)
    XCTAssertEqual(secondCaptured?["callback"] as? String, "probe")
  }
}
