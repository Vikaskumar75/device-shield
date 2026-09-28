import 'package:flutter/material.dart';

import '../core/manual_test_case.dart';

const _statusColors = {
  ManualTestStatus.pending: Colors.grey,
  ManualTestStatus.running: Colors.blue,
  ManualTestStatus.passed: Colors.green,
  ManualTestStatus.failed: Colors.red,
};

const _statusIcons = {
  ManualTestStatus.pending: Icons.radio_button_unchecked,
  ManualTestStatus.running: Icons.hourglass_top,
  ManualTestStatus.passed: Icons.check_circle,
  ManualTestStatus.failed: Icons.cancel,
};

/// Renders the checklist mirrored exactly in docs/MANUAL_TEST_PLAN.md
/// ([buildDefaultManualTestCases]), grouped by category, with status
/// transitions, freeform notes, and a per-case reset. This screen tracks
/// its own state locally (a manual QA checklist, not SDK-observed data),
/// so it owns a plain [StatefulWidget] rather than going through
/// `ShieldController`.
class ManualTestScreen extends StatefulWidget {
  const ManualTestScreen({super.key});

  @override
  State<ManualTestScreen> createState() => _ManualTestScreenState();
}

class _ManualTestScreenState extends State<ManualTestScreen> {
  late final List<ManualTestCase> _cases = buildDefaultManualTestCases();

  Map<String, List<ManualTestCase>> get _grouped {
    final map = <String, List<ManualTestCase>>{};
    for (final c in _cases) {
      map.putIfAbsent(c.category, () => []).add(c);
    }
    return map;
  }

  int get _passed =>
      _cases.where((c) => c.status == ManualTestStatus.passed).length;
  int get _failed =>
      _cases.where((c) => c.status == ManualTestStatus.failed).length;

  void _setStatus(ManualTestCase c, ManualTestStatus status) {
    setState(() {
      c.status = status;
      c.lastRunAt = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: (_passed + _failed) / _cases.length,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$_passed passed / $_failed failed / ${_cases.length} total',
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final entry in grouped.entries)
                ExpansionTile(
                  title: Text(
                    entry.key,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  children: [
                    for (final c in entry.value)
                      _TestCaseTile(
                        testCase: c,
                        onStatusChanged: (s) => _setStatus(c, s),
                        onNotesChanged: (notes) =>
                            setState(() => c.notes = notes),
                        onReset: () => setState(c.reset),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TestCaseTile extends StatelessWidget {
  const _TestCaseTile({
    required this.testCase,
    required this.onStatusChanged,
    required this.onNotesChanged,
    required this.onReset,
  });

  final ManualTestCase testCase;
  final ValueChanged<ManualTestStatus> onStatusChanged;
  final ValueChanged<String> onNotesChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _statusIcons[testCase.status],
                    color: _statusColors[testCase.status],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      testCase.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reset',
                    icon: const Icon(Icons.restart_alt, size: 18),
                    onPressed: onReset,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                testCase.instructions,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final status in ManualTestStatus.values)
                    ChoiceChip(
                      label: Text(status.name),
                      selected: testCase.status == status,
                      onSelected: (_) => onStatusChanged(status),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: testCase.notes,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: onNotesChanged,
              ),
              if (testCase.lastRunAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Last run: ${testCase.lastRunAt}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
