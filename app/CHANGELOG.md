# Changelog

All notable changes to this package are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package
follows [Semantic Versioning](https://semver.org/). Until 1.0.0, minor
versions may contain breaking changes.

## Unreleased

Not yet published.

### Changed
- **Renamed the package from `flutter_shield` to `device_shield`**, because
  `flutter_shield` is already taken on pub.dev. The import is now
  `package:device_shield/device_shield.dart`, the facade is `DeviceShield`,
  and `FlutterShieldConfig`/`FlutterShieldException` are now
  `DeviceShieldConfig`/`DeviceShieldException`. Channel names changed to
  `device_shield/…`.
- Android package and example identifiers renamed from `com.example` to
  `com.geekyants` (`com.geekyants.device_shield`).
- Minimum iOS version lowered from 18.0 to 15.0.
- Stricter Dart analysis; all Dart and Swift sources formatted.

### Fixed
- Android 14+: declared `DETECT_SCREEN_CAPTURE`, whose absence crashed the
  host app on attach (not yet verified on a device).
