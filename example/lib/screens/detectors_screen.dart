import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_shield/src/detectors/debugger_detector.dart';
import 'package:flutter_shield/src/detectors/emulator_detector.dart';
import 'package:flutter_shield/src/detectors/screen_recording_detector.dart';
import 'package:flutter_shield/src/detectors/screenshot_detector.dart';
import 'package:flutter_shield/src/models/detection_result.dart';

import '../core/shield_scope.dart';
import '../widgets/status_card.dart';

class _DetectorMeta {
  const _DetectorMeta({
    required this.typeId,
    required this.label,
    required this.platformSupport,
  });

  final String typeId;
  final String label;
  final String platformSupport;
}

const _detectors = [
  _DetectorMeta(
    typeId: EmulatorDetector.typeId,
    label: 'Emulator Detector',
    platformSupport: 'Android & iOS — always supported',
  ),
  _DetectorMeta(
    typeId: DebuggerDetector.typeId,
    label: 'Debugger Detector',
    platformSupport: 'Android & iOS — always supported',
  ),
  _DetectorMeta(
    typeId: ScreenshotDetector.typeId,
    label: 'Screenshot Detector',
    platformSupport: 'Android API 34+ only; iOS all versions',
  ),
  _DetectorMeta(
    typeId: ScreenRecordingDetector.typeId,
    label: 'Screen Recording Detector',
    platformSupport: 'iOS only — Android honestly reports unsupported',
  ),
];

/// Per-detector inspection screen — demonstrates the open `Detector`
/// contract (FR-18) directly: each "Run check now" button calls
/// `Detector.check()` on the app's own held instance, bypassing the SDK's
/// evaluate→executeAction→emit pipeline entirely, purely to surface the
/// raw [DetectionResult] (including `evidence`, which `SecurityEvent`
/// never carries — documented SDK limitation #3).
class DetectorsScreen extends StatelessWidget {
  const DetectorsScreen({super.key});

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
              message: '"Run check now" calls Detector.check() directly on '
                  'the held instance — a read-only inspection tool, not '
                  'part of the real detection pipeline. It emits no '
                  'SecurityEvent of its own.',
            ),
            for (final meta in _detectors)
              _DetectorCard(
                meta: meta,
                enabled: controller.detectorEnabled[meta.typeId] ?? false,
                eventCount: controller.events
                    .where((e) => e.type == meta.typeId)
                    .length,
                lastResult: controller.lastDetectorResults[meta.typeId],
                onRunCheck: () => controller.runDetectorCheck(meta.typeId),
              ),
          ],
        );
      },
    );
  }
}

class _DetectorCard extends StatelessWidget {
  const _DetectorCard({
    required this.meta,
    required this.enabled,
    required this.eventCount,
    required this.lastResult,
    required this.onRunCheck,
  });

  final _DetectorMeta meta;
  final bool enabled;
  final int eventCount;
  final DetectionResult? lastResult;
  final Future<bool> Function() onRunCheck;

  @override
  Widget build(BuildContext context) {
    final result = lastResult;
    return SectionCard(
      title: meta.label,
      subtitle: meta.platformSupport,
      trailing: OutlinedButton.icon(
        icon: const Icon(Icons.play_arrow, size: 18),
        label: const Text('Run check'),
        onPressed: () => onRunCheck(),
      ),
      children: [
        StatusRow(
          label: 'Registered with SDK',
          value: enabled ? 'Yes' : 'No',
          valueColor: enabled ? Colors.green : null,
        ),
        StatusRow(label: 'Events emitted (session)', value: '$eventCount'),
        if (result == null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No manual check run yet.'),
          )
        else ...[
          StatusRow(
              label: 'Last result — detected',
              value: result.detected ? 'Yes' : 'No',
              valueColor: result.detected ? Colors.red : Colors.green),
          StatusRow(
              label: 'Confidence',
              value: result.confidence.toStringAsFixed(2)),
          StatusRow(label: 'Status', value: result.status.name),
          StatusRow(
              label: 'Last execution',
              value: result.timestamp.toIso8601String()),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(result.evidence),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}
