import '../models/detection_result.dart';
import '../registry/detector.dart';
import 'manager.dart';

/// Framework for running registered detectors and aggregating results —
/// technique-agnostic. See ARCHITECTURE_CONTRACTS.md Group D.
///
/// Holds a `DetectorRegistry` (Phase 6) internally; runs enabled detectors
/// with bounded concurrency and a per-detector timeout (Phase 9's
/// concurrency model — see `DefaultDetectionManager`/
/// `ConcurrencyController`); optionally reuses cached results via
/// `DetectionCache` (see `DefaultDetectionManager`/`DetectionCache`),
/// disabled unless one is explicitly injected. This file itself defines
/// only the shape — the contract below is unchanged by either addition;
/// only the concrete implementation's internals did.
///
/// Public/Internal: internal. `registerDetector` is reachable publicly only
/// via `DeviceShield.registerDetector()` → `SecurityManager` → here.
///
/// Extension point: no — the extension point is `Detector` +
/// `DetectorRegistry`, not `DetectionManager` itself.
abstract class DetectionManager implements Manager {
  /// Runs every enabled detector for one check cycle.
  Future<List<DetectionResult>> runAllChecks();

  /// Runs a single detector identified by [type] on demand.
  Future<DetectionResult> runCheck(String type);

  /// Registers [detector] at runtime — the FR-18 extension path.
  Future<void> registerDetector(Detector detector);
}
