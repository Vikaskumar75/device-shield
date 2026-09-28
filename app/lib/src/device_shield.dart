import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'results.dart';

/// Runtime device-security checks and screen protections.
///
/// Every method is static and can be called at any time. There's nothing to
/// initialise. Checks never throw: a check that can't run returns
/// [CheckStatus.failed].
///
/// ```dart
/// final report = await DeviceShield.check();
/// if (report.root.detected) {
///   // e.g. hide sensitive screens or ask for extra verification
/// }
/// ```
abstract final class DeviceShield {
  static const MethodChannel _methods = MethodChannel(
    'device_shield/native_bridge',
  );
  static const EventChannel _events = EventChannel('device_shield/events');

  /// How long a native call may take before it counts as failed.
  @visibleForTesting
  static Duration callTimeout = const Duration(seconds: 5);

  /// Runs every check and returns them together. Checks that don't apply on
  /// this platform come back as [CheckStatus.notApplicable].
  static Future<SecurityReport> check() async {
    final results = await Future.wait<CheckResult>([
      checkRoot(),
      checkJailbreak(),
      checkEmulator(),
      checkDebugger(),
      checkMockLocation(),
    ]);
    return SecurityReport(
      root: results[0],
      jailbreak: results[1],
      emulator: results[2],
      debugger: results[3],
      mockLocation: results[4] as MockLocationResult,
    );
  }

  /// Checks for root access. Android only; not applicable on iOS.
  static Future<CheckResult> checkRoot() => _check(CheckType.root, 'checkRoot');

  /// Checks for a jailbreak. iOS only; not applicable on Android. Results on
  /// the iOS Simulator are unreliable.
  static Future<CheckResult> checkJailbreak() =>
      _check(CheckType.jailbreak, 'checkJailbreak');

  /// Checks whether the app runs on an Android emulator or the iOS
  /// Simulator.
  static Future<CheckResult> checkEmulator() =>
      _check(CheckType.emulator, 'checkEmulator');

  /// Checks for an attached debugger.
  static Future<CheckResult> checkDebugger() =>
      _check(CheckType.debugger, 'checkDebugger');

  /// Checks for a mocked location. Location-based signals only work if your
  /// app already holds location permission; the SDK never requests it.
  static Future<MockLocationResult> checkMockLocation() async {
    final Map<Object?, Object?> response;
    try {
      response = await _invokeMap('checkMockLocation');
    } on Object catch (error) {
      return MockLocationResult(
        status: CheckStatus.failed,
        error: _describe(error),
      );
    }
    final base = CheckResult.fromSignalIds(
      CheckType.mockLocation,
      _signalIds(response),
    );
    return MockLocationResult(
      status: base.status,
      signals: base.signals,
      locationPermissionGranted: response['permissionGranted'] == true,
      locationAvailable: response['locationAvailable'] == true,
    );
  }

  /// Whether the screen is being recorded, mirrored or shown on an external
  /// display right now. iOS only: `null` where it can't be determined.
  static Future<bool?> isScreenRecorded() async {
    try {
      final response = await _invokeMap('isScreenCaptureActive');
      if (response['supported'] != true) return null;
      return response['isCaptured'] == true;
    } on Object {
      return null;
    }
  }

  /// Fires after the user takes a screenshot while your app is in the
  /// foreground. Android 14+ and iOS; never fires elsewhere. It can't
  /// prevent the screenshot; see [setScreenshotProtection].
  static Stream<void> get screenshots => _nativeEvents
      .where((event) => event.callback == 'onScreenshotTaken')
      .map((_) {});

  /// Emits `true` when screen recording or mirroring starts and `false` when
  /// it stops. iOS only. Emits on changes, not the current state; call
  /// [isScreenRecorded] for that.
  static Stream<bool> get screenRecordingChanges => _nativeEvents
      .where((event) => event.callback == 'onScreenCaptureStateChanged')
      .map((event) => event.data['isCaptured'] == true);

  /// Blocks screenshots and screen recording of your app. On Android this is
  /// `FLAG_SECURE`, which also hides the app in Recents. See the docs site for
  /// iOS support.
  static Future<ProtectionResult> setScreenshotProtection(bool enabled) =>
      _protect('setScreenshotProtection', enabled);

  /// Hides your app's content in the app switcher / Recents screen.
  static Future<ProtectionResult> setAppSwitcherProtection(bool enabled) =>
      _protect('setAppSwitcherProtection', enabled);

  static Future<CheckResult> _check(CheckType type, String method) async {
    final Map<Object?, Object?> response;
    try {
      response = await _invokeMap(method);
    } on Object catch (error) {
      return CheckResult(
        type: type,
        status: CheckStatus.failed,
        error: _describe(error),
      );
    }
    if (response['applicable'] == false) {
      return CheckResult(type: type, status: CheckStatus.notApplicable);
    }
    return CheckResult.fromSignalIds(type, _signalIds(response));
  }

  static Future<ProtectionResult> _protect(String method, bool enabled) async {
    try {
      final response = await _invokeMap(method, {'enabled': enabled});
      if (response['supported'] == false) return ProtectionResult.unsupported;
      return response['applied'] == true
          ? ProtectionResult.applied
          : ProtectionResult.failed;
    } on MissingPluginException {
      return ProtectionResult.unsupported;
    } on Object {
      return ProtectionResult.failed;
    }
  }

  static Future<Map<Object?, Object?>> _invokeMap(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final response = await _methods
        .invokeMethod<Object?>(method, arguments)
        .timeout(callTimeout);
    if (response is! Map<Object?, Object?>) {
      throw FormatException('Unexpected response from $method: $response');
    }
    return response;
  }

  static List<String> _signalIds(Map<Object?, Object?> response) =>
      (response['signals'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList();

  static String _describe(Object error) => switch (error) {
    MissingPluginException() => 'Not supported on this platform',
    TimeoutException() => 'Timed out after ${callTimeout.inSeconds}s',
    PlatformException(:final code, :final message) =>
      message == null ? code : '$code: $message',
    _ => '$error',
  };

  // One shared native subscription: an EventChannel supports a single active
  // listener, so every public stream is derived from this one.
  static final Stream<_NativeEvent> _nativeEvents = _events
      .receiveBroadcastStream()
      .map(_NativeEvent.parse)
      .where((event) => event != null)
      .cast<_NativeEvent>();
}

class _NativeEvent {
  const _NativeEvent(this.callback, this.data);

  final String callback;
  final Map<Object?, Object?> data;

  static _NativeEvent? parse(Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    final callback = raw['callback'];
    if (callback is! String) return null;
    final data = raw['data'];
    return _NativeEvent(
      callback,
      data is Map<Object?, Object?> ? data : const {},
    );
  }
}
