import '../models/device_shield_config.dart';

/// Accumulates state across one [PluginInitializer.initialize] run — which
/// steps completed, when boot started, and the config it's booting with.
///
/// Exists so a failure part-way through boot can report exactly what
/// completed and roll it back in reverse, and so a meaningful duration can
/// be logged on success. Purely a bookkeeping object — no logic of its own
/// beyond recording.
///
/// Public/Internal: internal.
class BootstrapContext {
  BootstrapContext(this.config) : startedAt = DateTime.now();

  final DeviceShieldConfig config;
  final DateTime startedAt;
  final List<String> completedSteps = [];

  void recordStep(String name) => completedSteps.add(name);

  Duration get elapsed => DateTime.now().difference(startedAt);
}
