import 'dart:async';

import 'package:device_shield/device_shield.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _methods = MethodChannel('device_shield/native_bridge');
const _events = EventChannel('device_shield/events');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Answers native calls from [responses]. A value that is a Function is
  /// invoked with the call's arguments; an Exception is thrown.
  void answer(Map<String, Object?> responses) {
    messenger.setMockMethodCallHandler(_methods, (call) async {
      if (!responses.containsKey(call.method)) {
        throw MissingPluginException();
      }
      final value = responses[call.method];
      if (value is Exception) throw value;
      if (value is Function) {
        return (value as Object? Function(Object?))(call.arguments);
      }
      return value;
    });
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(_methods, null);
    messenger.setMockStreamHandler(_events, null);
    DeviceShield.callTimeout = const Duration(seconds: 5);
  });

  group('checks', () {
    test('classifies native signals by strength', () async {
      answer({
        'checkRoot': {
          'detected': true,
          'signals': ['su_binary_path', 'busybox_present'],
          'applicable': true,
        },
      });

      final result = await DeviceShield.checkRoot();

      expect(result.type, CheckType.root);
      expect(result.status, CheckStatus.detected);
      expect(result.signals, [
        const Signal('su_binary_path', SignalStrength.strong),
        const Signal('busybox_present', SignalStrength.weak),
      ]);
    });

    test("ignores the native 'detected' flag and applies the rule", () async {
      // Native code still sets detected for any signal; Dart decides.
      answer({
        'checkRoot': {
          'detected': true,
          'signals': ['dangerous_system_props'],
          'applicable': true,
        },
      });

      expect((await DeviceShield.checkRoot()).status, CheckStatus.clear);
    });

    test(
      'a check that does not exist on this platform is not applicable',
      () async {
        answer({
          'checkJailbreak': {
            'detected': false,
            'signals': <String>[],
            'applicable': false,
          },
        });

        final result = await DeviceShield.checkJailbreak();

        expect(result.status, CheckStatus.notApplicable);
        expect(result.detected, isFalse);
      },
    );

    test('a platform error is a failed check, not a throw', () async {
      answer({
        'checkEmulator': PlatformException(
          code: 'CHECK_FAILED',
          message: 'boom',
        ),
      });

      final result = await DeviceShield.checkEmulator();

      expect(result.status, CheckStatus.failed);
      expect(result.error, 'CHECK_FAILED: boom');
    });

    test('an unsupported platform is a failed check', () async {
      answer({});

      final result = await DeviceShield.checkDebugger();

      expect(result.status, CheckStatus.failed);
      expect(result.error, 'Not supported on this platform');
    });

    test('a native call that never answers times out as failed', () async {
      DeviceShield.callTimeout = const Duration(milliseconds: 20);
      answer({'checkRoot': (_) => Completer<Object?>().future});

      final result = await DeviceShield.checkRoot();

      expect(result.status, CheckStatus.failed);
      expect(result.error, startsWith('Timed out'));
    });

    test('a malformed response is a failed check', () async {
      answer({'checkRoot': 'not a map'});

      expect((await DeviceShield.checkRoot()).status, CheckStatus.failed);
    });

    test('mock location reports what the check could observe', () async {
      answer({
        'checkMockLocation': {
          'detected': true,
          'signals': ['mock_provider_flag'],
          'applicable': true,
          'permissionGranted': true,
          'locationAvailable': true,
        },
      });

      final result = await DeviceShield.checkMockLocation();

      expect(result.detected, isTrue);
      expect(result.locationPermissionGranted, isTrue);
      expect(result.locationAvailable, isTrue);
    });

    test('check() runs every check and summarises them', () async {
      answer({
        'checkRoot': {'signals': <String>[], 'applicable': true},
        'checkJailbreak': {'signals': <String>[], 'applicable': false},
        'checkEmulator': {
          'signals': ['qemu_pipe'],
        },
        'checkDebugger': PlatformException(code: 'X'),
        'checkMockLocation': {'signals': <String>[], 'applicable': true},
      });

      final report = await DeviceShield.check();

      expect(report.root.status, CheckStatus.clear);
      expect(report.jailbreak.status, CheckStatus.notApplicable);
      expect(report.emulator.status, CheckStatus.detected);
      expect(report.debugger.status, CheckStatus.failed);
      expect(report.all, hasLength(5));
      expect(report.detections.map((r) => r.type), [CheckType.emulator]);
      expect(report.anyDetected, isTrue);
      expect(report.anyFailed, isTrue);
    });
  });

  group('screen recording', () {
    test('reports the current state where supported', () async {
      answer({
        'isScreenCaptureActive': {'isCaptured': true, 'supported': true},
      });

      expect(await DeviceShield.isScreenRecorded(), isTrue);
    });

    test('is unknown where the platform has no signal', () async {
      answer({
        'isScreenCaptureActive': {'isCaptured': false, 'supported': false},
      });

      expect(await DeviceShield.isScreenRecorded(), isNull);
    });
  });

  group('protection', () {
    test('passes the requested state and reports it applied', () async {
      Object? received;
      answer({
        'setScreenshotProtection': (Object? args) {
          received = args;
          return {'applied': true};
        },
      });

      expect(
        await DeviceShield.setScreenshotProtection(true),
        ProtectionResult.applied,
      );
      expect(received, {'enabled': true});
    });

    test('reports failed when the platform could not apply it', () async {
      answer({
        'setAppSwitcherProtection': {'applied': false},
      });

      expect(
        await DeviceShield.setAppSwitcherProtection(true),
        ProtectionResult.failed,
      );
    });

    test('reports unsupported when the platform says so', () async {
      answer({
        'setScreenshotProtection': {'applied': false, 'supported': false},
      });

      expect(
        await DeviceShield.setScreenshotProtection(true),
        ProtectionResult.unsupported,
      );
    });

    test('reports unsupported on a platform without the plugin', () async {
      answer({});

      expect(
        await DeviceShield.setScreenshotProtection(true),
        ProtectionResult.unsupported,
      );
    });
  });

  group('events', () {
    void pushEvents(List<Object?> events) {
      messenger.setMockStreamHandler(
        _events,
        MockStreamHandler.inline(
          onListen: (arguments, sink) {
            // The native side never ends this stream, so neither do we.
            events.forEach(sink.success);
          },
        ),
      );
    }

    test('screenshots fire only for screenshot events', () async {
      pushEvents([
        {'callback': 'onScreenshotTaken', 'data': <String, Object?>{}},
        {
          'callback': 'onScreenCaptureStateChanged',
          'data': {'isCaptured': true},
        },
        'malformed',
        {'callback': 'onScreenshotTaken', 'data': null},
      ]);

      expect(await DeviceShield.screenshots.take(2).length, 2);
    });

    test('recording changes carry the new state', () async {
      pushEvents([
        {
          'callback': 'onScreenCaptureStateChanged',
          'data': {'isCaptured': true},
        },
        {'callback': 'onScreenshotTaken', 'data': <String, Object?>{}},
        {
          'callback': 'onScreenCaptureStateChanged',
          'data': {'isCaptured': false},
        },
      ]);

      expect(await DeviceShield.screenRecordingChanges.take(2).toList(), [
        true,
        false,
      ]);
    });
  });
}
