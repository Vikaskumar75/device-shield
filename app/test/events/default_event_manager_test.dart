import 'package:device_shield/src/events/default_event_manager.dart';
import 'package:device_shield/src/models/security_event.dart';
import 'package:flutter_test/flutter_test.dart';

SecurityEvent _event(
  String type, {
  EventSeverity severity = EventSeverity.info,
}) {
  return SecurityEvent(
    type: type,
    timestamp: DateTime.now(),
    severity: severity,
  );
}

void main() {
  group('DefaultEventManager — generic pub/sub', () {
    test('subscribers receive emitted events', () async {
      final manager = DefaultEventManager();
      final received = <SecurityEvent>[];
      manager.subscribe(received.add);

      await manager.emit(_event('a'));
      await Future<void>.delayed(Duration.zero);

      expect(received.map((e) => e.type), ['a']);
      await manager.dispose();
    });

    test('a filtered subscription only receives matching events', () async {
      final manager = DefaultEventManager();
      final received = <SecurityEvent>[];
      manager.subscribe(
        received.add,
        filter: (e) => e.severity == EventSeverity.critical,
      );

      await manager.emit(_event('low'));
      await manager.emit(_event('high', severity: EventSeverity.critical));
      await Future<void>.delayed(Duration.zero);

      expect(received.map((e) => e.type), ['high']);
      await manager.dispose();
    });

    test('a throwing subscriber does not affect other subscribers', () async {
      final manager = DefaultEventManager();
      final received = <SecurityEvent>[];
      manager.subscribe((e) => throw Exception('boom'));
      manager.subscribe(received.add);

      await manager.emit(_event('a'));
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      await manager.dispose();
    });

    test('history is bounded by maxHistorySize', () async {
      final manager = DefaultEventManager(maxHistorySize: 2);
      await manager.emit(_event('a'));
      await manager.emit(_event('b'));
      await manager.emit(_event('c'));

      final history = manager.getRecentEvents(limit: 10);

      expect(history.map((e) => e.type), ['b', 'c']);
      await manager.dispose();
    });

    test('clearHistory empties recorded events', () async {
      final manager = DefaultEventManager();
      await manager.emit(_event('a'));

      manager.clearHistory();

      expect(manager.getRecentEvents(), isEmpty);
      await manager.dispose();
    });

    test('pause queues events; resume flushes them in order', () async {
      final manager = DefaultEventManager();
      final received = <SecurityEvent>[];
      manager.subscribe(received.add);

      manager.pause();
      await manager.emit(_event('a'));
      await manager.emit(_event('b'));
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);

      manager.resume();
      await Future<void>.delayed(Duration.zero);

      expect(received.map((e) => e.type), ['a', 'b']);
      await manager.dispose();
    });

    test(
      'a registered processor transforms the event before dispatch',
      () async {
        final manager = DefaultEventManager();
        manager.addProcessor(
          (event) async => SecurityEvent(
            type: '${event.type}-processed',
            timestamp: event.timestamp,
            severity: event.severity,
          ),
        );
        final received = <SecurityEvent>[];
        manager.subscribe(received.add);

        await manager.emit(_event('a'));
        await Future<void>.delayed(Duration.zero);

        expect(received.single.type, 'a-processed');
        await manager.dispose();
      },
    );
  });
}
