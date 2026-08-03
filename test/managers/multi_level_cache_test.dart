import 'package:flutter_shield/src/managers/memory_cache_level.dart';
import 'package:flutter_shield/src/managers/multi_level_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MultiLevelCache — construction', () {
    test('rejects an explicit empty levels list', () {
      expect(
        () => MultiLevelCache<String, int>(levels: []),
        throwsArgumentError,
      );
    });
  });

  group('MultiLevelCache — cache hits / misses', () {
    test('get returns null for a key that was never put', () {
      final cache = MultiLevelCache<String, int>();
      expect(cache.get('a'), isNull);
    });

    test('put then get returns the stored value', () {
      final cache = MultiLevelCache<String, int>();
      cache.put('a', 42);
      expect(cache.get('a'), 42);
    });

    test('contains reflects hits and misses', () {
      final cache = MultiLevelCache<String, int>();
      cache.put('a', 1);
      expect(cache.contains('a'), isTrue);
      expect(cache.contains('b'), isFalse);
    });
  });

  group('MultiLevelCache — remove / clear', () {
    test('remove deletes only the targeted key', () {
      final cache = MultiLevelCache<String, int>();
      cache.put('a', 1);
      cache.put('b', 2);

      cache.remove('a');

      expect(cache.get('a'), isNull);
      expect(cache.get('b'), 2);
    });

    test('clear removes every entry', () {
      final cache = MultiLevelCache<String, int>();
      cache.put('a', 1);
      cache.put('b', 2);

      cache.clear();

      expect(cache.get('a'), isNull);
      expect(cache.get('b'), isNull);
    });
  });

  group('MultiLevelCache — TTL expiration and lazy expiration on read', () {
    test('a value within its TTL is still returned', () async {
      final cache = MultiLevelCache<String, int>(
        ttl: const Duration(milliseconds: 200),
      );
      cache.put('a', 1);

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(cache.get('a'), 1);
    });

    test('a value past its TTL is treated as absent on the next read '
        '(lazy expiration)', () async {
      final cache = MultiLevelCache<String, int>(
        ttl: const Duration(milliseconds: 10),
      );
      cache.put('a', 1);

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(cache.get('a'), isNull);
      expect(cache.contains('a'), isFalse);
    });

    test('clearExpired proactively removes stale entries without a read',
        () async {
      // A directly-held level reference lets this test inspect storage
      // state without going through cache.get(), which would itself lazily
      // expire the entry and make it impossible to tell whether
      // clearExpired actually did anything.
      final level = MemoryCacheLevel<String, CacheEntry<int>>();
      final cache = MultiLevelCache<String, int>(
        ttl: const Duration(milliseconds: 10),
        levels: [level],
      );
      cache.put('stale', 1);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      cache.put('fresh', 2);
      expect(level.has('stale'), isTrue); // still physically present

      cache.clearExpired();

      expect(level.has('stale'), isFalse); // proactively removed
      expect(level.has('fresh'), isTrue);
      expect(cache.get('fresh'), 2);
    });
  });

  group('MultiLevelCache — capacity limits and LRU eviction', () {
    test('capacity is enforced: the oldest, least-recently-used entry is '
        'evicted first', () {
      final cache = MultiLevelCache<String, int>(maxCapacity: 2);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3); // should evict 'a' (never touched since insertion)

      expect(cache.get('a'), isNull);
      expect(cache.get('b'), 2);
      expect(cache.get('c'), 3);
    });

    test('reading an entry protects it from eviction over one that was '
        'never re-touched', () {
      final cache = MultiLevelCache<String, int>(maxCapacity: 2);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.get('a'); // touch 'a' — now 'b' is the least recently used
      cache.put('c', 3); // should evict 'b', not 'a'

      expect(cache.get('a'), 1);
      expect(cache.get('b'), isNull);
      expect(cache.get('c'), 3);
    });
  });

  group('MemoryCacheLevel — construction and direct behavior', () {
    test('rejects a maxCapacity below 1', () {
      expect(
        () => MemoryCacheLevel<String, int>(maxCapacity: 0),
        throwsArgumentError,
      );
    });

    test('read/write/delete/has/wipe behave as a plain bounded store', () {
      final level = MemoryCacheLevel<String, int>(maxCapacity: 10);
      expect(level.has('a'), isFalse);

      level.write('a', 1);
      expect(level.has('a'), isTrue);
      expect(level.read('a'), 1);

      level.delete('a');
      expect(level.has('a'), isFalse);

      level.write('b', 2);
      level.wipe();
      expect(level.has('b'), isFalse);
    });
  });

  group('MultiLevelCache — pluggable levels (future-ready abstraction)',
      () {
    test('a custom CacheLevel can be supplied and is used for storage',
        () {
      final customLevel = MemoryCacheLevel<String, CacheEntry<int>>(
        maxCapacity: 5,
      );
      final cache = MultiLevelCache<String, int>(levels: [customLevel]);

      cache.put('a', 1);

      expect(customLevel.has('a'), isTrue);
      expect(cache.get('a'), 1);
    });
  });
}
