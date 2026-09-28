# Manual test plan (0.1.0)

How `device_shield` is verified on real platforms, and what has been
verified so far. Record negative results as carefully as positive ones.

The previous plan, written for the pre-0.1 API, is kept in
[`reports/MANUAL_TEST_PLAN_pre-0.1.md`](reports/MANUAL_TEST_PLAN_pre-0.1.md).

## 1. Automated device test

Runs every native check on a connected device, emulator or simulator:

```bash
cd app/example
flutter test integration_test -d <device-id>
```

On iOS, run it from a copy of `app/` named `device_shield` (F10 in
`HANDOVER.md`).

| Run | Date | Result | Signals observed |
|---|---|---|---|
| Android 17 emulator, API 37 (`sdk_gphone16k_arm64`) | 2026-09-28 | 2/2 pass | root: none · emulator: `hardware`, `product` (detected) · debugger: `debuggable_flag` (clear) · mock location: none |
| iOS 26.5 Simulator, iPhone 17 Pro | 2026-09-28 | 2/2 pass | root: not applicable · jailbreak: not applicable · emulator: `simulator_target` (detected) · debugger: none · mock location: none |
| Physical Android device | — | Not run | |
| Physical iPhone | — | Not run | |

## 2. Manual checks with the example app

Build and run `app/example`. Use a release build on Android
(`flutter build apk --release`), since a debug APK started outside
`flutter run` can stall on the splash screen.

| # | Check | Android 17 emulator | iOS 26.5 Simulator | Physical iPhone |
|---|---|---|---|---|
| M1 | App starts; all five checks show a status, none `Failed` | ✓ | ✓ | |
| M2 | Screenshot: the event log shows "Screenshot taken" | ✓ (`adb shell input keyevent 120`) | Not tested | |
| M3 | Screenshot protection on: system screenshot content is black | ✓ | Can't be verified on the Simulator | **See §3** |
| M4 | Screenshot protection on: screen recording content is black | Not tested | Can't be verified on the Simulator | **See §3** |
| M5 | Screenshot protection on, then rotate: still black | ✓ | — | |
| M6 | Screenshot protection off: captures show content again | ✓ | ✓ layout and touch unaffected | |
| M7 | Screenshot protection on and off: layout, scrolling and taps unaffected | ✓ | ✓ | |
| M8 | App-switcher protection on: the app-switcher snapshot hides content | Not tested | Earlier Simulator run ✓ | |
| M9 | Screen recording starts/stops: "Screen being recorded" updates | — | Not tested | |

On Android, `dumpsys gfxinfo` can't measure Flutter frame timing, because
Flutter renders to its own surface. That checks run off the main thread is
covered by JVM tests instead (`DeviceShieldPluginTest`).

## 3. iOS screenshot protection on a physical iPhone

iOS screenshot protection relies on undocumented UIKit behaviour, and the
Simulator can't show whether it blocks captures. This decides whether 0.1.0
ships it (as experimental) or reports `unsupported`.

1. Build the example from a copy named `device_shield` and run it on the
   iPhone (release or profile mode):
   ```bash
   cd <copy>/device_shield/example && flutter run --release -d <iphone-id>
   ```
2. Turn on **Screenshot protection**. The switch turns on only if the
   platform reported `applied`; the event log shows the result.
3. Take a screenshot (side button + volume up). Open it in Photos.
   **Pass:** the app's content is black or blank.
4. Start a screen recording from Control Center, return to the app for a
   few seconds, and stop. **Pass:** the app's content is black or blank in
   the recording.
5. With protection still on, scroll, tap both switches, rotate to landscape
   and back, and open and close the app switcher. **Pass:** layout and
   touch behave normally, and nothing is stuck.
6. Turn protection off and take another screenshot. **Pass:** content is
   visible again.

Record the iOS version, device model and each step's result here:

| Step | Result | Notes |
|---|---|---|
| iOS version / model | | |
| 3. Screenshot blank | | |
| 4. Recording blank | | |
| 5. Layout and touch normal | | |
| 6. Off restores content | | |
