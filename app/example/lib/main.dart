import 'dart:async';

import 'package:device_shield/device_shield.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

/// A one-screen demo of every device_shield feature.
class ExampleApp extends StatelessWidget {
  /// Creates the demo app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'device_shield example',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

/// Runs the checks and toggles the protections.
class HomePage extends StatefulWidget {
  /// Creates the home page.
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  SecurityReport? _report;
  bool _checking = false;

  bool _screenshotProtection = false;
  bool _appSwitcherProtection = false;
  bool? _screenRecorded;
  final List<String> _events = [];
  final List<StreamSubscription<Object?>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _subscriptions
      ..add(DeviceShield.screenshots.listen((_) => _log('Screenshot taken')))
      ..add(
        DeviceShield.screenRecordingChanges.listen((recording) {
          setState(() => _screenRecorded = recording);
          _log(
            recording ? 'Screen recording started' : 'Screen recording stopped',
          );
        }),
      );
    unawaited(_refreshRecording());
    unawaited(_runChecks());
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  Future<void> _runChecks() async {
    setState(() => _checking = true);
    final report = await DeviceShield.check();
    if (!mounted) return;
    setState(() {
      _report = report;
      _checking = false;
    });
  }

  Future<void> _refreshRecording() async {
    final recorded = await DeviceShield.isScreenRecorded();
    if (mounted) setState(() => _screenRecorded = recorded);
  }

  Future<void> _setProtection({
    required bool screenshot,
    required bool enabled,
  }) async {
    final result = screenshot
        ? await DeviceShield.setScreenshotProtection(enabled)
        : await DeviceShield.setAppSwitcherProtection(enabled);
    if (!mounted) return;
    if (result == ProtectionResult.applied) {
      setState(() {
        if (screenshot) {
          _screenshotProtection = enabled;
        } else {
          _appSwitcherProtection = enabled;
        }
      });
    }
    _log(
      '${screenshot ? 'Screenshot' : 'App-switcher'} protection '
      '${enabled ? 'on' : 'off'}: ${result.name}',
    );
  }

  void _log(String message) {
    if (!mounted) return;
    final time = TimeOfDay.now().format(context);
    setState(() => _events.insert(0, '$time  $message'));
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('device_shield')),
      body: RefreshIndicator(
        onRefresh: _runChecks,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionHeader(
              title: 'Device checks',
              trailing: _checking
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: 'Run checks again',
                      icon: const Icon(Icons.refresh),
                      onPressed: _runChecks,
                    ),
            ),
            if (report == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final result in report.all) _CheckTile(result),
            const SizedBox(height: 24),
            const _SectionHeader(title: 'Screen'),
            SwitchListTile(
              title: const Text('Screenshot protection'),
              subtitle: const Text('Blocks screenshots and recording'),
              value: _screenshotProtection,
              onChanged: (value) =>
                  _setProtection(screenshot: true, enabled: value),
            ),
            SwitchListTile(
              title: const Text('App-switcher protection'),
              subtitle: const Text('Hides content in the app switcher'),
              value: _appSwitcherProtection,
              onChanged: (value) =>
                  _setProtection(screenshot: false, enabled: value),
            ),
            ListTile(
              title: const Text('Screen being recorded'),
              trailing: Text(switch (_screenRecorded) {
                true => 'Yes',
                false => 'No',
                null => 'Unknown on this platform',
              }),
            ),
            const Card(
              child: ListTile(
                leading: Icon(Icons.account_balance),
                title: Text('Sample sensitive content'),
                subtitle: Text('Account •••• 4821 · Balance 12,450.00'),
              ),
            ),
            const SizedBox(height: 24),
            const _SectionHeader(title: 'Events'),
            if (_events.isEmpty)
              const ListTile(
                title: Text('Take a screenshot or start a screen recording.'),
              )
            else
              for (final event in _events.take(20))
                ListTile(dense: true, title: Text(event)),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile(this.result);

  final CheckResult result;

  static const _titles = {
    CheckType.root: 'Root',
    CheckType.jailbreak: 'Jailbreak',
    CheckType.emulator: 'Emulator / simulator',
    CheckType.debugger: 'Debugger',
    CheckType.mockLocation: 'Mock location',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (result.status) {
      CheckStatus.detected => (Icons.warning_amber, colors.error, 'Detected'),
      CheckStatus.clear => (
        Icons.check_circle_outline,
        colors.primary,
        'Clear',
      ),
      CheckStatus.notApplicable => (
        Icons.remove_circle_outline,
        colors.outline,
        'Not applicable',
      ),
      CheckStatus.failed => (Icons.error_outline, colors.tertiary, 'Failed'),
    };
    final details = [
      ?result.error,
      if (result case MockLocationResult(locationPermissionGranted: false))
        'No location permission: location signals skipped',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 12),
                Expanded(child: Text(_titles[result.type]!)),
                Text(label, style: TextStyle(color: color)),
              ],
            ),
            if (result.signals.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final signal in result.signals)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${signal.id} · ${signal.strength.name}'),
                    ),
                ],
              ),
            ],
            for (final detail in details)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
