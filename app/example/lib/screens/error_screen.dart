import 'package:flutter/material.dart';

import '../core/shield_scope.dart';
import '../widgets/status_card.dart';

/// Every [AppError] captured by `ShieldController._run` — proof that no
/// SDK exception ever crashes this app outright (log-3 manual test case).
/// Expandable to the full stack trace for debugging.
class ErrorScreen extends StatelessWidget {
  const ErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ShieldScope.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.errors.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No errors captured — every SDK call so far has '
                'either succeeded or is not yet attempted.',
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const InfoBanner(
              icon: Icons.error_outline,
              message:
                  'Every exception thrown by an SDK call in this app '
                  'is caught here — never a crash. Try "Initialize" twice '
                  'in a row to see ALREADY_INITIALIZING captured live.',
            ),
            for (final error in controller.errors)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ExpansionTile(
                  leading: const Icon(Icons.error, color: Colors.red),
                  title: Text(error.operation),
                  subtitle: Text(
                    error.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Occurred: ${error.timestamp.toIso8601String()}',
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SelectableText(
                              '${error.error}\n\n${error.stackTrace}',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
