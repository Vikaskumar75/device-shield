import 'detector.dart';
import 'detector_registry.dart';

/// Real implementation of [DetectorRegistry].
///
/// Pure storage: a type-keyed map plus an explicit insertion-order list
/// used as the tiebreak when sorting by priority — `List.sort` is not
/// documented as stable in Dart, so registration order is tracked and
/// compared explicitly rather than relied upon implicitly.
class DefaultDetectorRegistry implements DetectorRegistry {
  final Map<String, Detector> _detectors = {};
  final List<String> _registrationOrder = [];

  @override
  void register(Detector entry) {
    if (_detectors.containsKey(entry.type)) {
      throw ArgumentError.value(
        entry.type,
        'entry.type',
        'A detector with this type is already registered',
      );
    }
    _detectors[entry.type] = entry;
    _registrationOrder.add(entry.type);
  }

  @override
  void unregister(Detector entry) {
    if (_detectors[entry.type] != entry) return;
    _detectors.remove(entry.type);
    _registrationOrder.remove(entry.type);
  }

  @override
  Detector? find(bool Function(Detector entry) predicate) {
    for (final detector in getAll()) {
      if (predicate(detector)) return detector;
    }
    return null;
  }

  @override
  List<Detector> list() => getAll();

  @override
  bool contains(String type) => _detectors.containsKey(type);

  @override
  void clear() {
    _detectors.clear();
    _registrationOrder.clear();
  }

  @override
  List<Detector> getAll() {
    final indexed = <({int index, Detector detector})>[
      for (var i = 0; i < _registrationOrder.length; i++)
        (index: i, detector: _detectors[_registrationOrder[i]]!),
    ];
    indexed.sort((a, b) {
      final byPriority = a.detector.priority.compareTo(b.detector.priority);
      return byPriority != 0 ? byPriority : a.index.compareTo(b.index);
    });
    return List.unmodifiable(indexed.map((e) => e.detector));
  }

  @override
  Detector? getById(String type) => _detectors[type];
}
