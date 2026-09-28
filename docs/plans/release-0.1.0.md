# Release 0.1.0 plan

**Status:** implemented except phase 4 device test, 2026-09-28 · **Branch:** `release/0.1.0` (from `main` at `8e8f175`)

**Goal:** make `device_shield` 0.1.0 ready to publish to pub.dev and the docs
site ready to deploy. **Publishing and deploying are out of scope.** The
owner triggers both separately.

## Scope

### Ships in 0.1.0

| Module | Android | iOS |
|---|---|---|
| Root detection | ✓ | not applicable |
| Jailbreak detection | not applicable | ✓ |
| Emulator / simulator detection | ✓ | ✓ |
| Debugger detection | ✓ | ✓ |
| Mock location detection | ✓ | limited (unchanged) |
| Screenshot detection | API 34+ | ✓ |
| Screen recording detection | — | ✓ |
| Screenshot protection | ✓ `FLAG_SECURE` | see phase 4 |
| App-switcher protection | ✓ | ✓ |

### Coming soon (website only, no code)

Runtime hook detection · app integrity (Play Integrity / App Attest) ·
developer options detection · overlay detection · Android 15+ screen-recording
detection · improved iOS mock location.

### Explicitly not planned

SSL pinning, clipboard protection, policy/rule engine, remote event reporting.
These aren't listed as coming soon, because a listed item reads as a promise.

## Phases

Each phase leaves `app/tool/check.sh` green and is reviewable on its own.

### 1. Android checks off the main thread (F2): done

Done 2026-09-28. 70 Kotlin tests pass, including 3 new threading tests.
The iOS handlers still run on the main thread; tracked as F2 (iOS) in
`HANDOVER.md`.


- Detection methods (`checkRoot`, `checkEmulator`, `checkDebugger`,
  `checkMockLocation`, `isScreenCaptureActive`) run on a single background
  executor. Results are posted back on the main looper.
- A single thread keeps checks serial, which matters because
  `MockLocationDetector` keeps the previous fix in memory.
- Protection methods (`FLAG_SECURE`) stay on the main thread; they touch the
  window.
- The executor and main-thread poster are injectable, so JVM tests stay
  synchronous. The executor shuts down in `onDetachedFromEngine`.

### 2. Signal weighting (F5): done

- Native code keeps returning raw signals. **Dart classifies them**: one
  table covering both platforms, unit-tested.
- Each signal has a strength: `strong`, `medium` or `weak`.
- A check counts as **detected** if at least one strong signal fired, or
  at least two medium ones. Weak signals are reported but never decide the
  result on their own.
- Proposed strengths (the table from the docs site's signals page):
  - **Strong:** `su_binary_path`, `su_executable`, `magisk_artifacts`,
    `writable_system`, `debugger_connected`, `waiting_for_debugger`,
    `ptrace_flag`, `simulator_target`, `qemu_pipe`, `mock_provider_flag`,
    `mock_app_selected_for_this_app`, and every jailbreak signal on a
    physical device.
  - **Medium:** `superuser_apps_installed`, `root_cloaking_apps_installed`,
    the Android emulator build heuristics, `impossible_velocity`,
    `invalid_location_accuracy`, `legacy_allow_mock_location_setting`.
  - **Weak:** `busybox_present`, `build_tags_test_keys`,
    `dangerous_system_props`, `debuggable_flag`, `fake_gps_app_installed`.
- Effect: a stock emulator no longer reports **rooted**, a debug build no
  longer reports a **debugger**, and an installed fake-GPS app alone no
  longer reports a **mock location**.

### 3. Simplified public API (breaking): done

Implemented as proposed. `screenshots` is a `Stream<void>` and
`isScreenRecorded()` returns `bool?`.


Replace the facade, DI container, registries, policy manager, rules, cache,
lifecycle state machine, security profile and permission manager with a
small static API. No `initialize()`, no native bridge to construct, no
timer:

```dart
final report = await DeviceShield.check(); // every applicable check
report.root.detected;        // bool, weighted (phase 2)
report.root.status;          // detected | clear | notApplicable | failed
report.root.signals;         // [Signal(id, strength)]

await DeviceShield.checkRoot(); // or any single check

DeviceShield.screenshots;              // Stream<void>
DeviceShield.screenRecording;          // Stream<bool>, iOS
await DeviceShield.isScreenRecorded(); // bool?, null where unsupported

await DeviceShield.setScreenshotProtection(true);   // ProtectionResult
await DeviceShield.setAppSwitcherProtection(true);  // ProtectionResult
```

- `ProtectionResult` is `applied`, `unsupported` or `failed`. It never
  reports `applied` for something that isn't in effect.
- Screenshot and app-switcher protection get **one** state on Android (the
  shared `FLAG_SECURE`), which removes the desync bug.
- Native channels and native code are unchanged apart from phases 1 and 4.
- Deletes most of `app/lib/src/` and the tests of the deleted
  infrastructure. The example app is rewritten onto the new API.
- `test/public_api_test.dart` is rewritten to guard the new surface.

### 4. iOS screenshot protection (F4): implemented, awaiting device test

Window-level implementation done. It installs and removes cleanly on the iOS
26.5 Simulator. The iPhone test procedure is in `MANUAL_TEST_PLAN.md` §3.


The current technique moves the root view's layer under a secure text
field's layer. That creates a layer cycle, breaks layout, and reports
`applied` without blocking anything.

- Reimplement it by hosting the Flutter view inside a secure
  `UITextField`'s internal canvas view, pinned to the window with Auto
  Layout, with no layer re-parenting.
- This still relies on undocumented UIKit behaviour. It can break in any
  iOS release, and screenshots from the Simulator don't show whether it
  works.
- **Acceptance needs the owner's physical iPhone:** a system screenshot and
  a screen recording both come out blank for protected content, and layout
  and rotation are unaffected.
- **If device testing fails**, iOS returns `unsupported` and the docs keep
  saying so. The API never claims a protection that isn't there.

### 5. Android emulator verification: done

All checks and protections verified on the API 37 emulator; results are in
`MANUAL_TEST_PLAN.md`. Also found and fixed along the way:
- a jailbreak false positive on the iOS Simulator (now `notApplicable`);
- the protection-state desync on Android;
- protection not being re-applied after a configuration change.


- Run the example on the `Pixel_10_Pro` AVD (API 37).
- Record the real results in `docs/MANUAL_TEST_PLAN.md`:
  - which signals fire;
  - that the app doesn't crash on attach (verifies F1);
  - screenshot detection;
  - `FLAG_SECURE` blocking screenshots;
  - no dropped frames during checks.
- Physical Android devices, and a rooted phone in particular, stay
  unverified. The docs say so.

### 6. Release preparation: done, except owner actions

Version 0.1.0, CHANGELOG, README, docs and the Coming soon section are done.
Publishing, deploying and enabling GitHub Pages are the owner's.


- `pubspec.yaml` version `0.1.0`, and a `CHANGELOG.md` `## 0.1.0` entry.
- The package README rewritten for the new API.
- `flutter pub publish --dry-run` is clean.
- Website:
  - quick start and API pages rewritten for the new API, with the "API is
    changing" warnings removed;
  - platform support and verification tables updated;
  - a **Coming soon** section on the landing page and a Roadmap docs page.
- Docs deploy readiness: the workflow already builds on PRs. GitHub Pages
  must be enabled in repository settings (owner action).
- `docs/HANDOVER.md` updated: F2, F4 and F5 resolved or re-scoped.

## Order and dependencies

Phase 1 → 5 (verify on the new threading) · 2 → 3 (the API exposes
strengths) · 3 → 6 (docs describe the new API) · 4 needs the owner's
device · the website Coming soon section doesn't depend on anything.

## Owner decisions (2026-09-28)

1. API shape and strength table approved; breaking changes are fine.
2. The owner tests iOS screenshot protection on their iPhone.
