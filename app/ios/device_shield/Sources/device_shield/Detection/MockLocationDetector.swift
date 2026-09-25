import CoreLocation
import Foundation

/// FR-06: heuristic mock/spoofed GPS location detection via three
/// independent signal categories — the same signal-count confidence
/// model `JailbreakDetector`/`EmulatorDetector` already use.
/// doc/features/MOCK_LOCATION_DETECTION.md.
///
/// Unlike `checkRoot` on iOS, this never reports `applicable: false` —
/// mock location is a real concept on iOS too (jailbreak location-
/// spoofing tweaks, Xcode's debugger-attached location simulation), just
/// with weaker signals than Android: CoreLocation exposes no public
/// "this fix was mocked" flag the way `Location.isFromMockProvider()`
/// does on Android, so every iOS signal here is necessarily indirect.
///
/// Deliberately does **not** re-check jailbreak status itself — that is
/// `JailbreakDetector`'s own scope; composing signals across detectors
/// happens at the `SecurityManager` level, not by one detector calling
/// another (the same separation `JailbreakDetector` documents for not
/// duplicating FR-07's runtime-hook scanning).
enum MockLocationDetector {
  private static let spoofingTweakPaths = [
    "/Library/MobileSubstrate/DynamicLibraries/LocationFaker.plist",
    "/Library/MobileSubstrate/DynamicLibraries/fakelocation.plist",
    "/Library/MobileSubstrate/DynamicLibraries/FakeLocation.dylib",
    "/Applications/LocationFaker.app",
    "/Applications/FakeGPS.app",
  ]

  // knownSpoofingTweakArtifact, invalidLocationAccuracy, impossibleVelocity.
  private static let signalCategoryCount = 3.0

  // Same physically-implausible-speed threshold as the Android
  // implementation (~1080 km/h) — kept identical across platforms so the
  // signal means the same thing wherever it fires.
  private static let impossibleSpeedMps = 300.0
  private static let minDistanceMeters = 10.0
  private static let minTimeSeconds = 3.0

  // In-memory only, per process — reset on app restart, expected (same
  // "expected false-negative" framing RootDetector.kt documents for
  // systemless Magisk). Guarded by a private queue since `check()` could
  // in principle be invoked from more than one thread.
  private static var lastFix: (lat: Double, lon: Double, timestamp: TimeInterval)?
  private static let stateQueue = DispatchQueue(
    label: "device_shield.mock_location_detector.state")

  /// Passive read only — a manager is created and a single `location`
  /// snapshot read, never `startUpdatingLocation()`/a delegate callback.
  /// That keeps `check()` synchronous like every other detector in this
  /// SDK, at the cost of possibly finding no cached fix at all (no prior
  /// location request has ever been made in this process) — an honest
  /// `locationAvailable: false` rather than a confident "not detected".
  /// This SDK never requests location authorization itself, matching the
  /// Android side's documented no-permission-request stance.
  static func check() -> [String: Any] {
    let manager = CLLocationManager()
    let authorized = isAuthorized(manager.authorizationStatus)
    let location = authorized ? manager.location : nil

    let velocityResult =
      location.map {
        evaluateVelocity(
          lat: $0.coordinate.latitude, lon: $0.coordinate.longitude,
          timestamp: $0.timestamp.timeIntervalSince1970)
      } ?? false

    return evaluate(
      permissionGranted: authorized,
      locationAvailable: location != nil,
      knownSpoofingTweakArtifact: spoofingTweakPaths.contains {
        FileManager.default.fileExists(atPath: $0)
      },
      invalidLocationAccuracy: (location?.horizontalAccuracy ?? 0) < 0,
      impossibleVelocity: velocityResult
    )
  }

  /// Pure decision logic, separated from the real CoreLocation/
  /// FileManager reads in `check()` above so it can be unit-tested with
  /// synthetic inputs — the same split `JailbreakDetector`/
  /// `EmulatorDetector` already document for the same reason.
  static func evaluate(
    permissionGranted: Bool,
    locationAvailable: Bool,
    knownSpoofingTweakArtifact: Bool,
    invalidLocationAccuracy: Bool,
    impossibleVelocity: Bool
  ) -> [String: Any] {
    var signals: [String] = []

    if knownSpoofingTweakArtifact { signals.append("known_spoofing_tweak_artifact") }
    if invalidLocationAccuracy { signals.append("invalid_location_accuracy") }
    if impossibleVelocity { signals.append("impossible_velocity") }

    let confidence = min(Double(signals.count) / signalCategoryCount, 1.0)
    return [
      "detected": !signals.isEmpty,
      "confidence": confidence,
      "signals": signals,
      "applicable": true,
      "permissionGranted": permissionGranted,
      "locationAvailable": locationAvailable,
    ]
  }

  private static func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
    status == .authorizedWhenInUse || status == .authorizedAlways
  }

  /// Stateful by design — compares this fix against the previous
  /// `check()` call's fix on this same process. The first call ever made
  /// has nothing to compare against, so it neither fires nor counts as a
  /// clean signal; it simply seeds state for the next call. Deltas below
  /// `minDistanceMeters`/`minTimeSeconds` are ignored outright to
  /// avoid ordinary GPS jitter reading as "teleportation". A manipulated
  /// system clock could mask or inflate the computed speed either way —
  /// a known, unaddressed weak point, the same class of caveat
  /// `RootDetector.kt` documents for `build_tags_test_keys`.
  private static func evaluateVelocity(lat: Double, lon: Double, timestamp: TimeInterval) -> Bool {
    stateQueue.sync {
      defer { lastFix = (lat, lon, timestamp) }
      guard let previous = lastFix else { return false }

      let elapsedSeconds = timestamp - previous.timestamp
      guard elapsedSeconds >= minTimeSeconds else { return false }

      let distanceMeters = haversineMeters(
        lat1: previous.lat, lon1: previous.lon, lat2: lat, lon2: lon)
      guard distanceMeters >= minDistanceMeters else { return false }

      return (distanceMeters / elapsedSeconds) > impossibleSpeedMps
    }
  }

  private static func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double)
    -> Double
  {
    let earthRadiusMeters = 6_371_000.0
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let a =
      sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2)
      * sin(dLon / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return earthRadiusMeters * c
  }
}
