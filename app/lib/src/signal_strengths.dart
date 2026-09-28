import 'results.dart';

/// Strength of every signal the native checks can report. Keep in sync with
/// the docs site's signals page (website/src/content/docs/reference/signals.mdx).
///
/// The strength reflects how often a signal fires on devices that aren't
/// actually compromised: emulators, custom ROMs and debug builds trigger the
/// weak ones routinely.
const Map<String, SignalStrength> signalStrengths = {
  // Root (Android)
  'su_binary_path': SignalStrength.strong,
  'su_executable': SignalStrength.strong,
  'magisk_artifacts': SignalStrength.strong,
  'writable_system': SignalStrength.strong,
  'superuser_apps_installed': SignalStrength.medium,
  'root_cloaking_apps_installed': SignalStrength.medium,
  'busybox_present': SignalStrength.weak,
  'build_tags_test_keys': SignalStrength.weak,
  'dangerous_system_props': SignalStrength.weak,

  // Jailbreak (iOS). Path and process checks can fire on the Simulator.
  'jailbreak_app_paths': SignalStrength.strong,
  'suspicious_system_paths': SignalStrength.strong,
  'writable_outside_sandbox': SignalStrength.strong,
  'process_spawn_check': SignalStrength.strong,
  'dyld_env_var': SignalStrength.strong,

  // Emulator
  'simulator_target': SignalStrength.strong,
  'qemu_pipe': SignalStrength.strong,
  'fingerprint': SignalStrength.medium,
  'model': SignalStrength.medium,
  'manufacturer': SignalStrength.medium,
  'hardware': SignalStrength.medium,
  'product': SignalStrength.medium,
  'brand_device': SignalStrength.medium,

  // Debugger
  'debugger_connected': SignalStrength.strong,
  'waiting_for_debugger': SignalStrength.strong,
  'ptrace_flag': SignalStrength.strong,
  'debuggable_flag': SignalStrength.weak,

  // Mock location
  'mock_provider_flag': SignalStrength.strong,
  'mock_app_selected_for_this_app': SignalStrength.strong,
  'known_spoofing_tweak_artifact': SignalStrength.strong,
  'impossible_velocity': SignalStrength.medium,
  'invalid_location_accuracy': SignalStrength.medium,
  'legacy_allow_mock_location_setting': SignalStrength.medium,
  'fake_gps_app_installed': SignalStrength.weak,
};

/// The strength of [id]. Unknown ids are weak, so a native signal added
/// without updating [signalStrengths] can never cause a detection by itself.
SignalStrength strengthOf(String id) =>
    signalStrengths[id] ?? SignalStrength.weak;

/// The detection rule: detected with at least one strong signal or at least
/// two medium ones; weak signals never decide it.
CheckStatus statusFor(List<Signal> signals) {
  var strong = 0;
  var medium = 0;
  for (final signal in signals) {
    switch (signal.strength) {
      case SignalStrength.strong:
        strong++;
      case SignalStrength.medium:
        medium++;
      case SignalStrength.weak:
        break;
    }
  }
  return strong >= 1 || medium >= 2 ? CheckStatus.detected : CheckStatus.clear;
}
