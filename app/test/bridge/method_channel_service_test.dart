import 'dart:async';

import 'package:device_shield/src/bridge/method_channel_service.dart';
import 'package:device_shield/src/models/device_shield_exception.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/method_channel_service');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('MethodChannelService — successful calls', () {
    test('invoke returns the native response, correctly typed', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => 42);
      final service = MethodChannelService(channel);

      final result = await service.invoke<int>(method: 'getValue');

      expect(result, 42);
    });

    test(
      'arguments are serialized through to the native side unchanged',
      () async {
        Map<Object?, Object?>? received;
        messenger.setMockMethodCallHandler(channel, (call) async {
          received = call.arguments as Map<Object?, Object?>?;
          return null;
        });
        final service = MethodChannelService(channel);

        await service.invoke<void>(
          method: 'doSomething',
          arguments: {
            'confidenceThreshold': 0.8,
            'techniques': ['a', 'b'],
          },
        );

        expect(received?['confidenceThreshold'], 0.8);
        expect(received?['techniques'], ['a', 'b']);
      },
    );

    test('a complex nested response deserializes correctly', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          'detected': true,
          'confidence': 0.95,
          'evidence': {
            'paths': ['/a', '/b'],
          },
        },
      );
      final service = MethodChannelService(channel);

      final result = await service.invoke<Map<Object?, Object?>>(
        method: 'check',
      );

      expect(result['detected'], true);
      expect((result['evidence'] as Map)['paths'], ['/a', '/b']);
    });

    test('null arguments and a null response both work', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.arguments, isNull);
        return null;
      });
      final service = MethodChannelService(channel);

      final result = await service.invoke<String?>(method: 'ping');

      expect(result, isNull);
    });
  });

  group('MethodChannelService — error mapping', () {
    test(
      'PlatformException maps to NativeBridgeException with the same code',
      () async {
        messenger.setMockMethodCallHandler(
          channel,
          (call) async => throw PlatformException(
            code: 'ROOT_CHECK_FAILED',
            message: 'native failure',
          ),
        );
        final service = MethodChannelService(channel);

        await expectLater(
          service.invoke<void>(method: 'check'),
          throwsA(
            isA<NativeBridgeException>()
                .having((e) => e.code, 'code', 'ROOT_CHECK_FAILED')
                .having((e) => e.message, 'message', 'native failure'),
          ),
        );
      },
    );

    test(
      'no handler registered (unknown method) maps to BRIDGE_UNAVAILABLE',
      () async {
        // No setMockMethodCallHandler call at all — the engine throws
        // MissingPluginException automatically.
        final service = MethodChannelService(channel);

        await expectLater(
          service.invoke<void>(method: 'neverImplemented'),
          throwsA(
            isA<NativeBridgeException>().having(
              (e) => e.code,
              'code',
              'BRIDGE_UNAVAILABLE',
            ),
          ),
        );
      },
    );

    test('a call exceeding the timeout maps to BRIDGE_TIMEOUT', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return 'too late';
      });
      final service = MethodChannelService(channel);

      await expectLater(
        service.invoke<String>(
          method: 'slow',
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(
          isA<NativeBridgeException>().having(
            (e) => e.code,
            'code',
            'BRIDGE_TIMEOUT',
          ),
        ),
      );
    });

    test(
      'a malformed (wrong-type) response maps to BRIDGE_MALFORMED_RESPONSE',
      () async {
        messenger.setMockMethodCallHandler(
          channel,
          (call) async => 'not a map',
        );
        final service = MethodChannelService(channel);

        await expectLater(
          service.invoke<Map<String, dynamic>>(method: 'check'),
          throwsA(
            isA<NativeBridgeException>().having(
              (e) => e.code,
              'code',
              'BRIDGE_MALFORMED_RESPONSE',
            ),
          ),
        );
      },
    );
  });

  group('MethodChannelService — invokeAsync', () {
    test('invokeAsync returns synchronously (void) without awaiting the '
        'native response', () async {
      final called = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        called.complete();
        return null;
      });
      final service = MethodChannelService(channel);

      // A void-returning call: this line completing at all (rather than
      // hanging) proves invokeAsync doesn't await the native response.
      service.invokeAsync(method: 'fireAndForget');

      await called.future.timeout(const Duration(seconds: 1));
    });

    test('invokeAsync swallows a native-side failure rather than throwing', () {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'ERR'),
      );
      final service = MethodChannelService(channel);

      expect(
        () => service.invokeAsync(method: 'fireAndForget'),
        returnsNormally,
      );
    });
  });
}
