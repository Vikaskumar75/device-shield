import XCTest
@testable import flutter_shield

/// EmulatorDetector's logic is a compile-time `#if targetEnvironment(simulator)`
/// branch, not runtime-parameterizable the way Android's Build-fingerprint
/// heuristics are — so unlike `EmulatorDetectorTest.kt` (which exercises
/// synthetic inputs), this test simply asserts the branch that's actually
/// compiled in whenever these tests run, which is always the simulator
/// branch (XCTest bundles for this package build for the simulator target).
final class EmulatorDetectorTests: XCTestCase {
  func testCheckReportsDetectedWithFullConfidenceUnderSimulatorCompilation() {
    let result = EmulatorDetector.check()

    #if targetEnvironment(simulator)
    XCTAssertEqual(result["detected"] as? Bool, true)
    XCTAssertEqual(result["confidence"] as? Double, 1.0)
    XCTAssertEqual(result["signals"] as? [String], ["simulator_target"])
    #else
    XCTAssertEqual(result["detected"] as? Bool, false)
    XCTAssertEqual(result["confidence"] as? Double, 0.0)
    XCTAssertEqual(result["signals"] as? [String], [])
    #endif
  }

  func testCheckAlwaysReturnsAllThreeExpectedKeys() {
    let result = EmulatorDetector.check()

    XCTAssertNotNil(result["detected"])
    XCTAssertNotNil(result["confidence"])
    XCTAssertNotNil(result["signals"])
  }
}
