import 'dart:async';

import 'package:device_shield/src/bootstrap/plugin_initializer.dart';
import 'package:device_shield/src/bootstrap/service_container.dart';
import 'package:device_shield/src/bridge/native_bridge.dart';
import 'package:device_shield/src/config/configuration_manager.dart';
import 'package:device_shield/src/core/logger.dart';
import 'package:device_shield/src/events/event_manager.dart';
import 'package:device_shield/src/managers/detection_manager.dart';
import 'package:device_shield/src/managers/policy_manager.dart';
import 'package:device_shield/src/managers/security_manager.dart';
import 'package:device_shield/src/models/detection_result.dart';
import 'package:device_shield/src/models/device_shield_config.dart';
import 'package:device_shield/src/models/device_shield_exception.dart';
import 'package:device_shield/src/models/sdk_state.dart';
import 'package:device_shield/src/models/security_event.dart';
import 'package:device_shield/src/permission/permission_manager.dart';
import 'package:device_shield/src/state/lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test-only fakes proving the bootstrap sequence works end-to-end once
/// every dependency is present — none of these carry real native/event/
/// manager logic; each just records that it was called.

class _FakeNativeBridge implements NativeBridge {
  bool disposed = false;

  @override
  Future<T> invoke<T>({
    required String method,
    Map<String, dynamic>? arguments,
    Duration timeout = const Duration(seconds: 5),
  }) async => throw UnimplementedError();

  @override
  void invokeAsync({required String method, Map<String, dynamic>? arguments}) {}

  @override
  void registerCallback(String name, void Function(dynamic data) callback) {}

  @override
  void unregisterCallback(String name) {}

  @override
  Future<void> dispose() async => disposed = true;
}

class _FakeEventManager implements EventManager {
  bool initialized = false;
  bool disposed = false;
  final List<SecurityEvent> emitted = [];

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<void> dispose() async => disposed = true;

  @override
  Future<void> emit(SecurityEvent event) async => emitted.add(event);

  @override
  StreamSubscription<SecurityEvent> subscribe(
    SecurityEventHandler handler, {
    SecurityEventFilter? filter,
  }) => const Stream<SecurityEvent>.empty().listen(handler);

  @override
  List<SecurityEvent> getRecentEvents({int limit = 20}) => emitted;

  @override
  void clearHistory() => emitted.clear();

  @override
  void pause() {}

  @override
  void resume() {}

  @override
  void addProcessor(EventProcessor processor) {}
}

class _FakeSecurityManager
    implements SecurityManager, SecurityLifecycleHandler {
  bool initialized = false;
  bool disposed = false;

  @override
  SDKState get status => SDKState.running;

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<void> dispose() async => disposed = true;

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> shutdown() async {}

  @override
  Future<void> checkNow() async {}

  @override
  Future<void> processResult(DetectionResult result) async {}

  @override
  Future<bool> enableScreenshotProtection() async => false;

  @override
  Future<bool> disableScreenshotProtection() async => false;

  @override
  bool get isScreenshotProtectionEnabled => false;

  @override
  Future<bool> enableAppSwitcherProtection() async => false;

  @override
  Future<bool> disableAppSwitcherProtection() async => false;

  @override
  bool get isAppSwitcherProtectionEnabled => false;

  @override
  Future<void> onResume() async {}

  @override
  Future<void> onInactive() async {}

  @override
  Future<void> onPause() async {}

  @override
  Future<void> onDetached() async {}
}

class _FakeLifecycleManager implements LifecycleManager {
  SecurityLifecycleHandler? attached;
  bool detachCalled = false;

  @override
  void attach(SecurityLifecycleHandler handler) => attached = handler;

  @override
  void detach() => detachCalled = true;
}

class _FakePermissionManager implements PermissionManager {
  bool initialized = false;
  bool disposed = false;

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<void> dispose() async => disposed = true;

  @override
  Future<void> requestPermissions(Set<String> permissions) async {}

  @override
  bool isGranted(String permission) => false;

  @override
  Set<String> get grantedPermissions => const {};
}

class _ThrowingPermissionManager implements PermissionManager {
  bool disposed = false;

  @override
  Future<void> initialize() async => throw StateError('permission boom');

  @override
  Future<void> dispose() async => disposed = true;

  @override
  Future<void> requestPermissions(Set<String> permissions) async {}

  @override
  bool isGranted(String permission) => false;

  @override
  Set<String> get grantedPermissions => const {};
}

void _registerFullDependencySet(ServiceContainer container) {
  container.registerSingleton<NativeBridge>(_FakeNativeBridge());
  container.registerSingleton<EventManager>(_FakeEventManager());
  container.registerSingleton<SecurityManager>(_FakeSecurityManager());
  container.registerSingleton<LifecycleManager>(_FakeLifecycleManager());
}

void main() {
  // Required now that PluginInitializer's default SecurityManager/
  // LifecycleManager path is exercised directly by tests that don't
  // pre-register fakes for them — DefaultLifecycleManager touches
  // WidgetsBinding.instance in attach().
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PluginInitializer — full sequence success', () {
    test('reaches running when every dependency is registered', () async {
      final container = ServiceContainer();
      _registerFullDependencySet(container);
      final initializer = PluginInitializer(container: container);

      await initializer.initialize(const DeviceShieldConfig());

      final stateManager = container.resolve<Lifecycle>();
      expect(stateManager.current, SDKState.running);

      final eventManager =
          container.resolve<EventManager>() as _FakeEventManager;
      expect(eventManager.initialized, isTrue);
      expect(eventManager.emitted, hasLength(1));
      expect(eventManager.emitted.single.type, 'initialized');

      final securityManager =
          container.resolve<SecurityManager>() as _FakeSecurityManager;
      expect(securityManager.initialized, isTrue);

      final lifecycleManager =
          container.resolve<LifecycleManager>() as _FakeLifecycleManager;
      expect(lifecycleManager.attached, isNotNull);
    });

    test(
      'defaults Logger, Configuration, and the state machine when absent',
      () async {
        final container = ServiceContainer();
        _registerFullDependencySet(container);
        // Deliberately not registering Logger/ConfigurationManager/Lifecycle —
        // PluginInitializer must construct sensible defaults for these three.
        final initializer = PluginInitializer(container: container);

        await initializer.initialize(const DeviceShieldConfig());

        expect(container.isRegistered<Lifecycle>(), isTrue);
        expect(container.isRegistered<Logger>(), isTrue);
        expect(container.isRegistered<ConfigurationManager>(), isTrue);
        expect(
          container.resolve<ConfigurationManager>().current.debugLogging,
          isFalse,
        );
      },
    );

    test(
      'boots to running from an entirely empty container — '
      'PluginInitializer now constructs every service itself, including '
      'DetectionManager/PolicyManager/SecurityManager/LifecycleManager',
      () async {
        final container = ServiceContainer();
        // Nothing pre-registered at all — every one of the nine steps must
        // default on its own, proving PluginInitializer fully owns service
        // creation rather than requiring a caller to compose the manager
        // layer beforehand.
        final initializer = PluginInitializer(container: container);

        await initializer.initialize(const DeviceShieldConfig());

        expect(container.resolve<Lifecycle>().current, SDKState.running);
        expect(container.isRegistered<PermissionManager>(), isTrue);
        expect(container.isRegistered<DetectionManager>(), isTrue);
        expect(container.isRegistered<PolicyManager>(), isTrue);
        expect(container.isRegistered<SecurityManager>(), isTrue);
        expect(container.isRegistered<LifecycleManager>(), isTrue);
        expect(container.resolve<SecurityManager>().status, SDKState.running);

        await initializer.dispose();
      },
    );
  });

  group('PluginInitializer — failure and rollback', () {
    test('rolls back to failure when a pre-registered SecurityManager '
        'factory throws mid-boot', () async {
      final container = ServiceContainer();
      container.registerSingleton<NativeBridge>(_FakeNativeBridge());
      final eventManager = _FakeEventManager();
      container.registerSingleton<EventManager>(eventManager);
      // A broken pre-registration (not a missing one) is what now forces
      // a failure at the Managers step — every service defaults on its
      // own since the construction-ownership fix, so a caller has to
      // supply something that actively fails to exercise this path.
      container.registerLazySingleton<SecurityManager>(
        () => throw Exception('boom'),
      );
      final initializer = PluginInitializer(container: container);

      await expectLater(
        initializer.initialize(const DeviceShieldConfig()),
        throwsA(isA<Exception>()),
      );

      final stateManager = container.resolve<Lifecycle>();
      expect(stateManager.current, SDKState.failure);
      expect(eventManager.initialized, isTrue);
      expect(
        eventManager.disposed,
        isTrue,
        reason: 'a completed step must be torn down on later failure',
      );
    });

    test('invalid config throws before any step runs', () async {
      final container = ServiceContainer();
      _registerFullDependencySet(container);
      final initializer = PluginInitializer(container: container);

      await expectLater(
        initializer.initialize(
          const DeviceShieldConfig(periodicCheckInterval: 100),
        ),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('a second initialize call while running throws', () async {
      final container = ServiceContainer();
      _registerFullDependencySet(container);
      final initializer = PluginInitializer(container: container);
      await initializer.initialize(const DeviceShieldConfig());

      await expectLater(
        initializer.initialize(const DeviceShieldConfig()),
        throwsA(
          isA<InitializationException>().having(
            (e) => e.code,
            'code',
            'ALREADY_INITIALIZING',
          ),
        ),
      );
    });
  });

  group('PluginInitializer — shutdown, dispose, reinitialize', () {
    test('shutdown disposes and unregisters SecurityManager/EventManager/'
        'NativeBridge — a disposed service is never left resolvable', () async {
      final container = ServiceContainer();
      _registerFullDependencySet(container);
      final initializer = PluginInitializer(container: container);
      await initializer.initialize(const DeviceShieldConfig());
      // Captured before shutdown — resolving after shutdown must throw,
      // per Correction 4 (disposed services are unregistered, never
      // reused).
      final securityManager =
          container.resolve<SecurityManager>() as _FakeSecurityManager;
      final eventManager =
          container.resolve<EventManager>() as _FakeEventManager;
      final nativeBridge =
          container.resolve<NativeBridge>() as _FakeNativeBridge;
      final lifecycleManager =
          container.resolve<LifecycleManager>() as _FakeLifecycleManager;

      await initializer.shutdown();

      expect(container.resolve<Lifecycle>().current, SDKState.stopped);
      expect(securityManager.disposed, isTrue);
      expect(eventManager.disposed, isTrue);
      expect(nativeBridge.disposed, isTrue);
      expect(lifecycleManager.detachCalled, isTrue);
      // The real assertion for Correction 4: none of the three disposed
      // services remain resolvable.
      expect(container.isRegistered<SecurityManager>(), isFalse);
      expect(container.isRegistered<EventManager>(), isFalse);
      expect(container.isRegistered<NativeBridge>(), isFalse);
      // LifecycleManager is detached, not disposed — it persists so it
      // can be re-attached on the next initialize().
      expect(container.isRegistered<LifecycleManager>(), isTrue);
    });

    test('reinitialize rebuilds SecurityManager fresh — the caller must '
        're-register it, since composing one needs detector/rule content '
        'this framework layer doesn\'t have', () async {
      final container = ServiceContainer();
      _registerFullDependencySet(container);
      final initializer = PluginInitializer(container: container);
      await initializer.initialize(const DeviceShieldConfig());
      await initializer.shutdown();

      // SecurityManager was unregistered by shutdown() — re-register a
      // fresh one, exactly as a real caller composing the SDK would.
      container.registerSingleton<SecurityManager>(_FakeSecurityManager());

      await initializer.reinitialize(const DeviceShieldConfig());

      final stateManager = container.resolve<Lifecycle>();
      expect(stateManager.current, SDKState.running);
      // NativeBridge/EventManager were also unregistered by shutdown()
      // but ARE auto-defaulted by Steps 3/4 — no manual re-registration
      // needed for either.
      expect(container.isRegistered<NativeBridge>(), isTrue);
      expect(container.isRegistered<EventManager>(), isTrue);
    });

    test('reinitialize with a different config updates the persisting '
        'ConfigurationManager in place, rather than ignoring the change '
        '(Correction 3)', () async {
      final container = ServiceContainer();
      _registerFullDependencySet(container);
      final initializer = PluginInitializer(container: container);
      await initializer.initialize(const DeviceShieldConfig());
      final configManagerBeforeShutdown = container
          .resolve<ConfigurationManager>();
      await initializer.shutdown();
      container.registerSingleton<SecurityManager>(_FakeSecurityManager());

      await initializer.reinitialize(
        const DeviceShieldConfig(periodicCheckInterval: 60000),
      );

      final configManagerAfterReinit = container
          .resolve<ConfigurationManager>();
      // Same instance — not recreated, per Correction 3's explicit "do
      // not recreate ConfigurationManager solely for configuration
      // changes."
      expect(
        identical(configManagerAfterReinit, configManagerBeforeShutdown),
        isTrue,
      );
      // But its value reflects the new config — proving updateConfig()
      // was actually called, not silently skipped.
      expect(configManagerAfterReinit.current.periodicCheckInterval, 60000);
    });

    test('dispose reaches destroyed and clears the container', () async {
      final container = ServiceContainer();
      _registerFullDependencySet(container);
      final initializer = PluginInitializer(container: container);
      await initializer.initialize(const DeviceShieldConfig());

      await initializer.dispose();

      expect(container.isRegistered<Lifecycle>(), isFalse);
      expect(container.isRegistered<NativeBridge>(), isFalse);
    });

    test(
      'shutdown without a prior initialize throws NOT_INITIALIZED',
      () async {
        final container = ServiceContainer();
        final initializer = PluginInitializer(container: container);

        await expectLater(
          initializer.shutdown(),
          throwsA(
            isA<InitializationException>().having(
              (e) => e.code,
              'code',
              'NOT_INITIALIZED',
            ),
          ),
        );
      },
    );
  });

  group('PluginInitializer — PermissionManager step', () {
    test('a pre-registered PermissionManager is used instead of the '
        'default, and is initialized during boot', () async {
      final container = ServiceContainer();
      _registerFullDependencySet(container);
      final permissionManager = _FakePermissionManager();
      container.registerSingleton<PermissionManager>(permissionManager);
      final initializer = PluginInitializer(container: container);

      await initializer.initialize(const DeviceShieldConfig());

      expect(permissionManager.initialized, isTrue);
      expect(
        identical(container.resolve<PermissionManager>(), permissionManager),
        isTrue,
      );
    });

    test('defaults a real PermissionManager when none is registered', () async {
      final container = ServiceContainer();
      _registerFullDependencySet(container);
      final initializer = PluginInitializer(container: container);

      await initializer.initialize(const DeviceShieldConfig());

      expect(container.isRegistered<PermissionManager>(), isTrue);
    });

    test(
      'a throwing PermissionManager rolls the boot back to failure',
      () async {
        final container = ServiceContainer();
        _registerFullDependencySet(container);
        container.registerSingleton<PermissionManager>(
          _ThrowingPermissionManager(),
        );
        final initializer = PluginInitializer(container: container);

        await expectLater(
          initializer.initialize(const DeviceShieldConfig()),
          throwsA(isA<StateError>()),
        );

        expect(container.resolve<Lifecycle>().current, SDKState.failure);
      },
    );
  });

  group('Architecture Correction 1 — ServiceContainer has an independent '
      'lifecycle', () {
    test('the same container survives dispose and can be reused by a new '
        'PluginInitializer', () async {
      final container = ServiceContainer();
      _registerFullDependencySet(container);
      final first = PluginInitializer(container: container);
      await first.initialize(const DeviceShieldConfig());
      await first.dispose();

      // The container object itself is untouched by dispose() — only its
      // registrations were cleared. Re-registering and building a second,
      // independent PluginInitializer against the same container proves
      // PluginInitializer never owned the container's own lifecycle.
      expect(container.isRegistered<Lifecycle>(), isFalse);
      _registerFullDependencySet(container);
      final second = PluginInitializer(container: container);

      await second.initialize(const DeviceShieldConfig());

      expect(container.resolve<Lifecycle>().current, SDKState.running);
    });
  });
}
