import 'package:flutter/material.dart';

import '../core/shield_scope.dart';
import '../widgets/action_button.dart';
import '../widgets/status_card.dart';

/// Demonstrates `DeviceShield.enableScreenshotProtection()` /
/// `disableScreenshotProtection()` / `isScreenshotProtectionEnabled` —
/// imperative, proactive blocking, independent of detection entirely.
/// States the platform truth plainly: Android applies `FLAG_SECURE`,
/// confirmed working. iOS re-parents the Flutter root view's layer under
/// a `UITextField` secure-rendering layer — via undocumented internals,
/// not a supported Apple API, **and its black-screenshot effect is
/// unconfirmed**: live Simulator testing this session showed the
/// re-parenting executes (`applied: true`) but the actual screenshot
/// still captured full content, not black (design doc §18.5). Untested
/// on real hardware. `applied: true` on iOS means the call executed, not
/// that protection visibly works (protect-1/protect-9 manual test
/// cases).
class ProtectionScreen extends StatelessWidget {
  const ProtectionScreen({super.key});

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
              message:
                  'Android: FLAG_SECURE is applied SDK-wide — every '
                  'screen blocks screenshots and shows a black rectangle in '
                  'the recent-apps switcher, and "applied" is true. This is '
                  'confirmed working. iOS: attempts the same effect via an '
                  'undocumented UITextField secure-layer technique — NOT a '
                  'supported Apple API. "applied" is true on iOS too, but '
                  'that only means the call executed — live Simulator '
                  'testing found the screenshot still captured real '
                  'content, not black. UNCONFIRMED on real hardware. Do '
                  'not rely on this for iOS until physical-device-tested '
                  '(design doc §18.5).',
            ),
            SectionCard(
              title: 'Live status',
              children: [
                StatusRow(
                  label: 'Screenshot protection enabled',
                  value: controller.protectionEnabled ? 'Yes' : 'No',
                  valueColor: controller.protectionEnabled
                      ? Colors.green
                      : null,
                ),
              ],
            ),
            SectionCard(
              title: 'Controls',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ShieldActionButton(
                      label: 'Enable protection',
                      icon: Icons.shield,
                      filled: true,
                      onPressed: controller.enableProtection,
                    ),
                    ShieldActionButton(
                      label: 'Disable protection',
                      icon: Icons.shield_outlined,
                      onPressed: controller.disableProtection,
                    ),
                  ],
                ),
              ],
            ),
            const SectionCard(
              title: 'How to test',
              children: [
                Text('1. Runtime Controls → Initialize SDK.'),
                Text('2. Tap "Enable protection" above.'),
                Text(
                  '3. Android: try to take a screenshot — it will be '
                  'blocked (black image) and the recent-apps thumbnail '
                  'goes blank.',
                ),
                Text(
                  '4. iOS: try to take a screenshot (Cmd+S in '
                  'Simulator, or the side/volume-up chord on a real '
                  'device). On Simulator this is expected to still '
                  'show real content — unconfirmed whether it comes '
                  'back black on physical hardware (design doc §18.5).',
                ),
                Text(
                  '5. Tap "Disable protection" and confirm normal '
                  'screenshot behavior returns on both platforms.',
                ),
              ],
            ),
            const InfoBanner(
              message:
                  'App-switcher protection: Android is a documented '
                  'alias for the same FLAG_SECURE flag above. iOS is a '
                  'real, independent mechanism — a blur overlay covers '
                  'the app the instant it resigns active, before the OS '
                  'captures the app-switcher snapshot — "applied" is '
                  'true on iOS too.',
            ),
            SectionCard(
              title: 'Live status',
              children: [
                StatusRow(
                  label: 'App-switcher protection enabled',
                  value: controller.appSwitcherProtectionEnabled ? 'Yes' : 'No',
                  valueColor: controller.appSwitcherProtectionEnabled
                      ? Colors.green
                      : null,
                ),
              ],
            ),
            SectionCard(
              title: 'Controls',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ShieldActionButton(
                      label: 'Enable app-switcher protection',
                      icon: Icons.blur_on,
                      filled: true,
                      onPressed: controller.enableAppSwitcherProtection,
                    ),
                    ShieldActionButton(
                      label: 'Disable app-switcher protection',
                      icon: Icons.blur_off,
                      onPressed: controller.disableAppSwitcherProtection,
                    ),
                  ],
                ),
              ],
            ),
            const SectionCard(
              title: 'How to test (app-switcher)',
              children: [
                Text('1. Tap "Enable app-switcher protection" above.'),
                Text(
                  '2. iOS: swipe up to the App Switcher (or press Home) '
                  '— the app content is blurred instead of showing raw '
                  'content.',
                ),
                Text(
                  '3. Android: same as screenshot protection above — '
                  'Recents already shows a blank thumbnail.',
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
