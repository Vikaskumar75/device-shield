# DeviceShield — Current Code & Folder Structure

A snapshot of exactly what exists in the repo today, checked directly against the filesystem. This is the "as-is" — compare against `ARCHITECTURE.md` (the target design) and `ROADMAP.md` (the plan to get from here to there).

**Bottom line:** this is the unmodified `flutter create --template=plugin` output, plus one shell script (`setup.sh`) that scaffolded 17 empty feature folders. **56 lines of real Dart code total**, all of it default-plugin boilerplate. Nothing SRS-specific has been implemented yet.

---

## Annotated Folder Tree

```
device_shield/
├── pubspec.yaml                          # placeholder: name/description generic, no homepage,
│                                          #   android package = com.example.device_shield
├── pubspec.lock
├── analysis_options.yaml                 # default flutter_lints config
├── README.md                             # default plugin README, unedited
├── CHANGELOG.md                          # default, empty entry
├── LICENSE
├── setup.sh                              # the script that created the 17 empty feature folders below
├── ARCHITECTURE.md                       # ← target design (written this session)
├── ROADMAP.md                            # ← build plan (written this session)
│
├── lib/
│   ├── device_shield.dart               # 8 lines  — DeviceShield class, ONE method: getPlatformVersion()
│   ├── device_shield_platform_interface.dart   # 29 lines — federated-plugin platform interface (real, reusable)
│   ├── device_shield_method_channel.dart       # 19 lines — MethodChannelDeviceShield, wraps getPlatformVersion()
│   │
│   └── features/                         # 17 identical empty scaffolds — see detail below
│       ├── root_detection/
│       ├── jailbreak_detection/
│       ├── emulator_detection/
│       ├── debugger_detection/
│       ├── developer_options/
│       ├── mock_location/
│       ├── runtime_hook/
│       ├── app_integrity/
│       ├── screenshot/
│       ├── screen_recording/
│       ├── overlay_detection/
│       ├── clipboard/
│       ├── ssl_pinning/
│       ├── security_profile/
│       ├── policy_engine/
│       ├── event_system/
│       └── custom_rules/
│
├── android/
│   ├── build.gradle.kts                  # namespace com.example.device_shield, compileSdk 36, minSdk 24
│   ├── settings.gradle.kts
│   └── src/
│       ├── main/
│       │   ├── AndroidManifest.xml
│       │   └── kotlin/com/example/device_shield/
│       │       └── DeviceShieldPlugin.kt   # 38 lines — MethodCallHandler, ONE method: getPlatformVersion
│       └── test/kotlin/com/example/device_shield/
│           └── DeviceShieldPluginTest.kt   # default plugin test
│
├── ios/
│   ├── device_shield.podspec             # placeholder: homepage=example.com, author="Your Company"
│   │                                       #   platform :ios, '13.0'  (SRS wants 18.0 — see ROADMAP M0)
│   └── device_shield/
│       ├── Package.swift                  # platforms: [.iOS("13.0")]
│       └── Sources/device_shield/
│           ├── DeviceShieldPlugin.swift  # 19 lines — FlutterPlugin, ONE method: getPlatformVersion
│           └── PrivacyInfo.xcprivacy
│
├── test/
│   ├── device_shield_test.dart                    # tests getPlatformVersion() only
│   └── device_shield_method_channel_test.dart     # tests getPlatformVersion() only
│                                                    # no test/unit, test/integration, test/native dirs yet
│
└── example/                              # standard `flutter create` example app, unmodified
    ├── lib/main.dart                     # default counter-app template
    ├── android/…                         # default Android host app
    ├── ios/…                             # default iOS host app (Runner)
    ├── integration_test/plugin_integration_test.dart
    └── test/widget_test.dart
```

---

## `lib/features/` — detail (this is where most of the empty scaffolding lives)

`setup.sh` created **the same 7-folder skeleton, 17 times over** — once per SRS feature. Every single file below is **0 bytes**:

```
lib/features/<feature_name>/
├── <feature_name>.dart          # 0 bytes
├── data/
│   ├── datasource/               # empty directory, no files
│   └── models/                   # empty directory, no files
├── domain/
│   ├── entities/                 # empty directory, no files
│   ├── repositories/              # empty directory, no files
│   └── usecases/                 # empty directory, no files
└── infrastructure/                # empty directory, no files
```

Applies identically to all 17: `root_detection`, `jailbreak_detection`, `emulator_detection`, `debugger_detection`, `developer_options`, `mock_location`, `runtime_hook`, `app_integrity`, `screenshot`, `screen_recording`, `overlay_detection`, `clipboard`, `ssl_pinning`, `security_profile`, `policy_engine`, `event_system`, `custom_rules`.

**17 features × 7 subfolders = 119 directories, 17 files — all empty.**

---

## What's Real vs. Placeholder

| File | Status | Notes |
|---|---|---|
| `device_shield_platform_interface.dart` | ✅ Real, reusable | Correct federated-plugin pattern — the one piece of genuine foundation identified in the architecture review |
| `device_shield_method_channel.dart` | ✅ Real, but trivial | Wraps a single method (`getPlatformVersion`); will be superseded by `NativeBridge` (see `ARCHITECTURE.md`) |
| `device_shield.dart` | ⚠️ Placeholder | The `DeviceShield` public API class exists but exposes only `getPlatformVersion()` — none of §6.1's real surface |
| `DeviceShieldPlugin.kt` / `.swift` | ⚠️ Placeholder | Default plugin registration boilerplate; no detection/protection/bridge logic |
| All 17 `lib/features/*` files & subfolders | ❌ Empty | 0 bytes, 0 lines — scaffolding only |
| `pubspec.yaml` | ⚠️ Placeholder | `com.example.device_shield`, no homepage/repository |
| `ios/device_shield.podspec` | ⚠️ Placeholder | `homepage: http://example.com`, author `Your Company` |
| iOS deployment target | ⚠️ Mismatch | `13.0` in both `podspec` and `Package.swift`; SRS specifies `18.0` minimum |
| Android `minSdk` | ⚠️ Mismatch | `24`; SRS specifies API `21` minimum |
| `test/` | ⚠️ Default only | Both files test `getPlatformVersion()`; no `unit/`, `integration/`, `native/` split yet |

---

## By the Numbers

| Metric | Count |
|---|---|
| Real Dart lines in `lib/` | 56 (across 3 files) |
| Empty `.dart` files in `lib/features/` | 17 |
| Empty directories in `lib/features/` | 119 |
| Native plugin lines (Kotlin + Swift) | 57 (38 + 19) |
| Public methods implemented end-to-end | 1 (`getPlatformVersion`) |
| SRS functional requirements implemented | 0 of 18 |
| Architecture components implemented (of the 18 in `ARCHITECTURE.md`) | 1 of 18 — the platform interface only |

---

## Where This Goes Next

This structure is exactly what `ROADMAP.md`'s **M0 — Decisions & Repo Setup** exists to replace: the `lib/features/*` layout gets retired in favor of the SRS's `lib/src/{core,manager,bridge,detectors,protections,events,models,config,permission,utils}` layering, and the placeholder identifiers/versions get corrected before M1 begins.
