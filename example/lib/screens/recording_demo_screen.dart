import 'package:flutter/material.dart';
import 'package:flutter_shield/flutter_shield.dart';

import '../core/shield_scope.dart';
import '../widgets/alert_demo.dart';
import '../widgets/status_card.dart';

/// Live screen-recording-detection demo. iOS-only in practice
/// (`UIScreen.isCaptured`/`capturedDidChangeNotification`) — on Android the
/// detector is still registerable but honestly reports "unsupported on
/// this platform" rather than fabricating a result (plat-3 manual test
/// case), which this screen states plainly rather than hiding.
class RecordingDemoScreen extends StatefulWidget {
  const RecordingDemoScreen({super.key});

  @override
  State<RecordingDemoScreen> createState() => _RecordingDemoScreenState();
}

class _RecordingDemoScreenState extends State<RecordingDemoScreen> {
  AlertStyle _style = AlertStyle.banner;
  bool? _lastKnownActive;
  bool _seeded = false;

  @override
  Widget build(BuildContext context) {
    final controller = ShieldScope.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!_seeded) {
          _lastKnownActive = controller.recordingActive;
          _seeded = true;
        } else if (controller.recordingActive != _lastKnownActive) {
          final becameActive = controller.recordingActive == true;
          _lastKnownActive = controller.recordingActive;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            showSecurityAlert(
              context,
              style: _style,
              title: becameActive
                  ? 'Screen Recording Started'
                  : 'Screen Recording Stopped',
              message: becameActive
                  ? 'This screen is currently being recorded or mirrored.'
                  : 'Screen recording has ended.',
            );
          });
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const InfoBanner(
              message: 'iOS only, via UIScreen.isCaptured / '
                  'capturedDidChangeNotification. On Android the detector '
                  'registers successfully but always reports "unsupported '
                  'on this platform" — never a fabricated result.',
            ),
            SectionCard(
              title: 'Live status',
              children: [
                StatusRow(
                  label: 'Detector registered',
                  value: controller
                              .detectorEnabled[ScreenRecordingDetector.typeId] ==
                          true
                      ? 'Yes'
                      : 'No — enable it in Runtime Controls',
                ),
                StatusRow(
                  label: 'Recording state (inferred)',
                  value: controller.recordingActive == null
                      ? 'Unknown'
                      : (controller.recordingActive! ? 'Active' : 'Inactive'),
                  valueColor: controller.recordingActive == true
                      ? Colors.red
                      : null,
                ),
              ],
            ),
            const InfoBanner(
              icon: Icons.warning_amber_rounded,
              message: 'Documented SDK limitation: SecurityEvent.data only '
                  'ever carries {action, confidence} — the state above is '
                  'inferred from confidence == 1.0, not a direct field.',
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
                    title: 'Screen Recording (preview)',
                    message: 'This is a manual preview, not a real event.',
                  ),
                ),
              ],
            ),
            const SectionCard(
              title: 'How to test',
              children: [
                Text('1. Runtime Controls → Initialize SDK.'),
                Text(
                    '2. Runtime Controls → enable the Screen Recording Detector.'),
                Text('3. On iOS, start a Control Center screen recording.'),
                Text('4. The alert above fires automatically, and the '
                    'event appears on the Events screen.'),
              ],
            ),
          ],
        );
      },
    );
  }
}
