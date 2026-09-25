/// FlutterShield — runtime security detection for Flutter apps.
///
/// This is the package's entire public API. Everything a host app needs is
/// exported here; nothing below `src/` should ever be imported directly.
///
/// Typical use:
///
/// ```dart
/// import 'package:flutter_shield/flutter_shield.dart';
///
/// await FlutterShield.initialize(
///   config: const FlutterShieldConfig(periodicCheckInterval: 5000),
/// );
///
/// final bridge = DefaultNativeBridge();
/// await FlutterShield.registerDetector(RootDetector(nativeBridge: bridge));
///
/// FlutterShield.subscribe((event) => print(event.type));
/// ```
///
/// Deliberately **not** exported, so the public surface only advertises what
/// is actually wired today:
///
/// - `SecurityProfile`/`DetectionConfig`/`PolicyConfig`/`ProtectionConfig` —
///   no `initialize()` overload accepts one yet, so exporting them would
///   advertise a configuration path that does nothing.
/// - `Logger`/`LogSink`/`LogLevel` — no injection point exists; logging is
///   controlled by `FlutterShieldConfig.debugLogging`.
/// - The manager/bootstrap internals (`SecurityManager`, `ServiceContainer`,
///   `ScreenCaptureController`, …) — reachable behavior is on [FlutterShield].
library;

// The SDK facade — lifecycle, registration, subscription, protection.
export 'src/api/flutter_shield.dart';

// Configuration and SDK state.
export 'src/models/flutter_shield_config.dart';
export 'src/models/sdk_state.dart';

// What a detector returns and what a policy decides.
export 'src/models/detection_result.dart';
export 'src/models/security_action.dart';
export 'src/models/security_event.dart';

// Thrown by the facade — host apps need these to catch meaningfully.
export 'src/models/flutter_shield_exception.dart';

// Extension points: implement these to add your own detection/policy.
export 'src/registry/detector.dart';
export 'src/registry/rule.dart';
export 'src/registry/detector_factory.dart';

// Handler/filter signatures for FlutterShield.subscribe(). The EventManager
// contract itself stays internal — only the callback types a caller must
// write are public.
export 'src/events/event_manager.dart'
    show SecurityEventFilter, SecurityEventHandler;

// The native transport every built-in detector is constructed with.
export 'src/bridge/native_bridge.dart';
export 'src/bridge/default_native_bridge.dart';
export 'src/bridge/method_codes.dart';

// The seven built-in detectors. None is registered automatically — a host
// app opts in per detector via FlutterShield.registerDetector.
export 'src/detectors/debugger_detector.dart';
export 'src/detectors/emulator_detector.dart';
export 'src/detectors/jailbreak_detector.dart';
export 'src/detectors/mock_location_detector.dart';
export 'src/detectors/root_detector.dart';
export 'src/detectors/screen_recording_detector.dart';
export 'src/detectors/screenshot_detector.dart';
