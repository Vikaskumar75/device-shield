import 'package:flutter/material.dart';

import '../core/shield_scope.dart';
import '../widgets/status_card.dart';

/// Displays every counter on [Statistics] — purely local bookkeeping
/// derived from observing SDK calls/events, useful for eyeballing that
/// nothing is silently dropped during rapid or repeated actions (the
/// Performance manual test category).
class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ShieldScope.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final stats = controller.stats;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const InfoBanner(
              message:
                  'Local counters only, derived from observing this '
                  'app\'s own SDK calls and event stream — not an SDK API.',
            ),
            SectionCard(
              title: 'Counters',
              trailing: TextButton.icon(
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Reset'),
                onPressed: controller.resetStatistics,
              ),
              children: [
                StatusRow(
                  label: 'SDK initialized count',
                  value: '${stats.sdkInitializedCount}',
                ),
                StatusRow(
                  label: 'Screenshots detected',
                  value: '${stats.screenshotsDetected}',
                ),
                StatusRow(
                  label: 'Recording started',
                  value: '${stats.recordingStarted}',
                ),
                StatusRow(
                  label: 'Recording stopped',
                  value: '${stats.recordingStopped}',
                ),
                StatusRow(
                  label: 'Protection enabled count',
                  value: '${stats.protectionEnabledCount}',
                ),
                StatusRow(
                  label: 'Protection disabled count',
                  value: '${stats.protectionDisabledCount}',
                ),
                StatusRow(
                  label: 'Callbacks fired',
                  value: '${stats.callbacksFired}',
                ),
                StatusRow(
                  label: 'Events emitted',
                  value: '${stats.eventsEmitted}',
                ),
                StatusRow(label: 'Errors', value: '${stats.errors}'),
                StatusRow(label: 'Warnings', value: '${stats.warnings}'),
              ],
            ),
          ],
        );
      },
    );
  }
}
