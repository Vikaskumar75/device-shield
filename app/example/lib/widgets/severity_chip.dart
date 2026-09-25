import 'package:device_shield/device_shield.dart';
import 'package:flutter/material.dart';

/// Maps [EventSeverity] to a color and icon — the Events screen's own
/// color-coding/icon requirement, centralized here so every place that
/// renders a severity (Events list, Home's "last event", Logs) stays
/// visually consistent.
Color severityColor(EventSeverity severity) {
  switch (severity) {
    case EventSeverity.debug:
      return Colors.grey;
    case EventSeverity.info:
      return Colors.blue;
    case EventSeverity.warning:
      return Colors.orange;
    case EventSeverity.high:
      return Colors.deepOrange;
    case EventSeverity.critical:
      return Colors.red;
  }
}

IconData severityIcon(EventSeverity severity) {
  switch (severity) {
    case EventSeverity.debug:
      return Icons.bug_report_outlined;
    case EventSeverity.info:
      return Icons.info_outline;
    case EventSeverity.warning:
      return Icons.warning_amber_rounded;
    case EventSeverity.high:
      return Icons.error_outline;
    case EventSeverity.critical:
      return Icons.dangerous_outlined;
  }
}

IconData eventTypeIcon(String type) {
  switch (type) {
    case 'screenshot':
      return Icons.screenshot_monitor_outlined;
    case 'screen_recording':
      return Icons.fiber_smart_record_outlined;
    case 'emulator':
      return Icons.developer_mode_outlined;
    case 'debugger':
      return Icons.adb_outlined;
    case 'simulated_event':
      return Icons.science_outlined;
    default:
      return Icons.help_outline;
  }
}

class SeverityChip extends StatelessWidget {
  const SeverityChip({super.key, required this.severity});

  final EventSeverity severity;

  @override
  Widget build(BuildContext context) {
    final color = severityColor(severity);
    return Chip(
      avatar: Icon(severityIcon(severity), size: 16, color: color),
      label: Text(severity.name, style: TextStyle(color: color, fontSize: 12)),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
