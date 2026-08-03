import 'dart:async';

import 'package:flutter_shield/src/bootstrap/bootstrap_context.dart';
import 'package:flutter_shield/src/bootstrap/service_container.dart';
import 'package:flutter_shield/src/bootstrap/shutdown_sequence.dart';
import 'package:flutter_shield/src/bridge/native_bridge.dart';
import 'package:flutter_shield/src/config/configuration_manager.dart';
import 'package:flutter_shield/src/core/logger.dart';
import 'package:flutter_shield/src/events/event_manager.dart';
import 'package:flutter_shield/src/managers/security_manager.dart';
import 'package:flutter_shield/src/models/flutter_shield_config.dart';
import 'package:flutter_shield/src/models/sdk_state.dart';
import 'package:flutter_shield/src/models/security_event.dart';
import 'package:flutter_shield/src/permission/permission_manager.dart';
import 'package:flutter_shield/src/state/lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test-only fakes — none carry real logic; each just records what was
/// called and in what order, via a shared [_CallLog].
class _CallLog {
  final List<String> calls = [];
}

class _FakeLogger implements Logger {
  _FakeLogger(this.log);
  final _CallLog log;

  @override
  void debug(String message, {Map<String, dynamic>? data}) {}
  @override
  void info(String message, {Map<String, dynamic>? data}) =>
      log.calls.add('Logger.info:$message');
  @override
  void warning(String message, {Map<String, dynamic>? data, Object? error}) {}
  @override
  void error(String message,
      {Map<String, dynamic>? data, Object? error, StackTrace? stackTrace}) {}
  @override
  void exception(String message, {Object? error, StackTrace? stackTrace}) {}
  @override
  void addSink(LogSink sink) {}
  @override
  void removeSink(LogSink sink) {}
}

class _FakeLifecycleManager implements LifecycleManager {
  _FakeLifecycleManager(this.log);
  final _CallLog log;

  @override
  void attach(SecurityLifecycleHandler handler) {}
  @override
  void detach() => log.calls.add('LifecycleManager.detach');
}

class _FakeSecurityManager
    implements SecurityManager, SecurityLifecycleHandler {
  _FakeSecurityManager(this.log);
  final _CallLog log;

  @override
  SDKState get status => SDKState.running;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async => log.calls.add('SecurityManager.dispose');
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> shutdown() async {}
  @override
  Future<void> checkNow() async {}
  @override
  Future<void> onResume() async {}
  @override
  Future<void> onInactive() async {}
  @override
  Future<void> onPause() async {}
  @override
  Future<void> onDetached() async {}
}

class _FakeEventManager implements EventManager {
  _FakeEventManager(this.log);
  final _CallLog log;

  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async => log.calls.add('EventManager.dispose');
  @override
  Future<void> emit(SecurityEvent event) async {}
  @override
  StreamSubscription<SecurityEvent> subscribe(
    SecurityEventHandler handler, {
    SecurityEventFilter? filter,
  }) =>
      const Stream<SecurityEvent>.empty().listen(handler);
  @override
  List<SecurityEvent> getRecentEvents({int limit = 20}) => const [];
  @override
  void clearHistory() {}
  @override
  void pause() {}
  @override
  void resume() {}
  @override
  void addProcessor(EventProcessor processor) {}
}

class _FakeNativeBridge implements NativeBridge {
  _FakeNativeBridge(this.log);
  final _CallLog log;

  @override
  Future<T> invoke<T>({
    required String method,
    Map<String, dynamic>? arguments,
    Duration timeout = const Duration(seconds: 5),
  }) async =>
      throw UnimplementedError();
  @override
  void invokeAsync({required String method, Map<String, dynamic>? arguments}) {}
  @override
  void registerCallback(String name, void Function(dynamic data) callback) {}
  @override
  void unregisterCallback(String name) {}
  @override
  Future<void> dispose() async => log.calls.add('NativeBridge.dispose');
}

class _FakeConfigurationManager implements ConfigurationManager {
  _FakeConfigurationManager(this.log);
  final _CallLog log;

  @override
  FlutterShieldConfig get current => const FlutterShieldConfig();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async =>
      log.calls.add('ConfigurationManager.dispose');
  @override
  Future<void> updateConfig(FlutterShieldConfig config) async {}
}

class _FakePermissionManager implements PermissionManager {
  _FakePermissionManager(this.log);
  final _CallLog log;

  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async => log.calls.add('PermissionManager.dispose');
  @override
  Future<void> requestPermissions(Set<String> permissions) async {}
  @override
  bool isGranted(String permission) => false;
  @override
  Set<String> get grantedPermissions => const {};
}

void main() {
  group('ShutdownSequence.run — graceful shutdown', () {
    test('detaches LifecycleManager, disposes+unregisters SecurityManager/'
        'EventManager/NativeBridge, in that order', () async {
      final log = _CallLog();
      final container = ServiceContainer();
      container.registerSingleton<LifecycleManager>(
          _FakeLifecycleManager(log));
      container.registerSingleton<SecurityManager>(
          _FakeSecurityManager(log));
      container.registerSingleton<EventManager>(_FakeEventManager(log));
      container.registerSingleton<NativeBridge>(_FakeNativeBridge(log));
      container.registerSingleton<Logger>(_FakeLogger(log));

      await const ShutdownSequence().run(container);

      expect(log.calls, [
        'LifecycleManager.detach',
        'SecurityManager.dispose',
        'EventManager.dispose',
        'NativeBridge.dispose',
        'Logger.info:Bootstrap: shutdown complete',
      ]);
      expect(container.isRegistered<SecurityManager>(), isFalse);
      expect(container.isRegistered<EventManager>(), isFalse);
      expect(container.isRegistered<NativeBridge>(), isFalse);
      // LifecycleManager persists — detached, not unregistered.
      expect(container.isRegistered<LifecycleManager>(), isTrue);
    });

    test('is a no-op for any service that was never registered', () async {
      final container = ServiceContainer();

      await expectLater(const ShutdownSequence().run(container), completes);
    });

    test('does not touch ConfigurationManager or PermissionManager — '
        'they persist across a shutdown/reinitialize cycle', () async {
      final log = _CallLog();
      final container = ServiceContainer();
      container.registerSingleton<ConfigurationManager>(
          _FakeConfigurationManager(log));
      container.registerSingleton<PermissionManager>(
          _FakePermissionManager(log));

      await const ShutdownSequence().run(container);

      expect(log.calls, isEmpty);
      expect(container.isRegistered<ConfigurationManager>(), isTrue);
      expect(container.isRegistered<PermissionManager>(), isTrue);
    });
  });

  group('ShutdownSequence.unwind — best-effort rollback', () {
    test('only tears down steps present in the completed-steps list, in '
        'reverse order', () async {
      final log = _CallLog();
      final container = ServiceContainer();
      container.registerSingleton<EventManager>(_FakeEventManager(log));
      container.registerSingleton<ConfigurationManager>(
          _FakeConfigurationManager(log));
      container.registerSingleton<PermissionManager>(
          _FakePermissionManager(log));
      final context = BootstrapContext(const FlutterShieldConfig())
        ..recordStep('Permission')
        ..recordStep('Configuration')
        ..recordStep('EventManager');

      await const ShutdownSequence().unwind(container, context);

      expect(log.calls, [
        'EventManager.dispose',
        'ConfigurationManager.dispose',
        'PermissionManager.dispose',
      ]);
    });

    test('a step recorded but with nothing registered for it is skipped '
        'silently', () async {
      final container = ServiceContainer();
      final context = BootstrapContext(const FlutterShieldConfig())
        ..recordStep('NativeBridge');

      await expectLater(
          const ShutdownSequence().unwind(container, context), completes);
    });

    test('an unrecognized step name is ignored, not thrown', () async {
      final container = ServiceContainer();
      final context = BootstrapContext(const FlutterShieldConfig())
        ..recordStep('SomeFutureStep');

      await expectLater(
          const ShutdownSequence().unwind(container, context), completes);
    });

    test('Registries is a recognized no-op step — nothing is unregistered '
        'for it', () async {
      final container = ServiceContainer();
      final context = BootstrapContext(const FlutterShieldConfig())
        ..recordStep('Registries');

      await expectLater(
          const ShutdownSequence().unwind(container, context), completes);
    });

    test('one step throwing during teardown does not stop the remaining '
        'steps from being unwound', () async {
      final log = _CallLog();
      final container = ServiceContainer();
      container.registerSingleton<NativeBridge>(_ThrowingNativeBridge());
      container.registerSingleton<EventManager>(_FakeEventManager(log));
      final context = BootstrapContext(const FlutterShieldConfig())
        ..recordStep('EventManager')
        ..recordStep('NativeBridge');

      await expectLater(
        const ShutdownSequence().unwind(container, context),
        completes,
      );
      // NativeBridge's dispose() threw, but EventManager's still ran —
      // unwind proceeds in reverse order and swallows a single step's
      // failure rather than aborting the whole rollback.
      expect(log.calls, ['EventManager.dispose']);
    });
  });
}

class _ThrowingNativeBridge implements NativeBridge {
  @override
  Future<T> invoke<T>({
    required String method,
    Map<String, dynamic>? arguments,
    Duration timeout = const Duration(seconds: 5),
  }) async =>
      throw UnimplementedError();
  @override
  void invokeAsync({required String method, Map<String, dynamic>? arguments}) {}
  @override
  void registerCallback(String name, void Function(dynamic data) callback) {}
  @override
  void unregisterCallback(String name) {}
  @override
  Future<void> dispose() async => throw StateError('dispose boom');
}
