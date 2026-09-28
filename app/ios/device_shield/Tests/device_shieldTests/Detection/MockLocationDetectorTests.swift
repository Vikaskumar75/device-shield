import XCTest

@testable import device_shield

/// Exercises `MockLocationDetector.evaluate()` (the pure decision logic)
/// with synthetic inputs, mirroring `JailbreakDetectorTests`'/
/// `EmulatorDetectorTests`' own split between real-signal-reading
/// (`check()`) and pure decision logic (`evaluate()`).
final class MockLocationDetectorTests: XCTestCase {
  func testEvaluate_noSignals_reportsNotDetectedWithZeroConfidence() {
    let result = MockLocationDetector.evaluate(
      permissionGranted: true,
      locationAvailable: true,
      knownSpoofingTweakArtifact: false,
      invalidLocationAccuracy: false,
      impossibleVelocity: false
    )

    XCTAssertEqual(result["detected"] as? Bool, false)
    XCTAssertEqual(result["confidence"] as? Double, 0.0)
    XCTAssertEqual((result["signals"] as? [String])?.isEmpty, true)
    XCTAssertEqual(result["applicable"] as? Bool, true)
  }

  func testEvaluate_knownSpoofingTweakArtifactAlone_isDetected() {
    let result = MockLocationDetector.evaluate(
      permissionGranted: true,
      locationAvailable: true,
      knownSpoofingTweakArtifact: true,
      invalidLocationAccuracy: false,
      impossibleVelocity: false
    )

    XCTAssertEqual(result["detected"] as? Bool, true)
    XCTAssertEqual(result["signals"] as? [String], ["known_spoofing_tweak_artifact"])
    XCTAssertEqual(result["confidence"] as? Double, 1.0 / 3.0)
  }

  func testEvaluate_invalidLocationAccuracyAlone_isDetected() {
    let result = MockLocationDetector.evaluate(
      permissionGranted: true,
      locationAvailable: true,
      knownSpoofingTweakArtifact: false,
      invalidLocationAccuracy: true,
      impossibleVelocity: false
    )

    XCTAssertEqual(result["detected"] as? Bool, true)
    XCTAssertEqual(result["signals"] as? [String], ["invalid_location_accuracy"])
  }

  func testEvaluate_impossibleVelocityAlone_isDetected() {
    let result = MockLocationDetector.evaluate(
      permissionGranted: true,
      locationAvailable: true,
      knownSpoofingTweakArtifact: false,
      invalidLocationAccuracy: false,
      impossibleVelocity: true
    )

    XCTAssertEqual(result["detected"] as? Bool, true)
    XCTAssertEqual(result["signals"] as? [String], ["impossible_velocity"])
  }

  func testEvaluate_everySignalFiring_reportsFullConfidence() {
    let result = MockLocationDetector.evaluate(
      permissionGranted: true,
      locationAvailable: true,
      knownSpoofingTweakArtifact: true,
      invalidLocationAccuracy: true,
      impossibleVelocity: true
    )

    XCTAssertEqual(result["detected"] as? Bool, true)
    XCTAssertEqual(result["confidence"] as? Double, 1.0)
    XCTAssertEqual((result["signals"] as? [String])?.count, 3)
  }

  func testEvaluate_partialSignals_reportsProportionalConfidence() {
    let result = MockLocationDetector.evaluate(
      permissionGranted: true,
      locationAvailable: true,
      knownSpoofingTweakArtifact: true,
      invalidLocationAccuracy: false,
      impossibleVelocity: true
    )

    XCTAssertEqual(result["confidence"] as? Double, 2.0 / 3.0)
    XCTAssertEqual((result["signals"] as? [String])?.count, 2)
  }

  func testEvaluate_alwaysReportsApplicableTrue() {
    // Unlike checkRoot on iOS, mock location is a real concept on iOS
    // too — never a false "not applicable", regardless of permission/
    // location availability.
    let result = MockLocationDetector.evaluate(
      permissionGranted: false,
      locationAvailable: false,
      knownSpoofingTweakArtifact: false,
      invalidLocationAccuracy: false,
      impossibleVelocity: false
    )

    XCTAssertEqual(result["applicable"] as? Bool, true)
  }

  func testEvaluate_permissionNotGranted_isCarriedThroughHonestly() {
    let result = MockLocationDetector.evaluate(
      permissionGranted: false,
      locationAvailable: false,
      knownSpoofingTweakArtifact: false,
      invalidLocationAccuracy: false,
      impossibleVelocity: false
    )

    XCTAssertEqual(result["permissionGranted"] as? Bool, false)
    XCTAssertEqual(result["locationAvailable"] as? Bool, false)
    XCTAssertEqual(result["detected"] as? Bool, false)
  }

  func testEvaluate_permissionNotGranted_stillDetectsPermissionFreeSignals() {
    let result = MockLocationDetector.evaluate(
      permissionGranted: false,
      locationAvailable: false,
      knownSpoofingTweakArtifact: true,
      invalidLocationAccuracy: false,
      impossibleVelocity: false
    )

    XCTAssertEqual(result["detected"] as? Bool, true)
    XCTAssertEqual(result["signals"] as? [String], ["known_spoofing_tweak_artifact"])
  }

  func testCheck_neverThrowsAndReturnsTheExpectedShape() {
    // check() exercises the real CoreLocation/FileManager reads — this
    // only confirms it runs to completion with the right shape on
    // whatever CI/Simulator host executes this test; it cannot assert a
    // specific detected/not-detected outcome, since that depends on the
    // real host environment, not a synthetic input.
    let result = MockLocationDetector.check()

    XCTAssertNotNil(result["detected"])
    XCTAssertNotNil(result["confidence"])
    XCTAssertNotNil(result["signals"])
    XCTAssertEqual(result["applicable"] as? Bool, true)
    XCTAssertNotNil(result["permissionGranted"])
    XCTAssertNotNil(result["locationAvailable"])
  }
}
