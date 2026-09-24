import 'package:flutter/material.dart';
import 'package:flutter_shield/flutter_shield.dart';

import '../core/shield_scope.dart';
import '../widgets/action_button.dart';
import '../widgets/status_card.dart';

/// Demonstrates: a single, live, at-a-glance view of everything the SDK
/// currently reports — status, platform, protection, recording, last
/// screenshot/event/callback, and feature availability. Every value here
/// is read live from [ShieldController]/`FlutterShield` itself, never
/// cached separately, so this screen can never drift from reality.
///
/// Expected behavior: values update immediately after any action taken on
/// any other screen (Runtime Controls, Protection, etc.) — this screen
/// has no state of its own.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ShieldScope.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final status = controller.status;
        final statusColor = switch (status) {
          SDKState.running => Colors.green,
          SDKState.paused => Colors.orange,
          SDKState.failure => Colors.red,
          SDKState.uninitialized => Colors.grey,
          _ => Colors.blueGrey,
        };
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const InfoBanner(
              message: 'This screen shows every live SDK value at a glance. '
                  'Use Runtime Controls to change SDK state.',
            ),
            SectionCard(
              title: 'Quick Actions',
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
                      label: 'Check Now',
                      icon: Icons.search,
                      onPressed: controller.checkNow,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Reset Demo'),
                      onPressed: () {
                        controller.resetDemo();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Local example-app state reset '
                                  '(SDK state untouched)')),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            SectionCard(
              title: 'SDK Status',
              children: [
                StatusRow(
                  label: 'Initialization state',
                  value: status.name,
                  valueColor: statusColor,
                  icon: Icons.power_settings_new,
                ),
                StatusRow(
                  label: 'Platform',
                  value: Theme.of(context).platform.name,
                  icon: Icons.devices_other,
                ),
                StatusRow(
                  label: 'Platform version',
                  value: controller.platformVersion,
                  icon: Icons.info_outline,
                ),
              ],
            ),
            SectionCard(
              title: 'Protection & Detection',
              children: [
                StatusRow(
                  label: 'Screenshot protection enabled',
                  value: controller.protectionEnabled ? 'Yes' : 'No',
                  valueColor:
                      controller.protectionEnabled ? Colors.green : null,
                  icon: Icons.shield_outlined,
                ),
                StatusRow(
                  label: 'Recording state',
                  value: controller.recordingActive == null
                      ? 'Unknown'
                      : (controller.recordingActive! ? 'Active' : 'Inactive'),
                  icon: Icons.fiber_smart_record_outlined,
                ),
                StatusRow(
                  label: 'Last screenshot',
                  value: controller.lastScreenshotAt == null
                      ? 'None yet'
                      : controller.lastScreenshotAt!.toIso8601String(),
                  icon: Icons.screenshot_monitor_outlined,
                ),
                StatusRow(
                  label: 'Screenshots detected (session)',
                  value: '${controller.screenshotCount}',
                  icon: Icons.numbers,
                ),
              ],
            ),
            SectionCard(
              title: 'Events & Callbacks',
              children: [
                StatusRow(
                  label: 'Last event',
                  value: controller.lastEvent?.type ?? 'None yet',
                  icon: Icons.event_note_outlined,
                ),
                StatusRow(
                  label: 'Total events',
                  value: '${controller.events.length}',
                  icon: Icons.list_alt,
                ),
                StatusRow(
                  label: 'Registered callbacks',
                  value:
                      '${controller.callbacks.values.where((c) => c.registered).length}',
                  icon: Icons.link,
                ),
              ],
            ),
            SectionCard(
              title: 'Current Configuration',
              children: [
                StatusRow(
                    label: 'Periodic check interval',
                    value: '${controller.config.periodicCheckInterval} ms'),
                StatusRow(
                    label: 'Check timeout',
                    value: '${controller.config.checkTimeout} ms'),
                StatusRow(
                    label: 'Debug logging',
                    value: controller.config.debugLogging ? 'On' : 'Off'),
                StatusRow(
                    label: 'Screenshot detection (config flag)',
                    value: controller.config.enableScreenshotDetection
                        ? 'On'
                        : 'Off'),
                StatusRow(
                    label: 'Recording detection (config flag)',
                    value: controller.config.enableScreenRecordingDetection
                        ? 'On'
                        : 'Off'),
              ],
            ),
            SectionCard(
              title: 'Feature Availability (this platform)',
              children: const [
                StatusRow(
                    label: 'Screenshot detection', value: 'See About screen'),
                StatusRow(
                    label: 'Recording detection', value: 'See About screen'),
                StatusRow(
                    label: 'Screenshot protection', value: 'See About screen'),
              ],
            ),
          ],
        );
      },
    );
  }
}
