// Guards the package's public API surface.
//
// This file deliberately imports ONLY `package:flutter_shield/flutter_shield.dart`
// — no `package:flutter_shield/src/...` anywhere — so it fails to compile the
// moment an export a host app depends on is dropped from the barrel. Every
// other test in this suite reaches into `src/` directly (legal within the
// package, invisible to consumers), so none of them would catch that.
//
// It asserts reachability and wiring, not detector behavior; each detector's
// own test file covers what it does.

import 'package:flutter_shield/flutter_shield.dart';
import 'package:flutter_test/flutter_test.dart';

/// A host-app detector written against nothing but the public [Detector]
/// contract — proves the extension point is genuinely implementable from
/// outside the package.
class _HostDetector implements Detector {
  @override
  String get type => 'host_custom';
  @override
  int get priority => 42;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<DetectionResult> check() async => DetectionResult(
        type: type,
        detected: false,
        confidence: 0.0,
        timestamp: DateTime.now(),
        status: DetectionStatus.completed,
      );
}

/// Same, for the public [Rule] contract.
class _HostRule implements Rule {
  @override
  String get id => 'host-rule';
  @override
  int get priority => 1;
  @override
  SecurityAction get action => SecurityAction.report;
  @override
  bool matches(DetectionResult result) => result.detected;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the facade, config and state types are exported', () {
    expect(FlutterShield.status, SDKState.uninitialized);
    expect(const FlutterShieldConfig().periodicCheckInterval, isPositive);
    expect(
      const FlutterShieldConfig(debugLogging: true).copyWith().debugLogging,
      isTrue,
    );
  });

  test('all seven built-in detectors are constructible by a host app', () {
    final bridge = DefaultNativeBridge();
    addTearDown(bridge.dispose);

    final detectors = <Detector>[
      DebuggerDetector(nativeBridge: bridge),
      EmulatorDetector(nativeBridge: bridge),
      JailbreakDetector(nativeBridge: bridge),
      MockLocationDetector(nativeBridge: bridge),
      RootDetector(nativeBridge: bridge),
      ScreenRecordingDetector(nativeBridge: bridge),
      ScreenshotDetector(nativeBridge: bridge),
    ];

    expect(detectors.map((d) => d.type).toSet(), {
      'debugger',
      'emulator',
      'jailbreak',
      'mock_location',
      'root',
      'screen_recording',
      'screenshot',
    });
  });

  test('DetectorFactory exposes the same seven types by id', () {
    final bridge = DefaultNativeBridge();
    addTearDown(bridge.dispose);

    final factory = DetectorFactory(nativeBridge: bridge);
    expect(factory.availableTypes, hasLength(7));
    expect(factory.create('root'), isA<Detector>());
    expect(
      () => factory.create('nope'),
      throwsA(isA<DetectionException>()),
    );
  });

  test('Detector and Rule are implementable from outside the package', () async {
    final detector = _HostDetector();
    final result = await detector.check();

    expect(result.type, 'host_custom');
    expect(result.status, DetectionStatus.completed);
    expect(_HostRule().matches(result), isFalse);
    expect(_HostRule().action, SecurityAction.report);
  });

  test('event types and subscribe() callback signatures are exported', () {
    final event = SecurityEvent(
      type: 'root',
      timestamp: DateTime.now(),
      severity: EventSeverity.warning,
      source: 'test',
    );

    // The exact shapes FlutterShield.subscribe(handler, filter:) expects.
    const SecurityEventHandler handler = _noopHandler;
    const SecurityEventFilter filter = _alwaysTrue;

    // Field-wise, not `==`. SecurityEvent compares `data` by reference, a
    // trade-off documented deliberately on DetectionResult (avoids taking
    // on the `collection` package for deep map equality) and inherited
    // here. One consequence: fromJson(toJson(e)) is never `==` to `e`,
    // because fromJson's `.cast()` builds a new map — true even when
    // `data` is the default empty map. Asserted field-wise so this export
    // guard tests reachability, not that equality semantics.
    final restored = SecurityEvent.fromJson(event.toJson());
    expect(restored.type, event.type);
    expect(restored.timestamp, event.timestamp);
    expect(restored.severity, event.severity);
    expect(restored.source, event.source);

    expect(filter(event), isTrue);
    expect(() => handler(event), returnsNormally);
  });

  test('the exception hierarchy hosts must catch is exported', () {
    expect(
      const InitializationException(code: 'X', message: 'm'),
      isA<FlutterShieldException>(),
    );
    expect(
      const ConfigurationException(code: 'X', message: 'm'),
      isA<FlutterShieldException>(),
    );
    expect(
      const DetectionException(type: 't', code: 'X', message: 'm'),
      isA<FlutterShieldException>(),
    );
    expect(
      const NativeBridgeException(
        method: 'checkRoot',
        nativeError: 'boom',
        code: 'X',
        message: 'm',
      ),
      isA<FlutterShieldException>(),
    );
  });

  test('bridge transport types are exported', () {
    final bridge = DefaultNativeBridge();
    addTearDown(bridge.dispose);

    expect(bridge, isA<NativeBridge>());
    expect(MethodCodes.checkRoot, 'checkRoot');
  });

  test('calling the facade before initialize() throws, never crashes', () {
    expect(
      () => FlutterShield.registerDetector(_HostDetector()),
      throwsA(isA<InitializationException>()),
    );
  });
}

void _noopHandler(SecurityEvent event) {}

bool _alwaysTrue(SecurityEvent event) => true;
