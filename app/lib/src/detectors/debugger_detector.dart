import '../bridge/method_codes.dart';
import '../bridge/native_bridge.dart';
import '../models/detection_result.dart';
import '../registry/detector.dart';

/// FR-04 (SRS §5.4): debugger detection, Android + iOS — the second
/// Priority-0 built-in `Detector`, following `EmulatorDetector`'s exact
/// pattern: all technique-specific logic lives natively (see
/// `android/.../detection/DebuggerDetector.kt` and
/// `ios/.../Detection/DebuggerDetector.swift`), this class only shapes the
/// native response into a [DetectionResult] and reports a failure as
/// [DetectionStatus.failed] rather than throwing, per the frozen
/// `Detector` contract's documented convention.
class DebuggerDetector implements Detector {
  DebuggerDetector({required this.nativeBridge});

  /// The registered `Detector.type` identifier for this built-in
  /// detector. `Detector.type` is deliberately an open `String`, not a
  /// closed enum (see `registry/detector.dart`) — `DetectorFactory` keys
  /// its registration map on this same constant rather than switching
  /// over a closed enum.
  static const String typeId = 'debugger';

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
        method: MethodCodes.checkDebugger,
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
