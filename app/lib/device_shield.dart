/// DeviceShield — runtime security detection for Flutter apps.
///
/// This is the package's entire public API. Everything a host app needs is
/// exported here; nothing below `src/` should ever be imported directly.
///
/// Typical use:
///
/// ```dart
/// import 'package:device_shield/device_shield.dart';
///
/// await DeviceShield.initialize(
///   config: const DeviceShieldConfig(periodicCheckInterval: 5000),
/// );
///
/// final bridge = DefaultNativeBridge();
/// await DeviceShield.registerDetector(RootDetector(nativeBridge: bridge));
///
/// DeviceShield.subscribe((event) => print(event.type));
/// ```
///
/// Deliberately **not** exported, so the public surface only advertises what
/// is actually wired today:
///
/// - `SecurityProfile`/`DetectionConfig`/`PolicyConfig`/`ProtectionConfig` —
///   no `initialize()` overload accepts one yet, so exporting them would
///   advertise a configuration path that does nothing.
/// - `Logger`/`LogSink`/`LogLevel` — no injection point exists; logging is
///   controlled by `DeviceShieldConfig.debugLogging`.
/// - The manager/bootstrap internals (`SecurityManager`, `ServiceContainer`,
///   `ScreenCaptureController`, …) — reachable behavior is on [DeviceShield].
library;

// The SDK facade — lifecycle, registration, subscription, protection.
export 'src/api/device_shield.dart';
export 'src/bridge/default_native_bridge.dart';
export 'src/bridge/method_codes.dart';
// The native transport every built-in detector is constructed with.
export 'src/bridge/native_bridge.dart';
// The seven built-in detectors. None is registered automatically — a host
// app opts in per detector via DeviceShield.registerDetector.
export 'src/detectors/debugger_detector.dart';
export 'src/detectors/emulator_detector.dart';
export 'src/detectors/jailbreak_detector.dart';
export 'src/detectors/mock_location_detector.dart';
export 'src/detectors/root_detector.dart';
export 'src/detectors/screen_recording_detector.dart';
export 'src/detectors/screenshot_detector.dart';
// Handler/filter signatures for DeviceShield.subscribe(). The EventManager
// contract itself stays internal — only the callback types a caller must
// write are public.
export 'src/events/event_manager.dart'
    show SecurityEventFilter, SecurityEventHandler;
// What a detector returns and what a policy decides.
export 'src/models/detection_result.dart';
// Configuration and SDK state.
export 'src/models/device_shield_config.dart';
// Thrown by the facade — host apps need these to catch meaningfully.
export 'src/models/device_shield_exception.dart';
export 'src/models/sdk_state.dart';
export 'src/models/security_action.dart';
export 'src/models/security_event.dart';
// Extension points: implement these to add your own detection/policy.
export 'src/registry/detector.dart';
export 'src/registry/detector_factory.dart';
export 'src/registry/rule.dart';
