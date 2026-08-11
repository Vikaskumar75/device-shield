import 'package:flutter/material.dart';
import 'package:flutter_shield/src/detectors/screenshot_detector.dart';

import '../core/shield_scope.dart';
import '../widgets/alert_demo.dart';
import '../widgets/status_card.dart';

/// Live screenshot-detection demo. Explains the platform mechanism
/// honestly (Android: `Activity.registerScreenCaptureCallback`, API 34+
/// only; iOS: `UIApplication.userDidTakeScreenshotNotification`, any
/// version — deliberately **not** ReplayKit) and fires a chosen
/// [AlertStyle] the instant a real screenshot event arrives.
class ScreenshotDemoScreen extends StatefulWidget {
  const ScreenshotDemoScreen({super.key});

  @override
  State<ScreenshotDemoScreen> createState() => _ScreenshotDemoScreenState();
}

class _ScreenshotDemoScreenState extends State<ScreenshotDemoScreen> {
  AlertStyle _style = AlertStyle.snackBar;
  int _lastKnownCount = 0;
  bool _seeded = false;

  @override
  Widget build(BuildContext context) {
    final controller = ShieldScope.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!_seeded) {
          _lastKnownCount = controller.screenshotCount;
          _seeded = true;
        } else if (controller.screenshotCount != _lastKnownCount) {
          _lastKnownCount = controller.screenshotCount;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            showSecurityAlert(
              context,
              style: _style,
              title: 'Screenshot Detected',
              message: 'A screenshot was just taken of this app.',
            );
          });
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const InfoBanner(
              message: 'Android requires API 34+ and no extra permissions '
                  '(Activity.registerScreenCaptureCallback). iOS works on '
                  'any version via UIApplication.userDidTakeScreenshot'
                  'Notification — not ReplayKit.',
            ),
            SectionCard(
              title: 'Live status',
              children: [
                StatusRow(
                  label: 'Detector registered',
                  value: controller.detectorEnabled[ScreenshotDetector.typeId] ==
                          true
                      ? 'Yes'
                      : 'No — enable it in Runtime Controls',
                ),
                StatusRow(
                  label: 'Screenshots detected (session)',
                  value: '${controller.screenshotCount}',
                ),
                StatusRow(
                  label: 'Last screenshot',
                  value: controller.lastScreenshotAt?.toIso8601String() ??
                      'None yet',
                ),
              ],
            ),
            SectionCard(
              title: 'Alert style',
              children: [
                DropdownButtonFormField<AlertStyle>(
                  initialValue: _style,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final style in AlertStyle.values)
                      DropdownMenuItem(value: style, child: Text(style.label)),
                  ],
                  onChanged: (v) => setState(() => _style = v ?? _style),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Preview alert now'),
                  onPressed: () => showSecurityAlert(
                    context,
                    style: _style,
                    title: 'Screenshot Detected (preview)',
                    message: 'This is a manual preview, not a real event.',
                  ),
                ),
              ],
            ),
            const SectionCard(
              title: 'How to test',
              children: [
                Text('1. Runtime Controls → Initialize SDK.'),
                Text('2. Runtime Controls → enable the Screenshot Detector.'),
                Text('3. Take a real screenshot of this device.'),
                Text('4. The alert above fires automatically within ~1s, '
                    'and the event appears on the Events screen.'),
              ],
            ),
          ],
        );
      },
    );
  }
}
