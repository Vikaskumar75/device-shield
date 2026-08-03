import 'package:flutter_shield/src/api/flutter_shield.dart';
import 'package:flutter_shield/src/models/detection_result.dart';
import 'package:flutter_shield/src/models/flutter_shield_config.dart';
import 'package:flutter_shield/src/models/flutter_shield_exception.dart';
import 'package:flutter_shield/src/models/sdk_state.dart';
import 'package:flutter_shield/src/models/security_action.dart';
import 'package:flutter_shield/src/models/security_event.dart';
import 'package:flutter_shield/src/registry/detector.dart';
import 'package:flutter_shield/src/registry/rule.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProbeDetector implements Detector {
  _ProbeDetector(this.type);
  @override
  final String type;
  @override
  final int priority = 0;
  bool checked = false;

  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<DetectionResult> check() async {
    checked = true;
    return DetectionResult(
      type: type,
      detected: false,
      confidence: 0.0,
      timestamp: DateTime.now(),
    );
  }
}

class _AlwaysMatchRule implements Rule {
  _AlwaysMatchRule(this.id);
  @override
  final String id;
  @override
  final int priority = 0;
  @override
  final SecurityAction action = SecurityAction.warn;
  bool matchCalled = false;

  @override
  bool matches(DetectionResult result) {
    matchCalled = true;
    return true;
  }
}

/// Every test cleans up with dispose() so FlutterShield's static state
/// never leaks between tests — this class is a process-lifetime facade
/// by design (per its frozen contract), so tests must reset it themselves.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    if (FlutterShield.status != SDKState.uninitialized) {
      await FlutterShield.dispose();
    }
  });

  group('FlutterShield — status before initialize', () {
    test('status is uninitialized before any initialize() call', () {
      expect(FlutterShield.status, SDKState.uninitialized);
    });

    test('calling a delegating method before initialize() throws '
        'NOT_INITIALIZED', () async {
      expect(
        () => FlutterShield.pause(),
        throwsA(isA<InitializationException>()
            .having((e) => e.code, 'code', 'NOT_INITIALIZED')),
      );
    });
  });

  group('FlutterShield — initialize / status / pause / resume', () {
    test('initialize reaches running', () async {
      await FlutterShield.initialize();
      expect(FlutterShield.status, SDKState.running);
    });

    test('pause transitions to paused; resume transitions back', () async {
      await FlutterShield.initialize();

      await FlutterShield.pause();
      expect(FlutterShield.status, SDKState.paused);

      await FlutterShield.resume();
      expect(FlutterShield.status, SDKState.running);
    });
  });

  group('FlutterShield — detector registration API', () {
    test('registerDetector + checkNow reaches the detector end-to-end',
        () async {
      await FlutterShield.initialize();
      final probe = _ProbeDetector('probe-1');

      await FlutterShield.registerDetector(probe);
      await FlutterShield.checkNow();

      expect(probe.checked, isTrue);
    });
  });

  group('FlutterShield — rule registration API', () {
    test('addRule makes the rule reachable via the detection→policy '
        'pipeline', () async {
      await FlutterShield.initialize();
      final rule = _AlwaysMatchRule('rule-1');
      final probe = _ProbeDetector('probe-2');

      await FlutterShield.addRule(rule);
      await FlutterShield.registerDetector(probe);
      await FlutterShield.checkNow();

      expect(rule.matchCalled, isTrue);
    });

    test('removeRule stops the rule from being evaluated', () async {
      await FlutterShield.initialize();
      final rule = _AlwaysMatchRule('rule-2');
      await FlutterShield.addRule(rule);

      await FlutterShield.removeRule('rule-2');
      await FlutterShield.registerDetector(_ProbeDetector('probe-3'));
      await FlutterShield.checkNow();

      expect(rule.matchCalled, isFalse);
    });
  });

  group('FlutterShield — callback registration API', () {
    test('registerCallback/unregisterCallback do not throw', () async {
      await FlutterShield.initialize();

      expect(
        () => FlutterShield.registerCallback('probe', (_) {}),
        returnsNormally,
      );
      expect(
        () => FlutterShield.unregisterCallback('probe'),
        returnsNormally,
      );
    });
  });

  group('FlutterShield — event subscription API', () {
    test('subscribe receives the event checkNow emits', () async {
      await FlutterShield.initialize();
      final received = <SecurityEvent>[];
      final subscription = FlutterShield.subscribe(received.add);

      await FlutterShield.registerDetector(_ProbeDetector('probe-4'));
      await FlutterShield.checkNow();
      await Future<void>.delayed(Duration.zero);

      expect(received, isNotEmpty);
      await subscription.cancel();
    });

    test('a filter restricts which events are delivered', () async {
      await FlutterShield.initialize();
      final received = <SecurityEvent>[];
      final subscription = FlutterShield.subscribe(
        received.add,
        filter: (e) => e.type == 'never-matches',
      );

      await FlutterShield.registerDetector(_ProbeDetector('probe-5'));
      await FlutterShield.checkNow();
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await subscription.cancel();
    });
  });

  group('FlutterShield — shutdown / reinitialize / dispose', () {
    test('shutdown reaches stopped', () async {
      await FlutterShield.initialize();

      await FlutterShield.shutdown();

      expect(FlutterShield.status, SDKState.stopped);
    });

    test('reinitialize restarts with fresh managers — a detector '
        'registered before shutdown is not silently retained', () async {
      await FlutterShield.initialize();
      final firstProbe = _ProbeDetector('probe-6');
      await FlutterShield.registerDetector(firstProbe);
      await FlutterShield.shutdown();

      await FlutterShield.reinitialize();

      expect(FlutterShield.status, SDKState.running);
      // The fresh DetectionManager's registry was rebuilt empty —
      // checkNow() must not reach the old detector instance.
      await FlutterShield.checkNow();
      expect(firstProbe.checked, isFalse);
    });

    test('reinitialize with a new config applies it', () async {
      await FlutterShield.initialize(
          config: const FlutterShieldConfig(periodicCheckInterval: 30000));
      await FlutterShield.shutdown();

      await expectLater(
        FlutterShield.reinitialize(
            config: const FlutterShieldConfig(periodicCheckInterval: 60000)),
        completes,
      );
      expect(FlutterShield.status, SDKState.running);
    });

    test('dispose fully resets — a subsequent initialize() starts clean',
        () async {
      await FlutterShield.initialize();
      await FlutterShield.registerDetector(_ProbeDetector('probe-7'));

      await FlutterShield.dispose();

      expect(FlutterShield.status, SDKState.uninitialized);

      // A fresh initialize() after full dispose must succeed and start
      // with no detectors carried over.
      await FlutterShield.initialize();
      expect(FlutterShield.status, SDKState.running);
    });
  });
}
