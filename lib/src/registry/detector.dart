import '../models/detection_result.dart';

/// Contract every detection module implements.
///
/// A [Detector] performs one independent security check and reports its
/// finding as a [DetectionResult]. This contract intentionally knows
/// nothing about *what* any given detector checks for — see
/// ARCHITECTURE_CONTRACTS.md Group E. No detector-specific logic exists
/// here or anywhere in Phase 2.
///
/// Public/Internal: public — host apps implement this directly to register
/// a custom detector (FR-18), so it must be importable outside the SDK.
///
/// Extension point: yes — this contract, together with `DetectorRegistry`
/// (Phase 6), is the FR-18 mechanism itself.
abstract class Detector {
  /// Open, extensible identifier for this detector's check (e.g. an SDK
  /// built-in name or a host-app custom identifier).
  ///
  /// Deliberately a [String], not a closed enum — so a custom detector
  /// never requires a framework change just to add a new identifier.
  String get type;

  /// Relative execution priority within a check cycle. Lower runs first.
  int get priority;

  /// Prepares the detector for use.
  ///
  /// Called once, during `DetectionManager` initialization. A detector
  /// that throws here is excluded from subsequent check cycles rather than
  /// failing the whole batch — per this component's frozen failure
  /// behavior.
  Future<void> initialize();

  /// Performs one check and returns its result.
  ///
  /// Must not throw for expected failure modes (native timeout, permission
  /// denial, etc.) — return a [DetectionResult] with
  /// `status: DetectionStatus.failed` instead.
  Future<DetectionResult> check();

  /// Releases any resources held by this detector.
  Future<void> dispose();
}
