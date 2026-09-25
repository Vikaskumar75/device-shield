# Root Detection (Android) & Jailbreak Detection (iOS) — Design Document

**Status:** Implemented. FR-01/FR-02 (ROADMAP.md, SDK_MILESTONE_PLAN.md M7) — two of the six P0 detectors.

---

## 1. Overview

### 1.1 Why this is needed

Root (Android) and jailbreak (iOS) both mean the same underlying thing: the OS's own security model — sandboxing, code-signing enforcement, filesystem permission boundaries — has been deliberately removed by the user or an attacker with physical/malware access. For a payment app, a rooted/jailbroken device is the precondition that makes almost every other attack in this SDK's scope (screen recording malware, injected hooks reading memory, tampered binaries) dramatically easier. Detecting it lets the app react — block sensitive flows, log for fraud review, force step-up authentication — before those follow-on attacks even need to succeed.

### 1.2 What this reuses — nothing new architecturally

This feature is a direct extension of the existing `Detector` pattern (`EmulatorDetector`/`DebuggerDetector`) — no new manager, no new controller, no new `FlutterShieldConfig` fields, no new `NativeBridge` transport. Two pure-poll `Detector`s, registered via the existing `DetectorFactory`, exactly like every built-in detector before them. See §8 for why this is deliberately minimal.

---

## 2. Capability Matrix

| Capability | Android (`RootDetector`) | iOS (`JailbreakDetector`) |
|---|---|---|
| Detect root/jailbreak | Yes — 9-category heuristic signal count | Yes — 5-category heuristic signal count |
| Runs on the "wrong" platform | Honest `{'applicable': false}` — root is not an iOS concept | Honest `{'applicable': false}` — jailbreak is not an Android concept |
| Requires host-app config | No — registered explicitly like every other built-in detector | No |
| Requires host-app manifest/Info.plist changes | No — `<queries>` declared in the plugin's own manifest, merges automatically | No |

---

## 3. Android: `RootDetector` — 9 signal categories

| Signal | Technique | Honesty note |
|---|---|---|
| `su_binary_path` | Common `su` paths exist (`/system/bin/su`, `/system/xbin/su`, `/sbin/su`, ...) | — |
| `su_executable` | `su` resolves via `which` on `PATH` | Distinct from the static path check — catches non-standard install locations |
| `superuser_apps_installed` | Known root-manager packages installed (Magisk, SuperSU, KingRoot, ...) via `PackageManager` | Requires the `<queries>` block in `android/src/main/AndroidManifest.xml` — see §3.1 |
| `magisk_artifacts` | Magisk-specific paths (`/sbin/.magisk`, `/data/adb/magisk`, ...), kept separate from the package check | Magisk's DenyList/Hide feature can evade plain package listing; a dedicated path check is independent evidence |
| `writable_system` | Attempted write to `/system`/`/system/bin` | **Weaker signal, by design**: systemless Magisk (the dominant rooting method since ~2019, OverlayFS/magic-mount) frequently leaves `/system` genuinely read-only. Kept because it costs nothing and the signal-count model tolerates a miss — never treated as authoritative alone |
| `busybox_present` | `/system/xbin/busybox`, `/system/bin/busybox` exist | — |
| `build_tags_test_keys` | `Build.TAGS` contains `"test-keys"` | **Noisy signal, by design**: legitimate custom ROMs (LineageOS, GrapheneOS) and some OEM builds ship test-keys without being rooted |
| `dangerous_system_props` | `ro.debuggable=1` / `ro.secure=0` via shelling out to `getprop` | Deliberately **not** reflection into the hidden `android.os.SystemProperties` class — that's on Android's non-SDK interface restriction list on modern API levels; shelling out is a plain process call with no such risk |
| `root_cloaking_apps_installed` | Known root-hiding app packages, separate list from the superuser-app check | Evidence of an active evasion attempt, not just root itself |

Confidence: `(signals.size / 9.0).coerceAtMost(1.0)` — identical formula to `EmulatorDetector`/`DebuggerDetector`, no new confidence model invented.

### 3.1 Why `<queries>` and not `QUERY_ALL_PACKAGES`

Android 11 (API 30) restricts `PackageManager.getPackageInfo()` for a specific package name to `NameNotFoundException`, regardless of whether it's actually installed, unless the caller either declares that package in a `<queries>` manifest element or holds the `QUERY_ALL_PACKAGES` permission. The latter requires a Play Console declaration/justification form and draws heavy review scrutiny — an unreasonable, unnecessary ask to put on every host app for a generic security SDK. `<queries>` entries declared in **this plugin's own** `AndroidManifest.xml` merge automatically into the host app's final manifest via Gradle's standard manifest merger — zero host-app configuration required, no runtime permission prompt (declaring a `<package>` element is not a dangerous-permission grant).

---

## 4. iOS: `JailbreakDetector` — 5 signal categories

| Signal | Technique | Honesty note |
|---|---|---|
| `jailbreak_app_paths` | `/Applications/Cydia.app`, `Sileo.app`, `Zebra.app` exist | — |
| `suspicious_system_paths` | `/Library/MobileSubstrate/MobileSubstrate.dylib`, `/bin/bash`, `/etc/apt`, `/var/lib/cydia`, `/private/var/stash`, ... | — |
| `writable_outside_sandbox` | Attempt to write+delete a file at `/private/flutter_shield_jailbreak_test.txt` | Should fail under App Sandbox on a non-jailbroken device |
| `dyld_env_var` | `DYLD_INSERT_LIBRARIES` environment variable non-empty | Deliberately **not** a full `_dyld_image_count`/image-name scan for injected tweak dylibs — comprehensive runtime injection/hook-framework scanning is a separate, already-planned P0 feature (FR-07, "Runtime Hook Detection: Frida, Xposed, Substrate, Magisk modules"); this detector doesn't duplicate that scope |
| `process_spawn_check` | `posix_spawn` successfully launching `/bin/ls` as a child process | This is SRS §5.2's "jailbreak APIs" category. The classic version of this check is `fork()` — **not used here**: Swift's Darwin overlay marks `fork()` `@available(*, unavailable, message: "Please use threads or posix_spawn*()")`, a hard compiler error on this SDK, not a lint. Rather than route around that via `dlsym`/`dlopen` to reach the raw C symbol (crossing into the same "circumventing a deliberate platform restriction" territory `ScreenCaptureProtection.swift` already documents the risk of, and not separately approved for this detector), this uses `posix_spawn` — literally Apple's own suggested alternative in that error message, and an equivalent signal: a sandboxed app shouldn't be able to spawn an arbitrary system binary either |

Confidence: `min(Double(signals.count) / 5.0, 1.0)` — same formula.

### 4.1 Explicitly dropped for this pass

**`cydia://` URL-scheme `canOpenURL` check.** Unlike Android's `<queries>`, there is no manifest-merge equivalent for iOS `LSApplicationQueriesSchemes` via Swift Package Manager — adding this check would require the *host app* to manually edit its own `Info.plist`, breaking the zero-host-app-config pattern every other check in this feature preserves. Documented here as a candidate future enhancement, not silently forgotten.

---

## 5. Response shape and the `'applicable'` evidence key

Both detectors return the same shape as every existing detector — `{'detected': bool, 'confidence': double, 'signals': [String]}` — plus one new key, `'applicable': bool`.

This is deliberately **not** `ScreenRecordingDetector`'s existing `'supported'` key. That distinction is intentional, not incidental:

- `ScreenRecordingDetector`'s Android `'supported': false` describes a **capability gap** — Android genuinely cannot tell whether the screen is being recorded; the platform *could* theoretically support this, but no reliable OS signal exists.
- `RootDetector`'s iOS `'applicable': false` (and `JailbreakDetector`'s Android `'applicable': false`) describe something categorically different — "root" and "jailbreak" are not gaps in iOS/Android capability at all. The concept structurally doesn't exist on the other platform. There is nothing to detect, ever, on any iOS version, for `RootDetector` — this isn't a limitation that a future iOS release could lift.

Both are honest "no" answers, for genuinely different reasons — hence two different words.

---

## 6. Architecture — why this needed none

Every other piece of machinery this SDK has (`ScreenCaptureController`, the three `FlutterShieldConfig` fields, the `NativeBridge.registerCallback` push path) exists specifically because the screenshot/recording feature has a **native push mechanism** — an OS event that fires asynchronously and needs a boot-time decision about whether to listen for it. Root/jailbreak detection has no such mechanism: it's a synchronous poll, "what is true about this device right now," exactly like `EmulatorDetector`/`DebuggerDetector` already are. Those two detectors need zero `FlutterShieldConfig` fields and are registered explicitly by the host app via `DetectorFactory` + `DetectionManager.registerDetector()` — `RootDetector`/`JailbreakDetector` follow that exact precedent.

This is a deliberate choice informed by this SDK's own history: the screenshot/recording feature originally shipped three `FlutterShieldConfig` boolean flags that were validated and stored but never actually read by any runtime code — a real bug, found and fixed in a later audit. Adding config surface here that mirrors that same shape, for a feature that structurally doesn't need it, would risk repeating that exact mistake. No config field exists for this feature that isn't wired to something.

---

## 7. Security Considerations

### 7.1 This is heuristic detection, not a guarantee

Every signal, on both platforms, is independently weak evidence — confidence is a proportional signal count, never a certainty claim. A sophisticated attacker specifically targeting this SDK's own detection logic could evade some or all of these checks (root-cloaking tools exist precisely for this purpose — `root_cloaking_apps_installed` detects the presence of some of them, not their effectiveness). This is consistent with every other heuristic detector in this SDK (`EmulatorDetector`, `DebuggerDetector`) and is not a new limitation introduced here.

### 7.2 No private APIs, no App Store/Play Store policy risk

Every technique on both platforms uses only public, documented APIs: `File`/`FileManager` filesystem checks, `PackageManager` (Android, with proper `<queries>` declaration), `ProcessBuilder`/shelling out to `getprop` (Android), `posix_spawn`/`FileManager`/`ProcessInfo.environment` (iOS). Root/jailbreak detection itself is standard, widely accepted practice in production banking/payment apps on both stores. No private-API usage, no non-SDK-interface reflection (`SystemProperties` reflection was deliberately rejected in favor of shelling out — see §3), no `fork()` circumvention (see §4).

### 7.3 Privacy

No signal in either detector reads, transmits, or retains any user data — only filesystem/process/package-existence facts about the device itself. The `<queries>` package list (§3.1) never triggers any data collection; it only makes specific `getPackageInfo()` lookups possible.

---

## 8. Testing

| Layer | Coverage |
|---|---|
| Dart unit | `test/detectors/root_detector_test.dart`, `jailbreak_detector_test.dart` — response-shaping logic against a fake `NativeBridge`, mirroring `emulator_detector_test.dart`'s pattern exactly, including the `'applicable'` key on both the real and not-applicable response shapes |
| Dart integration | `test/detectors/root_jailbreak_detector_integration_test.dart` — real `DetectorFactory` + `DefaultDetectionManager` pipeline; the pre-existing "all built-in detectors together" test in `screenshot_recording_detector_integration_test.dart` was updated (4 → 6 detectors), not duplicated |
| Android unit | `RootDetectorTest.kt` — one test per signal category against `evaluate()`'s pure logic, synthetic inputs, mirroring `EmulatorDetectorTest.kt`'s pattern; `FlutterShieldPluginTest.kt` — dispatch tests for both `checkRoot` and the honest `checkJailbreak` not-applicable response |
| iOS unit | `JailbreakDetectorTests.swift` — one test per signal category against `evaluate()`; `FlutterShieldPluginTests.swift` — dispatch tests for both `checkJailbreak` and the honest `checkRoot` not-applicable response |
| Real device — non-negotiable, not satisfiable by mocks | A real rooted Android device/emulator (Magisk, both systemless and legacy) and a real jailbroken iOS device (checkra1n/unc0ver/palera1n, whichever is current) confirming `detected: true` with a real signal set, plus a real non-rooted/non-jailbroken device confirming `detected: false` — **not performed as part of this implementation pass**; flagged here explicitly, not silently assumed to pass |
