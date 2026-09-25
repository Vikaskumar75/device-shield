import '../bridge/method_codes.dart';
import '../bridge/native_bridge.dart';
import '../models/detection_result.dart';
import '../registry/detector.dart';

/// FR-06: mock/spoofed GPS location detection.
/// doc/features/MOCK_LOCATION_DETECTION.md.
///
/// Unlike `RootDetector`/`JailbreakDetector`, mock location is a real
/// concept on **both** platforms — `evidence['applicable']` is always
/// `true` here, never the "this concept doesn't exist on this platform"
/// signal those two use. What genuinely differs by platform is signal
/// *strength* (Android has a direct OS-level flag; iOS has none) and, on
/// Android only, whether the SDK currently holds the location permission
/// needed for the strongest signal — an honest capability gap, the same
/// `'supported'`-style pattern `ScreenRecordingDetector` already uses,
/// surfaced here as `evidence['permissionGranted']` /
/// `evidence['locationAvailable']`.
///
/// This SDK never requests the location permission itself (see the class
/// doc on `android/.../detection/MockLocationDetector.kt` for why) — it
/// only reads whatever grant state already exists, so a host app that
/// wants the strongest signal must request `ACCESS_FINE_LOCATION`/
/// `ACCESS_COARSE_LOCATION` itself, for its own reasons.
class MockLocationDetector implements Detector {
  MockLocationDetector({required this.nativeBridge});

  /// The registered `Detector.type` identifier for this built-in
  /// detector.
  static const String typeId = 'mock_location';

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
        method: MethodCodes.checkMockLocation,
      );
      return DetectionResult(
        type: typeId,
        detected: response['detected'] as bool? ?? false,
        confidence: (response['confidence'] as num?)?.toDouble() ?? 0.0,
        timestamp: DateTime.now(),
        evidence: {
          'signals': response['signals'],
          'applicable': response['applicable'] as bool? ?? true,
          'permissionGranted': response['permissionGranted'] as bool? ?? false,
          'locationAvailable': response['locationAvailable'] as bool? ?? false,
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
