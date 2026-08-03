import Foundation

/// FR-03 (SRS section 5.3): emulator/simulator detection.
///
/// Unlike Android's heuristic Build-fingerprint signals, iOS exposes a
/// reliable, Apple-provided compile-time signal for "running in
/// Simulator" — `targetEnvironment(simulator)` — so this implementation
/// is exact, not heuristic, when compiled for the Simulator target: it
/// reports full confidence rather than a weighted signal count.
enum EmulatorDetector {
  static func check() -> [String: Any] {
    #if targetEnvironment(simulator)
    return [
      "detected": true,
      "confidence": 1.0,
      "signals": ["simulator_target"],
    ]
    #else
    return [
      "detected": false,
      "confidence": 0.0,
      "signals": [String](),
    ]
    #endif
  }
}
