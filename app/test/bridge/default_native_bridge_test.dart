import 'package:flutter/services.dart';
import 'package:flutter_shield/src/bridge/default_native_bridge.dart';
import 'package:flutter_shield/src/bridge/event_channel_service.dart';
import 'package:flutter_shield/src/bridge/method_channel_service.dart';
import 'package:flutter_shield/src/models/flutter_shield_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('test/default_bridge_method');
  const eventChannel = EventChannel('test/default_bridge_event');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockStreamHandler(eventChannel, null);
  });

  DefaultNativeBridge buildBridge() => DefaultNativeBridge(
        methodChannelService: MethodChannelService(methodChannel),
        eventChannelService: EventChannelService(eventChannel),
      );

  group('DefaultNativeBridge — method call delegation', () {
    test('invoke delegates to the underlying MethodChannelService',
        () async {
      messenger.setMockMethodCallHandler(
          methodChannel, (call) async => 'pong');
      final bridge = buildBridge();

      final result = await bridge.invoke<String>(method: 'ping');

      expect(result, 'pong');
    });

    test('a native failure surfaces as NativeBridgeException through the '
        'bridge, same as through MethodChannelService directly', () async {
      messenger.setMockMethodCallHandler(
        methodChannel,
        (call) async => throw PlatformException(code: 'FAILED'),
      );
      final bridge = buildBridge();

      await expectLater(
        bridge.invoke<void>(method: 'check'),
        throwsA(isA<NativeBridgeException>()
            .having((e) => e.code, 'code', 'FAILED')),
      );
    });
  });

  group('DefaultNativeBridge — callback registration and routing', () {
    test('a native event matching a registered callback name is routed to it',
        () async {
      late MockStreamHandlerEventSink sink;
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(onListen: (args, events) => sink = events),
      );
      final bridge = buildBridge();
      dynamic received;
      bridge.registerCallback('onSecurityEvent', (data) => received = data);
      await Future<void>.delayed(Duration.zero);

      sink.success({'callback': 'onSecurityEvent', 'data': 'root_detected'});
      await Future<void>.delayed(Duration.zero);

      expect(received, 'root_detected');
    });

    test('an event naming an unregistered callback is silently dropped',
        () async {
      late MockStreamHandlerEventSink sink;
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(onListen: (args, events) => sink = events),
      );
      final bridge = buildBridge();
      var called = false;
      bridge.registerCallback('known', (_) => called = true);
      await Future<void>.delayed(Duration.zero);

      sink.success({'callback': 'unknown', 'data': 'x'});
      await Future<void>.delayed(Duration.zero);

      expect(called, isFalse);
    });

    test('unregisterCallback stops routing to that name', () async {
      late MockStreamHandlerEventSink sink;
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(onListen: (args, events) => sink = events),
      );
      final bridge = buildBridge();
      var callCount = 0;
      bridge.registerCallback('probe', (_) => callCount++);
      await Future<void>.delayed(Duration.zero);
      sink.success({'callback': 'probe', 'data': null});
      await Future<void>.delayed(Duration.zero);

      bridge.unregisterCallback('probe');
      sink.success({'callback': 'probe', 'data': null});
      await Future<void>.delayed(Duration.zero);

      expect(callCount, 1);
    });

    test('a malformed native event (not a Map, or missing callback key) '
        'is dropped without throwing', () async {
      late MockStreamHandlerEventSink sink;
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(onListen: (args, events) => sink = events),
      );
      final bridge = buildBridge();
      bridge.registerCallback('probe', (_) {});
      await Future<void>.delayed(Duration.zero);

      sink.success('not a map');
      sink.success({'no_callback_key': true});
      await Future<void>.delayed(Duration.zero);
      // No exception means the malformed events were safely ignored.
    });

    test('multiple registered callbacks are each routed independently',
        () async {
      late MockStreamHandlerEventSink sink;
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(onListen: (args, events) => sink = events),
      );
      final bridge = buildBridge();
      final aEvents = <dynamic>[];
      final bEvents = <dynamic>[];
      bridge.registerCallback('a', aEvents.add);
      bridge.registerCallback('b', bEvents.add);
      await Future<void>.delayed(Duration.zero);

      sink.success({'callback': 'a', 'data': 1});
      sink.success({'callback': 'b', 'data': 2});
      await Future<void>.delayed(Duration.zero);

      expect(aEvents, [1]);
      expect(bEvents, [2]);
    });
  });

  group('DefaultNativeBridge — dispose', () {
    test('dispose stops event routing and clears callbacks', () async {
      var cancelled = false;
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (args, events) {},
          onCancel: (args) => cancelled = true,
        ),
      );
      final bridge = buildBridge();
      bridge.registerCallback('probe', (_) {});
      await Future<void>.delayed(Duration.zero);

      await bridge.dispose();

      expect(cancelled, isTrue);
    });
  });

}
