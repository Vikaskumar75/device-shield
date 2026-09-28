import '../bridge/method_codes.dart';
import '../bridge/native_bridge.dart';
import '../models/detection_result.dart';
import '../registry/detector.dart';

/// FR-03 (SRS §5.3): emulator/simulator detection, Android + iOS — the
/// first Priority-0 built-in `Detector`, chosen as this milestone's
/// end-to-end proof of pattern specifically because it's the one P0
/// technique that's genuinely cross-platform, exercising both native
/// implementations rather than leaving one platform unvalidated.
///
/// All technique-specific logic lives on the native side — see
/// `android/.../detection/EmulatorDetector.kt` and
/// `ios/.../Detection/EmulatorDetector.swift`. This class only shapes the
/// native response into a [DetectionResult] and reports a failure as
/// [DetectionStatus.failed] rather than throwing, per the frozen
/// `Detector` contract's documented convention.
class EmulatorDetector implements Detector {
  EmulatorDetector({required this.nativeBridge});

  /// The registered `Detector.type` identifier for this built-in
  /// detector. `Detector.type` is deliberately an open `String`, not a
  /// closed enum (see `registry/detector.dart`) — `DetectorFactory` keys
  /// its registration map on this same constant rather than switching
  /// over a `DetectionType` enum.
  static const String typeId = 'emulator';

  final NativeBridge nativeBridge;

  @override
  String get type => typeId;

  @override
  int get priority => 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<DetectionResult> check() async {
    try {
      final response = await nativeBridge.invoke<Map<Object?, Object?>>(
        method: MethodCodes.checkEmulator,
      );
      return DetectionResult(
        type: typeId,
        detected: response['detected'] as bool? ?? false,
        confidence: (response['confidence'] as num?)?.toDouble() ?? 0.0,
        timestamp: DateTime.now(),
        evidence: {'signals': response['signals']},
      );
    } catch (_) {
      // Expected failure modes (native timeout, missing handler,
      // malformed response) are reported as DetectionStatus.failed —
      // never thrown — per the frozen Detector contract.
      return DetectionResult(
        type: typeId,
        detected: false,
        confidence: 0.0,
        timestamp: DateTime.now(),
        status: DetectionStatus.failed,
      );
    }
  }
}
