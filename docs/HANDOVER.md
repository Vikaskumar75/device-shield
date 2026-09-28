# device_shield — Handover

**Updated:** 2026-09-28 · **Branch:** `release/0.1.0` (from `main` at
`8e8f175`) · **Working tree:** release work uncommitted

Written for a fresh session picking this up. Read this, then
[`plans/release-0.1.0.md`](plans/release-0.1.0.md).

## 1. Where things stand

0.1.0 is prepared for pub.dev but **not published**, and the docs site is not
deployed. The owner triggers both. Nothing on `release/0.1.0` is committed
yet.

Git notes:
- `release/0.1.0` was created tracking `origin/main`. Push it with
  `git push -u origin release/0.1.0`; a bare `git push` would target `main`.
- Claude doesn't run git write commands unless asked (`CLAUDE.md`). The
  `.claude/hooks/git_guard.py` hook prompts for approval.

## 2. What 0.1.0 changed

- **New public API.** A static `DeviceShield` with `check()`, one method per
  check, `screenshots` / `screenRecordingChanges` streams, and
  `setScreenshotProtection` / `setAppSwitcherProtection`. It replaces the DI
  container, registries, policy/rule engine, cache, lifecycle state machine,
  profiles and permission manager (about 4,900 lines of Dart removed). The
  native channel contract is unchanged.
- **Signal weighting (F5).** `app/lib/src/signal_strengths.dart` gives each
  signal a strength. Detected = at least one strong signal or two medium
  ones. A test scans the Kotlin and Swift sources and fails if a native
  signal has no strength.
- **Android off the main thread (F2).** `DeviceShieldPlugin.respondInBackground`.
- **Android protection state.** Screenshot and app-switcher protection share
  `FLAG_SECURE` but are tracked separately. The flag is re-applied after
  configuration changes.
- **iOS screenshot protection (F4) reimplemented** at window level, with the
  secure layer found by its canvas view. **Blocking isn't verified yet**; it
  needs the owner's iPhone (`MANUAL_TEST_PLAN.md` §3).
- **Jailbreak on the iOS Simulator** now returns `notApplicable`. Before, it
  reported a jailbreak because the Simulator sees the host Mac's paths.
- **The example app** is a single screen showing every feature.
- **The integration test** runs every native check on a device.

## 3. Findings

| # | Finding | Status |
|---|---|---|
| F1 | Android 14+ crash on attach (`DETECT_SCREEN_CAPTURE`) | **Fixed and verified** on an API 37 emulator |
| F2 | Native checks block the UI thread | **Android fixed.** iOS still synchronous; the jailbreak check's `posix_spawn` + `waitpid` is the costly one |
| F3 | Unusable public API | **Replaced** by the 0.1.0 API |
| F4 | iOS screenshot protection reports success without working | **Reimplemented; awaiting physical iPhone test.** If it fails, return `supported: false` from `setScreenshotProtection` on iOS (Dart maps that to `ProtectionResult.unsupported`) |
| F5 | One weak signal = detected | **Fixed** by signal strengths |
| F6 | iOS mock location reads `CLLocationManager().location` without updates, so location signals rarely fire; no `isSimulatedBySoftware` | Open, on the roadmap |
| F7 | Android screen recording unsupported; Android 15 has a callback | Open, on the roadmap |
| F8 | Events don't carry detection results | **Obsolete.** Events were replaced by direct results |
| F9 | App Store review risk: `posix_spawn`, write to `/private/` | Open; documented on the iOS setup page |
| F10 | iOS example can't resolve its Swift package while the package folder is named `app` | Open. Flutter 3.44.8 / Xcode 27 bug that also reproduces with a fresh `flutter create --template=plugin`; apps depending on the plugin are unaffected. Build the example from a copy named `device_shield` (CI does). Renaming `app/` to `device_shield/` removes it |

## 4. Open work

1. **Owner's iPhone test** of screenshot protection (`MANUAL_TEST_PLAN.md`
   §3), then decide F4.
2. **Physical-device runs**, Android and iOS, including a rooted or
   jailbroken device if one is available.
3. **Commit, push, CI.** The iOS job's simulator build step hasn't run in CI
   yet.
4. **Publish** (`cd app && flutter pub publish`) and **deploy the docs**
   (enable GitHub Pages → Source: GitHub Actions). Both are owner actions.
5. Later: F2 on iOS, F6, F7, and the roadmap items.

Small cleanups:
- Both native plugins still register the legacy `device_shield` channel for
  the template's `getPlatformVersion`. Dart no longer uses it. Removing it
  touches the Kotlin, Swift and `RunnerTests` tests.
- The archived docs in `docs/plans` and `docs/reports` predate 0.1.0. See
  `docs/README.md`.

## 5. Running things

```bash
app/tool/check.sh                     # format, analyze, tests, all linters
cd app && flutter test                # 31 package tests
cd app/example && flutter test        # 2 widget tests
cd app/example && flutter test integration_test -d <device>   # real native checks
```

- **Kotlin tests:** `flutter build apk --debug` in `app/example`, then
  `./gradlew :device_shield:testDebugUnitTest` in `app/example/android` with
  `JAVA_HOME` set to Android Studio's JDK. 74 passing. In Claude Code, Gradle
  must run unsandboxed (Java ignores the sandbox proxy).
- **Android emulator:** `flutter emulators --launch Pixel_10_Pro`. Use a
  release APK for manual checks; a debug APK started outside `flutter run`
  can stall on the splash screen.
- **iOS:** build and test from a copy of `app/` named `device_shield` (F10).
- **Swift tests** still can't run from the CLI (`swift test` can't resolve
  UIKit/Flutter). They're linted, not executed.

Toolchain: Flutter 3.44.8, Xcode 27, ktlint 1.8.0, detekt 1.23.8,
SwiftLint 0.65.1.

## 6. Notes

- Keep the honesty standard. Docs and results say what was verified where;
  `MANUAL_TEST_PLAN.md` records negative results.
- `app/test/public_api_test.dart` guards the public surface. A type host apps
  need must be exported from `lib/device_shield.dart` **and** referenced
  there.
- Changing a signal's strength changes what users see as detected. Update the
  website's signals page in the same change.
