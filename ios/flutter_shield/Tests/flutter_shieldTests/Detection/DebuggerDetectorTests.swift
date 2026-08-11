import XCTest
@testable import flutter_shield

/// `DebuggerDetector.evaluate()` (the pure decision logic, taking the
/// `sysctl`-derived boolean as a parameter) is exercised with synthetic
/// inputs, mirroring `EmulatorDetectorTests.swift`'s own split between
/// deterministic logic and the actual platform-specific signal gathering.
/// `DebuggerDetector.check()` itself is exercised separately, asserting
/// only the response shape — its actual `detected` value depends on
/// whether the test host process happens to be traced when this suite
/// runs (a debug server routinely is, under `xcodebuild test`), which
/// this file deliberately does not assume either way.
final class DebuggerDetectorTests: XCTestCase {
  func testEvaluateNotAttachedReportsNotDetectedWithZeroConfidence() {
    let result = DebuggerDetector.evaluate(debuggerAttached: false)

    XCTAssertEqual(result["detected"] as? Bool, false)
    XCTAssertEqual(result["confidence"] as? Double, 0.0)
    XCTAssertEqual(result["signals"] as? [String], [])
  }

  func testEvaluateAttachedReportsDetectedWithFullConfidence() {
    let result = DebuggerDetector.evaluate(debuggerAttached: true)

    XCTAssertEqual(result["detected"] as? Bool, true)
    XCTAssertEqual(result["confidence"] as? Double, 1.0)
    XCTAssertEqual(result["signals"] as? [String], ["ptrace_flag"])
  }

  func testCheckAlwaysReturnsAllThreeExpectedKeys() {
    let result = DebuggerDetector.check()

    XCTAssertNotNil(result["detected"])
    XCTAssertNotNil(result["confidence"])
    XCTAssertNotNil(result["signals"])
  }

  func testCheckConfidenceIsAlwaysExactlyZeroOrOne() {
    // A single authoritative binary signal (P_TRACED), not a weighted
    // heuristic count — unlike Android's DebuggerDetector, no partial
    // confidence value is ever possible here.
    let result = DebuggerDetector.check()
    let confidence = result["confidence"] as? Double

    XCTAssertTrue(confidence == 0.0 || confidence == 1.0)
  }

  func testCheckDetectedFlagIsConsistentWithConfidenceAndSignals() {
    let result = DebuggerDetector.check()
    let detected = result["detected"] as? Bool
    let confidence = result["confidence"] as? Double
    let signals = result["signals"] as? [String]

    if detected == true {
      XCTAssertEqual(confidence, 1.0)
      XCTAssertEqual(signals, ["ptrace_flag"])
    } else {
      XCTAssertEqual(confidence, 0.0)
      XCTAssertEqual(signals, [])
    }
  }
}
