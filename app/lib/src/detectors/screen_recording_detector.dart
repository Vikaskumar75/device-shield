import '../bridge/method_codes.dart';
import '../bridge/native_bridge.dart';
import '../models/detection_result.dart';
import '../registry/detector.dart';

/// Screenshot & Screen Recording Protection —
/// docs/features/SCREENSHOT_SCREEN_RECORDING_PROTECTION.md §9.2.
///
/// Unlike `ScreenshotDetector`, [check] does call a real native method —
/// `MethodCodes.isScreenCaptureActive` — since "is the screen currently
/// captured" is continuous state, not a discrete past event, and both
/// platforms answer it (Android always honestly as unsupported, iOS with
/// a real signal). This class does not branch by platform itself; it only
/// parses whatever shape native returns, the same pattern
/// `EmulatorDetector`/`DebuggerDetector` already use — the platform
/// difference lives entirely in what native sends back:
///
/// - **iOS**: `{'isCaptured': <real bool>, 'supported': true}` — a single
///   authoritative signal, reported at full confidence like iOS's own
///   `DebuggerDetector`, never a weighted heuristic.
/// - **Android**: `{'isCaptured': false, 'supported': false, 'reason':
///   '...'}` — no reliable discrete signal exists there (design doc
///   §7.1/§13); `supported: false` is carried into [DetectionResult
///   .evidence] so a caller can distinguish "confirmed clear" from
///   "platform can't tell," never a false, confident "not recording."
class ScreenRecordingDetector implements Detector {
  ScreenRecordingDetector({required this.nativeBridge});

  /// The registered `Detector.type` identifier for this built-in
  /// detector.
  static const String typeId = 'screen_recording';

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
        method: MethodCodes.isScreenCaptureActive,
      );
      final isCaptured = response['isCaptured'] as bool? ?? false;
      return DetectionResult(
        type: typeId,
        detected: isCaptured,
        confidence: isCaptured ? 1.0 : 0.0,
        timestamp: DateTime.now(),
        evidence: {
          'isCaptured': isCaptured,
          'supported': response['supported'] as bool? ?? false,
        },
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
