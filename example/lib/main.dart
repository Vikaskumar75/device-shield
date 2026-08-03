import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_shield/flutter_shield.dart';
import 'package:flutter_shield/src/bridge/default_native_bridge.dart';
import 'package:flutter_shield/src/detectors/debugger_detector.dart';
import 'package:flutter_shield/src/models/detection_result.dart';
import 'package:flutter_shield/src/models/flutter_shield_config.dart';
import 'package:flutter_shield/src/models/security_event.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  final _flutterShieldPlugin = FlutterShield();

  late final DebuggerDetector _debuggerDetector;

  bool _sdkReady = false;
  bool _isChecking = false;
  String? _initError;

  DetectionResult? _debuggerResult;

  final List<SecurityEvent> _recentEvents = [];
  StreamSubscription<SecurityEvent>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    final nativeBridge = DefaultNativeBridge();
    _debuggerDetector = DebuggerDetector(nativeBridge: nativeBridge);

    initPlatformState();
    _initShield();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      platformVersion =
          await _flutterShieldPlugin.getPlatformVersion() ?? 'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  /// Boots the SDK, registers the debugger detector so it takes part in the
  /// periodic/`checkNow()` pipeline, and subscribes to the security event
  /// stream so the UI can show what the SDK itself observes.
  Future<void> _initShield() async {
    try {
      await FlutterShield.initialize(
        config: const FlutterShieldConfig(periodicCheckInterval: 5000),
      );
      await FlutterShield.registerDetector(_debuggerDetector);

      _eventSubscription = FlutterShield.subscribe((event) {
        if (!mounted) return;
        setState(() {
          _recentEvents.insert(0, event);
          if (_recentEvents.length > 20) _recentEvents.removeLast();
        });
      });

      if (!mounted) return;
      setState(() => _sdkReady = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _initError = error.toString());
    }
  }

  /// Runs the debugger detector directly (independent of the SDK's own
  /// periodic timer) so the UI can show a fresh, detailed [DetectionResult]
  /// — including per-signal evidence. Also nudges the SDK's own coordinated
  /// pipeline via [FlutterShield.checkNow], which is what drives the event
  /// feed above.
  Future<void> _runCheck() async {
    setState(() => _isChecking = true);
    try {
      final result = await _debuggerDetector.check();
      if (_sdkReady) {
        await FlutterShield.checkNow();
      }
      if (!mounted) return;
      setState(() => _debuggerResult = result);
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    unawaited(FlutterShield.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('FlutterShield example — Debugger detection')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Running on: $_platformVersion'),
              const SizedBox(height: 8),
              Text('SDK status: ${_sdkReady ? FlutterShield.status.name : 'initializing…'}'),
              if (_initError != null) ...[
                const SizedBox(height: 8),
                Text(
                  'SDK init failed: $_initError',
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isChecking ? null : _runCheck,
                child: Text(_isChecking ? 'Checking…' : 'Run debugger detection check'),
              ),
              const SizedBox(height: 16),
              _DetectionResultCard(
                title: 'Debugger detector',
                result: _debuggerResult,
              ),
              const SizedBox(height: 24),
              const Text(
                'Recent security events',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (_recentEvents.isEmpty) const Text('No events yet.'),
              for (final event in _recentEvents)
                Text(
                  '[${event.severity.name}] ${event.type} — ${event.data}',
                  style: const TextStyle(fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetectionResultCard extends StatelessWidget {
  const _DetectionResultCard({required this.title, required this.result});

  final String title;
  final DetectionResult? result;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            if (result == null)
              const Text('Not run yet.')
            else ...[
              Text('detected: ${result.detected}'),
              Text('confidence: ${result.confidence.toStringAsFixed(2)}'),
              Text('status: ${result.status.name}'),
              Text('signals: ${result.evidence['signals']}'),
            ],
          ],
        ),
      ),
    );
  }
}
