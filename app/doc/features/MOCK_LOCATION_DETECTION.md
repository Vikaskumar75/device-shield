# Mock Location Detection (Android + iOS) — Design Document

**Status:** Implemented. FR-06 (ROADMAP.md, SDK_MILESTONE_PLAN.md M8) — one of the two P1 detectors.

---

## 1. Overview

### 1.1 Why this is needed

A spoofed GPS fix lets an attacker (or a legitimate user gaming a feature) present a false physical location to the host app — defeating location-based fraud checks, geofencing, ride-hailing/delivery proof-of-location, or "verify you're at the branch" flows. Unlike root/jailbreak, this is a real concept on **both** platforms: Android exposes a direct OS-level "this fix came from a mock provider" flag; iOS exposes nothing equivalent, so genuine spoofing there almost always requires a jailbreak tweak or an attached debugger's location simulation. This detector gives the host app a signal it can react to (block a location-gated flow, flag for fraud review) on both platforms, honestly reflecting that the signal is much stronger on one than the other.

### 1.2 What this reuses — nothing new architecturally

Same `Detector` pattern as every other built-in: one `MockLocationDetector` (Dart) + one native implementation per platform + registration in `DetectorFactory`. No new manager, no new controller, no new `FlutterShieldConfig` field, no new `NativeBridge` transport — see §6 of `docs/features/ROOT_JAILBREAK_DETECTION.md` for why that's the deliberate default for a synchronous poll-style detector, which this is.

The one genuinely new pattern: **per-instance statefulness**. The `impossible_velocity` signal (§5) compares this `check()` call's fix against the previous one, so both native implementations hold an in-memory "last fix" — every prior detector in this SDK is stateless per call.

---

## 2. Capability Matrix

| Capability | Android (`MockLocationDetector`) | iOS (`MockLocationDetector`) |
|---|---|---|
| Detect mock/spoofed location | Yes — 5-category heuristic signal count | Yes — 3-category heuristic signal count |
| `applicable` | Always `true` — real concept on this platform | Always `true` — real concept on this platform |
| Requires OS permission for its strongest signal | Yes — `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION`, **checked, never requested** (§3, §7.4) | Yes — location authorization, **checked, never requested** |
| Requires host-app config | No — registered explicitly like every other built-in detector | No |
| Requires host-app manifest/Info.plist changes | No — fake-GPS `<queries>` declared in the plugin's own manifest, merges automatically | No |

---

## 3. Android: `MockLocationDetector` — 5 signal categories

| Signal | Technique | Honesty note |
|---|---|---|
| `mock_provider_flag` | `Location.isFromMockProvider()` on the most recent fix from `GPS_PROVIDER`/`NETWORK_PROVIDER`/`PASSIVE_PROVIDER` via `LocationManager.getLastKnownLocation` (passive read, no active fix request) | Strongest signal, but absent entirely — not "false" — when location permission isn't granted or no provider has ever produced a fix. This SDK never requests that permission itself; see §7.4 |
| `fake_gps_app_installed` | Known fake-GPS packages (`com.lexa.fakegps`, `com.rosteam.gpsemulator`, ...) via `PackageManager` | Same non-exhaustive-list caveat `RootDetector`'s superuser-package check already documents; requires the `<queries>` block, same Android 11+ requirement |
| `mock_app_selected_for_this_app` | `AppOpsManager.checkOpNoThrow("android:mock_location", myUid, packageName) == MODE_ALLOWED` | **Weaker signal, by design**: since Android 6, an app can only learn whether *it itself* was selected as the system mock-location app in Developer Options — the OS deliberately hides which *other* app holds that role. A `false` here is not proof no other app is mocking |
| `legacy_allow_mock_location_setting` | `Settings.Secure.ALLOW_MOCK_LOCATION == "1"`, evaluated only on API < 23 | Pre-Marshmallow global toggle, superseded by the per-app model above; always `false` on API 23+ by design, not a real negative signal there |
| `impossible_velocity` | See §5 | Shared logic/name with the iOS implementation |

Confidence: `(signals.size / 5.0).coerceAtMost(1.0)` — same signal-count formula as every other detector.

Explicitly **excluded**: a "Developer Options enabled" signal — that's FR-05's entire scope (`DeveloperOptionsDetector`, not yet built). Including it here would duplicate a separately planned detector, the same non-duplication precedent `JailbreakDetector.swift` sets for not scanning for runtime hooks itself (FR-07's scope).

---

## 4. iOS: `MockLocationDetector` — 3 signal categories

| Signal | Technique | Honesty note |
|---|---|---|
| `known_spoofing_tweak_artifact` | Common jailbreak location-spoofing tweak paths (`LocationFaker.plist`, `FakeGPS.app`, ...) | Same static-path-list technique as `JailbreakDetector`'s `SUSPICIOUS_SYSTEM_PATHS` |
| `invalid_location_accuracy` | Last fix's `CLLocation.horizontalAccuracy < 0` (CoreLocation's own documented invalid-fix marker) | Weak, rare, but a real public-API signal |
| `impossible_velocity` | See §5 | Shared logic/name with the Android implementation |

Confidence: `min(Double(signals.count) / 3.0, 1.0)` — same formula.

CoreLocation exposes no public "this fix was mocked" API at all, unlike Android's `isFromMockProvider()` — so iOS signal strength is inherently lower. This is reported honestly as a smaller signal-category count, **not** as `applicable: false` — mock location is a real, detectable-in-principle concept on iOS, just with weaker evidence than Android, which is a genuinely different situation from root/jailbreak's platform-exclusive concepts (see §6 of `ROOT_JAILBREAK_DETECTION.md`'s own `'applicable'` distinction, which this feature follows without repeating it).

Deliberately does **not** re-check jailbreak status itself — that's `JailbreakDetector`'s own scope; composing signals across detectors happens at the `SecurityManager` level, not by one detector calling another.

---

## 5. Cross-platform signal: `impossible_velocity`

Computed identically on both platforms from two consecutive `check()` calls on the same detector instance: haversine distance between this fix and the previous one, divided by elapsed time, flagged if implied speed exceeds 300 m/s (~1080 km/h — well above commercial ground travel, so a real device should never legitimately trigger this).

Edge cases handled explicitly:
- **First-ever call**: nothing to compare against — the signal simply doesn't fire (not evaluated, not "false"); it only seeds state for the next call.
- **GPS jitter on a stationary device**: deltas below 10 m / 3 s are ignored outright rather than risk a false positive from ordinary drift.
- **State is in-memory only, per process** — reset on app restart or detector re-registration. Expected, not a bug — the same "expected false-negative" framing `RootDetector.kt` documents for systemless Magisk.
- **System clock manipulation** could mask or inflate the computed speed either way. A known, unaddressed weak point — the same class of caveat `RootDetector.kt` documents for `build_tags_test_keys` — not solved here.

---

## 6. Response shape

```
{ detected: bool, confidence: double, signals: [String], applicable: true,
  permissionGranted: bool,   // Android: real; iOS: real; always present
  locationAvailable: bool }  // whether any fix (fresh or cached) was found to inspect
```

`applicable` is always `true` on both platforms — mock location is a real concept on both, unlike root/jailbreak. The capability gap that does exist (Android's/iOS's location permission not being granted) is surfaced through `permissionGranted`/`locationAvailable` instead, the same `'supported'`-style honest-gap pattern `ScreenRecordingDetector` already uses for its own Android capability gap (`docs/features/ROOT_JAILBREAK_DETECTION.md` §5 draws this same distinction between "doesn't exist" and "can't currently tell").

---

## 7. Security Considerations

### 7.1 This is heuristic detection, not a guarantee

Every signal is independently weak evidence, same as every other detector in this SDK. `mock_provider_flag` is the strongest single Android signal but still not certainty — the OS honors whatever app was selected as the system mock-location provider, which this SDK cannot itself detect authoritatively (§3's `mock_app_selected_for_this_app` limitation).

### 7.2 No private APIs

`LocationManager`, `PackageManager`, `AppOpsManager.checkOpNoThrow` (Android), `CLLocationManager`, `FileManager` (iOS) are all public, documented APIs. The `AppOpsManager` op string (`"android:mock_location"`) is hardcoded rather than referencing `AppOpsManager.OPSTR_MOCK_LOCATION` (which is `@SystemApi`-hidden) — the string itself is stable AOSP and `checkOpNoThrow` is a public method, so no reflection into hidden APIs is used, the same restraint `RootDetector.kt` documents for avoiding `SystemProperties` reflection.

### 7.3 Privacy

The detector reads location data already available to the process (via whatever permission the host app separately obtained) — it does not request new access, transmit coordinates anywhere, or persist them beyond the single in-memory "last fix" used for the velocity check, which is cleared on process restart.

### 7.4 Deliberately never requests the location permission itself

This is the first detector in this SDK whose strongest signal depends on a dangerous runtime permission. No detector or protection in this codebase requests one — `PermissionManager`/`DefaultPermissionManager` exist only as scaffolding today (`requestPermissions` throws `UnimplementedError` for any non-empty set). Building a real `ActivityCompat.requestPermissions` flow just for this one detector was considered and deliberately rejected for this pass: it would be new SDK-wide plumbing (a bridge method, a permission-result callback, `Activity` lifecycle handling) with a host-app-visible side effect (a permission dialog) triggered just by enabling one detector, disproportionate to this feature's own scope. Instead, `check()` only reads whatever grant state already exists — if the host app separately holds location permission for its own features, this detector gets the strong signal for free; otherwise it degrades gracefully and reports `permissionGranted: false` rather than a silently confident "not detected". Building the request flow is a legitimate future enhancement, tracked here rather than silently assumed out of scope forever.

---

## 8. Testing

| Layer | Coverage |
|---|---|
| Dart unit | `test/detectors/mock_location_detector_test.dart` — response-shaping logic against a fake `NativeBridge`, mirroring `root_detector_test.dart`'s pattern, including the permission-denied honest-gap shape |
| Dart integration | `test/detectors/mock_location_detector_integration_test.dart` — real `DetectorFactory` + `DefaultDetectionManager` pipeline; the "all built-in detectors together" test in `screenshot_recording_detector_integration_test.dart` was updated (6 → 7 detectors), not duplicated |
| Android unit | `MockLocationDetectorTest.kt` — one test per signal category against `evaluate()`'s pure logic, synthetic inputs, plus dedicated permission-gap tests; `FlutterShieldPluginTest.kt` — dispatch test for `checkMockLocation` |
| iOS unit | `MockLocationDetectorTests.swift` — one test per signal category against `evaluate()`, plus a `testCheck_neverThrowsAndReturnsTheExpectedShape` smoke test; `FlutterShieldPluginTests.swift` — dispatch test for `checkMockLocation` |
| Real device — non-negotiable, not satisfiable by mocks | An Android emulator (whose default location genuinely is a mock provider — expected `detected: true`, not a bug, see §9), a real Android device with a fake-GPS app installed and location permission granted, and a real iOS device/Simulator — **not performed as part of this implementation pass**; flagged here explicitly, not silently assumed to pass |

---

## 9. Known overlap with `EmulatorDetector`

Android emulators' default location provider genuinely is a mock provider — `MockLocationDetector` will correctly (not spuriously) report `detected: true` on most AVDs, the same effect `EmulatorDetector` reports for a different reason. This is expected overlap in *outcome*, not scope duplication — each detector reaches its answer independently through its own signals, exactly as intended when a host app combines multiple detectors' results.
