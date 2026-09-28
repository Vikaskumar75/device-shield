# device_shield

Runtime device-security checks for Flutter apps on Android and iOS.

Documentation: **[vikaskumar75.github.io/device-shield](https://vikaskumar75.github.io/device-shield/)**

> Verified on an Android 17 emulator and the iOS 26.5 Simulator. Not yet
> verified on physical devices. See
> [platform support](https://vikaskumar75.github.io/device-shield/reference/platform-support/).

## What it does

| Capability | Android | iOS |
|---|---|---|
| Root / jailbreak detection | ✓ | ✓ |
| Emulator / simulator detection | ✓ | ✓ |
| Debugger detection | ✓ | ✓ |
| Mock location detection | ✓ | Limited |
| Screenshot detection | API 34+ | ✓ (after the fact) |
| Screen recording detection | — | ✓ |
| Screenshot protection | ✓ (`FLAG_SECURE`) | Experimental |
| App-switcher snapshot protection | ✓ | ✓ |

## Limitations

These checks all run on the device, so a determined attacker can bypass
them. Tools such as Magisk DenyList, Shamiko and Frida can hide root or
disable the checks. Treat the results as risk signals for your app to act
on, not as proof. For strong app-integrity guarantees, use a server-verified
attestation service ([Play Integrity](https://developer.android.com/google/play/integrity),
[App Attest](https://developer.apple.com/documentation/devicecheck)).

Heuristic checks can also give false positives on legitimate devices, such
as custom ROMs and developer builds. Test against your own user base before
blocking anyone.

## Requirements

- Flutter 3.44.8+ (Dart 3.12.2+)
- Android API 21+
- iOS 15.0+

## Usage

```dart
import 'package:device_shield/device_shield.dart';

// Run every check. Nothing to initialise, nothing throws.
final report = await DeviceShield.check();

if (report.root.detected || report.jailbreak.detected) {
  print(report.root.signals); // e.g. [su_binary_path (strong)]
}

// Keep a sensitive screen out of screenshots and recordings.
await DeviceShield.setScreenshotProtection(true);

// Know when the user takes a screenshot.
DeviceShield.screenshots.listen((_) => print('Screenshot taken'));
```

A check is `detected` when at least one strong signal fires, or two medium
ones. Weak signals are reported but never decide the result. See
[detection results](https://vikaskumar75.github.io/device-shield/concepts/detection-results/).

See [`example/`](example/) for a complete app.

## Contributing

Development setup, coding rules and the checks CI runs are in the
[repository README](https://github.com/Vikaskumar75/device-shield#readme) and
[CONTRIBUTING.md](https://github.com/Vikaskumar75/device-shield/blob/main/docs/CONTRIBUTING.md).

## License

BSD 3-Clause. See [LICENSE](LICENSE).
