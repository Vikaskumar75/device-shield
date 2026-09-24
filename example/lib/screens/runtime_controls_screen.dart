import 'package:flutter/material.dart';
import 'package:flutter_shield/src/detectors/debugger_detector.dart';
import 'package:flutter_shield/src/detectors/emulator_detector.dart';
import 'package:flutter_shield/src/detectors/screen_recording_detector.dart';
import 'package:flutter_shield/src/detectors/screenshot_detector.dart';

import '../core/shield_scope.dart';
import '../widgets/action_button.dart';
import '../widgets/status_card.dart';

const _detectorLabels = {
  EmulatorDetector.typeId: 'Emulator Detector',
  DebuggerDetector.typeId: 'Debugger Detector',
  ScreenshotDetector.typeId: 'Screenshot Detector',
  ScreenRecordingDetector.typeId: 'Screen Recording Detector',
};

/// Demonstrates every SDK lifecycle entry point (`initialize`, `shutdown`,
/// `reinitialize`, `dispose`, `pause`, `resume`, `checkNow`), detector
/// registration (FR-18) and rule registration (FR-17), each wired to a
/// [ShieldActionButton] so every action shows success/failure explicitly.
class RuntimeControlsScreen extends StatelessWidget {
  const RuntimeControlsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ShieldScope.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const InfoBanner(
              message: 'Every button here calls a real FlutterShield static '
                  'method. Failures surface as a red SnackBar, never a '
                  'crash — see Errors for the captured exception.',
            ),
            SectionCard(
              title: 'Lifecycle',
              subtitle: 'Current state: ${controller.status.name}',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ShieldActionButton(
                      label: 'Initialize',
                      icon: Icons.power_settings_new,
                      filled: true,
                      onPressed: controller.initialize,
                    ),
                    ShieldActionButton(
                      label: 'Shutdown',
                      icon: Icons.stop_circle_outlined,
                      onPressed: controller.shutdown,
                    ),
                    ShieldActionButton(
                      label: 'Reinitialize',
                      icon: Icons.refresh,
                      onPressed: controller.reinitialize,
                    ),
                    ShieldActionButton(
                      label: 'Dispose',
                      icon: Icons.delete_outline,
                      onPressed: controller.dispose_,
                    ),
                    ShieldActionButton(
                      label: 'Pause',
                      icon: Icons.pause_circle_outline,
                      onPressed: controller.pause,
                    ),
                    ShieldActionButton(
                      label: 'Resume',
                      icon: Icons.play_circle_outline,
                      onPressed: controller.resume,
                    ),
                    ShieldActionButton(
                      label: 'Check Now',
                      icon: Icons.search,
                      onPressed: controller.checkNow,
                    ),
                  ],
                ),
              ],
            ),
            SectionCard(
              title: 'Detectors',
              subtitle: 'Toggling off cannot remove a live detector — see '
                  'the warning banner if you try while running.',
              children: [
                for (final entry in controller.detectorEnabled.entries)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_detectorLabels[entry.key] ?? entry.key),
                    subtitle: controller.isDetectorPendingRemoval(entry.key)
                        ? const Text(
                            'Pending removal on next Reinitialize',
                            style: TextStyle(color: Colors.orange),
                          )
                        : null,
                    value: entry.value,
                    onChanged: (value) =>
                        controller.setDetectorEnabled(entry.key, value),
                  ),
                const SizedBox(height: 8),
                ShieldActionButton(
                  label: 'Register custom detector (FR-18 demo)',
                  icon: Icons.extension_outlined,
                  onPressed: controller.registerCustomDetector,
                ),
              ],
            ),
            SectionCard(
              title: 'Rules (FR-17 demo)',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Demo rule active'),
                  subtitle: const Text(
                      'A trivial custom Rule that never matches — proves '
                      'addRule/removeRule mechanics.'),
                  value: controller.demoRuleActive,
                  onChanged: controller.toggleDemoRule,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
