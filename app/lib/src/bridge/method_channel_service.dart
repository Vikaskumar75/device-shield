import 'dart:async';

import 'package:flutter/services.dart';

import '../models/device_shield_exception.dart';

/// Request/response native calls. See ARCHITECTURE_CONTRACTS.md Group F.
///
/// Wraps a single `MethodChannel`: transport only — no interpretation of
/// what a method call means, no detector/policy/security content. Every
/// failure mode (timeout, missing native handler, native-thrown error,
/// unexpected response type) is translated into a `NativeBridgeException`
/// so callers never see raw platform-channel exception types.
///
/// Owned exclusively by `NativeBridge` — never held elsewhere, per the
/// frozen contract.
class MethodChannelService {
  MethodChannelService(this._channel);

  MethodChannelService.withName(String name) : _channel = MethodChannel(name);

  final MethodChannel _channel;

  /// Sends [method] to native code and awaits a typed response.
  ///
  /// Throws [NativeBridgeException] for every failure mode: the call
  /// exceeding [timeout] (`BRIDGE_TIMEOUT`), no native handler registered
  /// for [method] (`BRIDGE_UNAVAILABLE`), a native-thrown
  /// [PlatformException] (code/message/details forwarded as-is), or a
  /// response that doesn't match the expected type `T`
  /// (`BRIDGE_MALFORMED_RESPONSE`).
  Future<T> invoke<T>({
    required String method,
    Map<String, dynamic>? arguments,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    dynamic result;
    try {
      result = await _channel.invokeMethod(method, arguments).timeout(timeout);
    } on TimeoutException {
      throw NativeBridgeException(
        method: method,
        nativeError: 'timeout after ${timeout.inMilliseconds}ms',
        code: 'BRIDGE_TIMEOUT',
        message: 'Method "$method" timed out after ${timeout.inSeconds}s',
      );
    } on MissingPluginException catch (e) {
      throw NativeBridgeException(
        method: method,
        nativeError: e,
        code: 'BRIDGE_UNAVAILABLE',
        message: 'No native implementation registered for method "$method"',
      );
    } on PlatformException catch (e) {
      throw NativeBridgeException(
        method: method,
        nativeError: e,
        code: e.code,
        message: e.message ?? 'Platform channel error',
        details: e.details,
      );
    }

    try {
      return result as T;
    } on TypeError catch (e) {
      throw NativeBridgeException(
        method: method,
        nativeError: e,
        code: 'BRIDGE_MALFORMED_RESPONSE',
        message: 'Native response for "$method" was not the expected type $T',
      );
    }
  }

  /// Sends [method] to native code without awaiting a response.
  /// Fire-and-forget: any failure is swallowed, matching the frozen
  /// contract's `void` return — there is no way to report it back.
  void invokeAsync({required String method, Map<String, dynamic>? arguments}) {
    unawaited(_channel.invokeMethod(method, arguments).catchError((_) => null));
  }
}
