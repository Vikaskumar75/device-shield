# Contributing

These are the rules for code in this repository. CI enforces the mechanical
ones; reviewers enforce the rest.

## Layout

| Path | What it is |
|---|---|
| `app/` | The Flutter plugin package: `lib/`, `android/`, `ios/`, `test/`, `example/`. This is what ships to pub.dev. |
| `app/tool/` | `setup.sh` and `check.sh` |
| `website/` | The landing page and documentation site (Astro Starlight) |
| `docs/` | Project documents: plans, architecture, feature designs, reports. See [docs/README.md](README.md). |

## Setup

Prerequisites and the setup script are in the [README](../README.md). In short:

```bash
git clone https://github.com/Vikaskumar75/flutter-shield.git
cd flutter-shield
app/tool/setup.sh
```

## Before you push

```bash
app/tool/check.sh
```

This runs everything CI runs that your machine supports and skips (with a
notice) any tool that isn't installed. CI runs all of it on every pull
request:

| Area | Tool | Config |
|---|---|---|
| Dart format | `dart format` | defaults (80 columns) |
| Dart analysis | `flutter analyze` | `app/analysis_options.yaml` |
| Dart tests | `flutter test` (package and example) | — |
| Kotlin format | ktlint | `.editorconfig` |
| Kotlin analysis | detekt | `app/android/config/detekt.yml` |
| Kotlin tests | Gradle `testDebugUnitTest` | — |
| Swift format | `swift format lint --strict` | `.swift-format` |
| Swift analysis | SwiftLint | `app/.swiftlint.yml` |
| Packaging | `flutter pub publish --dry-run` | `app/pubspec.yaml` |

The formatters are the final word on style. Don't hand-format around them or
argue with them in review.

## Code rules

### Public API

- Host apps import only `package:device_shield/device_shield.dart`. Nothing
  under `app/lib/src/` is public API.
- A type a host app needs must be exported from the barrel **and** referenced
  in `app/test/public_api_test.dart`, which fails to compile if an export is
  dropped.
- Until 1.0.0, a breaking change is allowed but must be listed under
  `## Unreleased` in `app/CHANGELOG.md`.

### Detection and protection

- **Report honestly.** A protection that isn't verified to work returns
  `false`/`applied: false`. A check that can't run on the current platform
  returns `applicable: false`, not a clean pass. Never report success you
  haven't observed on a device.
- **Separate I/O from decisions.** Each native detector has a `check()` that
  reads the platform and a pure `evaluate(...)` that decides. `evaluate` gets
  unit tests; `check` stays small enough to review by eye.
- **Never block the main thread.** Detector work that touches the filesystem,
  spawns processes or queries `PackageManager` runs off the platform main
  thread. (Known violation: F2 in `HANDOVER.md`.)
- **Never throw across the channel.** An expected failure (timeout, missing
  permission, unsupported OS version) comes back as a result with a failure
  status.
- **No network access and no persistence** from the SDK itself.
- **Never log sensitive data.** That includes device identifiers and
  location values.

### Platform declarations

- Every Android permission or `<queries>` entry gets a comment in
  `app/android/src/main/AndroidManifest.xml` saying which code needs it.
- A Swift change that starts using an Apple
  [required-reason API](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api)
  (file timestamps, `UserDefaults`, system boot time, disk space) must
  update `app/ios/device_shield/Sources/device_shield/PrivacyInfo.xcprivacy`.
- Minimum versions are Android API 21 and iOS 15.0. Guard any newer API
  with `Build.VERSION.SDK_INT` / `#available`.

### Simplicity

- Add an interface, registry, factory or configuration option only when a
  second concrete use exists today, not for a use that might come later.
- A configuration field that no code reads doesn't get added.

### Comments

- Comment *why*, not *what*. If the code needs a comment to say what it
  does, simplify the code first.
- Keep doc comments short: one summary sentence, then only what a caller
  can't see from the signature.
- Don't cite phases, steps, SRS section numbers, requirement IDs or
  planning documents in code. They go stale, and the code outlives them. Put
  that context in the pull request.

### Tests

- A bug fix comes with a test that fails without the fix.
- Detection logic is tested at the pure-function level on every layer it
  exists in (Dart, Kotlin, Swift).
- Behaviour that can only be confirmed on hardware is recorded in
  `MANUAL_TEST_PLAN.md`, including negative results.

## Commits and pull requests

- One logical change per pull request. CI must be green before merge.
- Commit subjects are imperative and ≤ 72 characters ("Fix Android 14+
  crash on attach"), with the reason in the body.
- User-visible changes get a line under `## Unreleased` in `app/CHANGELOG.md`.
- Naming and identifiers: Android package `com.geekyants.device_shield`,
  iOS example bundle ID `com.geekyants.deviceShieldExample`.
