import 'dart:async';

import 'event_channel_service.dart';
import 'method_channel_service.dart';
import 'native_bridge.dart';

/// Resolution 1 (this phase): the SDK's dedicated bridge channels — final,
/// separate from the pre-existing `device_shield` channel (Phase 1's
/// `getPlatformVersion`, kept unchanged for backward compatibility, never
/// merged or renamed).
const String kNativeBridgeMethodChannel = 'device_shield/native_bridge';
const String kNativeBridgeEventChannel = 'device_shield/events';

/// Real implementation of [NativeBridge] — the sole path any Dart code
/// takes to reach native code. See ARCHITECTURE_CONTRACTS.md Group F.
///
/// Pure transport: composes [MethodChannelService] and
/// [EventChannelService], routes [registerCallback]/[unregisterCallback]
/// requests against native-pushed events by name. Holds **no** reference
/// to `EventManager` or `SecurityEvent` — per Resolution 2, the only path
/// from native-pushed events back into the rest of the SDK is through a
/// registered callback, wired by a later phase.
class DefaultNativeBridge implements NativeBridge {
  DefaultNativeBridge({
    MethodChannelService? methodChannelService,
    EventChannelService? eventChannelService,
  }) : _methodChannelService =
           methodChannelService ??
           MethodChannelService.withName(kNativeBridgeMethodChannel),
       _eventChannelService =
           eventChannelService ??
           EventChannelService.withName(kNativeBridgeEventChannel);

  final MethodChannelService _methodChannelService;
  final EventChannelService _eventChannelService;

  final Map<String, void Function(dynamic data)> _callbacks = {};
  bool _listening = false;

  @override
  Future<T> invoke<T>({
    required String method,
    Map<String, dynamic>? arguments,
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _methodChannelService.invoke<T>(
      method: method,
      arguments: arguments,
      timeout: timeout,
    );
  }

  @override
  void invokeAsync({required String method, Map<String, dynamic>? arguments}) {
    _methodChannelService.invokeAsync(method: method, arguments: arguments);
  }

  /// Registers [callback] under [name]. Native-pushed events shaped as
  /// `{'callback': name, 'data': ...}` are routed to it — pure name-based
  /// dispatch, no interpretation of `data`'s content. Starts listening to
  /// the event channel on first registration.
  @override
  void registerCallback(String name, void Function(dynamic data) callback) {
    _callbacks[name] = callback;
    _ensureListening();
  }

  @override
  void unregisterCallback(String name) {
    _callbacks.remove(name);
  }

  void _ensureListening() {
    if (_listening) return;
    _listening = true;
    _eventChannelService.listen(_routeNativeEvent);
  }

  /// Routing only — dispatches by the `callback` key to whichever handler
  /// was registered under that name. Anything not shaped as expected
  /// (missing/non-`Map`, missing `callback` key, unregistered name) is
  /// silently dropped, matching `EventChannelService`'s own documented
  /// failure behavior: transport-level errors are handled, event
  /// *content* is never validated or interpreted here.
  void _routeNativeEvent(dynamic raw) {
    if (raw is! Map) return;
    final name = raw['callback'];
    if (name is! String) return;
    _callbacks[name]?.call(raw['data']);
  }

  /// Stops listening to native events and releases both channel services.
  @override
  Future<void> dispose() async {
    await _eventChannelService.dispose();
    _listening = false;
    _callbacks.clear();
  }
}
