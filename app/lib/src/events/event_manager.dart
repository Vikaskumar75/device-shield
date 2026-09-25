import 'dart:async';

import '../managers/manager.dart';
import '../models/security_event.dart';

/// Predicate used to filter which events a subscriber receives. Applied at
/// dispatch time, not at emit time — history always retains everything
/// unfiltered.
typedef SecurityEventFilter = bool Function(SecurityEvent event);

/// A subscriber's event handler.
typedef SecurityEventHandler = void Function(SecurityEvent event);

/// A pipeline stage an emitted event passes through before it reaches
/// history/dispatch (e.g. deduplication). See ARCHITECTURE.md's event
/// pipeline.
typedef EventProcessor = Future<SecurityEvent> Function(SecurityEvent event);

/// The single event bus every [SecurityEvent], from any source, passes
/// through. See ARCHITECTURE_CONTRACTS.md Group D.
///
/// `emit()` runs an event through the processor chain, appends it to a
/// bounded history, and broadcasts it to filtered subscribers. None of that
/// is implemented here — Phase 5/8 own it.
///
/// Public/Internal: internal emit path; `FlutterShield.events` is the
/// public read-only view built on top of [subscribe].
///
/// Extension point: yes — [EventProcessor] registration via [addProcessor].
abstract class EventManager implements Manager {
  Future<void> emit(SecurityEvent event);

  /// Subscribes [handler] to events matching [filter] (or all events, if
  /// `filter` is omitted). A handler that throws is caught and logged —
  /// never rethrown to the emitting caller, and never breaks other
  /// subscribers.
  StreamSubscription<SecurityEvent> subscribe(
    SecurityEventHandler handler, {
    SecurityEventFilter? filter,
  });

  List<SecurityEvent> getRecentEvents({int limit});

  void clearHistory();

  /// Queues emitted events instead of dispatching them, until [resume] is
  /// called.
  void pause();

  void resume();

  void addProcessor(EventProcessor processor);
}
