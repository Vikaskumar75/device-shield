import '../bridge/default_native_bridge.dart';
import '../bridge/native_bridge.dart';
import '../config/configuration_manager.dart';
import '../config/default_configuration_manager.dart';
import '../config/flutter_shield_config_validator.dart';
import '../core/console_logger.dart';
import '../core/logger.dart';
import '../events/default_event_manager.dart';
import '../events/event_manager.dart';
import '../managers/default_detection_manager.dart';
import '../managers/default_policy_manager.dart';
import '../managers/default_security_manager.dart';
import '../managers/detection_manager.dart';
import '../managers/policy_manager.dart';
import '../managers/security_manager.dart';
import '../models/flutter_shield_config.dart';
import '../models/flutter_shield_exception.dart';
import '../models/sdk_state.dart';
import '../models/security_event.dart';
import '../permission/default_permission_manager.dart';
import '../permission/permission_manager.dart';
import '../registry/default_detector_registry.dart';
import '../registry/detector_registry.dart';
import '../state/default_lifecycle_manager.dart';
import '../state/lifecycle.dart';
import '../state/security_state_manager.dart';
import 'bootstrap_context.dart';
import 'service_container.dart';
import 'shutdown_sequence.dart';

/// Runs the SDK's boot sequence exactly once per successful call, wires
/// every service through [ServiceContainer], and reverses cleanly on
/// [shutdown] or [dispose]. See ARCHITECTURE_CONTRACTS.md Part 3/4.
///
/// Steps, in order: Logger → Permission → Configuration → NativeBridge →
/// EventManager → Registries → Managers → Lifecycle → Public API ready.
///
/// The reverse direction — both the graceful [shutdown] path and the
/// best-effort rollback of a boot that failed partway through — is owned
/// by [ShutdownSequence] (ROADMAP.md M6's named "reverse-order teardown"
/// deliverable), composed here rather than inlined, so this class stays
/// focused on running the sequence forward.
///
/// Every service is resolved-or-defaulted here: this initializer
/// constructs a sensible built-in implementation for any type the caller
/// hasn't already registered — this now includes `DetectionManager`,
/// `PolicyManager`, `SecurityManager`, and `LifecycleManager`, not just
/// the infrastructure-level services (`Logger`, `PermissionManager`,
/// `ConfigurationManager`, `NativeBridge`, `EventManager`,
/// `DetectorRegistry`) it already defaulted before this pass. This closes
/// the gap ARCHITECTURE_CONTRACTS.md Group B's own wording describes —
/// `PluginInitializer` is "the only code path that constructs and wires
/// every other service" — which previously wasn't quite true: composing
/// `SecurityManager` (and its dependents) was this class's caller's job
/// instead. A caller that pre-registers its own implementation for any of
/// these four (as `phase5_managers_integration_test.dart` does, and as a
/// host app supplying custom detector/rule content will keep doing) is
/// unaffected — the resolve-or-default check only ever constructs a
/// default when nothing is already registered, exactly the same pattern
/// already proven for the five services this class has always defaulted.
///
/// Architecture Correction 1: this class does not create or own a
/// [ServiceContainer] — the container is application infrastructure with
/// its own independent lifecycle, constructed and held by whatever wires
/// the SDK together (today: test/call-site code; once the Public API is
/// integrated, that integration point). `PluginInitializer` only *uses*
/// the container's operations (`register*`/`resolve`/`reset`) — using an
/// operation is not the same as owning the object's lifecycle. Concretely:
/// [dispose] calls `container.reset()` to undo its own registrations, but
/// never discards the container reference itself, and the same container
/// can be handed to a fresh `PluginInitializer` for a later reinitialize
/// cycle without losing continuity.
///
/// `PermissionManager`'s step deliberately does **not** depend on
/// `NativeBridge`, even though real permission requests are inherently a
/// native-platform operation. The frozen Init Matrix places
/// `PermissionManager` at step 2, two steps before `NativeBridge` (step
/// 4) — constructing it with a `NativeBridge` dependency would either
/// force reordering past what a real permission implementation could
/// consistently want, or require `NativeBridge` to exist before its own
/// documented step. `DefaultPermissionManager`'s only reachable scenario
/// today (an empty required-permission set — no `SecurityProfile` feeds a
/// real one in yet) needs no native call at all, so this is deferred
/// rather than resolved by inventing a premature dependency; see that
/// class's own doc comment for the full reasoning.
class PluginInitializer {
  PluginInitializer({
    required this.container,
    this.shutdownSequence = const ShutdownSequence(),
  });

  final ServiceContainer container;

  /// The reverse-order teardown logic ROADMAP.md's M6 names as its own
  /// deliverable — extracted into its own class (see `shutdown_sequence.dart`)
  /// rather than inlined here, so "run the boot sequence" and "reverse it"
  /// stay independently readable/testable. Constructor-injected with a
  /// `const` default, matching every other collaborator this class's
  /// sibling managers take (e.g. `DefaultDetectionManager.registry`/
  /// `.concurrencyController`) — a public field, not a hidden default, so
  /// every existing `PluginInitializer(container: ...)` call site keeps
  /// working unchanged while still being swappable by a caller/test.
  final ShutdownSequence shutdownSequence;

  /// Runs the full boot sequence. Safe to call again after [shutdown]
  /// (state `stopped`) or a prior failure (state `failure`) — calling while
  /// already initializing/initialized/running/paused throws, and calling
  /// after [dispose] (state `destroyed`) always throws, since `destroyed`
  /// is terminal.
  Future<void> initialize(FlutterShieldConfig config) async {
    final stateManager = _resolveOrRegisterStateManager();
    final startingState = stateManager.current;

    const reentrantStates = {
      SDKState.initializing,
      SDKState.initialized,
      SDKState.running,
      SDKState.paused,
    };
    if (reentrantStates.contains(startingState)) {
      throw InitializationException(
        code: 'ALREADY_INITIALIZING',
        message: 'Cannot initialize from state $startingState',
      );
    }
    if (startingState == SDKState.destroyed) {
      throw InitializationException(
        code: 'ALREADY_DISPOSED',
        message: 'Cannot initialize a disposed SDK instance',
      );
    }

    final context = BootstrapContext(config);

    // The frozen transition table (ARCHITECTURE_CONTRACTS.md Part 3) only
    // allows an observable `initializing` phase from `uninitialized`.
    // Restarting from `stopped` is a direct hop straight to `running`;
    // restarting from `failure` hops to `initialized` then `running` —
    // neither passes through `initializing` again. See Step 9 below for
    // the matching exit hop, and the catch block for why a failed restart
    // from `stopped` must not attempt an illegal `stopped -> failure`.
    final isFreshBoot = startingState == SDKState.uninitialized;
    if (isFreshBoot) {
      stateManager.transitionTo(SDKState.initializing);
    }

    late final Logger logger;
    try {
      // Step 1: Logger.
      logger = _resolveOrRegisterLogger();
      context.recordStep('Logger');
      logger.info('Bootstrap: Logger ready');

      // Step 2: PermissionManager — resolved or default-registered. See
      // this class's own doc comment for why it deliberately doesn't
      // depend on NativeBridge yet.
      final permissionManager = _resolveOrRegisterPermissionManager();
      await permissionManager.initialize();
      context.recordStep('Permission');
      logger.info('Bootstrap: Permission ready');

      // Step 3: Configuration. Architecture Correction 2 — validation runs
      // here, before storage, as its own component; ConfigurationManager
      // itself never validates.
      final validatedConfig = FlutterShieldConfigValidator().validate(config);
      final configManager =
          await _resolveOrRegisterConfiguration(validatedConfig);
      await configManager.initialize();
      context.recordStep('Configuration');
      logger.info('Bootstrap: Configuration ready');

      // Step 4: NativeBridge — resolved or default-registered.
      _resolveOrRegisterNativeBridge();
      context.recordStep('NativeBridge');
      logger.info('Bootstrap: NativeBridge ready');

      // Step 5: EventManager — resolved or default-registered.
      final eventManager = _resolveOrRegisterEventManager();
      await eventManager.initialize();
      context.recordStep('EventManager');
      logger.info('Bootstrap: EventManager ready');

      // Step 6: Registries. DetectorRegistry is resolved or default-
      // registered here, exactly like Logger/Configuration above, since
      // it's pure storage with zero security logic.
      _resolveOrRegisterDetectorRegistry();
      context.recordStep('Registries');
      logger.info('Bootstrap: Registries ready');

      // Step 7: Managers — resolved or default-registered. Composing a
      // default SecurityManager also resolves-or-registers its
      // DetectionManager/PolicyManager dependents the same way, so a
      // caller that pre-registered only one of the three still gets
      // sensible defaults for whichever it left out.
      final securityManager = _resolveOrRegisterSecurityManager();
      await securityManager.initialize();
      context.recordStep('Managers');
      logger.info('Bootstrap: Managers ready');

      // Step 8: Lifecycle — resolved or default-registered.
      final lifecycleManager = _resolveOrRegisterLifecycleManager();
      if (securityManager is SecurityLifecycleHandler) {
        lifecycleManager.attach(securityManager as SecurityLifecycleHandler);
      }
      context.recordStep('Lifecycle');
      logger.info('Bootstrap: Lifecycle attached');

      // Step 9: Public API ready. `stopped` hops directly to `running`;
      // `uninitialized`/`failure` both hop through `initialized` first —
      // exactly mirroring the entry-side logic above.
      if (startingState == SDKState.stopped) {
        stateManager.transitionTo(SDKState.running);
      } else {
        stateManager.transitionTo(SDKState.initialized);
        stateManager.transitionTo(SDKState.running);
      }
      context.recordStep('Ready');
      await eventManager.emit(SecurityEvent(
        type: 'initialized',
        timestamp: DateTime.now(),
        severity: EventSeverity.info,
        source: 'PluginInitializer',
      ));
      logger.info(
          'Bootstrap complete in ${context.elapsed.inMilliseconds}ms');
    } catch (error, stackTrace) {
      if (container.isRegistered<Logger>()) {
        container.resolve<Logger>().exception(
              'Bootstrap failed at step after: '
              '${context.completedSteps.join(', ')}',
              error: error,
              stackTrace: stackTrace,
            );
      }
      // `failure` is only reachable from `initializing` or `running` in
      // the frozen table. A restart attempt from `stopped` never entered
      // `initializing` (see entry-side logic above), so it has no legal
      // `failure` transition — attempting one would throw a second,
      // masking StateError on top of the real failure. Such a restart
      // simply remains at `stopped`.
      if (stateManager.current == SDKState.initializing ||
          stateManager.current == SDKState.running) {
        stateManager.transitionTo(SDKState.failure);
      }
      await shutdownSequence.unwind(container, context);
      rethrow;
    }
  }

  /// Pauses monitoring and tears down every service that completed
  /// initialization, in reverse order. Leaves the SDK in `stopped` —
  /// resumable via [initialize] or [reinitialize].
  ///
  /// `SecurityManager`, `EventManager`, and `NativeBridge` are disposed
  /// *and* unregistered here — a disposed service is never reused;
  /// [initialize]/[reinitialize] always resolves a fresh instance for
  /// these three afterward. `DetectionManager`/`PolicyManager` are this
  /// same class's own composition detail now (previously
  /// `FlutterShield`'s), so they're unregistered alongside
  /// `SecurityManager` here too — already disposed via
  /// `SecurityManager.dispose()`'s own internal cascade, so only
  /// unregistering (not a second dispose call) is needed.
  /// `ConfigurationManager` is deliberately **not** disposed or
  /// unregistered — per ARCHITECTURE_CONTRACTS.md Part 3's shutdown-order
  /// table, it is only released later, at full `container.reset()` (see
  /// [dispose]). It persists across a shutdown/reinitialize cycle so a
  /// subsequent [PluginInitializer.initialize] call can apply a new
  /// config via `updateConfig()` rather than losing continuity by being
  /// recreated. `LifecycleManager` is detached, not disposed or
  /// unregistered, for the same reason.
  Future<void> shutdown() async {
    if (!container.isRegistered<Lifecycle>()) {
      throw InitializationException(
        code: 'NOT_INITIALIZED',
        message: 'Cannot shut down — the SDK was never initialized',
      );
    }
    final stateManager = container.resolve<Lifecycle>();
    const shutdownableStates = {SDKState.running, SDKState.paused};
    if (!shutdownableStates.contains(stateManager.current)) {
      throw InitializationException(
        code: 'NOT_RUNNING',
        message: 'Cannot shut down from state ${stateManager.current}',
      );
    }

    await shutdownSequence.run(container);
    stateManager.transitionTo(SDKState.stopped);
  }

  /// Full teardown: shuts down if still running, transitions to the
  /// terminal `destroyed` state, and clears every registration. A disposed
  /// [PluginInitializer] cannot be reinitialized — construct a new one.
  Future<void> dispose() async {
    if (!container.isRegistered<Lifecycle>()) {
      container.reset();
      return;
    }
    final stateManager = container.resolve<Lifecycle>();
    if (stateManager.current == SDKState.running ||
        stateManager.current == SDKState.paused) {
      await shutdown();
    }
    if (stateManager.current != SDKState.destroyed) {
      stateManager.transitionTo(SDKState.destroyed);
    }
    if (stateManager is DefaultSecurityStateManager) {
      stateManager.dispose();
    }
    container.reset();
  }

  /// Semantically identical to [initialize] — a named, self-documenting
  /// entry point for restarting after [shutdown] or a failure. The
  /// transition guard inside [initialize] already permits both
  /// (`stopped`/`failure` → `initializing`), so no separate check is
  /// needed here.
  Future<void> reinitialize(FlutterShieldConfig config) => initialize(config);

  Lifecycle _resolveOrRegisterStateManager() {
    if (!container.isRegistered<Lifecycle>()) {
      container.registerSingleton<Lifecycle>(DefaultSecurityStateManager());
    }
    return container.resolve<Lifecycle>();
  }

  Logger _resolveOrRegisterLogger() {
    if (!container.isRegistered<Logger>()) {
      container.registerSingleton<Logger>(ConsoleLogger());
    }
    return container.resolve<Logger>();
  }

  PermissionManager _resolveOrRegisterPermissionManager() {
    if (!container.isRegistered<PermissionManager>()) {
      container.registerSingleton<PermissionManager>(
        DefaultPermissionManager(),
      );
    }
    return container.resolve<PermissionManager>();
  }

  /// Resolves the current [ConfigurationManager], registering a new one
  /// with [config] if none exists yet. If one already exists (persisted
  /// across a shutdown/reinitialize cycle — see [shutdown]'s doc comment),
  /// it is **updated in place** via `updateConfig(config)` rather than
  /// recreated, so a `reinitialize()` call with a different config is
  /// correctly applied instead of silently ignored.
  Future<ConfigurationManager> _resolveOrRegisterConfiguration(
      FlutterShieldConfig config) async {
    if (!container.isRegistered<ConfigurationManager>()) {
      container.registerSingleton<ConfigurationManager>(
        DefaultConfigurationManager(config),
      );
      return container.resolve<ConfigurationManager>();
    }
    final existing = container.resolve<ConfigurationManager>();
    await existing.updateConfig(config);
    return existing;
  }

  NativeBridge _resolveOrRegisterNativeBridge() {
    if (!container.isRegistered<NativeBridge>()) {
      container.registerSingleton<NativeBridge>(DefaultNativeBridge());
    }
    return container.resolve<NativeBridge>();
  }

  EventManager _resolveOrRegisterEventManager() {
    if (!container.isRegistered<EventManager>()) {
      container.registerSingleton<EventManager>(DefaultEventManager());
    }
    return container.resolve<EventManager>();
  }

  DetectorRegistry _resolveOrRegisterDetectorRegistry() {
    if (!container.isRegistered<DetectorRegistry>()) {
      container.registerSingleton<DetectorRegistry>(
        DefaultDetectorRegistry(),
      );
    }
    return container.resolve<DetectorRegistry>();
  }

  /// Resolves-or-registers `DetectionManager`. Reads `checkTimeout` as a
  /// plain primitive off the already-registered `ConfigurationManager` —
  /// `DetectionManager` itself never holds a `ConfigurationManager`
  /// reference, preserving the frozen dependency matrix exactly.
  DetectionManager _resolveOrRegisterDetectionManager() {
    if (!container.isRegistered<DetectionManager>()) {
      container.registerSingleton<DetectionManager>(
        DefaultDetectionManager(
          logger: container.resolve<Logger>(),
          registry: container.resolve<DetectorRegistry>(),
          detectorTimeout: Duration(
            milliseconds:
                container.resolve<ConfigurationManager>().current.checkTimeout,
          ),
        ),
      );
    }
    return container.resolve<DetectionManager>();
  }

  PolicyManager _resolveOrRegisterPolicyManager() {
    if (!container.isRegistered<PolicyManager>()) {
      container.registerSingleton<PolicyManager>(
        DefaultPolicyManager(logger: container.resolve<Logger>()),
      );
    }
    return container.resolve<PolicyManager>();
  }

  /// Resolves-or-registers `SecurityManager`. Composing a default instance
  /// also resolves-or-registers its `DetectionManager`/`PolicyManager`
  /// dependents first, so a caller that pre-registered only one of the
  /// three still gets sensible defaults for whichever it left out —
  /// exactly the same "don't overwrite what's already there" rule every
  /// other resolve-or-register method in this class follows.
  SecurityManager _resolveOrRegisterSecurityManager() {
    if (!container.isRegistered<SecurityManager>()) {
      final detectionManager = _resolveOrRegisterDetectionManager();
      final policyManager = _resolveOrRegisterPolicyManager();
      container.registerSingleton<SecurityManager>(
        DefaultSecurityManager(
          detectionManager: detectionManager,
          policyManager: policyManager,
          eventManager: container.resolve<EventManager>(),
          configurationManager: container.resolve<ConfigurationManager>(),
          lifecycle: container.resolve<Lifecycle>(),
          logger: container.resolve<Logger>(),
          // Handed off solely to construct ScreenCaptureController — never
          // retained as a field on DefaultSecurityManager itself. Already
          // registered by step 4, long before this step runs.
          nativeBridge: container.resolve<NativeBridge>(),
        ),
      );
    }
    return container.resolve<SecurityManager>();
  }

  LifecycleManager _resolveOrRegisterLifecycleManager() {
    if (!container.isRegistered<LifecycleManager>()) {
      container.registerSingleton<LifecycleManager>(
        DefaultLifecycleManager(),
      );
    }
    return container.resolve<LifecycleManager>();
  }

}
