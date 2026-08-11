import 'package:flutter/material.dart';
import 'package:flutter_shield/src/models/flutter_shield_config.dart';

import '../core/shield_scope.dart';
import '../widgets/status_card.dart';

/// Every editable [FlutterShieldConfig] field, applied via
/// `ShieldController.updateConfig` + a transparent `reinitialize()` when
/// the SDK is already running (config-3 manual test case) — this screen
/// never mutates the config field-by-field on the SDK itself, since no
/// such API exists; the only supported way to change config is a fresh
/// `initialize`/`reinitialize` call, which this screen makes explicit.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late FlutterShieldConfig _pending;
  late final TextEditingController _periodicCheckInterval;
  late final TextEditingController _maxRetryAttempts;
  late final TextEditingController _retryDelay;
  late final TextEditingController _checkTimeout;
  late final TextEditingController _riskWeight;
  bool _initializedFromController = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedFromController) {
      _pending = ShieldScope.of(context).config;
      _periodicCheckInterval =
          TextEditingController(text: '${_pending.periodicCheckInterval}');
      _maxRetryAttempts =
          TextEditingController(text: '${_pending.maxRetryAttempts}');
      _retryDelay = TextEditingController(text: '${_pending.retryDelay}');
      _checkTimeout = TextEditingController(text: '${_pending.checkTimeout}');
      _riskWeight = TextEditingController(
          text: _pending.screenshotRecordingRiskScoreWeight.toStringAsFixed(2));
      _initializedFromController = true;
    }
  }

  @override
  void dispose() {
    _periodicCheckInterval.dispose();
    _maxRetryAttempts.dispose();
    _retryDelay.dispose();
    _checkTimeout.dispose();
    _riskWeight.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final controller = ShieldScope.of(context);
    final newConfig = _pending.copyWith(
      periodicCheckInterval: int.tryParse(_periodicCheckInterval.text) ??
          _pending.periodicCheckInterval,
      maxRetryAttempts:
          int.tryParse(_maxRetryAttempts.text) ?? _pending.maxRetryAttempts,
      retryDelay: int.tryParse(_retryDelay.text) ?? _pending.retryDelay,
      checkTimeout: int.tryParse(_checkTimeout.text) ?? _pending.checkTimeout,
      screenshotRecordingRiskScoreWeight:
          (double.tryParse(_riskWeight.text) ?? _pending
                  .screenshotRecordingRiskScoreWeight)
              .clamp(0.0, 1.0),
    );
    controller.updateConfig(newConfig);
    final messenger = ScaffoldMessenger.of(context);
    if (controller.isInitialized) {
      final ok = await controller.reinitialize();
      messenger.showSnackBar(SnackBar(
        content: Text(ok
            ? 'Config applied — SDK reinitialized'
            : 'Config saved, but reinitialize failed — see Errors'),
      ));
    } else {
      messenger.showSnackBar(const SnackBar(
        content: Text('Config saved — will take effect on next Initialize'),
      ));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const InfoBanner(
          message: 'Changes apply on "Apply" — if the SDK is already '
              'running, it will be transparently reinitialized.',
        ),
        SectionCard(
          title: 'Core',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Debug logging'),
              value: _pending.debugLogging,
              onChanged: (v) =>
                  setState(() => _pending = _pending.copyWith(debugLogging: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Run on UI thread'),
              value: _pending.runOnUIThread,
              onChanged: (v) => setState(
                  () => _pending = _pending.copyWith(runOnUIThread: v)),
            ),
            _NumberField(
                label: 'Periodic check interval (ms)',
                controller: _periodicCheckInterval),
            _NumberField(
                label: 'Max retry attempts', controller: _maxRetryAttempts),
            _NumberField(label: 'Retry delay (ms)', controller: _retryDelay),
            _NumberField(
                label: 'Check timeout (ms)', controller: _checkTimeout),
          ],
        ),
        SectionCard(
          title: 'Screenshot & Recording',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable screenshot detection at boot'),
              value: _pending.enableScreenshotDetection,
              onChanged: (v) => setState(() =>
                  _pending = _pending.copyWith(enableScreenshotDetection: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable recording detection at boot'),
              value: _pending.enableScreenRecordingDetection,
              onChanged: (v) => setState(() => _pending = _pending.copyWith(
                  enableScreenRecordingDetection: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable screenshot protection at boot'),
              subtitle: const Text('Android only — applies FLAG_SECURE '
                  'SDK-wide from the start.'),
              value: _pending.enableScreenshotProtection,
              onChanged: (v) => setState(() =>
                  _pending = _pending.copyWith(enableScreenshotProtection: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable app-switcher protection at boot'),
              subtitle: const Text('Android: alias for screenshot '
                  'protection above (same FLAG_SECURE flag). iOS: a real, '
                  'independent blur overlay.'),
              value: _pending.enableAppSwitcherProtection,
              onChanged: (v) => setState(() => _pending =
                  _pending.copyWith(enableAppSwitcherProtection: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow recording detection in debug builds'),
              value: _pending.allowRecordingDetectionInDebug,
              onChanged: (v) => setState(() => _pending = _pending.copyWith(
                  allowRecordingDetectionInDebug: v)),
            ),
            _NumberField(
              label: 'Risk score weight (0.0–1.0)',
              controller: _riskWeight,
              isDouble: true,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton.icon(
            onPressed: _apply,
            icon: const Icon(Icons.check),
            label: const Text('Apply'),
          ),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    this.isDouble = false,
  });

  final String label;
  final TextEditingController controller;
  final bool isDouble;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: isDouble),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
