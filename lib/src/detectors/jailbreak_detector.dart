import '../bridge/method_codes.dart';
import '../bridge/native_bridge.dart';
import '../models/detection_result.dart';
import '../registry/detector.dart';

/// FR-02 (SRS §5.2): jailbreak detection.
/// docs/features/ROOT_JAILBREAK_DETECTION.md.
///
/// Constructible on either platform, mirroring [RootDetector]'s own
/// shape exactly (deliberately symmetric — see that class's doc comment
/// for the full reasoning behind the `'applicable'` evidence key):
///
/// - **iOS**: real signal evaluation — see
///   `ios/.../Detection/JailbreakDetector.swift`.
/// - **Android**: `{'applicable': false, 'detected': false, 'confidence':
///   0.0, 'signals': []}` — "jailbreak" is not an Android concept.
class JailbreakDetector implements Detector {
  JailbreakDetector({required this.nativeBridge});

  /// The registered `Detector.type` identifier for this built-in
  /// detector.
  static const String typeId = 'jailbreak';

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
        method: MethodCodes.checkJailbreak,
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
