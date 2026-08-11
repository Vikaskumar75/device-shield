import 'dart:async';

import '../core/logger.dart';
import '../models/detection_result.dart';
import '../models/flutter_shield_exception.dart';
import '../registry/detector.dart';
import '../registry/detector_registry.dart';
import 'concurrency_controller.dart';
import 'detection_cache.dart';
import 'detection_manager.dart';

/// Real, coordination-only implementation of [DetectionManager].
///
/// Architecture correction (Phase 6): storage is no longer an inline
/// `Map` on this class — it's delegated entirely to an injected
/// [DetectorRegistry], exactly as ARCHITECTURE_CONTRACTS.md always
/// specified (`DetectorRegistry` as `DetectionManager`'s own private,
/// owned storage component). Per Phase 4's dependency-injection pattern,
/// the registry is received through the constructor — this class never
/// constructs one itself. Public API and observable behavior are
/// unchanged, with one deliberate exception: registering two detectors
/// with the same `type` now throws (duplicate-registration prevention,
/// this phase's explicit requirement) instead of silently overwriting —
/// no existing test relied on the old silent-overwrite behavior.
///
/// Phase 9: [runAllChecks] now runs enabled detectors through a bounded
/// [ConcurrencyController] rather than one at a time, per ARCHITECTURE.md
/// §7's concurrency model. The controller (and therefore its
/// `maxConcurrent` limit) and `detectorTimeout` are both received through
/// the constructor (Phase 4's DI pattern, not read from
/// `ConfigurationManager` directly — this class still holds no reference
/// to it, matching the frozen dependency matrix exactly); the composition
/// root (`FlutterShield._registerDefaultManagers`) is what reads
/// `FlutterShieldConfig.checkTimeout` and passes the resulting primitive
/// value down.
///
/// Still holds no `NativeBridge` reference and no reference to
/// `PolicyManager` or `ConfigurationManager` — all three remain out of
/// scope / forbidden, unchanged from Phase 5.
///
/// [detectionCache] is optional and defaults to `null` (disabled) —
/// unlike [concurrencyController], which always runs (bounded concurrency
/// is transparent to callers), caching is *not* transparent: it changes
/// whether [Detector.check] is actually invoked on a given cycle. Defaulting
/// it off keeps every existing caller's observable behavior — "every
/// enabled detector runs, every cycle" — unchanged unless a cache is
/// explicitly supplied.
class DefaultDetectionManager implements DetectionManager {
  DefaultDetectionManager({
    required this.logger,
    required this.registry,
    ConcurrencyController? concurrencyController,
    this.detectorTimeout = const Duration(milliseconds: 5000),
    this.detectionCache,
  }) : concurrencyController =
            concurrencyController ?? ConcurrencyController();

  final Logger logger;
  final DetectorRegistry registry;
  final ConcurrencyController concurrencyController;

  /// When supplied, [runAllChecks] reuses a still-valid cached result
  /// instead of calling [Detector.check] again, and stores a fresh result
  /// after a detector succeeds. `null` (the default) disables caching
  /// entirely — every detector runs every cycle, exactly as before this
  /// field existed.
  final DetectionCache? detectionCache;

  /// Ceiling applied to every individual detector's [Detector.check] call
  /// during [runAllChecks] — one hung/slow detector is bounded rather than
  /// stalling the whole batch indefinitely. Defaults to
  /// `FlutterShieldConfig.checkTimeout`'s own default (5000ms) so behavior
  /// matches the config default even for callers that construct this
  /// class directly, without going through the composition root.
  final Duration detectorTimeout;

  /// The batch currently in flight, if any — reused by a reentrant
  /// [runAllChecks] call instead of starting a second, overlapping sweep
  /// over the same detectors (ROADMAP.md M6's "`_isChecking` reentrancy
  /// guard"). Cleared once the batch settles, success or failure.
  Future<List<DetectionResult>>? _inFlight;

  @override
  Future<void> initialize() async {
    for (final detector in registry.getAll()) {
      await detector.initialize();
    }
  }

  @override
  Future<void> dispose() async {
    // Stops any not-yet-started detector in an in-progress runAllChecks()
    // batch from beginning — cooperative cancellation, see
    // ConcurrencyController.dispose's own doc for exactly what this does
    // and does not guarantee.
    concurrencyController.dispose();
    detectionCache?.clear();
    for (final detector in registry.getAll()) {
      await detector.dispose();
    }
    registry.clear();
  }

  @override
  Future<List<DetectionResult>> runAllChecks() {
    // Duplicate-execution prevention: an overlapping call while a batch is
    // still in flight gets that same batch's Future rather than starting
    // a second concurrent sweep over the same detectors.
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final batch = _runAllChecks();
    _inFlight = batch;
    unawaited(batch.whenComplete(() => _inFlight = null));
    return batch;
  }

  Future<List<DetectionResult>> _runAllChecks() {
    return concurrencyController.run<Detector, DetectionResult>(
      items: registry.getAll(),
      task: (detector) => _checkWithCache(detector),
      timeout: detectorTimeout,
      onError: (detector, error, stackTrace) {
        // A single detector's failure must never fail the whole batch —
        // per this component's frozen failure behavior. Returning `null`
        // excludes it from the aggregated results, exactly like the
        // pre-Phase-9 sequential implementation did.
        logger.error(
          'Detector "${detector.type}" failed during runAllChecks',
          error: error,
          stackTrace: stackTrace,
        );
        return null;
      },
    );
  }

  /// Returns the still-valid cached result for [detector], if
  /// [detectionCache] is enabled and holds one; otherwise runs
  /// [Detector.check] and, only once it succeeds, stores the fresh result.
  /// A thrown/timed-out check is never cached — this method simply lets
  /// the exception propagate, so [ConcurrencyController]'s own catch
  /// block (via `onError` above) is what excludes it, exactly as for the
  /// no-cache path.
  Future<DetectionResult> _checkWithCache(Detector detector) async {
    final cache = detectionCache;
    if (cache == null) return detector.check();

    final cached = cache.get(detector.type);
    if (cached != null) return cached;

    final result = await detector.check();
    cache.put(detector.type, result);
    return result;
  }

  @override
  Future<DetectionResult> runCheck(String type) async {
    final detector = registry.getById(type);
    if (detector == null) {
      throw DetectionException(
        type: type,
        code: 'DETECTOR_UNAVAILABLE',
        message: 'No detector registered for type: $type',
      );
    }
    return detector.check();
  }

  @override
  Future<void> registerDetector(Detector detector) async {
    await detector.initialize();
    registry.register(detector);
  }
}
