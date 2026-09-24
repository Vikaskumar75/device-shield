# FlutterShield — Session Handover

**Date:** 2026-09-24 · **Branch:** `main` · **Working tree:** clean

Written for a fresh Claude Code session picking this up. Read this first, then
`git log --oneline -6`.

---

## 1. Where things stand

```
8a940f4  Correct equality note in public API guard test     ← local only
ee7c55d  Fix Android 14+ crash and expose a usable public API ← local only
b28c027  Merge debugger-detection into main                 ← on origin/main
fcb88f8  Merge screen/root/mock-location chain into main    ← on origin/main
7ed7488  Wire emulator detection into the example app       (old root)
```

- `origin/main` = `b28c027`. The two merge commits **are** pushed.
- Local `main` is **2 commits ahead**, unpushed: `ee7c55d`, `8a940f4`.
- `main` has **no upstream tracking set**. Use `git push origin main`
  (fast-forward, no force needed), or `git push -u origin main` to set it.
- Recovery point: `git reset --hard origin/main` drops both local commits.

### What the merge did

Five branches, three unrelated root commits, no shared base. Resolved by
merging with `--allow-unrelated-histories` and keeping both roots, so all five
branches are ancestors of `main` and show as merged.

The important fact: **`feature/mock-location-detection` was a strict content
superset of everything else.** All debugger/emulator files were byte-identical
across roots; no file existed on the old root that was absent from the chain.
All 46 add/add conflicts resolved one way. Final tree hash was verified
identical to `f4c3635`. **Nothing was lost — there is no merge work left.**

---

## 2. Done this session

**Finding 1 — Android 14+ crash (fixed, `ee7c55d`)**

`FlutterShieldPlugin.onAttachedToActivity` → `ScreenshotDetector.start()` →
`Activity.registerScreenCaptureCallback()`, which API 34 gates behind
`android.permission.DETECT_SCREEN_CAPTURE`. The permission was declared
nowhere, so this threw `SecurityException` on attach — before any Dart ran,
for every host app on Android 14+.

- Declared in `android/src/main/AndroidManifest.xml` (normal, install-time,
  no prompt, auto-merged into host manifest, ignored below API 34).
- `ScreenshotDetector.start()` catches `SecurityException`/
  `IllegalStateException` anyway — a host can strip a merged permission with
  `tools:node="remove"`, and this runs from a lifecycle callback.
- `callback` is now assigned only *after* registration succeeds; `stop()`
  hardened symmetrically.

> ⚠️ **Not device-verified.** No Android 14 device or emulator was run. The
> requirement comes from the API 34 docs. JVM tests cannot reach this path
> (`Build.VERSION.SDK_INT` reads 0, so `start()` returns at the `isSupported`
> check). **Confirming this needs a real API 34+ device — please do that
> before trusting the fix.**

**Finding 3 — unusable public API (fixed, `ee7c55d`)**

`lib/flutter_shield.dart` exported only the `FlutterShield` facade. Every type
needed to call it lived under `src/`. Now exports config/state, detection and
event models, the exception hierarchy, `Detector`/`Rule`/`DetectorFactory`,
the `subscribe()` typedefs, bridge transport, and all seven detectors.

Deliberately withheld (documented in the barrel): `SecurityProfile` — no
`initialize()` overload accepts one yet; `Logger` — no injection point;
manager/bootstrap internals.

All 10 example files rewritten onto the public import. Added
`test/public_api_test.dart`, which imports **only** the barrel, so dropping an
export fails compilation — verified by deleting the `root_detector` export and
watching it break.

---

## 3. Open work, highest value first

### Blocking a release

**F4 — iOS screenshot protection is broken but reports success.**
`ios/.../Protection/ScreenCaptureProtection.swift:71-92`. The secure-`UITextField`
layer trick creates a view/layer cycle (the field is a subview of `view` while
`view.layer` becomes a sublayer of the field's own sublayer) and picks
`sublayers?.last`, which is iOS-version dependent. It returns `applied: true`
regardless. The repo's own live test (`MANUAL_TEST_PLAN.md`, protect-9)
recorded screenshots **not** blocked and layout visibly breaking.

This is a decision, not a patch: return `applied: false` on iOS, or gate it
behind explicit opt-in, until device-verified. Don't ship a protection API
that lies about working.

**F2 — native detectors block the UI thread.**
`android/.../FlutterShieldPlugin.kt:93-116`. All `check*()` handlers run
synchronously in `onMethodCall`. `RootDetector.check()` spawns three
subprocesses (`which su`, `getprop` ×2), does filesystem writes under
`/system`, and ~21 `PackageManager` lookups; `MockLocationDetector` adds 10
more plus `LocationManager`. The example app fires this every 5s. Jank
guaranteed, ANR plausible. Fix: background executor, post result back.

### Medium

**F5 — false positives.** `detected = signals.isNotEmpty()` in all four Kotlin
detectors (`RootDetector.kt:132`, `MockLocationDetector.kt:139`,
`EmulatorDetector.kt:88`, `DebuggerDetector.kt:53`) and the Swift ones. One
weak signal is enough: `build_tags_test_keys` (common on OEM/custom ROMs),
`dangerous_system_props` (`ro.debuggable=1` on every emulator and eng build),
`busybox_present`. **Every Android emulator reports rooted.** A fake-GPS app
merely *installed* → `detected: true`. `confidence` is computed but the
boolean is what events and policy key on. Needs strong/weak weighting with a
threshold.

**F6 — iOS mock-location barely functions.**
`ios/.../Detection/MockLocationDetector.swift:56-58` creates a fresh
`CLLocationManager()` and reads `.location` without starting updates —
typically `nil`, so velocity and accuracy signals rarely fire. Doesn't use
`CLLocation.sourceInformation.isSimulatedBySoftware` (iOS 15+), the one
official API for this.

**F7 — Android screen-recording detection is stale.**
`ScreenRecordingDetector.kt:26` hard-codes "no reliable signal exists".
Android 15 (API 35) added `WindowManager.addScreenRecordingCallback`.

**F8 — events drop what matters.**
`default_security_manager.dart:177` always emits `severity: EventSeverity.info`
with `data: {action, confidence}` — no `detected`, no `status`, no `signals`.
A detector *failure* is indistinguishable from a clean pass to subscribers.
`default_policy_manager.dart:65` `executeAction` is a logging no-op, so with
no rules the SDK detects and reports only — nothing is enforced. Defensible at
this phase, but the README must say so.

**F9 — App Store review risk.** `JailbreakDetector.swift` uses
`posix_spawn("/bin/ls")` and writes to `/private/`. Standard heuristics, but
flag it.

### Decision, not a bug

**Map equality on round-trip.** `SecurityEvent.fromJson(e.toJson())` is never
`==` to `e` — including when `data` is the default empty map — because
`fromJson`'s `.cast()` builds a new map instance.

I initially called this a defect; **that was wrong.**
`lib/src/models/detection_result.dart:8-11` documents comparing maps by
reference as a deliberate trade-off (deep equality would pull in the
`collection` package), and `security_event.dart` inherits it explicitly. The
round-trip consequence is real and may surprise anyone deduplicating events —
worth a decision, not an oversight. `8a940f4` corrects the comment.

### Hygiene

- `CURRENT_STATE.md` is badly stale — says "56 lines of Dart, unmodified
  template". The repo is ~4,900 lines of Dart plus native.
- `README.md`, `CHANGELOG.md`, `pubspec.yaml` (description, homepage) are all
  template placeholders.
- Both plugin classes' doc comments still claim "every other bridge method
  still returns notImplemented()" — untrue since several landed.
- `FlutterShield.getPlatformVersion()` is the lone instance method on an
  otherwise all-static facade. Template leftover.
- No CI.

---

## 4. Running things

Works:

```bash
flutter analyze            # expect: No issues found!
flutter test               # expect: 360 passing
cd example && flutter test # expect: 1 passing
```

**Does not work** — don't burn time rediscovering:

- **Android unit tests.** No gradle wrapper in `example/android/`. Needs a
  `flutter build apk` first to generate it, or a wrapper committed.
  `MANUAL_TEST_PLAN.md` claims 40/40 passing from a 2026-08-11 audit run.
- **iOS Swift tests.** `swift test` in `ios/flutter_shield/` fails —
  can't resolve `UIKit`/`Flutter`. `ios/FlutterFramework` is an unpopulated
  placeholder SPM package outside Flutter's build pipeline, and `Runner`'s
  scheme only wires `RunnerTests`, not `flutter_shieldTests`. Pre-existing
  repo/tooling gap, documented in `MANUAL_TEST_PLAN.md`.
- If you run `swift test` anyway, delete `ios/flutter_shield/.build/`
  afterwards — it's untracked build noise.

Toolchain: Flutter 3.44.8 stable, via fvm at `~/fvm/default`.

---

## 5. Notes for whoever picks this up

- **The docs are unusually honest.** `MANUAL_TEST_PLAN.md` records real
  negative results (protect-9 tested and found not working) rather than
  claiming success. Trust them, and keep that standard — several findings
  above came straight out of reading them.
- **Android has never been run on a device or emulator.** The sign-off table
  in `MANUAL_TEST_PLAN.md` says so explicitly. F1 and F2 both follow from it.
- The Dart core is genuinely well-built: DI container, lifecycle state
  machine, per-detector timeout with error isolation, in-flight dedup on
  `runAllChecks()`, `MethodCodes` as single source of truth, honest
  `applicable: false` cross-platform answers, pure `evaluate()` functions
  unit-tested on all three layers. The problems are at the edges, not the
  architecture.
- `test/public_api_test.dart` is the guard for the public surface. If you add
  a type a host app needs, export it in `lib/flutter_shield.dart` **and**
  reference it there.

**Verdict as of this handover:** sound architecture, not shippable. F4 and F2
each independently block a release.
