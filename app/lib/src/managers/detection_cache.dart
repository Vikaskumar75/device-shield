import '../models/detection_result.dart';
import 'multi_level_cache.dart';

/// Stores the most recent [DetectionResult] per detector, honoring a
/// configurable time-to-live — the `DetectionCache` ARCHITECTURE_CONTRACTS.md
/// names as one of `DetectionManager`'s Group D dependencies ("cache
/// management" is a named responsibility there), and which ROADMAP.md's M6
/// lists as a building block.
///
/// Internally a thin wrapper over [MultiLevelCache] — ROADMAP.md's M14
/// entry reads "Generic `MultiLevelCache` (TTL-based, auto-expiry sweep)
/// ... backing `DetectionCache` from M6", which is exactly this
/// relationship: `MultiLevelCache` is the storage engine, `DetectionCache`
/// is the detector-shaped public surface on top of it. This class's own
/// public API (`get`/`put`/`remove`/`clear`/`contains`, `ttl`) and
/// observable behavior are unchanged by this refactor — `clearExpired`
/// and multi-level/LRU/capacity concerns are `MultiLevelCache`'s surface,
/// not exposed here, since nothing before this refactor needed them and
/// adding them wasn't requested.
///
/// Detector-agnostic: this class knows only [DetectionResult] and a
/// [String] key (matching `Detector.type`) — nothing about any specific
/// detector, technique, or even the `Detector` contract itself. No
/// dependency on `PolicyManager`, `EventManager`, `NativeBridge`, or any
/// Flutter widget.
///
/// Invalidation is lazy, on access: an expired entry is discarded and
/// treated as absent the moment [get] or [contains] observes it — see
/// [MultiLevelCache.get]'s own doc for the exact mechanics. This keeps the
/// cache free of any lifecycle of its own — no `Timer` to leak or for
/// [clear]/dispose callers to cancel — while still guaranteeing a caller
/// never observes a stale entry. Safe in practice because this cache holds
/// at most one entry per distinct detector ID ever stored (not one per
/// check call), so unaccessed stale entries piling up unboundedly isn't a
/// realistic growth path — well within `MultiLevelCache`'s default memory
/// capacity.
class DetectionCache {
  DetectionCache({this.ttl = const Duration(seconds: 30)})
    : _cache = MultiLevelCache<String, DetectionResult>(ttl: ttl);

  /// How long a stored result remains valid after [put].
  final Duration ttl;

  final MultiLevelCache<String, DetectionResult> _cache;

  /// The cached result for [detectorId], or `null` if there is none, or
  /// the stored entry has expired. An expired entry is removed as a side
  /// effect of this call.
  DetectionResult? get(String detectorId) => _cache.get(detectorId);

  /// Stores [result] for [detectorId], replacing any previous entry and
  /// restarting its TTL countdown from now.
  void put(String detectorId, DetectionResult result) =>
      _cache.put(detectorId, result);

  /// Removes any cached entry for [detectorId]. Safe to call whether or
  /// not one currently exists.
  void remove(String detectorId) => _cache.remove(detectorId);

  /// Removes every cached entry.
  void clear() => _cache.clear();

  /// Whether a non-expired entry exists for [detectorId]. Like [get], an
  /// expired entry is discarded as a side effect and reported as absent.
  bool contains(String detectorId) => _cache.contains(detectorId);
}
