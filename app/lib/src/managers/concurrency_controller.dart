import 'dart:async';

/// Generic bounded-concurrency executor — the mechanism behind
/// `DetectionManager.runAllChecks()`'s "detectors run in parallel, bounded"
/// requirement (ARCHITECTURE.md §7 Concurrency Model, reserved there as
/// "Phase 9's concurrency model").
///
/// Deliberately knows nothing about `Detector`, `DetectionResult`, or any
/// other detection-specific type — [run] is generic over the item and
/// result types, so this class is reusable wherever bounded, order-
/// preserving, per-item-isolated concurrent execution is needed. Holding
/// this out of `DetectionManager` itself keeps that manager's own file
/// free of scheduling mechanics, matching the "technique-agnostic
/// framework" shape the rest of `DetectionManager` already follows.
///
/// Owned exclusively by whichever `DetectionManager` implementation
/// constructs it — never held elsewhere — the same "owned exclusively by
/// X" pattern `MethodChannelService`/`EventChannelService` already use for
/// `NativeBridge`.
class ConcurrencyController {
  ConcurrencyController({this.maxConcurrent = 4}) {
    if (maxConcurrent < 1) {
      throw ArgumentError.value(
        maxConcurrent,
        'maxConcurrent',
        'must be at least 1',
      );
    }
  }

  /// The maximum number of [run] tasks executing at any one instant.
  final int maxConcurrent;

  bool _disposed = false;

  /// Runs [task] once per entry in [items], at most [maxConcurrent] at a
  /// time, and returns results in [items]' original order — completion
  /// order never affects the returned order, so callers get deterministic
  /// aggregation regardless of which task finishes first.
  ///
  /// Each task also races against [timeout] individually, if given, so one
  /// slow task never blocks others already running in a different pool
  /// slot. [onError] is called for any task that throws (including a
  /// timeout) and its return value — nullable — replaces that item's
  /// result; returning `null` excludes the item entirely, which is how a
  /// single failing task is kept from ever failing the whole batch.
  ///
  /// If [dispose] has already been called, every item is routed straight
  /// to [onError] with a [StateError] and no task is ever invoked — a
  /// disposed controller must never be reused, matching the same
  /// "never reused after dispose" rule `NativeBridge`/`EventChannelService`
  /// already follow elsewhere in this SDK. If [dispose] is called *while*
  /// a run is in progress, no further not-yet-started items begin — this
  /// is deliberately cooperative rather than forced cancellation: Dart has
  /// no way to preempt an in-flight `Future`, so an already-started item
  /// still runs to completion (bounded by its own [timeout], the same
  /// ceiling that already existed before cancellation).
  ///
  /// Thread-safety note: this class assumes Dart's single-threaded,
  /// cooperative-scheduling model, not true multi-threading. The one
  /// shared mutable field between concurrent workers — the next-index
  /// cursor — is only ever read and incremented in a single synchronous
  /// block with no `await` between the two operations, so no two workers
  /// can ever observe or claim the same index; each result slot is written
  /// by exactly one worker, so there is no concurrent write of the same
  /// memory a lock would otherwise be needed to protect.
  Future<List<R>> run<T, R>({
    required List<T> items,
    required Future<R> Function(T item) task,
    required R? Function(T item, Object error, StackTrace stackTrace) onError,
    Duration? timeout,
  }) async {
    if (_disposed) {
      final outcomes = <R>[];
      for (final item in items) {
        final result = onError(
          item,
          StateError('ConcurrencyController has been disposed'),
          StackTrace.current,
        );
        if (result != null) outcomes.add(result);
      }
      return outcomes;
    }

    final outcomes = List<R?>.filled(items.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        if (_disposed) return;
        final index = nextIndex;
        if (index >= items.length) return;
        nextIndex++;

        final item = items[index];
        try {
          final future = task(item);
          outcomes[index] = await (timeout == null
              ? future
              : future.timeout(timeout));
        } catch (error, stackTrace) {
          outcomes[index] = onError(item, error, stackTrace);
        }
      }
    }

    final workerCount = maxConcurrent < items.length
        ? maxConcurrent
        : items.length;
    await Future.wait(List.generate(workerCount, (_) => worker()));

    return [for (final outcome in outcomes) ?outcome];
  }

  /// Marks this controller permanently unusable: no not-yet-started item
  /// in an in-progress [run] will begin, and every future [run] call
  /// returns immediately without invoking any task. Safe to call more
  /// than once.
  void dispose() {
    _disposed = true;
  }
}
