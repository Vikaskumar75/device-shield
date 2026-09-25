/// State of one [ManualTestCase] as the user works through the checklist.
enum ManualTestStatus { pending, running, passed, failed }

/// One row in the Manual Test screen's checklist. Purely a UI/tracking
/// model — running a case does not call any hidden SDK API; the user
/// performs the described action (often via other screens/buttons in this
/// same app) and then marks the outcome here.
class ManualTestCase {
  ManualTestCase({
    required this.id,
    required this.category,
    required this.title,
    required this.instructions,
  });

  final String id;
  final String category;
  final String title;
  final String instructions;

  ManualTestStatus status = ManualTestStatus.pending;
  String notes = '';
  DateTime? lastRunAt;

  void reset() {
    status = ManualTestStatus.pending;
    notes = '';
    lastRunAt = null;
  }
}

/// The full checklist — mirrors the categories in MANUAL_TEST_PLAN.md
/// exactly, so the in-app screen and the markdown document never drift
/// apart silently.
List<ManualTestCase> buildDefaultManualTestCases() {
  ManualTestCase c(
    String id,
    String category,
    String title,
    String instructions,
  ) => ManualTestCase(
    id: id,
    category: category,
    title: title,
    instructions: instructions,
  );

  return [
    // Initialization
    c(
      'init-1',
      'Initialization',
      'SDK initializes',
      'Runtime Controls → Initialize SDK. Expect status → running.',
    ),
    c(
      'init-2',
      'Initialization',
      'Double initialize',
      'Initialize twice in a row without shutting down. Expect the second '
          'call to throw ALREADY_INITIALIZING (shown as a failure toast, '
          'not a crash).',
    ),
    c(
      'init-3',
      'Initialization',
      'Shutdown',
      'Runtime Controls → Shutdown. Expect status → stopped.',
    ),
    c(
      'init-4',
      'Initialization',
      'Reinitialize',
      'After shutdown, tap Reinitialize. Expect status → running again.',
    ),
    c(
      'init-5',
      'Initialization',
      'Dispose',
      'Tap Dispose. Expect status → uninitialized and all state reset.',
    ),
    c(
      'init-6',
      'Initialization',
      'Pause',
      'While running, tap Pause. Expect status → paused.',
    ),
    c(
      'init-7',
      'Initialization',
      'Resume',
      'While paused, tap Resume. Expect status → running.',
    ),
    c(
      'init-8',
      'Initialization',
      'CheckNow',
      'Tap Check Now. Expect at least one new event per registered '
          'detector in the Events screen.',
    ),

    // Configuration
    c(
      'config-1',
      'Configuration',
      'Configuration loads',
      'Open Settings before initializing. Expect the default '
          'DeviceShieldConfig values to be pre-filled.',
    ),
    c(
      'config-2',
      'Configuration',
      'Configuration updates',
      'Change Periodic Check Interval in Settings and tap Apply. Expect '
          'a success toast and the new value reflected on Home.',
    ),
    c(
      'config-3',
      'Configuration',
      'Runtime updates',
      'Apply a config change while already running. Expect the SDK to '
          'reinitialize transparently and resume running.',
    ),

    // Protection
    c(
      'protect-1',
      'Protection',
      'Enable protection',
      'Screenshot Protection screen → Enable. On Android, expect '
          '"applied: true"; on iOS, expect an honest "not supported" '
          'result — never a false success.',
    ),
    c(
      'protect-2',
      'Protection',
      'Disable protection',
      'Tap Disable. Expect the state to flip back.',
    ),
    c(
      'protect-3',
      'Protection',
      'Repeated enable',
      'Tap Enable twice in a row. Expect no crash and a consistent '
          'result both times.',
    ),
    c(
      'protect-4',
      'Protection',
      'Repeated disable',
      'Tap Disable twice in a row. Expect no crash.',
    ),

    // Events
    c(
      'event-1',
      'Events',
      'Screenshot event',
      'Take a real screenshot of the device (Android 14+, or any iOS '
          'version). Expect a screenshot event to appear in the Events '
          'screen within ~1 second.',
    ),
    c(
      'event-2',
      'Events',
      'Recording start',
      'iOS only: start a Control Center screen recording. Expect a '
          'screen_recording event with isCaptured:true.',
    ),
    c(
      'event-3',
      'Events',
      'Recording stop',
      'Stop the recording. Expect a follow-up event with '
          'isCaptured:false.',
    ),
    c(
      'event-4',
      'Events',
      'Unknown event',
      'Register a custom Detector with an unfamiliar type string and '
          'run Check Now. Expect it to appear in the Events list without '
          'crashing the UI.',
    ),
    c(
      'event-5',
      'Events',
      'Event ordering',
      'Trigger a poll (Check Now) and a push (screenshot) back to back. '
          'Expect both to appear in the Events screen in the order they '
          'actually occurred.',
    ),
    c(
      'event-6',
      'Events',
      'Duplicate prevention',
      'Take three screenshots in quick succession. Expect three distinct '
          'events, not one merged event and not zero.',
    ),

    // Callbacks
    c(
      'cb-1',
      'Callbacks',
      'Register callback',
      'Callbacks screen → Register a new callback with a custom name. '
          'Expect it to appear in the list as Registered.',
    ),
    c(
      'cb-2',
      'Callbacks',
      'Multiple callbacks',
      'Register a second, differently-named callback. Expect both to '
          'track invocation counts independently.',
    ),
    c(
      'cb-3',
      'Callbacks',
      'Remove callback',
      'Unregister one callback. Expect no further invocations recorded '
          'for it.',
    ),
    c(
      'cb-4',
      'Callbacks',
      'Re-register callback',
      'Register the same name again. Expect it to resume tracking from '
          'zero.',
    ),

    // Flutter lifecycle
    c(
      'life-1',
      'Flutter lifecycle',
      'Background',
      'Send the app to background (home button). Expect no crash on '
          'return.',
    ),
    c(
      'life-2',
      'Flutter lifecycle',
      'Foreground',
      'Bring the app back to foreground. Expect status still accurate.',
    ),
    c(
      'life-3',
      'Flutter lifecycle',
      'Hot restart',
      'Trigger a hot restart from your IDE. Expect the app to reach a '
          'clean, uninitialized state.',
    ),
    c(
      'life-4',
      'Flutter lifecycle',
      'Hot reload',
      'Edit a comment and hot reload while running. Expect no crash and '
          'SDK state preserved.',
    ),
    c(
      'life-5',
      'Flutter lifecycle',
      'Orientation change',
      'Rotate the device. Expect the layout to adapt without losing '
          'state.',
    ),
    c(
      'life-6',
      'Flutter lifecycle',
      'Navigation',
      'Navigate through every screen in the drawer. Expect no crash and '
          'consistent state across screens.',
    ),

    // Platform
    c(
      'plat-1',
      'Platform',
      'Android',
      'Run on a real or emulated Android 14+ device. Expect full '
          'screenshot detection support.',
    ),
    c(
      'plat-2',
      'Platform',
      'iOS',
      'Run on iOS Simulator or device. Expect screenshot + recording '
          'detection, but protection always reports unsupported.',
    ),
    c(
      'plat-3',
      'Platform',
      'Unsupported platform',
      'Run on Android < 14. Expect screenshot detection to honestly '
          'report unsupported, never a fabricated result.',
    ),

    // Logging
    c(
      'log-1',
      'Logging',
      'Logs generated',
      'Perform any SDK action. Expect a corresponding entry in the Logs '
          'screen.',
    ),
    c(
      'log-2',
      'Logging',
      'Errors logged',
      'Trigger a known failure (e.g. double initialize). Expect an '
          'error-level log entry.',
    ),
    c(
      'log-3',
      'Logging',
      'Exceptions handled',
      'Confirm the app never crashes outright from any SDK exception — '
          'check the Error screen instead.',
    ),

    // Performance
    c(
      'perf-1',
      'Performance',
      'Rapid screenshots',
      'Take 5+ screenshots within a few seconds. Expect the UI to '
          'remain responsive and all events to eventually appear.',
    ),
    c(
      'perf-2',
      'Performance',
      'Rapid callbacks',
      'Register/unregister a callback rapidly 10 times. Expect no '
          'crash.',
    ),
    c(
      'perf-3',
      'Performance',
      'Memory leak observation',
      'Leave the app running for several minutes with the Events '
          'screen open. Watch for unbounded memory growth using your '
          'platform\'s profiler.',
    ),
    c(
      'perf-4',
      'Performance',
      'Stress test',
      'Rapidly tap Check Now 20+ times. Expect no duplicate/overlapping '
          'batches (the SDK\'s own reentrancy guard should keep this '
          'safe).',
    ),

    // Regression — a specific, previously-confirmed SDK bug (fixed in
    // lib/src/managers/default_security_manager.dart) that must never
    // recur.
    c(
      'regr-1',
      'Regression',
      'resume() while already running',
      'Runtime Controls: Initialize, then tap Resume without ever '
          'pausing. Expect no crash and status to remain running (bug: '
          'this used to throw an uncaught StateError since running -> '
          'running was not a valid transition).',
    ),
    c(
      'regr-2',
      'Regression',
      'pause() while already paused',
      'Runtime Controls: Initialize, Pause, then tap Pause again. '
          'Expect no crash and status to remain paused.',
    ),
    c(
      'regr-3',
      'Regression',
      'Real inactive->resumed OS blip while running',
      'While running (Screenshot Detector enabled), open the '
          'notification shade or take a screenshot, then return to the '
          'app. Expect no crash — this is the real-world trigger for '
          'regr-1 (AppLifecycleState.resumed firing while never having '
          'left running).',
    ),

    // Detectors screen
    c(
      'det-1',
      'Events',
      'Run detector check directly',
      'Detectors screen: tap "Run check" on any detector. Expect a raw '
          'DetectionResult (detected/confidence/status/evidence) to '
          'display — this bypasses the event pipeline entirely.',
    ),

    // Health Monitor / Debug Info
    c(
      'health-1',
      'Platform',
      'Health Monitor reflects session state',
      'Initialize, then open Health Monitor. Expect uptime counting up '
          'and status "Healthy". Trigger a known failure (e.g. double '
          'initialize) and confirm the errors count increments.',
    ),
    c(
      'debug-1',
      'Platform',
      'Debug Info shows real platform facts',
      'Open Debug Info. Expect OS, Dart version, build mode, and '
          'architecture (ABI) to match the actual device/simulator — '
          'e.g. build mode reads "debug" when run via flutter run.',
    ),
  ];
}
