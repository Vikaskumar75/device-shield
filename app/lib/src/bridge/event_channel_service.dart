import 'dart:async';

import 'package:flutter/services.dart';

/// Native-originated pushes. See ARCHITECTURE_CONTRACTS.md Group F.
///
/// Wraps a single `EventChannel`: generic stream forwarding only. Per
/// Resolution 2 (this phase), this class does **not** know `EventManager`
/// or `SecurityEvent` exist — it forwards whatever raw value native code
/// sends, unmodified, with zero filtering or interpretation. The only
/// integration point back to the rest of the SDK is
/// `NativeBridge.registerCallback`/`unregisterCallback`, wired by a later
/// phase.
///
/// Owned exclusively by `NativeBridge` — never held elsewhere, per the
/// frozen contract.
class EventChannelService {
  EventChannelService(this._channel);

  EventChannelService.withName(String name) : _channel = EventChannel(name);

  final EventChannel _channel;
  StreamSubscription<dynamic>? _subscription;

  /// The raw native event stream, unfiltered and untransformed.
  Stream<dynamic> get events => _channel.receiveBroadcastStream();

  /// Begins forwarding native events to [onEvent]. A malformed or
  /// unexpected event is passed straight through — this class performs no
  /// validation of event *content*, only channel-level error handling.
  /// Replaces any previous subscription.
  void listen(
    void Function(dynamic event) onEvent, {
    void Function(Object error)? onError,
  }) {
    _subscription?.cancel();
    _subscription = events.listen(
      onEvent,
      onError: (Object error) => onError?.call(error),
      cancelOnError: false,
    );
  }

  /// Stops forwarding events. Safe to call even if [listen] was never
  /// called.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
