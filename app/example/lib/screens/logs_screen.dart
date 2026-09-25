import 'package:flutter/material.dart';

import '../core/log_entry.dart';
import '../core/shield_scope.dart';
import '../widgets/status_card.dart';

/// The example app's own action log — see [AppLogEntry]'s doc comment for
/// the documented SDK limitation this works around: `DeviceShield` never
/// exposes the SDK's internal `Logger`/`LogSink` extension point, so this
/// records every SDK call *this app* makes and its outcome, the closest
/// faithful substitute reachable from host-app code today.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  AppLogLevel? _levelFilter;

  Color _colorFor(AppLogLevel level, ThemeData theme) => switch (level) {
    AppLogLevel.debug => Colors.grey,
    AppLogLevel.info => theme.colorScheme.primary,
    AppLogLevel.warning => Colors.orange,
    AppLogLevel.error => theme.colorScheme.error,
  };

  @override
  Widget build(BuildContext context) {
    final controller = ShieldScope.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final logs = controller.logs
            .where((l) => _levelFilter == null || l.level == _levelFilter)
            .toList();
        return Column(
          children: [
            const InfoBanner(
              message:
                  'DeviceShield never exposes its internal Logger/'
                  'LogSink publicly — this log shows this app\'s own SDK '
                  'call history instead, the closest reachable substitute.',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<AppLogLevel?>(
                      initialValue: _levelFilter,
                      decoration: const InputDecoration(
                        labelText: 'Level filter',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(child: Text('All')),
                        for (final l in AppLogLevel.values)
                          DropdownMenuItem(value: l, child: Text(l.name)),
                      ],
                      onChanged: (v) => setState(() => _levelFilter = v),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Clear logs',
                    icon: const Icon(Icons.clear_all),
                    onPressed: controller.clearLogs,
                  ),
                ],
              ),
            ),
            Expanded(
              child: logs.isEmpty
                  ? const Center(child: Text('No logs yet'))
                  : ListView.builder(
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final entry = logs[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.circle,
                            size: 10,
                            color: _colorFor(entry.level, theme),
                          ),
                          title: Text(entry.message),
                          subtitle: Text(
                            '${entry.tag} • ${entry.timestamp.toIso8601String()}',
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
