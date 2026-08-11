/// One storage tier within a [MultiLevelCache] — e.g. the required
/// in-memory tier, or a future disk-backed tier. Pure storage: a
/// [CacheLevel] holds whatever it's given and hands it back unchanged: no
/// TTL bookkeeping, no eviction policy beyond whatever a level's own
/// concrete implementation needs to enforce its own capacity (see
/// `MemoryCacheLevel`'s LRU eviction). Expiration is owned entirely by
/// `MultiLevelCache`, one layer up — a level never inspects the value it
/// stores, so any `V` (including `MultiLevelCache`'s own internal
/// timestamped-entry wrapper) works unchanged.
///
/// Generic and detector-agnostic: knows nothing about `Detector`,
/// `DetectionResult`, `PolicyManager`, `EventManager`, `NativeBridge`, or
/// any Flutter type.
abstract class CacheLevel<K, V> {
  /// The stored value for [key], or `null` if this level holds none.
  V? read(K key);

  /// Stores [value] for [key], replacing any previous entry.
  void write(K key, V value);

  /// Removes the entry for [key]. Safe to call whether or not one exists.
  void delete(K key);

  /// Whether this level currently holds an entry for [key].
  bool has(K key);

  /// Removes every entry from this level.
  void wipe();

  /// A snapshot of every key currently stored — used by
  /// `MultiLevelCache.clearExpired` to sweep a level without relying on
  /// [read]'s own recency side effects.
  Iterable<K> get keys;
}
