# Manual Test Plan — FlutterShield Reference Example App

This document mirrors the in-app checklist on the **Manual Test** screen
(`example/lib/core/manual_test_case.dart` → `buildDefaultManualTestCases()`)
exactly, category-by-category and case-by-case, so the two never drift
apart silently. Use the in-app screen to track pass/fail/notes per device;
use this document as the reviewable, versioned source of truth for what
"fully tested" means for this SDK.

Each case lists: **what to do**, **where in the app**, and **what to
expect**.

---

## Prerequisites & environment

- Flutter 3.44+ (stable channel), Dart 3.x.
- **Android**: API 34+ device or emulator (screenshot detection requires
  `Activity.registerScreenCaptureCallback`, API 34+ only — see plat-3
  below for the honest below-34 behavior). Tested against Android 17
  (API 37) emulator images.
- **iOS**: iOS 18.0+ only — this SDK's `Package.swift` declares
  `.iOS("18.0")` as its platform floor, and the example app's
  `IPHONEOS_DEPLOYMENT_TARGET` is pinned to `18.0` to match. Earlier iOS
  versions are not supported and will not build. Tested against iOS
  26.4.1 Simulator (iPhone 17 Pro Max).
- No CocoaPods — the iOS side is Swift Package Manager only (no
  `ios/Podfile` exists by design).

---

## Initialization (8 cases)

| ID | Title | Steps | Expected result |
|----|-------|-------|------------------|
| init-1 | SDK initializes | Runtime Controls → **Initialize** | Status flips to `running`; Home screen reflects it live. |
| init-2 | Double initialize | Tap **Initialize** twice without shutting down | Second call fails with `ALREADY_INITIALIZING`, shown as a failure SnackBar — never a crash. |
| init-3 | Shutdown | Runtime Controls → **Shutdown** | Status → `stopped`. |
| init-4 | Reinitialize | After shutdown, tap **Reinitialize** | Status → `running` again. |
| init-5 | Dispose | Tap **Dispose** | Status → `uninitialized`; detector toggles, recording state, etc. reset. |
| init-6 | Pause | While running, tap **Pause** | Status → `paused`. |
| init-7 | Resume | While paused, tap **Resume** | Status → `running`. |
| init-8 | Check Now | Tap **Check Now** | At least one new event per currently-registered detector appears on the Events screen. |

## Configuration (3 cases)

| ID | Title | Steps | Expected result |
|----|-------|-------|------------------|
| config-1 | Configuration loads | Open Settings before initializing | Default `FlutterShieldConfig` values are pre-filled. |
| config-2 | Configuration updates | Change **Periodic Check Interval** in Settings, tap **Apply** | Success SnackBar; new value reflected on Home. |
| config-3 | Runtime updates | Apply a config change while already running | SDK transparently reinitializes and resumes `running`. |
| config-4 | Screenshot protection auto-applies at boot | Settings → enable **"Enable screenshot protection at boot"** → Apply → Initialize | Android: `protectionEnabled` reads `Yes` on Home immediately after initialize, with **zero** manual "Enable protection" tap. This is the fix for the audit's dead-config finding — see §18.2 of the design doc. |
| config-5 | Detection flags actually gate registration | Settings → leave both detection toggles **off** → Apply → Initialize → take a real screenshot | No `screenshot` event appears (previously it always would, regardless of the toggle) — confirms the flag is now consumed, not just stored. |
| config-6 | App-switcher protection auto-applies at boot | Settings → enable **"Enable app-switcher protection at boot"** → Apply → Initialize | `appSwitcherProtectionEnabled` reads `Yes` on the Protection screen immediately after initialize. |

## Protection (11 cases)

| ID | Title | Steps | Expected result |
|----|-------|-------|------------------|
| protect-1 | Enable protection | Protection screen → **Enable** | Android: `applied: true`, confirmed working. iOS: `applied: true` when a window exists — **this only proves the `UITextField` re-parenting call executed, NOT that a black-screenshot effect occurs**; see protect-9/protect-10. |
| protect-2 | Disable protection | Tap **Disable** | State flips back; live status reflects it. |
| protect-3 | Repeated enable | Tap **Enable** twice in a row | No crash; consistent result both times. |
| protect-4 | Repeated disable | Tap **Disable** twice in a row | No crash. |
| protect-5 | Enable app-switcher protection | Protection screen → **Enable app-switcher protection** | Android: `applied: true` (same `FLAG_SECURE` flag as protect-1 — documented alias). iOS: `applied: true` — **verified live this session**, see protect-6. |
| protect-6 | App-switcher blur is real, not just a flag | With app-switcher protection enabled, background the app (Home button / App Switcher gesture) | **iOS, verified live on iPhone 17 Pro Max Simulator (iOS 26.4.1) this session, via a real ground-truth `xcrun simctl io screenshot`**: the App Switcher card shows an opaque blurred rectangle — no readable app content — instead of the actual Protection screen. Foregrounding again restores the real content immediately, with no crash or stuck overlay. This mechanism is public UIKit API only and is confirmed working, unlike protect-1's mechanism. |
| protect-7 | Disable app-switcher protection | Tap **Disable app-switcher protection** | State flips back; backgrounding again shows real (unblurred) content in the App Switcher. |
| protect-8 | App-switcher protection independent of screenshot protection | Enable only app-switcher protection (leave screenshot protection off) | iOS: screenshot protection's `applied` state is independent of app-switcher protection's — the two are genuinely separate state on iOS (verified in `screen_capture_controller_test.dart`'s "is independent of screenshot protection" test), even though protect-1's underlying visual effect is unconfirmed. |
| protect-9 | iOS full-screenshot blocking — Simulator result | With screenshot protection enabled, take a real ground-truth screenshot (`xcrun simctl io <udid> screenshot out.png` — NOT the MCP/debug screenshot tool, which may not exercise the same compositor path) while the app is in the foreground | **Tested live this session on iPhone 17 Pro Max Simulator (iOS 26.4.1): the screenshot captured full, real content — not black.** The `enable()` re-parenting call did execute (confirmed by an observed real layout side effect — the app's responsive breakpoint changed immediately after enabling), but the intended capture-exclusion did not occur on this Simulator. Root cause unconfirmed — see design doc §18.5 for the two leading (unverified) hypotheses. **Do not treat this feature as working based on Simulator testing alone.** |
| protect-10 | iOS full-screenshot blocking — physical device | Same as protect-9, but on a real, physical iPhone, not a Simulator | **NOT TESTED — no physical iOS device was available in the session that implemented this feature.** This is the test that actually determines whether §18.5's mechanism works at all; treat the feature as unverified until this specific case passes on real hardware. |
| protect-11 | iOS screenshot protection does not visibly break the app | With screenshot protection enabled, use the app normally for a minute (navigate screens, scroll) | No crash. Note: enabling it was observed this session to change the app's responsive layout breakpoint (drawer → permanent nav rail) — confirm this is an acceptable/expected side effect of the layer re-parenting, or investigate further if it looks like a layout regression during your own testing. |

## Events (7 cases)

| ID | Title | Steps | Expected result |
|----|-------|-------|------------------|
| event-1 | Screenshot event | Take a real screenshot (Android 14+, or any iOS version) | A `screenshot` event appears on the Events screen within ~1s. |
| event-2 | Recording start | iOS only: start a Control Center screen recording | A `screen_recording` event appears (confidence `1.0`, inferred as active). |
| event-3 | Recording stop | Stop the recording | A follow-up `screen_recording` event appears (confidence `0.0`, inferred as inactive). |
| event-4 | Unknown event | Runtime Controls → **Register custom detector**, then **Check Now** | The custom `example_custom_probe` event appears in the Events list without crashing the UI. |
| event-5 | Event ordering | Trigger **Check Now** and a real screenshot back to back | Both appear on the Events screen in the order they actually occurred. |
| event-6 | Duplicate prevention | Take three screenshots in quick succession | Three distinct events appear — not one merged event, not zero. |
| det-1 | Run detector check directly | Detectors screen → tap **Run check** on any detector | A raw `DetectionResult` (detected/confidence/status/evidence) displays — this bypasses the event pipeline entirely and is the only way to see `evidence`, which `SecurityEvent` never carries (see limitation #3). |

## Callbacks (4 cases)

| ID | Title | Steps | Expected result |
|----|-------|-------|------------------|
| cb-1 | Register callback | Callbacks screen → register a custom-named callback | Appears in the list as **Registered**. |
| cb-2 | Multiple callbacks | Register a second, differently-named callback | Both track invocation counts independently. |
| cb-3 | Remove callback | Unregister one callback | No further invocations recorded for it. |
| cb-4 | Re-register callback | Register the same name again | Resumes tracking from zero. |

## Flutter lifecycle (6 cases)

| ID | Title | Steps | Expected result |
|----|-------|-------|------------------|
| life-1 | Background | Send the app to background (home button) | No crash on return. |
| life-2 | Foreground | Bring the app back to foreground | Status still accurate. |
| life-3 | Hot restart | Trigger a hot restart from your IDE | App reaches a clean, `uninitialized` state. |
| life-4 | Hot reload | Edit a comment, hot reload while running | No crash; SDK state preserved. |
| life-5 | Orientation change | Rotate the device | Layout adapts; state not lost. |
| life-6 | Navigation | Visit every screen in the drawer/rail | No crash; consistent state across screens. |

## Platform (5 cases)

| ID | Title | Steps | Expected result |
|----|-------|-------|------------------|
| plat-1 | Android | Run on real/emulated Android 14+ | Full screenshot detection support. |
| plat-2 | iOS | Run on iOS 18+ Simulator/device | Screenshot + recording detection; protection always reports unsupported. |
| plat-3 | Unsupported platform | Run on Android < 14 | Screenshot detection honestly reports unsupported — never a fabricated result. |
| health-1 | Health Monitor reflects session state | Initialize, open Health Monitor; then trigger a known failure (e.g. double initialize) | Uptime counts up, status reads "Healthy"; error count increments after the failure. |
| debug-1 | Debug Info shows real platform facts | Open Debug Info | OS, Dart version, build mode, and architecture (ABI) match the actual device/simulator — e.g. build mode reads "debug" under `flutter run`. |

## Logging (3 cases)

| ID | Title | Steps | Expected result |
|----|-------|-------|------------------|
| log-1 | Logs generated | Perform any SDK action | Corresponding entry appears on the Logs screen. |
| log-2 | Errors logged | Trigger a known failure (e.g. double initialize) | Error-level log entry appears. |
| log-3 | Exceptions handled | Try to break things generally | App never crashes outright from an SDK exception — check the Errors screen instead. |

## Performance (4 cases)

| ID | Title | Steps | Expected result |
|----|-------|-------|------------------|
| perf-1 | Rapid screenshots | Take 5+ screenshots within a few seconds | UI stays responsive; all events eventually appear. |
| perf-2 | Rapid callbacks | Register/unregister a callback rapidly 10 times | No crash. |
| perf-3 | Memory leak observation | Leave the Events screen open for several minutes | No unbounded memory growth (watch with your platform's profiler). |
| perf-4 | Stress test | Rapidly tap **Check Now** 20+ times | No duplicate/overlapping batches — the SDK's reentrancy guard holds. |

## Regression (3 cases)

A confirmed SDK bug and its fix — see "Bugs found, fixed, and tested"
below for the full root-cause writeup. These three cases must never
regress.

| ID | Title | Steps | Expected result |
|----|-------|-------|------------------|
| regr-1 | `resume()` while already running | Runtime Controls: Initialize, then tap **Resume** without ever pausing | No crash; status stays `running`. Before the fix, this threw an uncaught `StateError` (`running -> running` is not a valid transition). |
| regr-2 | `pause()` while already paused | Initialize, **Pause**, then **Pause** again | No crash; status stays `paused`. |
| regr-3 | Real inactive→resumed OS blip while running | While running with Screenshot Detector enabled, open the notification shade or take a screenshot, then return to the app | No crash — this is the real-world trigger for regr-1: `AppLifecycleState.resumed` fires on the transient blip even though the SDK never actually left `running`. |

### Negative tests (cross-referenced from the categories above)

These deliberately invoke the SDK incorrectly and confirm it fails
safely rather than crashing or silently succeeding:

- init-2 (double initialize), protect-3/protect-4 (repeated enable/
  disable), regr-1/regr-2/regr-3 (redundant pause/resume), plat-3
  (screenshot detection on an unsupported Android version).

---

## Bugs found, fixed, and tested

### Bug: `pause()`/`resume()` threw on a redundant call in the same state

- **Root cause**: `DefaultSecurityManager.pause()`/`resume()` in
  `lib/src/managers/default_security_manager.dart` called
  `lifecycle.transitionTo(...)` unconditionally. `DefaultSecurityStateManager`'s
  frozen transition table correctly excludes `running -> running` and
  `paused -> paused` (they are not real state changes), so `transitionTo`
  threw a `StateError` whenever `resume()`/`pause()` were called while
  already in the target state.
- **Why this is reachable in practice, not just in theory**:
  `DefaultLifecycleManager` (a `WidgetsBindingObserver`) calls
  `SecurityLifecycleHandler.onResume()` — which calls `resume()` — on
  *every* `AppLifecycleState.resumed` Flutter reports. That includes
  transient `inactive → resumed` blips (opening the notification shade, a
  screenshot toast, the app switcher, an incoming call) that occur while
  the SDK never actually left `running`. This was observed live, via a
  real screenshot interaction, during Android testing of this example
  app.
- **Fix**: both methods now check `lifecycle.current` first and return
  early as a no-op if already in the target state — idempotent, matching
  how a lifecycle API should behave when called defensively or
  redundantly. Calls from any *other*, genuinely invalid state (e.g.
  `pause()` before `initialize()`) still throw, unchanged.
- **Tests added**: three regression tests in
  `test/managers/default_security_manager_test.dart` — redundant
  `resume()`, redundant `pause()`, and `onResume()` called while already
  running (the real callback path). All pass; full suite (301 tests)
  passes with no regressions.
- **In-app regression cases**: regr-1, regr-2, regr-3 above.

### Bug: `FlutterShieldConfig`'s screenshot/recording flags were validated and stored but never read

- **Root cause**: `enableScreenshotDetection`, `enableScreenRecordingDetection`,
  and `enableScreenshotProtection` were added to `FlutterShieldConfig`,
  passed through `FlutterShieldConfigValidator`, and persisted by
  `ConfigurationManager` — but no runtime code ever read them back.
  `ScreenCaptureController.initialize()` registered both native push
  listeners unconditionally regardless of the flags, and protection was
  never auto-applied at boot no matter what a host app configured. The
  example app's own Settings screen had toggles for all three that
  silently did nothing.
- **Found during**: a full production-readiness audit (see design doc
  §18.2) that re-verified every prior claim against actual source rather
  than trusting an earlier report.
- **Fix**: `DefaultSecurityManager.initialize()` now passes
  `ConfigurationManager.current` into `ScreenCaptureController
  .initialize(config)`, which gates each flag independently (including
  the new `enableAppSwitcherProtection`) and stays idempotent.
- **Tests added**: `screen_capture_controller_test.dart`'s "config-gated
  initialize" group (7 tests) and `default_security_manager_test.dart`'s
  "config-driven boot" group (2 tests).
- **In-app regression cases**: config-4, config-5, config-6 above.

### Finding: iOS `ScreenCaptureProtection`'s black-screenshot effect does not occur on Simulator — root cause unconfirmed

- **What happened**: with explicit host-app approval, a `UITextField.isSecureTextEntry` layer re-parenting technique (the same one production apps like Google Pay/PhonePe reportedly use, and the same one the published `screen_protector` Flutter plugin implements) was built for iOS to give `enableScreenshotProtection()` a real effect there, instead of always returning `applied: false`.
- **What was tested, live, this session**: enabled via the real UI → `applied: true` returned → a real, observed side effect (the app's own responsive layout switched breakpoints) confirmed the layer re-parenting genuinely executed, not a silent no-op → a **ground-truth screenshot via `xcrun simctl io screenshot`** (not a debug/API capture — the same mechanism as Simulator's Cmd+S) was taken with protection enabled.
- **Result**: the screenshot showed full, real content. **Not black.** The intended capture-exclusion did not occur.
- **Root cause: not confirmed.** Two open hypotheses, neither verified: (1) the iOS Simulator's compositor may not honor this specific secure-layer exclusion the way real hardware's WindowServer/backboardd does — a known category of Simulator/device parity gap for other protected-content mechanisms; (2) the implementation may be re-parenting a layer that isn't actually the ancestor of Flutter's true Skia/Impeller rendering surface, which would also explain the layout side effect without the capture-exclusion. **Physical iOS hardware, not available in this session, is required to distinguish these.**
- **What was NOT done**: this was not "fixed" — the code is documented as unverified in every place it's mentioned (design doc §18.5, the class's own top-of-file comment, the plugin handler, the example app UI, this test plan). Nothing here claims this feature works.
- **In-app regression cases**: protect-1, protect-9 (tested, negative result), protect-10 (physical device, not yet tested).

---

## Documented SDK limitations (verify these are honestly surfaced, not hidden)

These are properties of the current SDK. They are **documented in the
app** (About screen, `ShieldController` doc comments), not silently
worked around. As part of manual testing, confirm each is still
accurately represented in-app:

1. **No detector removal API** — `FlutterShield`/`DetectionManager` expose
   `registerDetector()` but no `unregisterDetector()`/`removeDetector()`.
   Turning a detector off in Runtime Controls only takes effect on the next
   **Reinitialize**.
2. **No public `Logger`/`LogSink` access** — the SDK's internal logger is
   not reachable from host-app code. The Logs screen shows this app's own
   SDK call history instead.
3. **`SecurityEvent.data` is limited** — only ever carries `{action,
   confidence}`, never the original `DetectionResult.evidence`. Recording
   state is inferred from `confidence == 1.0`, not a direct field. The
   Detectors screen's "Run check" action is the only way to see raw
   `evidence`, and only for a manually-triggered check.
4. **Callback name collisions are undetected** — `NativeBridge
   .registerCallback` has zero collision detection. Registering
   `onScreenshotTaken`/`onScreenCaptureStateChanged` from host code
   silently overrides the SDK's own internal routing. The Callbacks
   screen refuses these names by default; an explicit "Advanced" opt-in
   demonstrates the risk.
5. **Public library exports only `FlutterShield`** —
   `package:flutter_shield/flutter_shield.dart` re-exports nothing else.
   Any app that registers a custom `Detector`/`Rule` or constructs a
   `FlutterShieldConfig` must import from `lib/src/...` directly, which is
   why `flutter analyze` reports `implementation_imports` info-lints
   throughout this example app — expected, not a defect in the app.
6. **No observable signal for periodic-timer check ticks** — the SDK's
   internal periodic `Timer` calls `checkNow()` on its own; no callback
   or event distinguishes a periodic tick from an explicit `checkNow()`
   call, or reports a periodic tick's own success/failure. The Health
   Monitor screen's "Explicit Check Now calls" counters therefore only
   count manually-triggered calls — an honest scope limit, not an
   omission.

---

## Sign-off

| Platform | Build | Native tests | Manual pass | Signed off by | Date |
|----------|-------|---------------|-------------|----------------|------|
| Android (Gradle, `testDebugUnitTest`) | ✅ built via `flutter build ios`/Gradle compile | ✅ 40/40 passed (2026-08-11 audit run) | Not run on a real Android emulator/device this session — NOT TESTED interactively | | |
| iOS (26.4.1 Simulator, iPhone 17 Pro Max) | ✅ `flutter build ios --simulator` (two runs, including after adding `ScreenCaptureProtection.swift`) | ⚠️ NOT TESTED — `xcodebuild test -scheme flutter_shieldTests` cannot run standalone in this repo (`ios/FlutterFramework` is an unpopulated placeholder SPM package outside Flutter's own build pipeline, and `Runner`'s scheme `TestAction` only wires up `RunnerTests`, not `flutter_shieldTests` — a pre-existing repo/tooling gap). Both new files (`AppSwitcherProtection.swift`, `ScreenCaptureProtection.swift`) were independently type-checked standalone (`swiftc -typecheck`, zero errors). | ✅ **protect-5/6/7 confirmed working live.** ⚠️ **protect-1/protect-9 tested live and found NOT working on Simulator** — see below. protect-10 (real device) NOT TESTED. | | 2026-08-11 |

**What "live" verification actually covered this session (iOS Simulator, real device pipeline, not simulated/assumed):**
- **App-switcher protection (protect-5/6/7) — confirmed working**: SDK initialized via real UI tap → Protection screen → "Enable app-switcher protection" → live status flipped to `Yes` via the real MethodChannel round-trip → Home-button-backgrounded the app → **the real App Switcher card showed an opaque blurred rectangle, not the actual Protection screen content** → foregrounded again → content restored correctly, no crash, no stuck overlay.
- **Screenshot protection (protect-1/protect-9) — tested, and found NOT to work as intended on Simulator**: enabled via the same real UI path → `applied: true` returned → a real, observable side effect confirmed the `CALayer` re-parenting genuinely executed (the app's responsive layout switched from a drawer to a permanent nav rail immediately) → took a **ground-truth screenshot via `xcrun simctl io screenshot`** (the same underlying mechanism as Simulator's Cmd+S, not a debug capture) → **the screenshot showed full, real content, not black.** This is a genuine negative result, not an assumption or an untested gap — see design doc §18.5 for the honest write-up and the two open, unverified hypotheses for why.

## Acceptance checklist

- [ ] Every case above run at least once on Android
- [ ] Every case above run at least once on iOS
- [ ] `flutter analyze` passes (only the documented `implementation_imports`
      info-lints remain)
- [ ] `flutter test` passes (Dart, SDK + example)
- [ ] Android native (Gradle) unit tests pass
- [ ] iOS native (XCTest) unit tests pass
- [ ] No SDK source files were modified without a verified, documented bug
      and accompanying regression test
