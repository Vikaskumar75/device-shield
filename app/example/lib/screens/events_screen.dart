import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_shield/flutter_shield.dart';

import '../core/shield_scope.dart';
import '../widgets/severity_chip.dart';

/// The live event feed — every [SecurityEvent] the SDK (or this app's own
/// "Simulate event" dev tool) has emitted, with search/filter, raw-JSON
/// inspection, copy-to-clipboard, and pausable auto-scroll (event-5/
/// event-6 manual test cases: ordering and duplicate handling are both
/// visible here in real time).
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  EventSeverity? _severityFilter;
  bool _autoScroll = true;
  int _lastKnownCount = 0;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeAutoScroll(int currentCount) {
    if (currentCount != _lastKnownCount) {
      _lastKnownCount = currentCount;
      if (_autoScroll && _scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ShieldScope.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final query = _searchController.text.trim().toLowerCase();
        final filtered = controller.events.where((event) {
          if (_severityFilter != null && event.severity != _severityFilter) {
            return false;
          }
          if (query.isEmpty) return true;
          return event.type.toLowerCase().contains(query) ||
              (event.source?.toLowerCase().contains(query) ?? false);
        }).toList();
        _maybeAutoScroll(controller.events.length);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search by type or source',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<EventSeverity?>(
                          initialValue: _severityFilter,
                          decoration: const InputDecoration(
                            labelText: 'Severity filter',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('All')),
                            for (final s in EventSeverity.values)
                              DropdownMenuItem(value: s, child: Text(s.name)),
                          ],
                          onChanged: (v) => setState(() => _severityFilter = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Auto-scroll'),
                        selected: _autoScroll,
                        onSelected: (v) => setState(() => _autoScroll = v),
                      ),
                      IconButton(
                        tooltip: 'Simulate a local event',
                        icon: const Icon(Icons.science_outlined),
                        onPressed: controller.simulateEvent,
                      ),
                      IconButton(
                        tooltip: 'Clear events',
                        icon: const Icon(Icons.clear_all),
                        onPressed: controller.clearEvents,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No events yet'))
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) =>
                          _EventTile(event: filtered[index]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final SecurityEvent event;

  @override
  Widget build(BuildContext context) {
    final json = const JsonEncoder.withIndent('  ').convert(event.toJson());
    return ExpansionTile(
      leading: Icon(eventTypeIcon(event.type)),
      title: Text(event.type),
      subtitle: Text(event.timestamp.toIso8601String()),
      trailing: SeverityChip(severity: event.severity),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.source != null)
                Text('Source: ${event.source}',
                    style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(json,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy raw JSON'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: json));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard')),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
