import 'package:device_shield/src/bridge/event_channel_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = EventChannel('test/event_channel_service');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockStreamHandler(channel, null);
  });

  group('EventChannelService — stream lifecycle and forwarding', () {
    test('listen forwards raw native events unchanged', () async {
      late MockStreamHandlerEventSink sink;
      messenger.setMockStreamHandler(
        channel,
        MockStreamHandler.inline(onListen: (args, events) => sink = events),
      );
      final service = EventChannelService(channel);
      final received = <dynamic>[];

      service.listen(received.add);
      await Future<void>.delayed(Duration.zero);
      sink.success({'callback': 'onSecurityEvent', 'data': 'root'});
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single, {'callback': 'onSecurityEvent', 'data': 'root'});
    });

    test('a non-Map / malformed event is still forwarded as-is — no '
        'content validation happens here', () async {
      late MockStreamHandlerEventSink sink;
      messenger.setMockStreamHandler(
        channel,
        MockStreamHandler.inline(onListen: (args, events) => sink = events),
      );
      final service = EventChannelService(channel);
      final received = <dynamic>[];

      service.listen(received.add);
      await Future<void>.delayed(Duration.zero);
      sink.success('just a string, not a map');
      await Future<void>.delayed(Duration.zero);

      expect(received, ['just a string, not a map']);
    });

    test(
      'dispose cancels the subscription — no further events arrive',
      () async {
        var cancelled = false;
        messenger.setMockStreamHandler(
          channel,
          MockStreamHandler.inline(
            onListen: (args, events) {},
            onCancel: (args) => cancelled = true,
          ),
        );
        final service = EventChannelService(channel);
        final received = <dynamic>[];
        service.listen(received.add);
        await Future<void>.delayed(Duration.zero);

        await service.dispose();
        await Future<void>.delayed(Duration.zero);

        expect(cancelled, isTrue);
      },
    );

    test('dispose is safe to call even if listen was never called', () async {
      final service = EventChannelService(channel);
      await expectLater(service.dispose(), completes);
    });

    test('calling listen twice replaces the previous subscription', () async {
      late MockStreamHandlerEventSink sink;
      messenger.setMockStreamHandler(
        channel,
        MockStreamHandler.inline(onListen: (args, events) => sink = events),
      );
      final service = EventChannelService(channel);
      final firstReceived = <dynamic>[];
      final secondReceived = <dynamic>[];

      service.listen(firstReceived.add);
      await Future<void>.delayed(Duration.zero);
      service.listen(secondReceived.add);
      await Future<void>.delayed(Duration.zero);
      sink.success('event-after-relisten');
      await Future<void>.delayed(Duration.zero);

      expect(firstReceived, isEmpty);
      expect(secondReceived, ['event-after-relisten']);
    });

    test('a native-side error on the stream is routed to onError, not '
        'onEvent', () async {
      late MockStreamHandlerEventSink sink;
      messenger.setMockStreamHandler(
        channel,
        MockStreamHandler.inline(onListen: (args, events) => sink = events),
      );
      final service = EventChannelService(channel);
      final received = <dynamic>[];
      Object? capturedError;

      service.listen(received.add, onError: (e) => capturedError = e);
      await Future<void>.delayed(Duration.zero);
      sink.error(code: 'NATIVE_STREAM_ERROR', message: 'boom');
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      expect(capturedError, isA<PlatformException>());
    });
  });
}
