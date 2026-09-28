import 'package:device_shield/device_shield.dart';
import 'package:flutter/material.dart';

import '../core/shield_scope.dart';
import '../widgets/status_card.dart';

String _formatDuration(Duration d) {
  if (d.inHours > 0) {
    return '${d.inHours}h ${d.inMinutes % 60}m ${d.inSeconds % 60}s';
  }
  if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
  return '${d.inSeconds}s';
}

/// A rollup of everything actually observable about the SDK's ongoing
/// health from host-app code. Deliberately does **not** report on the
/// SDK's own internal periodic timer's individual tick success/failure —
/// no callback or event exists for that (an honest scope limit, not an
/// omission); only explicit `checkNow()` calls, event arrival, and
/// recorded errors/warnings are counted.
class HealthMonitorScreen extends StatelessWidget {
  const HealthMonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ShieldScope.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final startedAt = controller.sessionStartedAt;
        final uptime = startedAt == null
            ? null
            : DateTime.now().difference(startedAt);
        final lastEventAt = controller.lastEvent?.timestamp;
        final sinceLastEvent = lastEventAt == null
            ? null
            : DateTime.now().difference(lastEventAt);
        final totalChecks =
            controller.checkNowSuccessCount + controller.checkNowFailureCount;
        final errorRate = totalChecks == 0
            ? 0.0
            : controller.checkNowFailureCount / totalChecks * 100;

        final healthy =
            controller.status == SDKState.running && controller.errors.isEmpty;
        final degraded =
            controller.status == SDKState.running &&
            controller.errors.isNotEmpty;

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            InfoBanner(
              icon: healthy
                  ? Icons.check_circle_outline
                  : (degraded ? Icons.warning_amber_rounded : Icons.circle),
              color: healthy
                  ? Colors.green.withValues(alpha: 0.15)
                  : (degraded ? Colors.orange.withValues(alpha: 0.15) : null),
              message: healthy
                  ? 'Healthy — running with no recorded errors.'
                  : degraded
                  ? 'Degraded — running, but ${controller.errors.length} '
                        'error(s) have been recorded.'
                  : 'Not running — status is ${controller.status.name}.',
            ),
            SectionCard(
              title: 'Session',
              children: [
                StatusRow(
                  label: 'Uptime (this session)',
                  value: uptime == null ? '—' : _formatDuration(uptime),
                ),
                StatusRow(
                  label: 'Session started at',
                  value: startedAt?.toIso8601String() ?? 'Not running',
                ),
                StatusRow(
                  label: 'Periodic check interval',
                  value: '${controller.config.periodicCheckInterval} ms',
                ),
              ],
            ),
            SectionCard(
              title: 'Explicit Check Now calls',
              subtitle:
                  'Only manually-triggered checks are counted — the '
                  'SDK exposes no signal for its own internal periodic '
                  'timer ticks.',
              children: [
                StatusRow(
                  label: 'Succeeded',
                  value: '${controller.checkNowSuccessCount}',
                ),
                StatusRow(
                  label: 'Failed',
                  value: '${controller.checkNowFailureCount}',
                ),
                StatusRow(
                  label: 'Failure rate',
                  value: '${errorRate.toStringAsFixed(1)}%',
                ),
              ],
            ),
            SectionCard(
              title: 'Event flow',
              children: [
                StatusRow(
                  label: 'Total events received',
                  value: '${controller.events.length}',
                ),
                StatusRow(
                  label: 'Last event received',
                  value: lastEventAt?.toIso8601String() ?? 'None yet',
                ),
                StatusRow(
                  label: 'Time since last event',
                  value: sinceLastEvent == null
                      ? '—'
                      : _formatDuration(sinceLastEvent),
                ),
              ],
            ),
            SectionCard(
              title: 'Errors & warnings',
              children: [
                StatusRow(
                  label: 'Errors recorded',
                  value: '${controller.stats.errors}',
                  valueColor: controller.stats.errors > 0 ? Colors.red : null,
                ),
                StatusRow(
                  label: 'Warnings recorded',
                  value: '${controller.stats.warnings}',
                  valueColor: controller.stats.warnings > 0
                      ? Colors.orange
                      : null,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
