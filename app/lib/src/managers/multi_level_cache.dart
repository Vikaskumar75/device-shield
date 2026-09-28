import 'cache_level.dart';
import 'memory_cache_level.dart';

/// Generic, reusable, detector-agnostic multi-tier cache — the component
/// ROADMAP.md's M14 names as backing `DetectionCache` (see that class's
/// own doc comment for the exact citation and sequencing reasoning).
///
/// Owns everything TTL-related — a stored value is wrapped with its
/// storage time once, here, and every [CacheLevel] beneath this class
/// stores that wrapper unchanged, so expiration behaves identically no
/// matter which level actually holds an entry. [get] checks the levels in
/// order (fastest/nearest first) and, on a hit in any level after the
/// first, promotes the entry into every faster level ahead of it — the
/// classic multi-level "promote on hit" behavior. With only the required
/// memory level configured (the default), promotion is simply a no-op,
/// but the mechanism is real, not a stub, for whenever a slower second
/// level (e.g. disk) is added later.
///
/// Independent of `DetectionManager`, `Detector`, `PolicyManager`,
/// `EventManager`, `NativeBridge`, and any Flutter type — this file
/// imports nothing beyond its own two collaborators
/// ([CacheLevel]/[MemoryCacheLevel]).
class MultiLevelCache<K, V> {
  MultiLevelCache({
    this.ttl = const Duration(seconds: 30),
    int maxCapacity = 1000,
    List<CacheLevel<K, CacheEntry<V>>>? levels,
  }) : _levels = levels ?? [MemoryCacheLevel(maxCapacity: maxCapacity)] {
    if (_levels.isEmpty) {
      throw ArgumentError.value(
        levels,
        'levels',
        'must contain at least one cache level',
      );
    }
  }

  /// How long a stored value remains valid after [put], regardless of
  /// which level holds it.
  final Duration ttl;

  final List<CacheLevel<K, CacheEntry<V>>> _levels;

  /// The cached value for [key], or `null` if no level holds one, or the
  /// entry found has expired (an expired entry is removed from every
  /// level as a side effect of this call — lazy expiration on read). A
  /// hit in any level past the first is promoted into every faster level
  /// ahead of it.
  V? get(K key) {
    for (var i = 0; i < _levels.length; i++) {
      final entry = _levels[i].read(key);
      if (entry == null) continue;
      if (_hasExpired(entry)) {
        _deleteFromEveryLevel(key);
        return null;
      }
      for (var faster = 0; faster < i; faster++) {
        _levels[faster].write(key, entry);
      }
      return entry.value;
    }
    return null;
  }

  /// Stores [value] for [key] in every level (write-through), replacing
  /// any previous entry and restarting its TTL countdown from now.
  void put(K key, V value) {
    final entry = CacheEntry(value, DateTime.now());
    for (final level in _levels) {
      level.write(key, entry);
    }
  }

  /// Removes any cached entry for [key] from every level. Safe to call
  /// whether or not one currently exists.
  void remove(K key) => _deleteFromEveryLevel(key);

  /// Whether a non-expired entry exists for [key] in any level. Reuses
  /// [get]'s own expiration-and-promotion logic rather than duplicating
  /// it, so "still valid" is decided in exactly one place.
  bool contains(K key) => get(key) != null;

  /// Removes every entry from every level.
  void clear() {
    for (final level in _levels) {
      level.wipe();
    }
  }

  /// Proactively sweeps every level for expired entries and removes them,
  /// independent of [get]'s lazy, per-read expiration — the "auto-expiry
  /// sweep" ROADMAP.md's M14 describes. Walks each level's own key list
  /// directly (not through [get], which only inspects whichever level
  /// answers first) so a stale entry sitting in a slower, not-yet-promoted
  /// level is still caught.
  void clearExpired() {
    for (final level in _levels) {
      for (final key in level.keys.toList()) {
        final entry = level.read(key);
        if (entry != null && _hasExpired(entry)) {
          level.delete(key);
        }
      }
    }
  }

  void _deleteFromEveryLevel(K key) {
    for (final level in _levels) {
      level.delete(key);
    }
  }

  bool _hasExpired(CacheEntry<V> entry) =>
      DateTime.now().difference(entry.storedAt) > ttl;
}

/// A value plus the time it was stored — the wrapper every [CacheLevel]
/// actually stores, letting [MultiLevelCache] own expiration uniformly
/// regardless of which level holds an entry. Public (not private) only so
/// a future custom [CacheLevel] implementation (e.g. a disk-backed tier)
/// can be typed against it; nothing outside this cache should construct
/// one directly.
class CacheEntry<V> {
  CacheEntry(this.value, this.storedAt);

  final V value;
  final DateTime storedAt;
}
