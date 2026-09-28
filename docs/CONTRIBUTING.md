# Contributing

These are the rules for code in this repository. CI enforces the mechanical
ones; reviewers enforce the rest.

## Layout

| Path | What it is |
|---|---|
| `app/` | The Flutter plugin package: `lib/`, `android/`, `ios/`, `test/`, `example/`. This is what ships to pub.dev. |
| `app/tool/` | `setup.sh` and `check.sh` |
| `website/` | The landing page and documentation site (Astro Starlight) |
| `README.md` | A copy of `app/README.md`, so GitHub and pub.dev show the same page. Edit `app/README.md` and copy it; `check.sh` and CI fail if they differ. |
| `docs/` | Project documents: plans, architecture, feature designs, reports. See [docs/README.md](README.md). |

## Setup

### Prerequisites

| Tool | Version | Needed for | Installed by `app/tool/setup.sh` |
|---|---|---|---|
| macOS | | iOS builds and Swift tooling (Dart and Android work on any OS) | — |
| [Homebrew](https://brew.sh) | | Installing the tools below | No |
| Flutter | 3.44.8, pinned in `app/.fvmrc` | Everything | Optional, via [fvm](https://fvm.app) |
| Xcode | 16 or later (tested with 27) | iOS builds, `swift format` | No (App Store) |
| Android Studio, or the Android SDK command-line tools | SDK 36 | Android builds | No |
| JDK | 17+. Android Studio's bundled JDK works | Android builds, Gradle | `openjdk@17`, only if none is found |
| Node.js | 22.12+ | The docs site in `website/` | Yes |
| [GitHub CLI](https://cli.github.com) (`gh`) | Recent | `/fix-issue`, opening PRs | Yes. Then run `gh auth login` |
| ktlint, detekt | 1.8.0, 1.23.8 | Kotlin linting | Yes |
| SwiftLint | Recent | Swift linting | Yes |

### Set up

```bash
git clone https://github.com/Vikaskumar75/device-shield.git
cd device-shield
app/tool/setup.sh
```

The setup script checks every prerequisite, offers to install the missing
command-line tools with Homebrew, and fetches the Dart and npm dependencies.
Re-running it is safe. Use `--check` to only report what's missing, or
`--yes` to install without prompts. It never uses `sudo` and never edits your
shell profile; when a step needs that, it prints the command for you to run.

The iOS example app can't build in place while the package folder is named
`app` (F10 in [HANDOVER.md](HANDOVER.md)). Build it from a copy of `app/`
named `device_shield`. Apps that depend on the plugin aren't affected.

### Everyday commands

| Task | Command |
|---|---|
| Run every check CI runs | `app/tool/check.sh` |
| Run the example app | `cd app/example && flutter run` |
| Run the real native checks on a device | `cd app/example && flutter test integration_test -d <device>` |
| Preview the docs site | `npm run dev --prefix website` |
| Fix a GitHub issue with Claude Code | `/fix-issue <number>` in a Claude Code session |

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
  the top `## <version> (unreleased)` heading in `app/CHANGELOG.md`.

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
  thread. On Android, route it through `respondInBackground` in
  `DeviceShieldPlugin.kt`. (Known violation: iOS handlers, F2 in
  `HANDOVER.md`.)
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
- User-visible changes get a line under the top `## <version> (unreleased)`
  heading in `app/CHANGELOG.md`. pub.dev requires that heading to name the
  version in `pubspec.yaml`.
- Naming and identifiers: Android package `com.geekyants.device_shield`,
  iOS example bundle ID `com.geekyants.deviceShieldExample`.
