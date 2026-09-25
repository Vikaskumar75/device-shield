import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_shield/flutter_shield.dart';

import 'app_error.dart';
import 'callback_record.dart';
import 'log_entry.dart';
import 'statistics.dart';

/// A trivial custom [Rule] — demonstrates the FR-17 extension point
/// (`FlutterShield.addRule`/`removeRule`). Matches nothing on its own;
/// its only job is to prove the registration mechanics work.
class DemoRule implements Rule {
  @override
  final String id = 'example-demo-rule';
  @override
  final int priority = 100;
  @override
  final SecurityAction action = SecurityAction.report;
  int evaluationCount = 0;

  @override
  bool matches(DetectionResult result) {
    evaluationCount++;
    return false;
  }
}

/// A trivial custom [Detector] — demonstrates the FR-18 extension point
/// and doubles as the Manual Test screen's "unknown event type" case: its
/// `type` is deliberately not one of the SDK's built-in identifiers.
class DemoCustomDetector implements Detector {
  @override
  final String type = 'example_custom_probe';
  @override
  final int priority = 50;

  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {}

  @override
  Future<DetectionResult> check() async => DetectionResult(
        type: type,
        detected: true,
        confidence: 0.42,
        timestamp: DateTime.now(),
        evidence: const {'note': 'example custom detector — always fires'},
      );
}

/// The application's single source of truth. Every SDK call the example
/// app makes goes through here, wrapped so nothing fails silently (every
/// async action is logged, and every exception is captured for the Error
/// screen — see [_run]) and so every screen observes the same live state
/// via [ChangeNotifier]/[ListenableBuilder], rather than each screen
/// managing its own copy.
///
/// Also the single place this app's own discovered SDK gaps are documented
/// in code (see the doc comments on [setDetectorEnabled] and
/// [setAdvancedRawCallbackInterception] below) — cross-referenced in
/// MANUAL_TEST_PLAN.md and the About screen, not hidden.
class ShieldController extends ChangeNotifier {
  ShieldController() {
    _nativeBridge = DefaultNativeBridge();
    _emulatorDetector = EmulatorDetector(nativeBridge: _nativeBridge);
    _debuggerDetector = DebuggerDetector(nativeBridge: _nativeBridge);
    _screenshotDetector = ScreenshotDetector(nativeBridge: _nativeBridge);
    _screenRecordingDetector =
        ScreenRecordingDetector(nativeBridge: _nativeBridge);
    _rootDetector = RootDetector(nativeBridge: _nativeBridge);
    _jailbreakDetector = JailbreakDetector(nativeBridge: _nativeBridge);
    _mockLocationDetector = MockLocationDetector(nativeBridge: _nativeBridge);
  }

  late final NativeBridge _nativeBridge;
  late final EmulatorDetector _emulatorDetector;
  late final DebuggerDetector _debuggerDetector;
  late final ScreenshotDetector _screenshotDetector;
  late final ScreenRecordingDetector _screenRecordingDetector;
  late final RootDetector _rootDetector;
  late final JailbreakDetector _jailbreakDetector;
  late final MockLocationDetector _mockLocationDetector;
  final DemoRule _demoRule = DemoRule();
  final DemoCustomDetector _demoCustomDetector = DemoCustomDetector();

  StreamSubscription<SecurityEvent>? _subscription;

  // ---------------------------------------------------------------------
  // Live state
  // ---------------------------------------------------------------------

  String platformVersion = 'Unknown';
  FlutterShieldConfig config = const FlutterShieldConfig();
  bool demoRuleActive = false;
  bool advancedRawCallbackInterceptionEnabled = false;

  /// Set when the current running session began (successful [initialize]
  /// or [reinitialize]), cleared on [shutdown]/[dispose_] — backs the
  /// Health Monitor screen's uptime display. Deliberately local-only:
  /// the SDK exposes no uptime API of its own.
  DateTime? sessionStartedAt;

  /// Explicit on-demand [checkNow] outcomes only — backs the Health
  /// Monitor screen. The SDK's own internal periodic timer runs
  /// `checkNow()` too, but exposes no callback/event marking a periodic
  /// tick's own success or failure, so those cannot be counted here; this
  /// is an honest, documented scope limit, not an omission.
  int checkNowSuccessCount = 0;
  int checkNowFailureCount = 0;

  /// Last raw [DetectionResult] obtained by calling `detector.check()`
  /// directly (Detectors screen's "run this detector now" action) — a
  /// deliberate, on-demand bypass of the SDK's own
  /// evaluate→executeAction→emit pipeline, used purely for display. This
  /// is the only way this app can see a `DetectionResult`'s `evidence` at
  /// all, since `SecurityEvent.data` never carries it (documented SDK
  /// limitation #3).
  final Map<String, DetectionResult> lastDetectorResults = {};

  SDKState get status =>
      FlutterShield.status; // always the SDK's own live truth, never cached

  bool get protectionEnabled {
    try {
      return FlutterShield.isScreenshotProtectionEnabled;
    } catch (_) {
      return false;
    }
  }

  bool get appSwitcherProtectionEnabled {
    try {
      return FlutterShield.isAppSwitcherProtectionEnabled;
    } catch (_) {
      return false;
    }
  }

  /// Inferred, not directly available — see the doc comment on
  /// [_handleEvent] for the documented `SecurityEvent.data` limitation
  /// this works around by inference rather than a direct field.
  bool? recordingActive;
  DateTime? lastScreenshotAt;
  int screenshotCount = 0;
  SecurityEvent? lastEvent;

  final List<SecurityEvent> events = [];
  final List<AppLogEntry> logs = [];
  final List<AppError> errors = [];
  final Statistics stats = Statistics();
  final Map<String, CallbackRecord> callbacks = {};
  final Map<String, bool> detectorEnabled = {
    EmulatorDetector.typeId: false,
    DebuggerDetector.typeId: false,
    ScreenshotDetector.typeId: false,
    ScreenRecordingDetector.typeId: false,
    RootDetector.typeId: false,
    JailbreakDetector.typeId: false,
    MockLocationDetector.typeId: false,
  };
  final Set<String> _detectorsPendingRemovalOnReinit = {};

  bool get isInitialized => status != SDKState.uninitialized;

  // ---------------------------------------------------------------------
  // Logging / error plumbing
  // ---------------------------------------------------------------------

  void _log(AppLogLevel level, String tag, String message) {
    logs.insert(0, AppLogEntry(level: level, tag: tag, message: message));
    if (logs.length > 500) logs.removeLast();
    if (level == AppLogLevel.warning) stats.warnings++;
    notifyListeners();
  }

  void _recordError(String operation, Object error, StackTrace stackTrace) {
    errors.insert(
        0, AppError(operation: operation, error: error, stackTrace: stackTrace));
    if (errors.length > 200) errors.removeLast();
    stats.errors++;
    _log(AppLogLevel.error, operation, 'Failed: $error');
  }

  /// Wraps every SDK call this app makes: logs the attempt, logs the
  /// outcome, and — critically — never lets an exception escape to crash
  /// the UI. Returns whether [action] completed without throwing, so
  /// calling widgets can show a success/failure toast per the "every
  /// button should show success/failure" requirement.
  Future<bool> _run(String operation, Future<void> Function() action) async {
    _log(AppLogLevel.info, 'Action', 'Starting: $operation');
    try {
      await action();
      _log(AppLogLevel.info, 'Action', '$operation — succeeded');
      return true;
    } catch (error, stackTrace) {
      _recordError(operation, error, stackTrace);
      return false;
    } finally {
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------
  // Initialization / lifecycle
  // ---------------------------------------------------------------------

  Future<bool> loadPlatformVersion() => _run('Get platform version', () async {
        platformVersion =
            await FlutterShield().getPlatformVersion() ?? 'Unknown';
      });

  Future<bool> initialize() => _run('Initialize SDK', () async {
        await FlutterShield.initialize(config: config);
        stats.sdkInitializedCount++;
        sessionStartedAt = DateTime.now();
        _subscribeToEvents();
        await _reapplyDetectorRegistrations();
      });

  Future<bool> shutdown() => _run('Shutdown SDK', () async {
        await FlutterShield.shutdown();
        sessionStartedAt = null;
      });

  Future<bool> reinitialize() => _run('Reinitialize SDK', () async {
        await FlutterShield.reinitialize(config: config);
        sessionStartedAt = DateTime.now();
        _detectorsPendingRemovalOnReinit.clear();
        _subscribeToEvents();
        await _reapplyDetectorRegistrations();
      });

  Future<bool> dispose_() => _run('Dispose SDK', () async {
        await _subscription?.cancel();
        _subscription = null;
        await FlutterShield.dispose();
        detectorEnabled.updateAll((key, value) => false);
        _detectorsPendingRemovalOnReinit.clear();
        recordingActive = null;
        sessionStartedAt = null;
      });

  Future<bool> pause() => _run('Pause SDK', () => FlutterShield.pause());

  Future<bool> resume() => _run('Resume SDK', () => FlutterShield.resume());

  Future<bool> checkNow() async {
    final ok = await _run('Check Now', () => FlutterShield.checkNow());
    if (ok) {
      checkNowSuccessCount++;
    } else {
      checkNowFailureCount++;
    }
    notifyListeners();
    return ok;
  }

  /// Runs [type]'s `Detector.check()` directly — bypassing
  /// evaluate→executeAction→emit entirely — purely so the Detectors
  /// screen can show a raw, current [DetectionResult] (including
  /// `evidence`, never forwarded into any `SecurityEvent`). This never
  /// touches `PolicyManager`/`EventManager` and produces no
  /// `SecurityEvent` of its own; it is a read-only inspection tool, not
  /// part of the SDK's real detection pipeline.
  Future<bool> runDetectorCheck(String type) => _run(
        'Run detector check: $type',
        () async {
          final result = await _detectorFor(type).check();
          lastDetectorResults[type] = result;
        },
      );

  // ---------------------------------------------------------------------
  // Protection
  // ---------------------------------------------------------------------

  Future<bool> enableProtection() => _run('Enable screenshot protection',
      () async {
    final applied = await FlutterShield.enableScreenshotProtection();
    stats.protectionEnabledCount++;
    if (!applied) {
      _log(AppLogLevel.warning, 'Protection',
          'Native reported applied:false — see Screenshot Protection screen '
              'for the honest platform explanation.');
    }
  });

  Future<bool> disableProtection() =>
      _run('Disable screenshot protection', () async {
        await FlutterShield.disableScreenshotProtection();
        stats.protectionDisabledCount++;
      });

  /// Android: a documented alias for [enableProtection] — same
  /// `FLAG_SECURE` flag. iOS: a real, independent mechanism (a blur
  /// overlay shown just before the OS captures the app-switcher
  /// snapshot) — the first protection call that can honestly report
  /// `applied: true` on iOS. See `ScreenCaptureController
  /// .enableAppSwitcherProtection`'s own doc comment.
  Future<bool> enableAppSwitcherProtection() =>
      _run('Enable app-switcher protection', () async {
        final applied = await FlutterShield.enableAppSwitcherProtection();
        if (!applied) {
          _log(AppLogLevel.warning, 'Protection',
              'Native reported applied:false for app-switcher protection.');
        }
      });

  Future<bool> disableAppSwitcherProtection() =>
      _run('Disable app-switcher protection',
          () => FlutterShield.disableAppSwitcherProtection());

  // ---------------------------------------------------------------------
  // Detectors — registration only; see the doc comment below for the
  // documented "no unregisterDetector" SDK gap this method works around
  // honestly rather than silently.
  // ---------------------------------------------------------------------

  /// Toggles whether [type] should be registered.
  ///
  /// **Documented SDK gap**: `FlutterShield`/`DetectionManager` expose
  /// `registerDetector()` but no `unregisterDetector()`/`removeDetector()`
  /// counterpart anywhere in the public API. Turning a detector **on**
  /// here calls the real API immediately. Turning one **off** cannot
  /// remove it from a running SDK at all — there is no API for that — so
  /// this only marks it for exclusion the next time [reinitialize] runs
  /// (which rebuilds `DetectionManager` fresh, per the SDK's own tested
  /// behavior). The UI surfaces this honestly rather than pretending an
  /// immediate removal happened.
  Future<bool> setDetectorEnabled(String type, bool enabled) async {
    if (enabled) {
      detectorEnabled[type] = true;
      _detectorsPendingRemovalOnReinit.remove(type);
      if (!isInitialized) return true;
      return _run('Register detector: $type', () async {
        await FlutterShield.registerDetector(_detectorFor(type));
      });
    } else {
      detectorEnabled[type] = false;
      if (isInitialized) {
        _detectorsPendingRemovalOnReinit.add(type);
        _log(AppLogLevel.warning, 'Detectors',
            '$type cannot be unregistered from a running SDK (no public API '
                'exists) — it will be excluded on the next Reinitialize.');
      }
      return true;
    }
  }

  bool isDetectorPendingRemoval(String type) =>
      _detectorsPendingRemovalOnReinit.contains(type);

  Detector _detectorFor(String type) {
    switch (type) {
      case EmulatorDetector.typeId:
        return _emulatorDetector;
      case DebuggerDetector.typeId:
        return _debuggerDetector;
      case ScreenshotDetector.typeId:
        return _screenshotDetector;
      case ScreenRecordingDetector.typeId:
        return _screenRecordingDetector;
      case RootDetector.typeId:
        return _rootDetector;
      case JailbreakDetector.typeId:
        return _jailbreakDetector;
      case MockLocationDetector.typeId:
        return _mockLocationDetector;
      default:
        return _demoCustomDetector;
    }
  }

  Future<void> _reapplyDetectorRegistrations() async {
    for (final entry in detectorEnabled.entries) {
      if (entry.value) {
        try {
          await FlutterShield.registerDetector(_detectorFor(entry.key));
        } catch (error, stackTrace) {
          _recordError('Re-register detector: ${entry.key}', error, stackTrace);
        }
      }
    }
    if (demoRuleActive) {
      try {
        await FlutterShield.addRule(_demoRule);
      } catch (_) {
        // Already added — ignore, matches PolicyManager's own additive model.
      }
    }
  }

  /// FR-18 demo: a custom [Detector] whose `type` the SDK has never seen —
  /// used by the Manual Test screen's "unknown event" case.
  Future<bool> registerCustomDetector() =>
      _run('Register custom detector', () async {
        await FlutterShield.registerDetector(_demoCustomDetector);
      });

  // ---------------------------------------------------------------------
  // Rules (FR-17 demo)
  // ---------------------------------------------------------------------

  Future<bool> toggleDemoRule(bool enabled) async {
    if (enabled) {
      final ok = await _run(
          'Add demo rule', () => FlutterShield.addRule(_demoRule));
      if (ok) demoRuleActive = true;
      return ok;
    } else {
      final ok = await _run('Remove demo rule',
          () => FlutterShield.removeRule(_demoRule.id));
      if (ok) demoRuleActive = false;
      return ok;
    }
  }

  // ---------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------

  void _subscribeToEvents() {
    _subscription?.cancel();
    _subscription = FlutterShield.subscribe(_handleEvent);
  }

  /// **Documented SDK limitation**: `SecurityEvent.data` — as actually
  /// constructed by `DefaultSecurityManager.processResult()` — only ever
  /// carries `{'action': ..., 'confidence': ...}`. The original
  /// `DetectionResult.evidence` (e.g. `isCaptured`, `signals`) is **not**
  /// forwarded into the emitted event at all. This app cannot show "why"
  /// a detection fired beyond its confidence score — only what's actually
  /// present is shown (see the Events screen's raw-JSON view), and
  /// `recordingActive` below is an *inference* from `confidence == 1.0`
  /// (`ScreenRecordingDetector`'s own confidence is always exactly `0.0`
  /// or `1.0`, never fractional — verified in the SDK's own source), not
  /// a directly-available field.
  void _handleEvent(SecurityEvent event) {
    events.insert(0, event);
    if (events.length > 500) events.removeLast();
    lastEvent = event;
    stats.eventsEmitted++;

    if (event.type == ScreenshotDetector.typeId) {
      lastScreenshotAt = event.timestamp;
      screenshotCount++;
      stats.screenshotsDetected++;
    } else if (event.type == ScreenRecordingDetector.typeId) {
      final confidence = (event.data['confidence'] as num?)?.toDouble();
      final wasActive = recordingActive;
      recordingActive = confidence == 1.0;
      if (recordingActive == true && wasActive != true) {
        stats.recordingStarted++;
      } else if (recordingActive == false && wasActive != false) {
        stats.recordingStopped++;
      }
    }
    notifyListeners();
  }

  void clearEvents() {
    events.clear();
    notifyListeners();
  }

  /// Developer-tool "simulate event" — inserts a clearly-labeled synthetic
  /// entry into this app's own local event list. This never calls into
  /// the SDK in any way and cannot be confused with a real detection: the
  /// `source` field is deliberately `'example-app-simulation'`, never
  /// `'SecurityManager'` (which only ever appears on genuine SDK events).
  void simulateEvent() {
    final event = SecurityEvent(
      type: 'simulated_event',
      timestamp: DateTime.now(),
      severity: EventSeverity.warning,
      source: 'example-app-simulation',
      data: const {'note': 'Locally simulated — never touched the SDK'},
    );
    _handleEvent(event);
    _log(AppLogLevel.info, 'DevTools', 'Simulated a fake event locally');
  }

  // ---------------------------------------------------------------------
  // Callbacks (NativeBridge.registerCallback/unregisterCallback demo)
  // ---------------------------------------------------------------------

  /// Registers a callback under an app-chosen [name].
  ///
  /// **Documented SDK risk, not silently avoided**: `NativeBridge
  /// .registerCallback` is a plain last-write-wins map with zero collision
  /// detection (verified directly in `DefaultNativeBridge`'s source). The
  /// SDK's own internal `ScreenCaptureController` already reserves the
  /// names `onScreenshotTaken`/`onScreenCaptureStateChanged`. Registering
  /// a callback under either of those exact names from host-app code
  /// would silently replace the SDK's own handler — breaking screenshot/
  /// recording event delivery with no warning from the SDK itself. This
  /// method refuses those two names for the ordinary demo path; see
  /// [setAdvancedRawCallbackInterception] for the deliberate,
  /// clearly-warned opt-in path that exists specifically to demonstrate
  /// this risk rather than hide it.
  bool registerCallback(String name) {
    if (_isReservedCallbackName(name)) {
      _log(AppLogLevel.warning, 'Callbacks',
          '"$name" is reserved internally by ScreenCaptureController — '
              'use the Advanced toggle to intercept it deliberately, with '
              'the documented risk shown.');
      return false;
    }
    final record = callbacks.putIfAbsent(name, () => CallbackRecord(name: name));
    record.registered = true;
    FlutterShield.registerCallback(name, (data) {
      record.recordInvocation(data);
      stats.callbacksFired++;
      _log(AppLogLevel.info, 'Callbacks', '"$name" invoked');
      notifyListeners();
    });
    _log(AppLogLevel.info, 'Callbacks', 'Registered "$name"');
    notifyListeners();
    return true;
  }

  void unregisterCallback(String name) {
    FlutterShield.unregisterCallback(name);
    callbacks[name]?.registered = false;
    _log(AppLogLevel.info, 'Callbacks', 'Unregistered "$name"');
    notifyListeners();
  }

  /// A local-only simulation — fires the callback's own recorded handler
  /// shape without a real native round trip, since no native code targets
  /// arbitrary app-chosen names (only the two reserved ones are ever
  /// actually sent). Mirrors [simulateEvent]'s same "clearly local, never
  /// touches the SDK" honesty.
  void simulateCallbackInvocation(String name) {
    final record = callbacks[name];
    if (record == null || !record.registered) return;
    record.recordInvocation({'simulated': true, 'at': DateTime.now().toIso8601String()});
    stats.callbacksFired++;
    _log(AppLogLevel.info, 'Callbacks', 'Simulated invocation of "$name"');
    notifyListeners();
  }

  static bool _isReservedCallbackName(String name) =>
      name == 'onScreenshotTaken' || name == 'onScreenCaptureStateChanged';

  /// The deliberate, clearly-warned opt-in path onto the collision risk
  /// documented on [registerCallback]. Enabling this **replaces** the
  /// SDK's own internal screenshot/recording routing until disabled —
  /// disabling it calls [reinitialize] to rebuild a fresh
  /// `ScreenCaptureController` and restore the SDK's own handlers, since
  /// this app holds no reference to what was overwritten.
  Future<bool> setAdvancedRawCallbackInterception(bool enabled) async {
    if (enabled) {
      advancedRawCallbackInterceptionEnabled = true;
      for (final name in const [
        'onScreenshotTaken',
        'onScreenCaptureStateChanged',
      ]) {
        final record =
            callbacks.putIfAbsent(name, () => CallbackRecord(name: name));
        record.registered = true;
        FlutterShield.registerCallback(name, (data) {
          record.recordInvocation(data);
          stats.callbacksFired++;
          _log(AppLogLevel.warning, 'Callbacks',
              'RAW native payload intercepted for "$name" — the SDK\'s own '
                  'internal handler for this name is NOT running right now.');
          notifyListeners();
        });
      }
      _log(AppLogLevel.warning, 'Callbacks',
          'Advanced raw interception ON — SDK\'s internal screenshot/'
              'recording routing is overridden until this is turned off.');
      notifyListeners();
      return true;
    } else {
      advancedRawCallbackInterceptionEnabled = false;
      callbacks.remove('onScreenshotTaken');
      callbacks.remove('onScreenCaptureStateChanged');
      // Reinitializing rebuilds ScreenCaptureController fresh, restoring
      // the SDK's own internal callback registrations.
      return reinitialize();
    }
  }

  // ---------------------------------------------------------------------
  // Misc
  // ---------------------------------------------------------------------

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  void resetStatistics() {
    stats.reset();
    notifyListeners();
  }

  Future<void> refreshStatus() async {
    // status/protectionEnabled are always read live from FlutterShield
    // itself (see the getters above) — this exists purely so UI code has
    // an explicit, discoverable "refresh" action per the spec, and to
    // re-read platform version if it hasn't loaded yet.
    if (platformVersion == 'Unknown') {
      await loadPlatformVersion();
    }
    notifyListeners();
  }

  void updateConfig(FlutterShieldConfig newConfig) {
    config = newConfig;
    notifyListeners();
  }

  /// Resets this app's own local bookkeeping only — events, logs, errors,
  /// statistics, callback records, per-detector last results, and health
  /// counters. Deliberately does **not** touch the SDK itself (no
  /// shutdown/dispose call): resetting live SDK state is already a
  /// distinct, explicit action via Runtime Controls, and conflating the
  /// two would make this button's effect surprising.
  void resetDemo() {
    events.clear();
    logs.clear();
    errors.clear();
    stats.reset();
    callbacks.clear();
    lastDetectorResults.clear();
    lastEvent = null;
    lastScreenshotAt = null;
    screenshotCount = 0;
    recordingActive = null;
    checkNowSuccessCount = 0;
    checkNowFailureCount = 0;
    _log(AppLogLevel.info, 'DevTools',
        'Reset Demo — local example-app state cleared (SDK state untouched)');
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
