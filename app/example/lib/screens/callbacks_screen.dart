import 'package:flutter/material.dart';

import '../core/shield_scope.dart';
import '../widgets/status_card.dart';

/// Demonstrates `NativeBridge.registerCallback`/`unregisterCallback` via
/// `ShieldController`, including the deliberately-refused reserved names
/// (`onScreenshotTaken`/`onScreenCaptureStateChanged`) and the opt-in
/// "Advanced raw interception" toggle that demonstrates — rather than
/// hides — the documented zero-collision-detection risk.
class CallbacksScreen extends StatefulWidget {
  const CallbacksScreen({super.key});

  @override
  State<CallbacksScreen> createState() => _CallbacksScreenState();
}

class _CallbacksScreenState extends State<CallbacksScreen> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

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
              message: 'The names "onScreenshotTaken" and '
                  '"onScreenCaptureStateChanged" are reserved internally by '
                  'ScreenCaptureController. Registering them here is '
                  'refused — see Advanced below to intercept them '
                  'deliberately.',
            ),
            SectionCard(
              title: 'Register a callback',
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Callback name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.add_link),
                  label: const Text('Register'),
                  onPressed: () {
                    final name = _nameController.text.trim();
                    if (name.isEmpty) return;
                    final ok = controller.registerCallback(name);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ok
                          ? 'Registered "$name"'
                          : '"$name" is reserved — refused'),
                    ));
                    if (ok) _nameController.clear();
                  },
                ),
              ],
            ),
            SectionCard(
              title: 'Registered callbacks',
              children: controller.callbacks.isEmpty
                  ? [const Text('None registered yet')]
                  : [
                      for (final record in controller.callbacks.values)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(record.registered
                              ? Icons.link
                              : Icons.link_off),
                          title: Text(record.name),
                          subtitle: Text(
                              'Invocations: ${record.invocationCount}'
                              '${record.lastInvokedAt != null ? ' • last: ${record.lastInvokedAt}' : ''}'),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              if (record.registered)
                                IconButton(
                                  tooltip: 'Simulate invocation',
                                  icon: const Icon(Icons.bolt),
                                  onPressed: () => controller
                                      .simulateCallbackInvocation(record.name),
                                ),
                              IconButton(
                                tooltip: 'Unregister',
                                icon: const Icon(Icons.close),
                                onPressed: record.registered
                                    ? () => controller
                                        .unregisterCallback(record.name)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                    ],
            ),
            SectionCard(
              title: 'Advanced: raw callback interception',
              subtitle: 'Deliberately demonstrates the collision risk — '
                  'do not enable unless you want to see SDK screenshot/'
                  'recording routing overridden.',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Intercept reserved names'),
                  value: controller.advancedRawCallbackInterceptionEnabled,
                  onChanged: (v) =>
                      controller.setAdvancedRawCallbackInterception(v),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
