import 'dart:async';

import 'package:device_shield/src/managers/concurrency_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConcurrencyController — construction', () {
    test('rejects a maxConcurrent below 1', () {
      expect(
        () => ConcurrencyController(maxConcurrent: 0),
        throwsArgumentError,
      );
    });
  });

  group('ConcurrencyController — sequential execution (maxConcurrent: 1)', () {
    test('runs one item at a time, in order, never overlapping', () async {
      final controller = ConcurrencyController(maxConcurrent: 1);
      var currentlyRunning = 0;
      var maxObserved = 0;
      final startOrder = <int>[];

      final results = await controller.run<int, int>(
        items: [1, 2, 3],
        task: (item) async {
          startOrder.add(item);
          currentlyRunning++;
          maxObserved = currentlyRunning > maxObserved
              ? currentlyRunning
              : maxObserved;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          currentlyRunning--;
          return item * 10;
        },
        onError: (item, error, stackTrace) => null,
      );

      expect(maxObserved, 1);
      expect(startOrder, [1, 2, 3]);
      expect(results, [10, 20, 30]);
    });
  });

  group('ConcurrencyController — parallel execution', () {
    test('multiple items are genuinely in flight at the same time', () async {
      // Deterministic proof of concurrency, not a wall-clock race: every
      // task blocks until all 3 have started. If the controller ran them
      // one at a time, the first task would never see the third start,
      // and this would hang (caught by the test's own timeout below)
      // instead of completing.
      final controller = ConcurrencyController(maxConcurrent: 3);
      final allStarted = Completer<void>();
      var startedCount = 0;

      final results = await controller
          .run<int, int>(
            items: [1, 2, 3],
            task: (item) async {
              startedCount++;
              if (startedCount == 3) allStarted.complete();
              await allStarted.future;
              return item;
            },
            onError: (item, error, stackTrace) => null,
          )
          .timeout(const Duration(seconds: 2));

      expect(results, [1, 2, 3]);
    });

    test('performance: bounded concurrency finishes faster than running '
        'the same work one at a time', () async {
      final sequentialStopwatch = Stopwatch()..start();
      await ConcurrencyController(maxConcurrent: 1).run<int, int>(
        items: List.generate(6, (i) => i),
        task: (item) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return item;
        },
        onError: (item, error, stackTrace) => null,
      );
      sequentialStopwatch.stop();

      final concurrentStopwatch = Stopwatch()..start();
      await ConcurrencyController(maxConcurrent: 6).run<int, int>(
        items: List.generate(6, (i) => i),
        task: (item) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return item;
        },
        onError: (item, error, stackTrace) => null,
      );
      concurrentStopwatch.stop();

      // Generous margin to avoid CI-timing flakiness — the point being
      // proven is "meaningfully faster", not an exact ratio.
      expect(
        concurrentStopwatch.elapsedMilliseconds,
        lessThan(sequentialStopwatch.elapsedMilliseconds),
      );
    });
  });

  group('ConcurrencyController — maximum concurrency enforcement', () {
    test('never runs more than maxConcurrent tasks at once', () async {
      final controller = ConcurrencyController(maxConcurrent: 2);
      var currentlyRunning = 0;
      var maxObserved = 0;

      await controller.run<int, int>(
        items: List.generate(8, (i) => i),
        task: (item) async {
          currentlyRunning++;
          maxObserved = currentlyRunning > maxObserved
              ? currentlyRunning
              : maxObserved;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          currentlyRunning--;
          return item;
        },
        onError: (item, error, stackTrace) => null,
      );

      expect(maxObserved, lessThanOrEqualTo(2));
      expect(maxObserved, greaterThan(0));
    });
  });

  group('ConcurrencyController — timeout handling', () {
    test('a task exceeding timeout is routed to onError as a '
        'TimeoutException', () async {
      final controller = ConcurrencyController();
      Object? capturedError;

      final results = await controller.run<int, String>(
        items: [1],
        task: (item) => Completer<String>().future, // never completes
        timeout: const Duration(milliseconds: 20),
        onError: (item, error, stackTrace) {
          capturedError = error;
          return 'timed-out';
        },
      );

      expect(capturedError, isA<TimeoutException>());
      expect(results, ['timed-out']);
    });

    test('a fast task under the timeout is unaffected', () async {
      final controller = ConcurrencyController();

      final results = await controller.run<int, int>(
        items: [1],
        task: (item) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return item;
        },
        timeout: const Duration(milliseconds: 200),
        onError: (item, error, stackTrace) => -1,
      );

      expect(results, [1]);
    });
  });

  group('ConcurrencyController — exception isolation', () {
    test('one task throwing does not stop or corrupt the others', () async {
      final controller = ConcurrencyController(maxConcurrent: 3);
      Object? capturedError;

      final results = await controller.run<String, String>(
        items: ['good-1', 'bad', 'good-2'],
        task: (item) async {
          if (item == 'bad') throw Exception('boom');
          return item;
        },
        onError: (item, error, stackTrace) {
          capturedError = error;
          return null; // excluded, matching DetectionManager's own policy
        },
      );

      expect(results, ['good-1', 'good-2']);
      expect(capturedError, isA<Exception>());
    });
  });

  group('ConcurrencyController — deterministic result ordering', () {
    test(
      'results are ordered by input position, not completion order',
      () async {
        final controller = ConcurrencyController(maxConcurrent: 3);
        // Item 0 is the slowest, item 2 the fastest — completion order is
        // the reverse of input order.
        final delaysMs = [40, 20, 5];

        final results = await controller.run<int, int>(
          items: [0, 1, 2],
          task: (item) async {
            await Future<void>.delayed(Duration(milliseconds: delaysMs[item]));
            return item;
          },
          onError: (item, error, stackTrace) => null,
        );

        expect(results, [0, 1, 2]);
      },
    );
  });

  group('ConcurrencyController — cancellation during shutdown/dispose', () {
    test(
      'items already claimed before dispose still complete normally',
      () async {
        final controller = ConcurrencyController(maxConcurrent: 1);
        final startedItem1 = Completer<void>();
        final releaseItem1 = Completer<void>();
        final ranItem2 = <int>[];

        final future = controller.run<int, int>(
          items: [1, 2],
          task: (item) async {
            if (item == 1) {
              startedItem1.complete();
              await releaseItem1.future;
            } else {
              ranItem2.add(item);
            }
            return item;
          },
          onError: (item, error, stackTrace) => null,
        );

        await startedItem1.future;
        controller.dispose();
        releaseItem1.complete();
        final results = await future;

        // Item 1 was already claimed/started, so it completes normally.
        expect(results, contains(1));
        // Item 2 was never claimed — dispose() stopped it from starting.
        expect(ranItem2, isEmpty);
        expect(results, isNot(contains(2)));
      },
    );

    test('run() called after dispose() invokes no task at all', () async {
      final controller = ConcurrencyController()..dispose();
      var invoked = false;

      final results = await controller.run<int, int>(
        items: [1, 2, 3],
        task: (item) async {
          invoked = true;
          return item;
        },
        onError: (item, error, stackTrace) {
          expect(error, isA<StateError>());
          return null;
        },
      );

      expect(invoked, isFalse);
      expect(results, isEmpty);
    });

    test('dispose is safe to call more than once', () {
      final controller = ConcurrencyController();
      controller.dispose();
      expect(controller.dispose, returnsNormally);
    });
  });
}
