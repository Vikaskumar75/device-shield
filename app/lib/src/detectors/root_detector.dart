import '../bridge/method_codes.dart';
import '../bridge/native_bridge.dart';
import '../models/detection_result.dart';
import '../registry/detector.dart';

/// FR-01 (SRS §5.1): root detection.
/// doc/features/ROOT_JAILBREAK_DETECTION.md.
///
/// Constructible on either platform (`DetectorFactory` is platform-
/// agnostic Dart) — the platform difference lives entirely in what
/// native sends back, the same pattern `ScreenRecordingDetector` already
/// uses:
///
/// - **Android**: real signal evaluation — see
///   `android/.../detection/RootDetector.kt`.
/// - **iOS**: `{'applicable': false, 'detected': false, 'confidence':
///   0.0, 'signals': []}` — "root" is not an iOS concept at all. This is
///   deliberately a different evidence key than `ScreenRecordingDetector`'s
///   `'supported'` — that one is an honest *capability* gap (Android
///   genuinely can't tell); this one isn't a gap, the concept structurally
///   doesn't exist on the other platform. See the design doc for the full
///   reasoning.
class RootDetector implements Detector {
  RootDetector({required this.nativeBridge});

  /// The registered `Detector.type` identifier for this built-in
  /// detector.
  static const String typeId = 'root';

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
        method: MethodCodes.checkRoot,
      );
      return DetectionResult(
        type: typeId,
        detected: response['detected'] as bool? ?? false,
        confidence: (response['confidence'] as num?)?.toDouble() ?? 0.0,
        timestamp: DateTime.now(),
        evidence: {
          'signals': response['signals'],
          'applicable': response['applicable'] as bool? ?? true,
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
