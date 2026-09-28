import XCTest

@testable import device_shield

/// Exercises `JailbreakDetector.evaluate()` (the pure decision logic)
/// with synthetic inputs, mirroring `DebuggerDetectorTests`'/
/// `ScreenRecordingDetectorTests`' own split between real-signal-reading
/// (`check()`) and pure decision logic (`evaluate()`).
final class JailbreakDetectorTests: XCTestCase {
  func testEvaluate_noSignals_reportsNotDetectedWithZeroConfidence() {
    let result = JailbreakDetector.evaluate(
      jailbreakAppPathExists: false,
      suspiciousSystemPathExists: false,
      writableOutsideSandbox: false,
      dyldEnvVarSet: false,
      processSpawnSucceeded: false
    )

    XCTAssertEqual(result["detected"] as? Bool, false)
    XCTAssertEqual(result["confidence"] as? Double, 0.0)
    XCTAssertEqual((result["signals"] as? [String])?.isEmpty, true)
    XCTAssertEqual(result["applicable"] as? Bool, true)
  }

  func testEvaluate_jailbreakAppPathAlone_isDetected() {
    let result = JailbreakDetector.evaluate(
      jailbreakAppPathExists: true,
      suspiciousSystemPathExists: false,
      writableOutsideSandbox: false,
      dyldEnvVarSet: false,
      processSpawnSucceeded: false
    )

    XCTAssertEqual(result["detected"] as? Bool, true)
    XCTAssertEqual(result["signals"] as? [String], ["jailbreak_app_paths"])
  }

  func testEvaluate_suspiciousSystemPathAlone_isDetected() {
    let result = JailbreakDetector.evaluate(
      jailbreakAppPathExists: false,
      suspiciousSystemPathExists: true,
      writableOutsideSandbox: false,
      dyldEnvVarSet: false,
      processSpawnSucceeded: false
    )

    XCTAssertEqual(result["detected"] as? Bool, true)
    XCTAssertEqual(result["signals"] as? [String], ["suspicious_system_paths"])
  }

  func testEvaluate_writableOutsideSandboxAlone_isDetected() {
    let result = JailbreakDetector.evaluate(
      jailbreakAppPathExists: false,
      suspiciousSystemPathExists: false,
      writableOutsideSandbox: true,
      dyldEnvVarSet: false,
      processSpawnSucceeded: false
    )

    XCTAssertEqual(result["detected"] as? Bool, true)
    XCTAssertEqual(result["signals"] as? [String], ["writable_outside_sandbox"])
  }

  func testEvaluate_dyldEnvVarAlone_isDetected() {
    let result = JailbreakDetector.evaluate(
      jailbreakAppPathExists: false,
      suspiciousSystemPathExists: false,
      writableOutsideSandbox: false,
      dyldEnvVarSet: true,
      processSpawnSucceeded: false
    )

    XCTAssertEqual(result["detected"] as? Bool, true)
    XCTAssertEqual(result["signals"] as? [String], ["dyld_env_var"])
  }

  func testEvaluate_processSpawnAlone_isDetected() {
    let result = JailbreakDetector.evaluate(
      jailbreakAppPathExists: false,
      suspiciousSystemPathExists: false,
      writableOutsideSandbox: false,
      dyldEnvVarSet: false,
      processSpawnSucceeded: true
    )

    XCTAssertEqual(result["detected"] as? Bool, true)
    XCTAssertEqual(result["signals"] as? [String], ["process_spawn_check"])
  }

  func testEvaluate_everySignalFiring_reportsFullConfidence() {
    let result = JailbreakDetector.evaluate(
      jailbreakAppPathExists: true,
      suspiciousSystemPathExists: true,
      writableOutsideSandbox: true,
      dyldEnvVarSet: true,
      processSpawnSucceeded: true
    )

    XCTAssertEqual(result["detected"] as? Bool, true)
    XCTAssertEqual(result["confidence"] as? Double, 1.0)
    XCTAssertEqual((result["signals"] as? [String])?.count, 5)
  }

  func testEvaluate_partialSignals_reportsProportionalConfidence() {
    let result = JailbreakDetector.evaluate(
      jailbreakAppPathExists: true,
      suspiciousSystemPathExists: false,
      writableOutsideSandbox: false,
      dyldEnvVarSet: true,
      processSpawnSucceeded: false
    )

    XCTAssertEqual(result["confidence"] as? Double, 2.0 / 5.0)
    XCTAssertEqual((result["signals"] as? [String])?.count, 2)
  }

  func testEvaluate_alwaysReportsApplicableTrue() {
    // Unlike RootDetector on iOS, JailbreakDetector always applies on
    // iOS — never a false "not applicable".
    let result = JailbreakDetector.evaluate(
      jailbreakAppPathExists: false,
      suspiciousSystemPathExists: false,
      writableOutsideSandbox: false,
      dyldEnvVarSet: false,
      processSpawnSucceeded: false
    )

    XCTAssertEqual(result["applicable"] as? Bool, true)
  }

  func testCheck_neverThrowsAndReturnsTheExpectedShape() {
    // check() exercises the real filesystem/environment/posix_spawn
    // reads — this only confirms it runs to completion with the right
    // shape on whatever CI/Simulator host executes this test; it cannot
    // assert a specific detected/not-detected outcome, since that
    // depends on the real host environment, not a synthetic input.
    let result = JailbreakDetector.check()

    XCTAssertNotNil(result["detected"])
    XCTAssertNotNil(result["confidence"])
    XCTAssertNotNil(result["signals"])
    // The Simulator can't be jailbroken, so the check doesn't apply there.
    #if targetEnvironment(simulator)
      XCTAssertEqual(result["applicable"] as? Bool, false)
    #else
      XCTAssertEqual(result["applicable"] as? Bool, true)
    #endif
  }
}
