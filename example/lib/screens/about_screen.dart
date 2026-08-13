import 'package:flutter/material.dart';

import '../core/shield_scope.dart';
import '../widgets/status_card.dart';

/// SDK metadata, platform-specific feature availability, and every
/// documented SDK limitation discovered while building this example app —
/// surfaced here explicitly per the "document it, do not silently work
/// around it" instruction, rather than only living in code comments.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ShieldScope.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            SectionCard(
              title: 'FlutterShield',
              children: [
                const StatusRow(label: 'Package version', value: '0.0.1'),
                StatusRow(
                    label: 'Platform version',
                    value: controller.platformVersion),
                StatusRow(
                    label: 'Platform', value: Theme.of(context).platform.name),
              ],
            ),
            const SectionCard(
              title: 'Feature availability by platform',
              children: [
                _FeatureRow(
                  feature: 'Emulator detection',
                  android: 'Full support',
                  ios: 'Full support',
                ),
                _FeatureRow(
                  feature: 'Debugger detection',
                  android: 'Full support',
                  ios: 'Full support',
                ),
                _FeatureRow(
                  feature: 'Root detection',
                  android: 'Full support — 9-signal heuristic',
                  ios: 'Not applicable (root is not an iOS concept)',
                ),
                _FeatureRow(
                  feature: 'Jailbreak detection',
                  android: 'Not applicable (jailbreak is not an Android '
                      'concept)',
                  ios: 'Full support — 5-signal heuristic',
                ),
                _FeatureRow(
                  feature: 'Screenshot detection',
                  android: 'API 34+ only (registerScreenCaptureCallback)',
                  ios: 'Any version (userDidTakeScreenshotNotification)',
                ),
                _FeatureRow(
                  feature: 'Screen recording detection',
                  android: 'Registers, but reports "unsupported"',
                  ios: 'Full support (UIScreen.isCaptured)',
                ),
                _FeatureRow(
                  feature: 'Screenshot protection',
                  android: 'Full support (FLAG_SECURE), confirmed working',
                  ios: 'Attempted via an undocumented UITextField '
                      'secure-layer technique — not an Apple API. '
                      'UNCONFIRMED: live Simulator testing found the '
                      'screenshot still captured real content, not '
                      'black. Untested on real hardware.',
                ),
                _FeatureRow(
                  feature: 'App-switcher protection',
                  android: 'Alias for screenshot protection (same flag)',
                  ios: 'Full support (blur overlay, public API only)',
                ),
              ],
            ),
            SectionCard(
              title: 'Documented SDK limitations',
              subtitle: 'Found while building this example app. Not worked '
                  'around silently — the SDK source was never modified.',
              children: const [
                _LimitationTile(
                  title: '1. No detector removal API',
                  body: 'FlutterShield/DetectionManager expose '
                      'registerDetector() but no unregisterDetector()/'
                      'removeDetector() counterpart. Disabling a detector '
                      'here only takes effect on the next Reinitialize, '
                      'which rebuilds DetectionManager fresh — see Runtime '
                      'Controls.',
                ),
                _LimitationTile(
                  title: '2. No public Logger/LogSink access',
                  body: 'FlutterShield never exposes the SDK\'s internal '
                      'Logger/LogSink extension point. The Logs screen '
                      'shows this app\'s own SDK call history instead — the '
                      'closest faithful substitute reachable from host-app '
                      'code today.',
                ),
                _LimitationTile(
                  title: '3. SecurityEvent.data is limited',
                  body: 'SecurityEvent.data — as constructed by '
                      'DefaultSecurityManager.processResult() — only ever '
                      'carries {action, confidence}. The original '
                      'DetectionResult.evidence is not forwarded. Recording '
                      'state is inferred from confidence == 1.0, not a '
                      'direct field — see the Recording Demo screen.',
                ),
                _LimitationTile(
                  title: '4. Callback name collisions are undetected',
                  body: 'NativeBridge.registerCallback is a last-write-wins '
                      'map with zero collision detection. Registering a '
                      'callback under "onScreenshotTaken" or '
                      '"onScreenCaptureStateChanged" silently overrides the '
                      'SDK\'s own internal ScreenCaptureController routing. '
                      'The Callbacks screen refuses these names by default '
                      'and offers a clearly-labeled "Advanced" opt-in to '
                      'demonstrate the risk deliberately.',
                ),
                _LimitationTile(
                  title: '5. Public library exports only FlutterShield',
                  body: 'package:flutter_shield/flutter_shield.dart exports '
                      'nothing but the FlutterShield facade — Detector, '
                      'Rule, FlutterShieldConfig, SecurityEvent, and every '
                      'concrete detector live under lib/src and are never '
                      're-exported. Any host app that registers a custom '
                      'Detector/Rule or constructs a config must import '
                      'from lib/src directly (as this example app does), '
                      'which is why flutter analyze reports '
                      '"implementation_imports" info-lints throughout — a '
                      'property of the SDK\'s current export surface, not '
                      'an error in this app.',
                ),
              ],
            ),
            const SectionCard(
              title: 'Credits',
              children: [
                Text('FlutterShield reference example app.'),
                Text('Built to demonstrate 100% of the public SDK surface '
                    'without modifying any SDK source.'),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.feature,
    required this.android,
    required this.ios,
  });

  final String feature;
  final String android;
  final String ios;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(feature, style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('Android: $android', style: theme.textTheme.bodySmall),
          Text('iOS: $ios', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _LimitationTile extends StatelessWidget {
  const _LimitationTile({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 18, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text(body, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
