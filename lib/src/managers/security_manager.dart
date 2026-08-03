import '../models/sdk_state.dart';
import 'manager.dart';

/// Runtime orchestrator — the one component every public call actually
/// reaches. See ARCHITECTURE_CONTRACTS.md Group D.
///
/// Owns references to `DetectionManager`, `PolicyManager`, `EventManager`,
/// `NativeBridge`, `ConfigurationManager`, `PermissionManager`, `Logger`,
/// and the state machine; drives the periodic check timer; runs the
/// confidence-gate → Policy → Event pipeline. None of that pipeline logic
/// is implemented here — Phase 5 owns it. This file defines only the shape.
///
/// Public/Internal: internal — fully wrapped by the `FlutterShield` public
/// facade.
///
/// Extension point: no.
abstract class SecurityManager implements Manager {
  /// Current SDK status. Delegates to the state machine
  /// (`Lifecycle`/`SecurityStateManager`) rather than tracking its own copy.
  SDKState get status;

  Future<void> pause();

  Future<void> resume();

  Future<void> shutdown();

  /// Runs one check cycle on demand, outside the periodic timer.
  Future<void> checkNow();
}
