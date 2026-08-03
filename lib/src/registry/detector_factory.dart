import '../bridge/native_bridge.dart';
import '../detectors/debugger_detector.dart';
import '../detectors/emulator_detector.dart';
import '../models/flutter_shield_exception.dart';
import 'detector.dart';

/// Constructs the SDK's built-in detectors by their `Detector.type`
/// identifier. See ARCHITECTURE_CONTRACTS.md's Part 2 matrix, which names
/// `DetectorFactory` alongside `DetectorRegistry` as a `Detector` contract
/// dependent.
///
/// Registration-based (a `String`-keyed map of constructors), **not** a
/// `switch` over a closed `DetectionType` enum — ROADMAP.md's own M6/M7
/// wording describes "factory switch over DetectionType," but this
/// codebase's `Detector.type` is deliberately an open `String` (see
/// `registry/detector.dart`'s own doc comment: "so a custom detector never
/// requires a framework change"). A closed-enum switch would contradict
/// that design; a registration map doesn't, and needs no redesign when a
/// later milestone adds another built-in detector — just another
/// constructor registered in this class's own constructor body.
///
/// Only ever constructs *built-in* detectors. A host app's custom
/// `Detector` never goes through this factory — it's registered directly
/// via `DetectionManager.registerDetector()` (FR-18), exactly as the
/// frozen `Detector` contract already documents ("concrete instances are
/// created by `DetectorFactory` (built-in) or the host app (custom)").
///
/// Deliberately not wired into `PluginInitializer`'s boot sequence: which
/// built-in detectors should be enabled by default is a `SecurityProfile`
/// decision (M10), which doesn't exist yet — auto-registering every
/// built-in unconditionally here would preempt that not-yet-built policy.
/// Until then, this factory is a standalone utility a caller (a test, a
/// host app, or a future profile-driven step) uses explicitly.
class DetectorFactory {
  DetectorFactory({required this.nativeBridge}) {
    _register(
      EmulatorDetector.typeId,
      () => EmulatorDetector(nativeBridge: nativeBridge),
    );
    _register(
      DebuggerDetector.typeId,
      () => DebuggerDetector(nativeBridge: nativeBridge),
    );
  }

  final NativeBridge nativeBridge;
  final Map<String, Detector Function()> _constructors = {};

  void _register(String type, Detector Function() constructor) {
    _constructors[type] = constructor;
  }

  /// Every built-in `Detector.type` this factory can construct.
  Set<String> get availableTypes => Set.unmodifiable(_constructors.keys);

  /// Constructs a fresh instance of the built-in detector identified by
  /// [type].
  ///
  /// Throws [DetectionException] (`DETECTOR_TYPE_UNKNOWN`) if [type]
  /// isn't a built-in this factory knows how to construct — this includes
  /// any custom (host-app) type, since those are never registered here.
  Detector create(String type) {
    final constructor = _constructors[type];
    if (constructor == null) {
      throw DetectionException(
        type: type,
        code: 'DETECTOR_TYPE_UNKNOWN',
        message: 'No built-in detector registered for type: $type',
      );
    }
    return constructor();
  }
}
