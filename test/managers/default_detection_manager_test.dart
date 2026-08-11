import 'dart:async';

import 'package:flutter_shield/src/core/console_logger.dart';
import 'package:flutter_shield/src/managers/concurrency_controller.dart';
import 'package:flutter_shield/src/managers/default_detection_manager.dart';
import 'package:flutter_shield/src/managers/detection_cache.dart';
import 'package:flutter_shield/src/models/detection_result.dart';
import 'package:flutter_shield/src/models/flutter_shield_exception.dart';
import 'package:flutter_shield/src/registry/default_detector_registry.dart';
import 'package:flutter_shield/src/registry/detector.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDetector implements Detector {
  _FakeDetector(this.type, {this.throwsOnCheck = false, this.priority = 0});

  @override
  final String type;
  @override
  final int priority;
  final bool throwsOnCheck;

  bool initialized = false;
  bool disposed = false;
  int checkCount = 0;

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<void> dispose() async => disposed = true;

  @override
  Future<DetectionResult> check() async {
    checkCount++;
    if (throwsOnCheck) throw Exception('boom');
    return DetectionResult(
      type: type,
      detected: false,
      confidence: 0.0,
      timestamp: DateTime.now(),
    );
  }
}

/// A detector whose `check()` is driven by a test-supplied closure —
/// used by the Phase 9 concurrency tests below to control exactly when
/// each detector starts/finishes, without relying on wall-clock races.
class _ControllableDetector implements Detector {
  _ControllableDetector(this.type, this.onCheck, {this.priority = 0});

  @override
  final String type;
  @override
  final int priority;
  final Future<DetectionResult> Function() onCheck;

  int checkCount = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<DetectionResult> check() {
    checkCount++;
    return onCheck();
  }
}

DetectionResult _resultFor(String type) => DetectionResult(
      type: type,
      detected: false,
      confidence: 0.0,
      timestamp: DateTime.now(),
    );

DefaultDetectionManager _buildManager({
  ConcurrencyController? concurrencyController,
  Duration? detectorTimeout,
  DetectionCache? detectionCache,
}) =>
    DefaultDetectionManager(
      logger: ConsoleLogger(),
      registry: DefaultDetectorRegistry(),
      concurrencyController: concurrencyController,
      detectorTimeout: detectorTimeout ?? const Duration(milliseconds: 5000),
      detectionCache: detectionCache,
    );

void main() {
  group('DefaultDetectionManager — coordination only, delegates storage '
      'to DetectorRegistry', () {
    test('registerDetector initializes and stores the detector', () async {
      final manager = _buildManager();
      final detector = _FakeDetector('alpha');

      await manager.registerDetector(detector);

      expect(detector.initialized, isTrue);
    });

    test('registering a duplicate type throws (Phase 6 duplicate-'
        'registration prevention)', () async {
      final manager = _buildManager();
      await manager.registerDetector(_FakeDetector('alpha'));

      expect(
        () => manager.registerDetector(_FakeDetector('alpha')),
        throwsArgumentError,
      );
    });

    test('runAllChecks calls check() on every registered detector',
        () async {
      final manager = _buildManager();
      final a = _FakeDetector('alpha');
      final b = _FakeDetector('beta');
      await manager.registerDetector(a);
      await manager.registerDetector(b);

      final results = await manager.runAllChecks();

      expect(a.checkCount, 1);
      expect(b.checkCount, 1);
      expect(results, hasLength(2));
    });

    test('runAllChecks respects the registry\'s priority ordering',
        () async {
      final manager = _buildManager();
      final low = _FakeDetector('low', priority: 10);
      final high = _FakeDetector('high', priority: 1);
      await manager.registerDetector(low);
      await manager.registerDetector(high);

      final results = await manager.runAllChecks();

      // high (priority 1) must run before low (priority 10) regardless of
      // registration order — proves DetectionManager consumes the
      // registry's ordering rather than its own.
      expect(results.map((r) => r.type), ['high', 'low']);
    });

    test('a failing detector is excluded but does not fail the batch',
        () async {
      final manager = _buildManager();
      await manager.registerDetector(_FakeDetector('good'));
      await manager.registerDetector(
          _FakeDetector('bad', throwsOnCheck: true));

      final results = await manager.runAllChecks();

      expect(results, hasLength(1));
      expect(results.single.type, 'good');
    });

    test('runCheck runs only the named detector', () async {
      final manager = _buildManager();
      final a = _FakeDetector('alpha');
      final b = _FakeDetector('beta');
      await manager.registerDetector(a);
      await manager.registerDetector(b);

      await manager.runCheck('alpha');

      expect(a.checkCount, 1);
      expect(b.checkCount, 0);
    });

    test('runCheck throws DETECTOR_UNAVAILABLE for an unknown type',
        () async {
      final manager = _buildManager();

      expect(
        () => manager.runCheck('nonexistent'),
        throwsA(isA<DetectionException>()
            .having((e) => e.code, 'code', 'DETECTOR_UNAVAILABLE')),
      );
    });

    test('dispose tears down every registered detector and clears the '
        'registry', () async {
      final manager = _buildManager();
      final a = _FakeDetector('alpha');
      await manager.registerDetector(a);

      await manager.dispose();

      expect(a.disposed, isTrue);
      expect(await manager.runAllChecks(), isEmpty);
    });
  });

  group('DefaultDetectionManager — Phase 9 bounded concurrency', () {
    test('runAllChecks runs detectors concurrently, bounded by the '
        'injected ConcurrencyController', () async {
      final manager = _buildManager(
        concurrencyController: ConcurrencyController(maxConcurrent: 3),
      );
      final allStarted = Completer<void>();
      var startedCount = 0;
      for (final type in ['a', 'b', 'c']) {
        await manager.registerDetector(_ControllableDetector(type, () async {
          startedCount++;
          if (startedCount == 3) allStarted.complete();
          // Every detector blocks until all 3 have started — only
          // possible if the manager actually dispatched them
          // concurrently rather than one at a time.
          await allStarted.future;
          return _resultFor(type);
        }));
      }

      final results =
          await manager.runAllChecks().timeout(const Duration(seconds: 2));

      expect(results.map((r) => r.type).toSet(), {'a', 'b', 'c'});
    });

    test('a detector exceeding detectorTimeout is excluded, and does not '
        'block the rest of the batch', () async {
      final manager = _buildManager(
        detectorTimeout: const Duration(milliseconds: 20),
      );
      await manager.registerDetector(
        _ControllableDetector('slow', () => Completer<DetectionResult>().future),
      );
      await manager.registerDetector(
        _ControllableDetector('fast', () async => _resultFor('fast')),
      );

      final results =
          await manager.runAllChecks().timeout(const Duration(seconds: 2));

      expect(results.map((r) => r.type), ['fast']);
    });

    test('an overlapping runAllChecks call reuses the in-flight batch '
        'instead of re-running detectors (duplicate-execution '
        'prevention)', () async {
      final manager = _buildManager();
      final release = Completer<void>();
      var checkCount = 0;
      await manager.registerDetector(_ControllableDetector('alpha', () async {
        checkCount++;
        await release.future;
        return _resultFor('alpha');
      }));

      final first = manager.runAllChecks();
      final second = manager.runAllChecks();
      release.complete();
      final firstResults = await first;
      final secondResults = await second;

      expect(checkCount, 1);
      expect(identical(first, second), isTrue);
      expect(firstResults, secondResults);
    });

    test('a fresh runAllChecks call after a batch settles runs detectors '
        'again', () async {
      final manager = _buildManager();
      final detector = _FakeDetector('alpha');
      await manager.registerDetector(detector);

      await manager.runAllChecks();
      // Lets the settled batch's whenComplete callback run before the
      // next call, so this doesn't depend on exact microtask ordering.
      await Future<void>.delayed(Duration.zero);
      await manager.runAllChecks();

      expect(detector.checkCount, 2);
    });

    test('dispose cancels not-yet-started detectors in an in-flight batch',
        () async {
      final manager = _buildManager(
        concurrencyController: ConcurrencyController(maxConcurrent: 1),
      );
      final startedFirst = Completer<void>();
      final releaseFirst = Completer<void>();
      var secondCheckCount = 0;
      await manager.registerDetector(
        _ControllableDetector('first', () async {
          startedFirst.complete();
          await releaseFirst.future;
          return _resultFor('first');
        }, priority: 0),
      );
      await manager.registerDetector(
        _ControllableDetector('second', () async {
          secondCheckCount++;
          return _resultFor('second');
        }, priority: 1),
      );

      final batch = manager.runAllChecks();
      await startedFirst.future;
      await manager.dispose();
      releaseFirst.complete();
      final results = await batch;

      expect(results.map((r) => r.type), ['first']);
      expect(secondCheckCount, 0);
    });
  });

  group('DefaultDetectionManager — DetectionCache integration', () {
    test('with no cache injected, every detector runs every cycle '
        '(caching stays fully opt-in)', () async {
      final manager = _buildManager();
      final detector = _FakeDetector('alpha');
      await manager.registerDetector(detector);

      await manager.runAllChecks();
      await manager.runAllChecks();

      expect(detector.checkCount, 2);
    });

    test('a cache hit reuses the cached result instead of calling check() '
        'again', () async {
      final cache = DetectionCache(ttl: const Duration(seconds: 30));
      final manager = _buildManager(detectionCache: cache);
      final detector = _FakeDetector('alpha');
      await manager.registerDetector(detector);

      await manager.runAllChecks();
      await manager.runAllChecks();

      // check() only actually ran once — the second cycle was served
      // entirely from the cache.
      expect(detector.checkCount, 1);
    });

    test('a cache miss (never cached) runs the detector and populates the '
        'cache', () async {
      final cache = DetectionCache();
      final manager = _buildManager(detectionCache: cache);
      final detector = _FakeDetector('alpha');
      await manager.registerDetector(detector);

      expect(cache.contains('alpha'), isFalse);
      await manager.runAllChecks();

      expect(cache.contains('alpha'), isTrue);
      expect(detector.checkCount, 1);
    });

    test('partial cache reuse: a cached detector is skipped while an '
        'uncached one still runs, in the same batch', () async {
      final cache = DetectionCache(ttl: const Duration(seconds: 30));
      cache.put('cached', _resultFor('cached'));
      final manager = _buildManager(detectionCache: cache);
      final cachedDetector = _FakeDetector('cached');
      final freshDetector = _FakeDetector('fresh');
      await manager.registerDetector(cachedDetector);
      await manager.registerDetector(freshDetector);

      final results = await manager.runAllChecks();

      expect(cachedDetector.checkCount, 0);
      expect(freshDetector.checkCount, 1);
      expect(results.map((r) => r.type).toSet(), {'cached', 'fresh'});
    });

    test('an expired cache entry is refreshed by re-running the '
        'detector', () async {
      final cache = DetectionCache(ttl: const Duration(milliseconds: 10));
      final manager = _buildManager(detectionCache: cache);
      final detector = _FakeDetector('alpha');
      await manager.registerDetector(detector);
      await manager.runAllChecks();
      expect(detector.checkCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      await manager.runAllChecks();

      expect(detector.checkCount, 2);
    });

    test('concurrent detector execution still applies the cache '
        'correctly, per detector', () async {
      final cache = DetectionCache(ttl: const Duration(seconds: 30));
      cache.put('cached', _resultFor('cached'));
      final manager = _buildManager(
        concurrencyController: ConcurrencyController(maxConcurrent: 3),
        detectionCache: cache,
      );
      final allFreshStarted = Completer<void>();
      var freshStartedCount = 0;
      for (final type in ['fresh-a', 'fresh-b']) {
        await manager.registerDetector(_ControllableDetector(type, () async {
          freshStartedCount++;
          if (freshStartedCount == 2) allFreshStarted.complete();
          await allFreshStarted.future;
          return _resultFor(type);
        }));
      }
      await manager.registerDetector(_FakeDetector('cached'));

      final results =
          await manager.runAllChecks().timeout(const Duration(seconds: 2));

      expect(results.map((r) => r.type).toSet(),
          {'cached', 'fresh-a', 'fresh-b'});
    });

    test('a failing detector is never cached', () async {
      final cache = DetectionCache();
      final manager = _buildManager(detectionCache: cache);
      await manager.registerDetector(
        _FakeDetector('bad', throwsOnCheck: true),
      );

      final results = await manager.runAllChecks();

      expect(results, isEmpty);
      expect(cache.contains('bad'), isFalse);
    });

    test('a timed-out detector is never cached', () async {
      final cache = DetectionCache();
      final manager = _buildManager(
        detectorTimeout: const Duration(milliseconds: 20),
        detectionCache: cache,
      );
      await manager.registerDetector(
        _ControllableDetector('slow', () => Completer<DetectionResult>().future),
      );

      final results =
          await manager.runAllChecks().timeout(const Duration(seconds: 2));

      expect(results, isEmpty);
      expect(cache.contains('slow'), isFalse);
    });

    test('dispose clears the cache', () async {
      final cache = DetectionCache();
      final manager = _buildManager(detectionCache: cache);
      final detector = _FakeDetector('alpha');
      await manager.registerDetector(detector);
      await manager.runAllChecks();
      expect(cache.contains('alpha'), isTrue);

      await manager.dispose();

      expect(cache.contains('alpha'), isFalse);
    });

    test('deterministic ordering is preserved with a mix of cache hits '
        'and misses', () async {
      final cache = DetectionCache(ttl: const Duration(seconds: 30));
      cache.put('high', _resultFor('high'));
      final manager = _buildManager(detectionCache: cache);
      await manager.registerDetector(_FakeDetector('low', priority: 10));
      await manager.registerDetector(_FakeDetector('high', priority: 1));

      final results = await manager.runAllChecks();

      // Registry priority ordering (high before low) still governs the
      // returned order, regardless of which entries were cache hits.
      expect(results.map((r) => r.type), ['high', 'low']);
    });
  });
}
