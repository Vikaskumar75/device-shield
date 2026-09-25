# device_shield

Runtime device-security checks for Flutter apps on Android and iOS.

> **Pre-release.** Not published to pub.dev. The public API is expected to
> change before 0.1.0. Android has not yet been verified on a physical
> device. See [known issues](https://github.com/Vikaskumar75/flutter-shield/blob/main/docs/HANDOVER.md).

## What it does

| Capability | Android | iOS |
|---|---|---|
| Root / jailbreak detection | ✓ | ✓ |
| Emulator / simulator detection | ✓ | ✓ |
| Debugger detection | ✓ | ✓ |
| Mock location detection | ✓ | Limited |
| Screenshot detection | API 34+ | ✓ (after the fact) |
| Screen recording detection | — | ✓ |
| Screenshot protection | ✓ (`FLAG_SECURE`) | Not working |
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

await DeviceShield.initialize();

final bridge = DefaultNativeBridge();
await DeviceShield.registerDetector(RootDetector(nativeBridge: bridge));

DeviceShield.subscribe((event) => print(event.type));
```

See [`example/`](example/) for a complete app.

## Contributing

Development setup, coding rules and the checks CI runs are in the
[repository README](https://github.com/Vikaskumar75/flutter-shield#readme) and
[CONTRIBUTING.md](https://github.com/Vikaskumar75/flutter-shield/blob/main/docs/CONTRIBUTING.md).

## License

BSD 3-Clause. See [LICENSE](LICENSE).
