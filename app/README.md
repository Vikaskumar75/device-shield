<p align="center">
  <img src="https://raw.githubusercontent.com/Vikaskumar75/device-shield/main/website/src/assets/logo.svg" alt="device_shield" width="88" height="88">
</p>

<h1 align="center">device_shield</h1>

<p align="center">
  <strong>Know when your Flutter app is running somewhere it shouldn't.</strong><br>
  Root, jailbreak, emulator, debugger and mock-location detection, plus screen
  capture protection, for Android and iOS.
</p>

<p align="center">
  <a href="https://pub.dev/packages/device_shield"><img src="https://img.shields.io/pub/v/device_shield.svg?label=pub.dev&color=0d9488" alt="pub.dev version"></a>
  <a href="https://pub.dev/packages/device_shield/score"><img src="https://img.shields.io/pub/points/device_shield?color=0d9488" alt="pub points"></a>
  <a href="https://github.com/Vikaskumar75/device-shield/actions/workflows/ci.yml"><img src="https://github.com/Vikaskumar75/device-shield/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/Vikaskumar75/device-shield/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-BSD--3--Clause-0d9488.svg" alt="License: BSD-3-Clause"></a>
  <img src="https://img.shields.io/badge/platform-Android%20%7C%20iOS-0d9488.svg" alt="Platforms: Android and iOS">
</p>

<p align="center">
  <a href="https://vikaskumar75.github.io/device-shield/"><b>Documentation</b></a> ·
  <a href="https://vikaskumar75.github.io/device-shield/quick-start/">Quick start</a> ·
  <a href="https://vikaskumar75.github.io/device-shield/reference/api/">API reference</a> ·
  <a href="https://vikaskumar75.github.io/device-shield/reference/roadmap/">Roadmap</a>
</p>

---

## Features

- 🛡️ **Five device checks.** Root (Android), jailbreak (iOS), emulator or
  simulator, attached debugger, and mock location.
- 🔎 **Evidence, not just a boolean.** Every result lists the signals that
  fired, each rated strong, medium or weak.
- ⚖️ **Fewer false positives.** Weak signals common on custom ROMs, emulators
  and debug builds never decide a result on their own.
- 📸 **Screen capture.** Block screenshots and screen recording, hide content
  in the app switcher, and get notified when a screenshot is taken.
- ✅ **Honest results.** A check that doesn't apply says so, and a check that
  can't run returns `failed`. Nothing throws, and nothing silently passes.
- 🔒 **Private by design.** No network requests, nothing stored, no data
  collected.

<p align="center">
  <img src="https://raw.githubusercontent.com/Vikaskumar75/device-shield/main/app/screenshots/android.png" alt="Example app on Android" width="280">
  &nbsp;&nbsp;
  <img src="https://raw.githubusercontent.com/Vikaskumar75/device-shield/main/app/screenshots/ios.png" alt="Example app on iOS" width="280">
</p>

## Platform support

| Feature | Android | iOS |
|---|:---:|:---:|
| Root detection | ✅ | — |
| Jailbreak detection | — | ✅ |
| Emulator / simulator detection | ✅ | ✅ |
| Debugger detection | ✅ | ✅ |
| Mock location detection | ✅ | Limited |
| Screenshot detection | ✅ API 34+ | ✅ |
| Screen recording detection | — | ✅ |
| Screenshot protection | ✅ | Experimental |
| App-switcher protection | ✅ | ✅ |

**Requirements:** Flutter 3.44.8+, Android API 21+, iOS 15.0+.

## Installation

```bash
flutter pub add device_shield
```

On iOS, set your deployment target to 15.0 or later. On Android there's
nothing to add: the plugin's manifest entries merge into your app
automatically. For the optional location-based mock-location signals, your
app requests location permission itself; see
[Android setup](https://vikaskumar75.github.io/device-shield/platforms/android/)
and [iOS setup](https://vikaskumar75.github.io/device-shield/platforms/ios/).

## Usage

### Run every check

```dart
import 'package:device_shield/device_shield.dart';

final report = await DeviceShield.check();

if (report.root.detected || report.jailbreak.detected) {
  // e.g. hide sensitive screens or ask for extra verification
}
if (report.anyFailed) {
  // A check couldn't run. Treat the report as incomplete.
}
```

There's nothing to initialise, and no method throws.

### Inspect the evidence

```dart
final root = await DeviceShield.checkRoot();

switch (root.status) {
  case CheckStatus.detected:
    print(root.signals); // [su_binary_path (strong)]
  case CheckStatus.clear:
    print('Clear');
  case CheckStatus.notApplicable:
    print('Not an Android device');
  case CheckStatus.failed:
    print('Could not check: ${root.error}');
}
```

A check is **detected** when at least one strong signal fires, or two medium
ones. Every signal and its strength is listed in the
[signals reference](https://vikaskumar75.github.io/device-shield/reference/signals/).

### Protect sensitive screens

```dart
// When the screen opens:
await DeviceShield.setScreenshotProtection(true);

// When it closes:
await DeviceShield.setScreenshotProtection(false);

// Hide content in the app switcher / Recents:
await DeviceShield.setAppSwitcherProtection(true);
```

Both return a `ProtectionResult`: `applied`, `unsupported` or `failed`.

### React to screenshots and recording

```dart
DeviceShield.screenshots.listen((_) {
  // The user took a screenshot.
});

DeviceShield.screenRecordingChanges.listen((isRecorded) {
  // iOS: recording or mirroring started (true) or stopped (false).
});
```

See the [example app](https://github.com/Vikaskumar75/device-shield/tree/main/app/example)
for every feature on one screen.

## Security model

These checks run on a device the user controls, so a determined attacker can
hide root or hook the checks themselves (Magisk DenyList, Shamiko, Frida).
Treat the results as **risk signals** that raise the cost of tampering and
let your app adapt, not as proof.

For hard guarantees, pair `device_shield` with server-verified attestation
([Play Integrity](https://developer.android.com/google/play/integrity),
[App Attest](https://developer.apple.com/documentation/devicecheck)), and
never let a client-side result grant access on its own. More in the
[security model](https://vikaskumar75.github.io/device-shield/concepts/security-model/).

## Verification status

Every check and Android protection has been verified on an Android 17
emulator, and every check on the iOS 26.5 Simulator. Physical devices, rooted
or jailbroken devices, and iOS screenshot blocking (which the Simulator can't
show) haven't been verified yet. Details are on the
[platform support](https://vikaskumar75.github.io/device-shield/reference/platform-support/)
page.

## Roadmap

Coming soon: runtime hook detection (Frida, Xposed), app integrity (Play
Integrity / App Attest), developer options and overlay detection, Android 15
screen-recording detection, and improved iOS mock location. See the
[roadmap](https://vikaskumar75.github.io/device-shield/reference/roadmap/).

## Contributing

Issues and pull requests are welcome.

```bash
git clone https://github.com/Vikaskumar75/device-shield.git
cd device-shield
app/tool/setup.sh   # checks and installs prerequisites
app/tool/check.sh   # runs everything CI runs
```

Prerequisites: Flutter 3.44.8, Xcode 16+, the Android SDK with JDK 17+,
Node.js 22.12+ (docs site), and the GitHub CLI. `setup.sh` reports what's
missing and installs the command-line tools with Homebrew. The full table,
repository layout and coding rules are in
[CONTRIBUTING.md](https://github.com/Vikaskumar75/device-shield/blob/main/docs/CONTRIBUTING.md).

## License

BSD 3-Clause. See [LICENSE](https://github.com/Vikaskumar75/device-shield/blob/main/LICENSE).
