import '../bridge/native_bridge.dart';
import '../config/configuration_manager.dart';
import '../core/logger.dart';
import '../events/event_manager.dart';
import '../managers/detection_manager.dart';
import '../managers/policy_manager.dart';
import '../managers/security_manager.dart';
import '../permission/permission_manager.dart';
import '../state/lifecycle.dart';
import 'bootstrap_context.dart';
import 'service_container.dart';

/// The reverse-order teardown logic ROADMAP.md's M6 names as its own
/// deliverable ("ShutdownSequence — reverse-order teardown (§4.9)"),
/// extracted out of `PluginInitializer` so "run the boot sequence" and
/// "reverse it" are independently readable and independently testable.
///
/// Not one of ARCHITECTURE_CONTRACTS.md's 20 frozen per-component
/// contracts — only a ROADMAP.md checklist item — so this extraction is a
/// structural change, not a behavioral one: every teardown call, order,
/// and guard below is unchanged from what `PluginInitializer.shutdown()`/
/// `_unwind()` previously did inline.
///
/// Public/Internal: internal — used exclusively by `PluginInitializer`.
class ShutdownSequence {
  const ShutdownSequence();

  /// Full graceful shutdown after a successful boot, in reverse
  /// construction order: detach the lifecycle observer; dispose +
  /// unregister `SecurityManager` (its `DetectionManager`/`PolicyManager`
  /// are already disposed via `SecurityManager.dispose()`'s own cascade,
  /// so only unregistering them is needed here); dispose + unregister
  /// `EventManager`; dispose + unregister `NativeBridge`.
  ///
  /// Deliberately does not touch `ConfigurationManager`/
  /// `PermissionManager`/`LifecycleManager`'s own registration — those
  /// persist across a shutdown/reinitialize cycle, per
  /// ARCHITECTURE_CONTRACTS.md Part 3's shutdown-order table.
  Future<void> run(ServiceContainer container) async {
    if (container.isRegistered<LifecycleManager>()) {
      container.resolve<LifecycleManager>().detach();
    }
    if (container.isRegistered<SecurityManager>()) {
      await container.resolve<SecurityManager>().dispose();
      container.unregister<SecurityManager>();
    }
    container.unregister<DetectionManager>();
    container.unregister<PolicyManager>();
    if (container.isRegistered<EventManager>()) {
      await container.resolve<EventManager>().dispose();
      container.unregister<EventManager>();
    }
    if (container.isRegistered<NativeBridge>()) {
      await container.resolve<NativeBridge>().dispose();
      container.unregister<NativeBridge>();
    }
    if (container.isRegistered<Logger>()) {
      container.resolve<Logger>().info('Bootstrap: shutdown complete');
    }
  }

  /// Best-effort reverse-order rollback of a boot that failed partway
  /// through — walks [context]'s completed steps in reverse, tearing down
  /// only what actually finished. A single step's teardown failure is
  /// swallowed so it never masks the original failure that triggered this
  /// rollback.
  Future<void> unwind(
    ServiceContainer container,
    BootstrapContext context,
  ) async {
    for (final step in context.completedSteps.reversed) {
      try {
        switch (step) {
          case 'Lifecycle':
            if (container.isRegistered<LifecycleManager>()) {
              container.resolve<LifecycleManager>().detach();
            }
            break;
          case 'Managers':
            if (container.isRegistered<SecurityManager>()) {
              await container.resolve<SecurityManager>().dispose();
              container.unregister<SecurityManager>();
            }
            // Already disposed via SecurityManager.dispose()'s own
            // cascade (see DefaultSecurityManager.dispose()) — only
            // unregistering is needed, so a retry constructs fresh
            // instances rather than reusing disposed ones.
            container.unregister<DetectionManager>();
            container.unregister<PolicyManager>();
            break;
          case 'Registries':
            // Pure storage, nothing to dispose — left registered so a
            // retry doesn't lose already-registered detectors for no
            // reason (mirrors ConfigurationManager's own persistence
            // reasoning below).
            break;
          case 'EventManager':
            if (container.isRegistered<EventManager>()) {
              await container.resolve<EventManager>().dispose();
            }
            break;
          case 'NativeBridge':
            if (container.isRegistered<NativeBridge>()) {
              await container.resolve<NativeBridge>().dispose();
            }
            break;
          case 'Configuration':
            if (container.isRegistered<ConfigurationManager>()) {
              await container.resolve<ConfigurationManager>().dispose();
            }
            break;
          case 'Permission':
            if (container.isRegistered<PermissionManager>()) {
              await container.resolve<PermissionManager>().dispose();
            }
            break;
          default:
            break;
        }
      } catch (_) {
        // Best-effort unwind — a teardown failure must never mask the
        // original failure that triggered this rollback.
      }
    }
  }
}
