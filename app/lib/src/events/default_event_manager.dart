import 'dart:async';

import '../models/security_event.dart';
import 'event_manager.dart';

/// Real, fully generic implementation of [EventManager].
///
/// Holds no knowledge of detector types or policy rules — every method
/// operates on plain [SecurityEvent]s, `String` types, and caller-supplied
/// predicates/processors. This matches the frozen dependency matrix
/// exactly: [EventManager] depends on nothing structurally, so this class
/// takes no constructor dependencies at all.
class DefaultEventManager implements EventManager {
  DefaultEventManager({this.maxHistorySize = 100});

  final int maxHistorySize;

  final StreamController<SecurityEvent> _controller =
      StreamController<SecurityEvent>.broadcast();
  final List<SecurityEvent> _history = [];
  final List<EventProcessor> _processors = [];
  final List<SecurityEvent> _queue = [];
  bool _paused = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
    _history.clear();
    _processors.clear();
    _queue.clear();
  }

  @override
  Future<void> emit(SecurityEvent event) async {
    var processed = event;
    for (final processor in _processors) {
      processed = await processor(processed);
    }
    _addToHistory(processed);
    if (_paused) {
      _queue.add(processed);
      return;
    }
    _controller.add(processed);
  }

  @override
  StreamSubscription<SecurityEvent> subscribe(
    SecurityEventHandler handler, {
    SecurityEventFilter? filter,
  }) {
    final stream =
        filter == null ? _controller.stream : _controller.stream.where(filter);
    return stream.listen((event) {
      try {
        handler(event);
      } catch (_) {
        // A subscriber's failure must never break the emitting caller or
        // any other subscriber — per this component's frozen failure
        // behavior. EventManager has no Logger dependency (frozen as a
        // leaf service with no structural dependencies), so this is a
        // deliberate silent catch, not a missed log call.
      }
    });
  }

  @override
  List<SecurityEvent> getRecentEvents({int limit = 20}) {
    final start = _history.length > limit ? _history.length - limit : 0;
    return List.unmodifiable(_history.sublist(start));
  }

  @override
  void clearHistory() => _history.clear();

  @override
  void pause() => _paused = true;

  @override
  void resume() {
    _paused = false;
    final queued = List<SecurityEvent>.of(_queue);
    _queue.clear();
    for (final event in queued) {
      _controller.add(event);
    }
  }

  @override
  void addProcessor(EventProcessor processor) => _processors.add(processor);

  void _addToHistory(SecurityEvent event) {
    _history.add(event);
    if (_history.length > maxHistorySize) {
      _history.removeAt(0);
    }
  }
}
