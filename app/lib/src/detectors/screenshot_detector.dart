import '../bridge/native_bridge.dart';
import '../models/detection_result.dart';
import '../registry/detector.dart';

/// Screenshot & Screen Recording Protection —
/// doc/features/SCREENSHOT_SCREEN_RECORDING_PROTECTION.md §9.1.
///
/// Unlike `EmulatorDetector`/`DebuggerDetector`, [check] calls no native
/// method at all — verified during Step 7's architecture review that no
/// `MethodCodes` constant for polling screenshot state exists anywhere in
/// the bridge (Steps 4–6 only wired the *push* path, `onScreenshotTaken`,
/// with no corresponding method-channel handler on either platform). This
/// is not an oversight: a screenshot is a discrete past event, not a
/// stable state to poll, and the design doc's own §9.1 already frames this
/// path as secondary — "the primary, real-time path is the push
/// mechanism, not this one." [check] therefore always returns a constant,
/// honest "nothing to report here" result; it exists solely so this class
/// satisfies the [Detector] contract and can be registered/appear in the
/// standard `DetectionManager` pipeline for API consistency with every
/// other detector. The real detection mechanism is the native push path
/// `ScreenCaptureController` (a later step) wires up via
/// `NativeBridge.registerCallback`.
class ScreenshotDetector implements Detector {
  ScreenshotDetector({required this.nativeBridge});

  /// The registered `Detector.type` identifier for this built-in
  /// detector. Matches `DetectionResult.type` in every emitted result and
  /// the key `DetectorFactory` registers this class under.
  static const String typeId = 'screenshot';

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
    return DetectionResult(
      type: typeId,
      detected: false,
      confidence: 0.0,
      timestamp: DateTime.now(),
      evidence: const {'signals': <String>[]},
    );
  }
}
