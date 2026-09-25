import 'package:device_shield/src/models/detection_result.dart';
import 'package:device_shield/src/registry/default_detector_registry.dart';
import 'package:device_shield/src/registry/detector.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDetector implements Detector {
  _FakeDetector(this.type, {this.priority = 0});
  @override
  final String type;
  @override
  final int priority;

  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<DetectionResult> check() async => DetectionResult(
    type: type,
    detected: false,
    confidence: 0.0,
    timestamp: DateTime.now(),
  );
}

void main() {
  group('DefaultDetectorRegistry — register/unregister', () {
    test('register adds an entry retrievable by getById', () {
      final registry = DefaultDetectorRegistry();
      final detector = _FakeDetector('alpha');

      registry.register(detector);

      expect(registry.getById('alpha'), same(detector));
    });

    test('register throws ArgumentError on a duplicate type', () {
      final registry = DefaultDetectorRegistry();
      registry.register(_FakeDetector('alpha'));

      expect(
        () => registry.register(_FakeDetector('alpha')),
        throwsArgumentError,
      );
    });

    test('a duplicate registration attempt does not replace the original', () {
      final registry = DefaultDetectorRegistry();
      final original = _FakeDetector('alpha');
      registry.register(original);

      try {
        registry.register(_FakeDetector('alpha'));
      } catch (_) {}

      expect(registry.getById('alpha'), same(original));
    });

    test('unregister removes a previously registered detector', () {
      final registry = DefaultDetectorRegistry();
      final detector = _FakeDetector('alpha');
      registry.register(detector);

      registry.unregister(detector);

      expect(registry.contains('alpha'), isFalse);
      expect(registry.getById('alpha'), isNull);
    });

    test('unregister with an entry that was never registered is a no-op', () {
      final registry = DefaultDetectorRegistry();
      registry.register(_FakeDetector('alpha'));

      expect(
        () => registry.unregister(_FakeDetector('never-registered')),
        returnsNormally,
      );
      expect(registry.contains('alpha'), isTrue);
    });

    test('unregister does not remove a different instance with a '
        'colliding type', () {
      final registry = DefaultDetectorRegistry();
      final original = _FakeDetector('alpha');
      registry.register(original);
      final impostor = _FakeDetector('alpha');

      registry.unregister(impostor);

      expect(registry.getById('alpha'), same(original));
    });
  });

  group('DefaultDetectorRegistry — retrieval', () {
    test('contains reflects current registration state', () {
      final registry = DefaultDetectorRegistry();
      expect(registry.contains('alpha'), isFalse);

      registry.register(_FakeDetector('alpha'));
      expect(registry.contains('alpha'), isTrue);
    });

    test('getById returns null for an unregistered type', () {
      final registry = DefaultDetectorRegistry();
      expect(registry.getById('nonexistent'), isNull);
    });

    test('find returns the first entry matching the predicate', () {
      final registry = DefaultDetectorRegistry();
      registry.register(_FakeDetector('alpha', priority: 5));
      registry.register(_FakeDetector('beta', priority: 1));

      final found = registry.find((d) => d.priority == 1);

      expect(found?.type, 'beta');
    });

    test('find returns null when nothing matches', () {
      final registry = DefaultDetectorRegistry();
      registry.register(_FakeDetector('alpha'));

      expect(registry.find((d) => d.type == 'nonexistent'), isNull);
    });
  });

  group('DefaultDetectorRegistry — ordering and priority sorting', () {
    test('getAll orders by priority ascending', () {
      final registry = DefaultDetectorRegistry();
      registry.register(_FakeDetector('low', priority: 10));
      registry.register(_FakeDetector('high', priority: 1));
      registry.register(_FakeDetector('mid', priority: 5));

      final ordered = registry.getAll().map((d) => d.type).toList();

      expect(ordered, ['high', 'mid', 'low']);
    });

    test('equal priorities fall back to registration order', () {
      final registry = DefaultDetectorRegistry();
      registry.register(_FakeDetector('first'));
      registry.register(_FakeDetector('second'));
      registry.register(_FakeDetector('third'));

      final ordered = registry.getAll().map((d) => d.type).toList();

      expect(ordered, ['first', 'second', 'third']);
    });

    test('list() and getAll() return the same priority-ordered content', () {
      final registry = DefaultDetectorRegistry();
      registry.register(_FakeDetector('b', priority: 2));
      registry.register(_FakeDetector('a', priority: 1));

      expect(
        registry.list().map((d) => d.type),
        registry.getAll().map((d) => d.type),
      );
    });

    test('unregistering and re-registering resets a detector\'s position '
        'to the end', () {
      final registry = DefaultDetectorRegistry();
      final a = _FakeDetector('a');
      final b = _FakeDetector('b');
      registry.register(a);
      registry.register(b);
      registry.unregister(a);
      registry.register(a);

      final ordered = registry.getAll().map((d) => d.type).toList();

      expect(ordered, ['b', 'a']);
    });
  });

  group('DefaultDetectorRegistry — clear', () {
    test('clear removes every registered detector', () {
      final registry = DefaultDetectorRegistry();
      registry.register(_FakeDetector('a'));
      registry.register(_FakeDetector('b'));

      registry.clear();

      expect(registry.getAll(), isEmpty);
      expect(registry.contains('a'), isFalse);
    });

    test('a type can be registered again after clear without throwing', () {
      final registry = DefaultDetectorRegistry();
      registry.register(_FakeDetector('a'));
      registry.clear();

      expect(() => registry.register(_FakeDetector('a')), returnsNormally);
    });
  });

  group('DefaultDetectorRegistry — immutable returned collections', () {
    test('getAll returns a list that cannot be mutated', () {
      final registry = DefaultDetectorRegistry();
      registry.register(_FakeDetector('a'));

      final result = registry.getAll();

      expect(() => result.add(_FakeDetector('b')), throwsUnsupportedError);
      expect(result.clear, throwsUnsupportedError);
    });

    test('mutating the returned list never affects the registry\'s own '
        'state', () {
      final registry = DefaultDetectorRegistry();
      registry.register(_FakeDetector('a'));
      final firstCall = registry.getAll();

      // Even attempting a no-op reassignment of the reference can't reach
      // internal state; re-fetch to prove the registry is unaffected by
      // whatever the caller did with the previous unmodifiable view.
      registry.register(_FakeDetector('b'));
      final secondCall = registry.getAll();

      expect(firstCall, hasLength(1));
      expect(secondCall, hasLength(2));
    });
  });

  group('DefaultDetectorRegistry — edge cases', () {
    test('an empty registry returns an empty, non-null list', () {
      final registry = DefaultDetectorRegistry();
      expect(registry.getAll(), isEmpty);
      expect(registry.list(), isEmpty);
    });

    test('registering many detectors with distinct types all succeed', () {
      final registry = DefaultDetectorRegistry();
      for (var i = 0; i < 50; i++) {
        registry.register(_FakeDetector('type-$i', priority: i));
      }
      expect(registry.getAll(), hasLength(50));
      expect(registry.getAll().first.type, 'type-0');
      expect(registry.getAll().last.type, 'type-49');
    });

    test('negative priority values sort correctly before zero/positive '
        'ones', () {
      final registry = DefaultDetectorRegistry();
      registry.register(_FakeDetector('positive', priority: 5));
      registry.register(_FakeDetector('negative', priority: -5));
      registry.register(_FakeDetector('zero'));

      final ordered = registry.getAll().map((d) => d.type).toList();

      expect(ordered, ['negative', 'zero', 'positive']);
    });
  });
}
