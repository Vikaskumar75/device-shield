import 'dart:collection';

import 'cache_level.dart';

/// The required in-memory [CacheLevel] — a bounded, LRU-evicting store.
///
/// Backed by a [LinkedHashMap], which preserves insertion order and lets
/// [read]/[write] cheaply re-insert a touched key at the end (Dart's
/// `Map` iteration/removal-then-add is how "most recently used" is
/// tracked here — no separate linked list or counters needed). Once the
/// map exceeds [maxCapacity], the entry at the front — by construction,
/// the least recently touched — is evicted.
///
/// Thread-safety note: as with `ConcurrencyController`/`DetectionCache`,
/// this assumes Dart's single-threaded, cooperative-scheduling model.
/// Every read-then-write on the backing map happens within one
/// synchronous block with no `await` in between, so no interleaving from
/// another task can ever observe a half-updated entry.
class MemoryCacheLevel<K, V> implements CacheLevel<K, V> {
  MemoryCacheLevel({this.maxCapacity = 1000}) {
    if (maxCapacity < 1) {
      throw ArgumentError.value(
        maxCapacity,
        'maxCapacity',
        'must be at least 1',
      );
    }
  }

  /// The maximum number of entries this level holds before evicting the
  /// least-recently-used one.
  final int maxCapacity;

  final LinkedHashMap<K, V> _store = LinkedHashMap<K, V>();

  @override
  V? read(K key) {
    if (!_store.containsKey(key)) return null;
    // Re-insert to move this key to the most-recently-used end.
    final value = _store.remove(key) as V;
    _store[key] = value;
    return value;
  }

  @override
  void write(K key, V value) {
    // Remove first so re-adding places it at the most-recently-used end,
    // whether or not this key already existed.
    _store.remove(key);
    _store[key] = value;
    if (_store.length > maxCapacity) {
      _store.remove(_store.keys.first);
    }
  }

  @override
  void delete(K key) => _store.remove(key);

  @override
  bool has(K key) => _store.containsKey(key);

  @override
  void wipe() => _store.clear();

  @override
  Iterable<K> get keys => List.unmodifiable(_store.keys);
}
