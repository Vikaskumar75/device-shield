import '../managers/manager.dart';
import '../models/device_shield_config.dart';

/// Sole owner of the current configuration. See ARCHITECTURE_CONTRACTS.md
/// Group C.
///
/// Architecture Correction 2: this contract performs no validation.
/// It only stores, exposes, and updates whatever config it is given —
/// validating a config is `DeviceShieldConfigValidator`'s job, run
/// *before* a config ever reaches an implementation of this contract
/// (flow: `DeviceShield.initialize(config)` →
/// `DeviceShieldConfigValidator` → `ConfigurationManager`). No manager
/// caches its own copy of the config — every manager reads [current] live
/// through this contract (see ARCHITECTURE_CONTRACTS.md Part 2's
/// Configuration System answer on "how do managers access it").
///
/// Public/Internal: internal — the config *values* this holds surface
/// publicly; the manager itself doesn't.
///
/// Extension point: no.
abstract class ConfigurationManager implements Manager {
  DeviceShieldConfig get current;

  /// Replaces [current] with [config], unconditionally — no validation
  /// happens here. Callers are expected to have already validated [config]
  /// (e.g. via `DeviceShieldConfigValidator`) before calling this.
  Future<void> updateConfig(DeviceShieldConfig config);
}
