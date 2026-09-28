# Changelog

All notable changes to this package are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package
follows [Semantic Versioning](https://semver.org/). Until 1.0.0, minor
versions may contain breaking changes.

## 0.1.0

First release.

### Detection
- Root (Android), jailbreak (iOS), emulator / simulator, debugger and mock
  location checks, through `DeviceShield.check()` or one method per check.
- Every result lists the signals that fired, each with a strength. A check is
  detected with at least one strong signal or two medium ones. Weak signals
  (common on custom ROMs, emulators and debug builds) never decide the result
  on their own.
- A check that can't run returns `CheckStatus.failed`; nothing throws. A check
  that doesn't exist on the platform returns `CheckStatus.notApplicable`,
  including jailbreak detection on the iOS Simulator.

### Screen
- `DeviceShield.screenshots` (Android 14+ and iOS) and
  `DeviceShield.screenRecordingChanges` / `isScreenRecorded()` (iOS).
- `setScreenshotProtection` and `setAppSwitcherProtection`. On Android both
  use `FLAG_SECURE`, tracked separately and re-applied after configuration
  changes. iOS screenshot protection is experimental until verified on a
  device.

### Platform
- Android checks run on a background thread.
- Android 14+: declares `DETECT_SCREEN_CAPTURE`, required for screenshot
  detection.
- Minimum Android API 21, iOS 15.0.
