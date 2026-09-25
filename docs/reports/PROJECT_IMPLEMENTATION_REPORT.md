# DeviceShield SDK — Project Implementation Report

**Prepared:** 2026-08-03
**Method:** every file under `lib/`, `test/`, `android/`, `ios/`, and `example/` was read directly in full; `flutter analyze` and `flutter test` were executed against the current working tree; every claim below is drawn from that direct reading, not from prior documentation. Where this report's findings differ from `CURRENT_PROGRESS.md` (dated 2026-07-24) or `CURRENT_STATE.md` (an early-scaffold snapshot, now badly stale), that is called out explicitly — the codebase has moved since those documents were written, most notably: `PermissionManager` now exists and is wired into boot, `PluginInitializer` now constructs every manager itself, `DetectorFactory` exists, a full P0 detector (`EmulatorDetector`) is implemented end-to-end on both platforms, and the iOS/Android platform-floor mismatch has been resolved.
**No SRS document exists anywhere in this repository.** `ARCHITECTURE.md`, `ARCHITECTURE_CONTRACTS.md`, `ROADMAP.md`, and `SDK_MILESTONE_PLAN.md` all cite an SRS by section number (§7.4, §13.1, §26.1, etc.), but no file matching `*srs*`/`*requirements*` exists. Every SRS-derived claim in this report is taken one level removed, from what those four documents say the SRS requires.
**Observed vs. inferred:** this report distinguishes what was directly read in source code ("observed") from architectural intent stated only in comments/docs ("documented intent") from this report's own analysis ("inferred"). Where something is missing, it is stated as "Not implemented" rather than guessed at.

---

## 1. Project Overview

### Purpose
DeviceShield is a Flutter plugin SDK for mobile application security: runtime threat detection (root/jailbreak, emulator, debugger, hooking frameworks, app-integrity attestation), a policy engine that turns detections into actions, an event bus for observability, and (per the roadmap, not yet built) app-hardening protections (screenshot/recording blocking, SSL pinning, clipboard protection, overlay detection).

### Goals (as expressed by the frozen architecture documents)
- A layered, dependency-injected core that is technique-agnostic — detectors and rules are pluggable via narrow contracts (`Detector`, `Rule`), never hardcoded into the managers that run them.
- One orchestrator (`SecurityManager`), one bridge (`NativeBridge`) — every public call and every native call has exactly one path through the system.
- A single source of truth for SDK status (`SecurityStateManager`) and for configuration (`ConfigurationManager`).
- Bounded, parallel detector execution that stays safe at 20+ registered detectors.
- Extensibility without modifying framework code: new detectors, new rules, new platforms, new log sinks, and new actions are all additive registrations, not edits to existing classes.

### SDK Responsibilities (as currently implemented — see §2/§8 for what's still missing)
- Boot/shutdown/reinitialize lifecycle management with a strict, tested state machine.
- Dependency injection and service composition (`ServiceContainer`, `PluginInitializer`).
- A native bridge over two dedicated Flutter platform channels (`device_shield/native_bridge`, `device_shield/events`), separate from the legacy Phase-1 `device_shield` channel.
- Detector registration/execution with bounded concurrency, per-detector timeout, and optional TTL caching.
- Policy rule registration/evaluation (mechanism only — no default rule content yet).
- An event bus with history, pause/resume queuing, and per-subscriber failure isolation.
- One real, working built-in detector: emulator/simulator detection, native on both Android and iOS.

### Supported Platforms
- **Android:** `minSdk 21`, `compileSdk 36`, Kotlin, Gradle (`com.android.library` plugin, AGP 9.0.1, Kotlin 2.3.20, JVM target 17).
- **iOS:** deployment target `18.0` (both `device_shield.podspec` and `Package.swift`), Swift 5.0/5.9 tools, Swift Package Manager layout (`ios/device_shield/Sources/device_shield`).
- Both platform floors were previously mismatched against the documented SRS targets (iOS was 13.0, Android was 24) — **this has since been corrected**: `ios/device_shield.podspec:16` and `ios/device_shield/Package.swift:9` both read `18.0`; `android/build.gradle.kts:31` reads `minSdk = 21`.
- No web, desktop, or other platform target exists or is planned in any frozen document.

### High-Level Architecture
Layered, top-down, strictly acyclic by design rule ("a component may depend on anything below it, never anything above it" — `ARCHITECTURE.md` §2):

```
Flutter App
   │
   ▼
DeviceShield (static facade)  ──────────────────────────────┐
   │                                                          │
   ▼                                                          │
PluginInitializer  (constructs + wires every service, once)   │
   │                                                          │
   ▼                                                          │
ServiceContainer  (type-keyed DI: singleton / lazy / factory) │
   │                                                          │
   ├── Logger              ├── EventManager                  │
   ├── PermissionManager    ├── DetectorRegistry               │
   ├── ConfigurationManager ├── DetectionManager               │
   ├── NativeBridge         ├── PolicyManager                  │
   ├── SecurityStateManager └── SecurityManager ◄──────────────┘
   │                              │
   │                              ▼
   │                        LifecycleManager (WidgetsBindingObserver)
   ▼
NativeBridge → MethodChannelService / EventChannelService → Native (Kotlin / Swift)
```

This matches the frozen design in `ARCHITECTURE.md`/`ARCHITECTURE_CONTRACTS.md` with one material, deliberate deviation from those documents' literal wording (see §17): construction of `DetectionManager`/`PolicyManager`/`SecurityManager`/`LifecycleManager` now lives inside `PluginInitializer` itself (as of the current code), not split across `PluginInitializer` and `DeviceShield` as `CURRENT_PROGRESS.md` (2026-07-24) found — that specific finding is **resolved** in the code as it stands today.

---

## 2. Current Repository Status

### Overall Completion
**~31%**, computed as an unweighted average of this report's own per-milestone completion assessment across all 23 milestones (M0–M22) defined in `ROADMAP.md` — see §8 for the full breakdown and §15 for why an unweighted milestone-count average likely understates remaining *feature* effort even though it's a fair measure of *framework* progress. This is a fresh assessment made for this report, not copied from `CURRENT_PROGRESS.md`'s ~28% (2026-07-24) — the code has advanced measurably since then, most importantly in M6 (framework) and the start of M7 (first real detector).

### Milestone Completion Table

| # | Milestone | Status | Completion |
|---|---|---|---|
| M0 | Decisions & Repo Setup | Partial | ~57% |
| M1 | Foundation Layer | Partial | ~70% |
| M2 | Configuration & Dependency Injection | Partial | ~55% |
| M3 | Native Bridge & Platform Channels | Partial | ~68% |
| M4 | Event System | Partial | ~85% |
| M5 | State Machine & SDK Lifecycle | **Completed** | ~95% |
| M6 | PluginInitializer, SecurityManager & Detector/Rule Framework | Partial (near-complete) | ~90% |
| M7 | Priority-0 Detectors | Partial (started) | ~17% (1 of 6) |
| M8 | Priority-1 Detectors | Not started | 0% |
| M9 | Policy Engine Content & Custom Rules | Partial | ~15% |
| M10 | Security Profiles | Partial | ~25% |
| M11 | Protections | Not started | 0% |
| M12 | Public API & UI Components | Partial | ~52% |
| M13 | Storage, Encryption & Security Utilities | Not started | 0% |
| M14 | Performance & Caching | Partial | ~35% |
| M15 | Compliance Packs | Not started | 0% |
| M16 | Internationalization | Not started | 0% |
| M17 | Logging & Error-Handling Hardening | Partial | ~10% |
| M18 | Testing Across All Modules | Partial | ~40% |
| M19 | Documentation & Developer Experience | Not started | 0% |
| M20 | Versioning & Deployment | Not started | 0% |
| M21 | Edge Case & Resilience Hardening | Not started | 0% |
| M22 | v1.0 Release | Not started | 0% |

### Implemented Components (summary — full detail in §4/§9)
Bootstrap (`ServiceContainer`, `DependencyResolver`, `PluginInitializer`, `BootstrapContext`), all 4 orchestration managers (`SecurityManager`, `DetectionManager`, `PolicyManager`, `EventManager`) with real implementations, `DetectorRegistry` + `DetectorFactory`, `PermissionManager`, `ConfigurationManager` + validator, `NativeBridge` + both channel services, `Logger`/`ConsoleLogger`, the full `SDKState` state machine, `LifecycleManager`, bounded concurrency (`ConcurrencyController`), a generic multi-level TTL cache backing `DetectionCache`, the complete model layer, the complete exception hierarchy, the `DeviceShield` public facade, and one real built-in detector (`EmulatorDetector`, Dart + Kotlin + Swift).

### Pending Components (summary)
Every detector except emulator (root, jailbreak, debugger, runtime-hook, app-integrity, developer-options, mock-location), all 5 protections (screenshot, screen-recording, overlay, clipboard, SSL pinning), all policy *content* (default rules, `ActionHandler`s, `CustomRule`), the 5 named `SecurityProfile` factory presets, storage/encryption utilities, compliance packs (GDPR/PCI-DSS/HIPAA), internationalization, `DeviceShieldWidget`/`SecurityAlertDialog`, production logging/recovery/retry infrastructure, the public export barrel (still exports only the facade), CI/CD, and all documentation/DX artifacts (the example app is still the unmodified `flutter create` counter template).

### Current Test Count
**202 tests**, all passing (`flutter test` run for this report, full pass, zero skips/failures), across 22 test files. Verified independently by counting `test(` occurrences directly (`grep -rc "test(" test --include="*.dart"` → 202), matching the runner's own `+202` completion line.

### `flutter analyze` Status
**Clean — "No issues found!"** (run directly for this report against the full working tree, ~21s).

### Architecture Health
Zero circular dependencies found (matches `ARCHITECTURE_CONTRACTS.md`'s own verification pass). Layer boundaries hold: `DetectionManager` has no `PolicyManager`/`EventManager`/`NativeBridge`-beyond-its-own-detectors reference; `PolicyManager` has no `DetectionManager` reference; `EventManager` remains a true dependency-free leaf; `LifecycleManager` holds only the narrow `SecurityLifecycleHandler` callback contract, never `SecurityManager` directly. One frozen-contract deviation remains open (construction ownership — see §17) and one architecture-diagram gap remains open (no built-in event dedup processor — see §17). Both are deliberate/known, not accidental drift.

---

## 3. Folder Structure

```
device_shield/
├── lib/
│   ├── device_shield.dart              # public export barrel (1 line)
│   └── src/
│       ├── api/                         # the DeviceShield public facade
│       ├── bootstrap/                   # DI container + boot/shutdown sequencing
│       ├── bridge/                      # native channel transport layer
│       ├── config/                      # configuration storage + validation
│       ├── core/                        # logging
│       ├── detectors/                   # built-in Detector implementations
│       ├── events/                      # the event bus
│       ├── managers/                    # the 4 orchestration managers + cache/concurrency
│       ├── models/                      # immutable value types + enums + exceptions
│       ├── permission/                  # OS permission request/tracking
│       ├── platform/                    # legacy Phase-1 platform-interface (getPlatformVersion)
│       ├── registry/                    # Detector/Rule contracts + registry + factory
│       ├── state/                       # SDK state machine + Flutter lifecycle observer
│       └── utilities/                   # EMPTY — no files (see §17 findings)
├── test/                                # mirrors lib/src/ layout, one *_test.dart per class-ish
├── android/src/main/kotlin/.../
│   ├── DeviceShieldPlugin.kt           # plugin registration, channel dispatch
│   └── detection/EmulatorDetector.kt    # native emulator-detection heuristics
├── ios/device_shield/Sources/device_shield/
│   ├── DeviceShieldPlugin.swift        # plugin registration, channel dispatch
│   └── Detection/EmulatorDetector.swift # native simulator-detection (compile-time check)
├── example/                             # UNMODIFIED flutter create counter-app template
├── ARCHITECTURE.md                      # frozen high-level design + diagrams
├── ARCHITECTURE_CONTRACTS.md            # frozen per-component contract table
├── ROADMAP.md                           # M0–M22 dependency-ordered build plan
├── SDK_MILESTONE_PLAN.md                # expanded restatement of ROADMAP.md (same content, more detail)
├── CURRENT_PROGRESS.md                  # a prior audit, dated 2026-07-24 — now partially stale
├── CURRENT_STATE.md                     # an even earlier snapshot — badly stale (pre-implementation)
└── README.md / CHANGELOG.md             # both still flutter-create defaults, unedited
```

### Folder-by-folder detail

**`lib/src/api/`** — Purpose: the SDK's single public entry point. Responsibility: pure delegation to the layers beneath it; owns no logic. Dependencies: everything (`bootstrap`, `bridge`, `events`, `managers`, `models`, `platform`, `registry`, `state`). Used by: host applications, all API-level tests.

**`lib/src/bootstrap/`** — Purpose: dependency injection and the fixed boot/shutdown sequence. Responsibility: type-keyed service lookup (`ServiceContainer`), circular-resolution guarding (`DependencyResolver`), the ordered construct-wire-start sequence and its reverse (`PluginInitializer`), per-boot bookkeeping (`BootstrapContext`). Dependencies: every concrete service it can default-construct (`bridge`, `config`, `core`, `events`, `managers`, `permission`, `registry`, `state`). Used by: `api` exclusively.

**`lib/src/bridge/`** — Purpose: the sole path any Dart code takes to reach native code. Responsibility: method-channel request/response (`MethodChannelService`), event-channel native-push forwarding (`EventChannelService`), the unifying façade and callback router (`NativeBridge`/`DefaultNativeBridge`), method-name constants (`MethodCodes`). Dependencies: `flutter/services.dart`, `models` (for `NativeBridgeException`). Used by: `managers` (`DetectionManager`), `detectors`.

**`lib/src/config/`** — Purpose: sole ownership of the active SDK configuration. Responsibility: bound validation before storage (`DeviceShieldConfigValidator`), pure store/expose/update (`ConfigurationManager`/`DefaultConfigurationManager`) — deliberately no validation logic of its own. Dependencies: `models` (`DeviceShieldConfig`, `DeviceShieldException`). Used by: `bootstrap`, `managers` (`SecurityManager`, indirectly `DetectionManager` at construction time only).

**`lib/src/core/`** — Purpose: the SDK's only sanctioned output path. Responsibility: level-gated logging with a registrable `LogSink` fan-out (`Logger`/`ConsoleLogger`). Dependencies: none. Used by: nearly every other module (constructor-injected).

**`lib/src/detectors/`** — Purpose: built-in `Detector` implementations. Responsibility: shape a native bridge response into a `DetectionResult`; currently contains exactly one detector, `EmulatorDetector`. Dependencies: `bridge` (`NativeBridge`, `MethodCodes`), `models`, `registry` (`Detector` contract). Used by: `registry` (`DetectorFactory`), directly registrable via `DetectionManager.registerDetector`.

**`lib/src/events/`** — Purpose: the single event bus every `SecurityEvent` passes through. Responsibility: emit/processor-chain/history/pause-resume/filtered-subscribe (`EventManager`/`DefaultEventManager`). Dependencies: `models` (`SecurityEvent`) only — a true dependency-free leaf. Used by: `managers` (`SecurityManager`), `bootstrap`, `api`.

**`lib/src/managers/`** — Purpose: the orchestration layer — the four managers plus their shared infrastructure. Responsibility: `SecurityManager` (runtime orchestrator), `DetectionManager` (runs detectors, bounded-concurrent, cached, timeout-bound), `PolicyManager` (rule evaluation, currently placeholder decisions), `ConcurrencyController` (generic bounded-parallel executor), `DetectionCache`/`MultiLevelCache`/`CacheLevel`/`MemoryCacheLevel` (generic TTL+LRU cache stack). Dependencies: `core`, `config`, `events`, `models`, `registry`, `state`. Used by: `bootstrap`, `api`.

**`lib/src/models/`** — Purpose: every immutable value type, enum, and exception the SDK uses. Responsibility: `DetectionResult`, `SecurityEvent`/`EventSeverity`, `DeviceShieldConfig`, `SDKState`, `SecurityAction`, `SecurityProfile`/`DetectionConfig`/`PolicyConfig`/`ProtectionConfig`, `DeviceShieldException` + 6 subtypes. Dependencies: none (leaf, pure Dart). Used by: everything.

**`lib/src/permission/`** — Purpose: OS permission request/tracking for whatever the active profile's detectors/protections require. Responsibility: `PermissionManager` contract + `DefaultPermissionManager` (honest about its own incompleteness — throws `UnimplementedError` for any non-empty request rather than fabricating a grant). Dependencies: `managers/manager.dart` only. Used by: `bootstrap`.

**`lib/src/platform/`** — Purpose: the pre-existing, unrelated Phase-1 `getPlatformVersion()` path — legacy, not part of the current Bridge architecture. Responsibility: `DeviceShieldPlatform` (federated-plugin interface) + `MethodChannelDeviceShield`. Dependencies: `plugin_platform_interface`, `flutter/services.dart`. Used by: `api`'s instance-method `getPlatformVersion()` only.

**`lib/src/registry/`** — Purpose: the FR-18/FR-17 extension mechanism itself. Responsibility: generic `Registry<T>` base, `Detector`/`Rule` contracts, `DetectorRegistry`/`DefaultDetectorRegistry` (priority-ordered storage), `DetectorFactory` (constructs built-in detectors by type-string). Dependencies: `models`, `bridge` (factory only), `detectors` (factory only). Used by: `managers` (`DetectionManager`, `PolicyManager`), `bootstrap`.

**`lib/src/state/`** — Purpose: SDK status and Flutter app-lifecycle integration. Responsibility: `Lifecycle`/`DefaultSecurityStateManager` (the 8-state machine, sole writer), `SecurityLifecycleHandler` (the narrow callback contract resolving the `SecurityManager`↔`LifecycleManager` cycle), `LifecycleManager`/`DefaultLifecycleManager` (`WidgetsBindingObserver`). Dependencies: `models` (`SDKState`), `flutter/widgets.dart`. Used by: `bootstrap`, `managers` (`SecurityManager` implements `SecurityLifecycleHandler`).

**`lib/src/utilities/`** — **Empty.** No files, no subdirectories beyond itself. Scaffolding left over from an earlier structural decision, never populated. Flagged in §17.

**`test/`** — Mirrors `lib/src/` one level down (`test/api/`, `test/bootstrap/`, `test/bridge/`, `test/config/`, `test/detectors/`, `test/events/`, `test/managers/`, `test/permission/`, `test/registry/`, `test/state/`), plus two root-level files (`test/device_shield_test.dart`, `test/device_shield_method_channel_test.dart`) covering the legacy `platform/` module. No `test/unit/`, `test/integration/`, `test/native/` split exists — `ROADMAP.md` M0/M18 calls for one; it was not adopted.

**`android/src/main/kotlin/com/example/device_shield/`** — `DeviceShieldPlugin.kt` (plugin registration + channel dispatch) and `detection/EmulatorDetector.kt` (the only native detection package that exists — `protection/`, `bridge/`, `utils/` subpackages from `ROADMAP.md` M0 were never created; everything else lives flat in the plugin file).

**`ios/device_shield/Sources/device_shield/`** — Same shape: `DeviceShieldPlugin.swift` + `Detection/EmulatorDetector.swift`. Same missing-subpackage gap as Android.

**`example/`** — Purpose (intended): a working demo app proving the public API. Actual state: **unmodified** `flutter create --template=plugin` counter-app boilerplate — confirmed directly (`example/lib/main.dart` still constructs `DeviceShield()` and calls the legacy `getPlatformVersion()`, no reference to `initialize()`/`status`/`events`/any manager).

---

## 4. Complete File-by-File Documentation

Every file under `lib/src/` (50 files) plus the barrel export, documented individually. Native files (Android/iOS) are documented in §11. Test files are documented in aggregate in §10 (individually listing all 22 would duplicate §10's table without adding information).

### `lib/device_shield.dart` (1 line)
- **Why it exists:** the package's public export barrel — the only file a host app's `import 'package:device_shield/device_shield.dart'` resolves against.
- **Responsibility:** re-export the public API surface.
- **Public surface exported:** `src/api/device_shield.dart` only.
- **Dependency graph:** → `src/api/device_shield.dart`.
- **Lifecycle:** N/A (no runtime object).
- **Who creates/owns/disposes it:** N/A.
- **Communication:** static re-export, no runtime behavior.
- **Design pattern:** Barrel/Facade export.
- **SOLID:** N/A (not a class).
- **Extension point:** no.
- **Gap/future work:** **incomplete** — `Detector`, `Rule`, `SecurityEvent`, `DetectionResult`, `DeviceShieldConfig`, and the exception hierarchy are not re-exported here, meaning a host app cannot today build a custom detector or rule (FR-17/FR-18) without importing from `package:device_shield/src/...` directly. This is a real, checkable, still-open public-API completeness gap (unchanged from `CURRENT_PROGRESS.md`'s finding — verified still true by reading this file directly).

### `lib/src/api/device_shield.dart` (154 lines)
- **Why it exists:** the SDK's single public entry point — per its own doc comment, "the only symbol a host app ever imports."
- **Responsibility:** delegate every call 1:1 to `PluginInitializer`/`SecurityManager`/`DetectionManager`/`PolicyManager`/`NativeBridge`/`EventManager`; owns no logic of its own.
- **Public classes:** `DeviceShield`.
- **Public methods:** `getPlatformVersion()` (legacy instance method, unchanged since Phase 1), `initialize({config})`, `status` (getter), `pause()`, `resume()`, `checkNow()`, `shutdown()`, `reinitialize({config})`, `dispose()`, `registerDetector(Detector)`, `addRule(Rule)`, `removeRule(String)`, `registerCallback(String, callback)`, `unregisterCallback(String)`, `subscribe(handler, {filter})`.
- **Important private members:** `_container`/`_initializer` (static, hold the current `ServiceContainer`/`PluginInitializer`), `_requireContainer` (throws `InitializationException(NOT_INITIALIZED)` if called before `initialize()`).
- **Dependency graph:** → `PluginInitializer`, `ServiceContainer`, and (via container resolution) `NativeBridge`, `EventManager`, `DetectionManager`, `PolicyManager`, `SecurityManager`, `Lifecycle`, `DeviceShieldPlatform` (legacy only).
- **Lifecycle:** process-lifetime static class, never instantiated for the static surface; the *instance* side (`getPlatformVersion()`) can be constructed freely and holds no state.
- **Who creates it:** N/A — static.
- **Who owns it:** N/A.
- **Who disposes it:** `dispose()` clears its own static references (`_container = null; _initializer = null`) so a subsequent `initialize()` starts genuinely clean.
- **Who depends on it:** host application code; every test in `test/api/`.
- **Communication:** synchronous static delegation; `subscribe`/`registerCallback` hand back the underlying `StreamSubscription`/void directly, no wrapping.
- **Design pattern:** Stateless Facade over the composed subsystem.
- **SOLID:** SRP holds (delegation only). DIP holds at the call-site level (depends on `SecurityManager`/`DetectionManager` interfaces via `ServiceContainer.resolve<T>()`, never a concrete class directly) — the one place concrete types are named is inside `PluginInitializer`, not here.
- **Extension point:** indirectly — `registerDetector`/`addRule` are how FR-18/FR-17 extensions reach the SDK.
- **Gap/future work:** no `profile` parameter on `initialize()` (blocked on M10's five factory presets not existing); no public `events` getter (the equivalent exists only via `subscribe()`, not the exact `DeviceShield.events` surface `ARCHITECTURE_CONTRACTS.md` describes).

### `lib/src/bootstrap/bootstrap_context.dart` (22 lines)
- **Why it exists:** accumulates state across one `PluginInitializer.initialize()` run so a mid-boot failure can report exactly what completed and roll it back in reverse.
- **Responsibility:** pure bookkeeping — no logic beyond recording.
- **Public classes:** `BootstrapContext`.
- **Public methods:** `recordStep(String)`, `elapsed` (getter).
- **Fields:** `config` (the `DeviceShieldConfig` being booted with), `startedAt`, `completedSteps` (`List<String>`).
- **Dependency graph:** → `models/device_shield_config.dart` only.
- **Lifecycle:** transient — one instance per `initialize()` call, discarded after boot succeeds or fails.
- **Who creates it:** `PluginInitializer.initialize()`.
- **Who owns it:** `PluginInitializer`, for the duration of one boot call.
- **Who disposes it:** garbage-collected; no explicit dispose needed (no held resources).
- **Who depends on it:** `PluginInitializer` exclusively.
- **Communication:** synchronous method calls, no streams/futures.
- **Design pattern:** Memento-ish (records state for rollback), Value/DTO.
- **SOLID:** SRP — single, narrow purpose.
- **Extension point:** no.
- **Future work:** none identified — complete for its scope.

### `lib/src/bootstrap/dependency_resolver.dart` (33 lines)
- **Why it exists:** detects circular dependencies during `ServiceContainer` resolution — a cycle can only arise when a registered factory calls back into the container to resolve another type while it is itself still being constructed.
- **Responsibility:** track an in-progress resolution stack; throw the moment a type reappears on it.
- **Public classes:** `DependencyResolver`.
- **Public methods:** `guard<T>(T Function() resolve)`.
- **Important private state:** `_resolutionStack` (`List<Type>`).
- **Dependency graph:** → `models/device_shield_exception.dart` (`InitializationException`).
- **Lifecycle:** one instance per `ServiceContainer`, lives exactly as long as the container.
- **Who creates it:** `ServiceContainer`'s own field initializer.
- **Who owns it:** `ServiceContainer` exclusively — never held elsewhere.
- **Who disposes it:** implicitly, when the owning `ServiceContainer` is discarded.
- **Who depends on it:** `ServiceContainer` exclusively.
- **Communication:** synchronous, direct method call wrapping a closure.
- **Design pattern:** Guard/Decorator around resolution.
- **SOLID:** SRP — one job, cycle detection.
- **Extension point:** no.
- **Future work:** none identified.

### `lib/src/bootstrap/plugin_initializer.dart` (501 lines — largest file in the codebase)
- **Why it exists:** the single code path that runs the SDK's fixed boot sequence, wires every service through `ServiceContainer`, and reverses cleanly on shutdown/dispose.
- **Responsibility:** validate config; construct-or-resolve every service in order (Logger → Permission → Configuration → NativeBridge → EventManager → Registries → Managers → Lifecycle → Ready); start monitoring; emit the `initialized` event; unwind to `failure` on any step's exception; own shutdown/dispose/reinitialize.
- **Public classes:** `PluginInitializer`.
- **Public methods:** `initialize(DeviceShieldConfig)`, `shutdown()`, `dispose()`, `reinitialize(DeviceShieldConfig)`.
- **Important private methods:** `_resolveOrRegisterStateManager/Logger/PermissionManager/Configuration/NativeBridge/EventManager/DetectorRegistry/DetectionManager/PolicyManager/SecurityManager/LifecycleManager` (one per boot step — each resolves an already-registered instance or constructs+registers a sensible default), `_unwind(BootstrapContext)` (reverse-order best-effort teardown on failure).
- **Dependency graph:** → every concrete default implementation in the codebase (`DefaultNativeBridge`, `DefaultConfigurationManager`, `DeviceShieldConfigValidator`, `ConsoleLogger`, `DefaultEventManager`, `DefaultDetectionManager`, `DefaultPolicyManager`, `DefaultSecurityManager`, `DefaultPermissionManager`, `DefaultDetectorRegistry`, `DefaultLifecycleManager`, `DefaultSecurityStateManager`) plus every corresponding contract type and `models/*`.
- **Lifecycle:** transient per the frozen contract's description, but in practice held by `DeviceShield` across the SDK's running lifetime (`DeviceShield._initializer`) so `shutdown()`/`reinitialize()` can be called on the same instance later.
- **Who creates it:** `DeviceShield.initialize()` (`_initializer ??= PluginInitializer(container: container)`).
- **Who owns it:** `DeviceShield` (via its static field), for the process lifetime until `DeviceShield.dispose()` discards the reference.
- **Who disposes it:** itself — no separate disposer; `dispose()` is a method on the class.
- **Who depends on it:** `DeviceShield` exclusively; every bootstrap-layer test.
- **Communication:** synchronous/async method calls into `ServiceContainer` and each service's own `initialize()`/`dispose()`; emits exactly one `SecurityEvent(type: 'initialized')` through `EventManager` at the end of a successful boot.
- **Design pattern:** Builder/Director (drives construction order), Command (encapsulates the whole boot operation), Template Method (fixed step sequence with per-step hooks).
- **SOLID:** SRP holds at the "orchestrate boot" level even though the file is large — every individual concern (constructing one service) is a separate, narrowly-named private method. OCP: adding a new defaultable service means adding one more `_resolveOrRegisterX` method, not editing existing ones. DIP: depends on every service's abstract contract for its own field/parameter types, only reaching for a concrete class inside the one `_resolveOrRegisterX` method responsible for defaulting it.
- **Extension point:** no (this class itself isn't meant to be swapped) — but every service it defaults *is* individually swappable by pre-registering into the `ServiceContainer` before calling `initialize()`.
- **Documented but historically inaccurate claim, now resolved:** its own doc comment explicitly states this class **now** constructs `DetectionManager`/`PolicyManager`/`SecurityManager`/`LifecycleManager` itself — closing the exact gap `CURRENT_PROGRESS.md` (2026-07-24) flagged as finding 2.1(a). Verified true by reading `_resolveOrRegisterSecurityManager` (lines 418–434), which itself calls `_resolveOrRegisterDetectionManager`/`_resolveOrRegisterPolicyManager`.
- **Future work:** `ShutdownSequence` is not factored into its own class (the reverse-order teardown is inlined in `shutdown()`/`_unwind()`) — `ROADMAP.md` M6 names this as a separate component that was never split out.

### `lib/src/bootstrap/service_container.dart` (127 lines)
- **Why it exists:** the type-keyed DI lookup point that decouples construction from use.
- **Responsibility:** three registration modes (`registerSingleton`, `registerLazySingleton`, `registerFactory`); `resolve<T>()`; `isRegistered<T>()`; `unregister<T>()`; `reset()`.
- **Public classes:** `ServiceContainer`. Private helper: `_Registration` (wraps one of the three registration kinds), `_RegistrationKind` (enum).
- **Public methods:** `registerSingleton<T>(T)`, `registerLazySingleton<T>(T Function())`, `registerFactory<T>(T Function())`, `isRegistered<T>()`, `resolve<T>()`, `unregister<T>()`, `reset()`.
- **Important private methods:** `_assertNotRegistered<T>()` (throws `DUPLICATE_REGISTRATION` if `T` is already present).
- **Dependency graph:** → `models/device_shield_exception.dart`, `dependency_resolver.dart`. No dependency on anything above it — a true foundation component.
- **Lifecycle:** SDK-lifetime — persists as an empty shell across `initialize`/`shutdown` cycles (confirmed by `plugin_initializer_test.dart`'s "the same container survives dispose and can be reused" test).
- **Who creates it:** whatever wires the SDK together — today, `DeviceShield.initialize()` (`_container ??= ServiceContainer()`) and test code directly.
- **Who owns it:** `DeviceShield` (static field), independent of `PluginInitializer`'s own lifetime — Architecture Correction 1, explicitly documented in `plugin_initializer.dart`'s own comments and verified by the container-reuse test.
- **Who disposes it:** never explicitly — `reset()` clears registrations but the container object itself is discarded only when `DeviceShield.dispose()` nulls out its static reference.
- **Who depends on it:** `PluginInitializer` exclusively at the framework level; every bootstrap/managers-integration test constructs one directly.
- **Communication:** entirely synchronous — no `Future`, no `await` anywhere in this class, by design (documented thread-safety rationale: Dart's single-threaded event loop only preempts at `await` points, so no partial-mutation window exists).
- **Design pattern:** Service Locator / Dependency Injection Container, Registry.
- **SOLID:** SRP (one job: type-keyed storage/lookup). OCP: three registration strategies without needing a fourth to be added by modifying existing ones — a new kind would extend `_RegistrationKind` and `_Registration.resolve()`'s switch, the one place that would need editing. DIP: this is the mechanism that lets everything else depend on abstractions — but note it is itself a concrete class with no interface of its own (acceptable — a DI container is typically the one place that isn't itself abstracted).
- **Extension point:** no.
- **Future work:** none identified — this is one of the most complete, gap-free files in the codebase, and (per `CURRENT_PROGRESS.md`, still true) exceeds its own frozen minimum spec (three registration modes plus circular-dependency guarding, versus the contract's bare `register`/`get`/`isRegistered`/`clear`).

### `lib/src/bridge/native_bridge.dart` (50 lines)
- **Why it exists:** defines the sole contract any Dart code uses to reach native code — no detector/protection/manager is permitted to hold a raw `MethodChannel`/`EventChannel` reference of its own.
- **Responsibility:** declare `invoke<T>()`, `invokeAsync()`, `registerCallback()`/`unregisterCallback()`, `dispose()`.
- **Public classes:** `NativeBridge` (abstract).
- **Dependency graph:** none (pure contract).
- **Lifecycle/ownership:** N/A — contract; `DefaultNativeBridge` is the concrete instance whose lifecycle is documented under that class.
- **Who depends on it:** `DetectionManager`, `DetectorFactory`, `EmulatorDetector`, `bootstrap`.
- **Design pattern:** Bridge (structural — decouples the abstraction used by the rest of the SDK from the platform-channel implementation), Strategy (swappable via `ServiceContainer`).
- **SOLID:** ISP — four narrow methods, no fat interface. DIP — the extension point for a hypothetical future platform (e.g. web) is "register a different `NativeBridge` implementation," not touching any caller.
- **Extension point:** **yes** — explicitly documented as superseding the legacy `PlatformAdapter` as the "new platform" extension point.
- **Future work:** none at the contract level; concrete implementations are where new platform support would land.

### `lib/src/bridge/default_native_bridge.dart` (100 lines)
- **Why it exists:** the real, production implementation of `NativeBridge`.
- **Responsibility:** compose `MethodChannelService` + `EventChannelService`; route `registerCallback`/`unregisterCallback` requests against native-pushed events by name; hold **no** reference to `EventManager` or `SecurityEvent`.
- **Public classes:** `DefaultNativeBridge`. Public constants: `kNativeBridgeMethodChannel` (`'device_shield/native_bridge'`), `kNativeBridgeEventChannel` (`'device_shield/events'`).
- **Public methods:** `invoke<T>()`, `invokeAsync()`, `registerCallback()`, `unregisterCallback()`, `dispose()`.
- **Important private methods:** `_ensureListening()` (lazily starts the event-channel subscription on first `registerCallback` call), `_routeNativeEvent(dynamic raw)` (dispatches by the `callback` key in a `{'callback': name, 'data': ...}` shaped map; silently drops anything malformed or unregistered).
- **Dependency graph:** → `event_channel_service.dart`, `method_channel_service.dart`, `native_bridge.dart` (implements it).
- **Lifecycle:** SDK-lifetime — constructed at boot step 4, disposed at shutdown step 5.
- **Who creates it:** `PluginInitializer._resolveOrRegisterNativeBridge()` (default), or a test/host-app pre-registration.
- **Who owns it:** `ServiceContainer`, referenced by `DetectionManager` (via detectors) and `bootstrap`.
- **Who disposes it:** `PluginInitializer.shutdown()`, which also unregisters it (a disposed bridge is never reused — a fresh one is always constructed on the next `initialize()`).
- **Who depends on it:** every `Detector` implementation, `DetectorFactory`.
- **Communication:** async request/response for `invoke`, fire-and-forget for `invokeAsync`, name-keyed callback dispatch for native pushes.
- **Design pattern:** Facade over two collaborators, Bridge (structural pattern this whole module is named for), Observer (event-channel listening).
- **SOLID:** SRP — pure transport, zero interpretation of what any method call *means*. LSP — fully substitutable behind `NativeBridge`.
- **Extension point:** indirectly, via the `NativeBridge` contract it implements.
- **Future work:** only one method constant exists in `MethodCodes` so far (`checkEmulator`) — every future detector/protection needs its own bridge method wired through here (transport is ready, content is not).

### `lib/src/bridge/method_channel_service.dart` (91 lines)
- **Why it exists:** wraps a single `MethodChannel` for request/response native calls, with typed error translation.
- **Responsibility:** `invoke<T>()` (timeout-bound, translates every failure mode to `NativeBridgeException`), `invokeAsync()` (fire-and-forget).
- **Public classes:** `MethodChannelService`.
- **Public methods:** `invoke<T>({method, arguments, timeout})`, `invokeAsync({method, arguments})`.
- **Dependency graph:** → `flutter/services.dart` (`MethodChannel`, `PlatformException`, `MissingPluginException`), `models/device_shield_exception.dart`.
- **Lifecycle:** shares `NativeBridge`'s exact lifetime.
- **Who creates it:** `DefaultNativeBridge`'s constructor (`MethodChannelService.withName(kNativeBridgeMethodChannel)`), or a test supplying one directly against a fake channel.
- **Who owns it:** `DefaultNativeBridge` exclusively — never held elsewhere.
- **Who disposes it:** implicitly, alongside `DefaultNativeBridge`.
- **Who depends on it:** `DefaultNativeBridge` exclusively.
- **Communication:** `MethodChannel.invokeMethod` under the hood, engine-marshaled onto the platform thread.
- **Design pattern:** Adapter (wraps Flutter's `MethodChannel` into a typed, exception-translating surface).
- **SOLID:** SRP — transport + error-translation only, zero business logic.
- **Extension point:** no.
- **Failure-mode mapping (verified against tests):** timeout → `BRIDGE_TIMEOUT`; `MissingPluginException` (no native handler) → `BRIDGE_UNAVAILABLE`; `PlatformException` → forwarded code/message/details unchanged; wrong response type → `BRIDGE_MALFORMED_RESPONSE`. Exactly matches `ARCHITECTURE_CONTRACTS.md` Group F's frozen table.
- **Future work:** none identified at this layer — fully spec-complete.

### `lib/src/bridge/event_channel_service.dart` (50 lines)
- **Why it exists:** wraps a single `EventChannel` for native-originated pushes.
- **Responsibility:** generic stream forwarding only — deliberately holds **zero** knowledge of `EventManager`/`SecurityEvent`; forwards whatever raw value native code sends, unmodified.
- **Public classes:** `EventChannelService`.
- **Public methods:** `events` (getter, raw broadcast stream), `listen(onEvent, {onError})`, `dispose()`.
- **Dependency graph:** → `flutter/services.dart` (`EventChannel`) only.
- **Lifecycle:** shares `NativeBridge`'s exact lifetime.
- **Who creates it:** `DefaultNativeBridge`'s constructor.
- **Who owns it:** `DefaultNativeBridge` exclusively.
- **Who disposes it:** `DefaultNativeBridge.dispose()` → cancels the underlying stream subscription.
- **Who depends on it:** `DefaultNativeBridge` exclusively.
- **Communication:** `EventChannel.receiveBroadcastStream()`, forwarded verbatim; a re-`listen()` call replaces the previous subscription.
- **Design pattern:** Adapter, Observer.
- **SOLID:** SRP — zero content validation, matching its documented failure behavior exactly (a malformed event passes through unchanged; only channel-level errors are routed to `onError`).
- **Extension point:** no.
- **Future work:** none — complete for its narrow scope.

### `lib/src/bridge/method_codes.dart` (15 lines)
- **Why it exists:** single source of truth for `NativeBridge` method-name string constants, called out explicitly in `ROADMAP.md` M3 as mattering "once 15+ detectors share the channel."
- **Responsibility:** hold method-name constants; knows nothing about what any method *does*.
- **Public classes:** `MethodCodes` (non-instantiable — private constructor).
- **Public constants:** `checkEmulator = 'checkEmulator'` — **the only one defined so far**.
- **Dependency graph:** none.
- **Lifecycle:** static, no instances.
- **Who depends on it:** `EmulatorDetector` (Dart side), `default_native_bridge_test.dart`, `emulator_detector_test.dart`.
- **Design pattern:** Constants/Namespace class.
- **SOLID:** SRP.
- **Extension point:** implicitly — every new detector/protection is expected to add its own constant here.
- **Future work:** will grow by exactly one line per new bridge method as M7/M8/M11 progress — currently a placeholder-sized file relative to its intended eventual scope.

### `lib/src/config/configuration_manager.dart` (28 lines)
- **Why it exists:** the sole-owner contract for the active configuration.
- **Responsibility:** `current` (getter), `updateConfig()` — deliberately performs **no validation**; that's `DeviceShieldConfigValidator`'s job, run before a config ever reaches this contract.
- **Public classes:** `ConfigurationManager` (abstract, `implements Manager`).
- **Dependency graph:** → `managers/manager.dart`, `models/device_shield_config.dart`.
- **Who depends on it:** every manager that reads `.current` live (`DetectionManager` at construction only, `SecurityManager` continuously for its periodic-check interval).
- **Design pattern:** Repository (single-owner store), Strategy contract.
- **SOLID:** SRP — explicitly narrowed by "Architecture Correction 2" (validation split out).
- **Extension point:** no.
- **Future work:** no detection/protection sub-config fields yet (deliberately deferred, additive when M7/M11 land).

### `lib/src/config/default_configuration_manager.dart` (32 lines)
- **Why it exists:** the real, complete implementation of `ConfigurationManager`.
- **Responsibility:** store/expose/update whatever config it's given, unconditionally — trusts its caller entirely (an out-of-bounds config passed directly to its constructor or `updateConfig` will **not** throw; that's by design, verified by `device_shield_config_validator_test.dart`'s "Architecture Correction 2" test group).
- **Public classes:** `DefaultConfigurationManager`.
- **Public methods:** `current` (getter), `initialize()` (no-op), `dispose()` (no-op), `updateConfig(DeviceShieldConfig)`.
- **Dependency graph:** → `configuration_manager.dart`, `models/device_shield_config.dart`.
- **Lifecycle:** SDK-lifetime, and unusually **persists across a shutdown/reinitialize cycle** — `PluginInitializer.shutdown()` deliberately does not dispose or unregister it, so a subsequent `reinitialize()` with a new config calls `updateConfig()` in place rather than losing continuity (verified directly in `plugin_initializer.dart`'s `_resolveOrRegisterConfiguration` and by `plugin_initializer_test.dart`'s "reinitialize with a different config updates the persisting ConfigurationManager in place" test).
- **Who creates it:** `PluginInitializer._resolveOrRegisterConfiguration()`.
- **Who owns it:** `ServiceContainer`.
- **Who disposes it:** never during a shutdown/reinitialize cycle; only released via `ServiceContainer.reset()` at full `dispose()`.
- **Design pattern:** Repository, "trust the caller" boundary object.
- **SOLID:** SRP.
- **Extension point:** no.
- **Future work:** none identified for this class specifically.

### `lib/src/config/device_shield_config_validator.dart` (48 lines)
- **Why it exists:** validates a config *before* it ever reaches `ConfigurationManager` — a dedicated, single-purpose component per "Architecture Correction 2."
- **Responsibility:** enforce 4 bounds and throw `ConfigurationException` on the first violation.
- **Public classes:** `DeviceShieldConfigValidator`.
- **Public methods:** `validate(DeviceShieldConfig) → DeviceShieldConfig` (returns the same instance unchanged if valid).
- **Bounds enforced (verified against tests):** `periodicCheckInterval ≥ 5000ms` (`INVALID_INTERVAL`); `0 ≤ maxRetryAttempts ≤ 10` (`INVALID_RETRY`); `500 ≤ retryDelay ≤ 10000ms` (`INVALID_RETRY_DELAY`); `1000 ≤ checkTimeout ≤ 30000ms` (`INVALID_TIMEOUT`).
- **Dependency graph:** → `models/device_shield_config.dart`, `models/device_shield_exception.dart`.
- **Who creates it:** `PluginInitializer.initialize()`, constructed fresh (stateless) on every boot call.
- **Who depends on it:** `PluginInitializer` exclusively.
- **Design pattern:** Validator/Specification.
- **SOLID:** SRP — exactly one job.
- **Extension point:** no.
- **Future work:** bounds match SRS §7.4 per its own doc comment — no detector-specific validation exists here by design (out of scope until M7+ needs it).

### `lib/src/core/logger.dart` (43 lines)
- **Why it exists:** the SDK's only sanctioned output path, and the shared vocabulary (`LogLevel`) every log call uses.
- **Responsibility:** declare the logging contract; must never throw.
- **Public classes:** `Logger` (abstract), `LogSink` (abstract — the extension point). Public enum: `LogLevel` (`debug, info, warning, error, exception`).
- **Public methods (contract):** `debug()`, `info()`, `warning()`, `error()`, `exception()`, `addSink(LogSink)`, `removeSink(LogSink)`.
- **Dependency graph:** none — a true leaf.
- **Who depends on it:** nearly every other class in the codebase (constructor-injected).
- **Design pattern:** Strategy (contract), Observer (`LogSink` fan-out).
- **SOLID:** ISP — narrow, single-purpose contract. OCP — new log destinations are `LogSink` registrations, never a `Logger` code change.
- **Extension point:** **yes** — `LogSink` registration.
- **Future work:** no `DataFilter`/sensitive-field redaction utility exists anywhere in the codebase — anything logged through `ConsoleLogger` is not screened against sensitive field names (`password`, `token`, `key`, `secret`, `authorization`, `credit_card`, `ssn`, `pin`), an SRS §17.3 requirement that has no implementation.

### `lib/src/core/console_logger.dart` (85 lines)
- **Why it exists:** the real, complete implementation of `Logger` — console output gated by level, plus `LogSink` fan-out.
- **Responsibility:** format and print (`[DeviceShield] [LEVEL] message {data}`), gate by `minLevel`, forward to every registered sink.
- **Public classes:** `ConsoleLogger`.
- **Public methods:** `debug/info/warning/error/exception`, `addSink`, `removeSink`.
- **Important private methods:** `_shouldLog(LogLevel)` (level-gate check), `_write(...)` (the single formatting/printing/fan-out path every public method funnels through).
- **Dependency graph:** → `logger.dart` only.
- **Lifecycle:** SDK-lifetime — constructed at boot step 1 (first), disposed conceptually last (though its own `dispose()` isn't part of the `Logger` contract — `Manager`-shaped disposal doesn't apply here, per `manager.dart`'s own doc comment explaining why `Logger` isn't a `Manager`).
- **Who creates it:** `PluginInitializer._resolveOrRegisterLogger()`.
- **Who owns it:** `ServiceContainer`.
- **Who depends on it:** effectively every other manager/service (constructor-injected).
- **Design pattern:** Strategy implementation, Observer (sinks).
- **SOLID:** SRP — pure I/O, zero business logic.
- **Extension point:** yes, inherited from `Logger`.
- **Future work:** no dedicated test file exists for this class anywhere under `test/` — its behavior is only exercised indirectly through other tests' log output, never directly asserted against (confirmed by the absence of a `test/core/` directory).

### `lib/src/detectors/emulator_detector.dart` (68 lines)
- **Why it exists:** FR-03 (SRS §5.3) — the SDK's **first and only** built-in `Detector`, chosen specifically because it's the one P0 technique that's genuinely cross-platform, exercising both native implementations at once.
- **Responsibility:** shape a native bridge response into a `DetectionResult`; report failure as `DetectionStatus.failed` rather than throwing (per the `Detector` contract's documented convention). All technique-specific logic lives natively (`EmulatorDetector.kt`/`.swift`) — this class is a thin, platform-agnostic shim.
- **Public classes:** `EmulatorDetector`.
- **Public constant:** `typeId = 'emulator'`.
- **Public methods:** `type`, `priority` (= 0), `initialize()` (no-op), `dispose()` (no-op), `check()`.
- **Dependency graph:** → `bridge/method_codes.dart`, `bridge/native_bridge.dart`, `models/detection_result.dart`, `registry/detector.dart` (implements it).
- **Lifecycle:** shares whatever registers it — either `DetectionManager`'s registry lifetime (if registered via `registerDetector`) or a fresh, un-cached instance per `DetectorFactory.create()` call.
- **Who creates it:** a test, a host app calling `registerDetector` directly, or `DetectorFactory.create(EmulatorDetector.typeId)`.
- **Who owns it:** `DetectorRegistry`, once registered.
- **Who disposes it:** `DetectionManager.dispose()`, via its cascade over every registered detector.
- **Who depends on it:** `DetectorFactory` (as its one built-in constructor), `registry/detector_factory_test.dart`, `test/detectors/emulator_detector_test.dart`.
- **Communication:** calls `nativeBridge.invoke<Map<Object?, Object?>>(method: MethodCodes.checkEmulator)`, reads `detected`/`confidence`/`signals` off the response defensively (`as bool? ?? false`, etc.).
- **Design pattern:** Adapter (native response → `DetectionResult`), Strategy (one concrete `Detector` implementation).
- **SOLID:** LSP — fully substitutable behind `Detector`; `DetectionManager` never special-cases it.
- **Extension point:** no (it *is* an extension instance, not an extension point itself).
- **Future work:** this is the template the remaining 5 P0 detectors (root, jailbreak, debugger, runtime-hook, app-integrity) and 2 P1 detectors (developer-options, mock-location) should follow.

### `lib/src/events/event_manager.dart` (53 lines)
- **Why it exists:** the contract for the single event bus every `SecurityEvent`, from any source, passes through.
- **Responsibility:** declare `emit()`, `subscribe()`, `getRecentEvents()`, `clearHistory()`, `pause()`/`resume()`, `addProcessor()`.
- **Public classes:** `EventManager` (abstract, `implements Manager`). Public typedefs: `SecurityEventFilter`, `SecurityEventHandler`, `EventProcessor`.
- **Dependency graph:** → `managers/manager.dart`, `models/security_event.dart` only — a dependency-free leaf contract.
- **Who depends on it:** `SecurityManager`, `PolicyManager` (contract-level dependency, per the frozen matrix, though `DefaultPolicyManager` doesn't actually hold one today), `bootstrap`, `api`.
- **Design pattern:** Observer (pub/sub contract), Strategy.
- **SOLID:** ISP — narrow surface. This is the frozen architecture's proof that a manager can depend on "nothing structurally."
- **Extension point:** **yes** — `EventProcessor` registration via `addProcessor`.
- **Future work:** none at the contract level.

### `lib/src/events/default_event_manager.dart` (101 lines)
- **Why it exists:** the real, fully generic implementation of `EventManager`.
- **Responsibility:** run an emitted event through the processor chain, append to bounded history, broadcast to filtered subscribers with per-subscriber exception isolation, queue emissions while paused.
- **Public classes:** `DefaultEventManager`.
- **Public methods:** `initialize()`, `dispose()`, `emit(SecurityEvent)`, `subscribe(handler, {filter})`, `getRecentEvents({limit})`, `clearHistory()`, `pause()`, `resume()`, `addProcessor(EventProcessor)`.
- **Important private methods:** `_addToHistory(SecurityEvent)` (FIFO-trims to `maxHistorySize`, default 100).
- **Dependency graph:** → `event_manager.dart`, `models/security_event.dart` only.
- **Lifecycle:** SDK-lifetime — constructed at boot step 5, disposed at shutdown step 4 (closes its `StreamController`, clears history/processors/queue).
- **Who creates it:** `PluginInitializer._resolveOrRegisterEventManager()`.
- **Who owns it:** `ServiceContainer`, referenced by `SecurityManager`.
- **Who disposes it:** `PluginInitializer.shutdown()`.
- **Communication:** a broadcast `StreamController<SecurityEvent>`; `subscribe()` applies an optional `.where(filter)` before listening; a throwing handler is caught silently per-invocation (documented as deliberate — this class has no `Logger` dependency by design, since `EventManager` is frozen as a leaf).
- **Design pattern:** Observer/Pub-Sub, Chain of Responsibility (`_processors` chain), FIFO bounded buffer.
- **SOLID:** SRP — pub/sub mechanics only, zero knowledge of detector/policy content.
- **Extension point:** yes, inherited (`addProcessor`).
- **Gap (verified against `ARCHITECTURE.md` §5's pipeline diagram):** **no built-in deduplication `EventProcessor` exists.** The architecture diagram shows every emitted event passing through a `DEDUP{Duplicate (type, source) in window?}` stage before history; `emit()` here runs the (empty-by-default) processor chain and unconditionally appends+dispatches. The extension point is real and generic; the specific dedup behavior the diagram depicts as intrinsic is absent unless a caller supplies it. This is an open, still-unresolved finding (also present in `CURRENT_PROGRESS.md`, confirmed still true by direct code reading).
- **Future work:** `SecurityEventFilter` is a bare predicate typedef, not the richer type/severity/source-matching component `ARCHITECTURE_CONTRACTS.md` describes.

### `lib/src/managers/manager.dart` (17 lines)
- **Why it exists:** the shared lifecycle shape implemented by `SecurityManager`, `DetectionManager`, `PolicyManager`, `EventManager`, and `ConfigurationManager`.
- **Responsibility:** declare `initialize()`/`dispose()`.
- **Public classes:** `Manager` (abstract).
- **Dependency graph:** none.
- **Who depends on it:** the 5 contracts named above; `Logger` and `LifecycleManager` are deliberately **not** implementations (their boot/teardown shapes differ — documented explicitly in this file's own comment).
- **Design pattern:** Template/shared lifecycle interface.
- **SOLID:** ISP.
- **Extension point:** no.
- **Future work:** none.

### `lib/src/managers/security_manager.dart` (30 lines)
- **Why it exists:** the contract for the runtime orchestrator — the one component every public call actually reaches.
- **Responsibility:** declare `status`, `pause()`, `resume()`, `shutdown()`, `checkNow()`.
- **Public classes:** `SecurityManager` (abstract, `implements Manager`).
- **Dependency graph:** → `models/sdk_state.dart`, `managers/manager.dart`.
- **Who depends on it:** `DeviceShield` (via `ServiceContainer.resolve`), `LifecycleManager` (via the inverted `SecurityLifecycleHandler` callback, not a direct reference).
- **Design pattern:** Facade contract, Mediator (coordinates the other three managers without them knowing about each other).
- **SOLID:** ISP — narrow public surface; all pipeline logic is delegated, not exposed here.
- **Extension point:** no.
- **Future work:** none at the contract level.

### `lib/src/managers/default_security_manager.dart` (143 lines)
- **Why it exists:** the real implementation — coordinates `DetectionManager`, `PolicyManager`, `EventManager` only; implements no detection/policy/native logic of its own.
- **Responsibility:** drive the periodic check timer; run the confidence-gate → Policy → Event pipeline (currently: no confidence gate is actually applied — every result is passed to `policyManager.evaluate()` unconditionally, a simplification versus `ARCHITECTURE.md`'s diagrammed gate); implement `SecurityLifecycleHandler`.
- **Public classes:** `DefaultSecurityManager` (`implements SecurityManager, SecurityLifecycleHandler`).
- **Public methods:** `status`, `initialize()`, `dispose()`, `pause()`, `resume()`, `shutdown()`, `checkNow()`, plus the `SecurityLifecycleHandler` callbacks `onResume/onInactive/onPause/onDetached`.
- **Important private methods:** `_startPeriodicChecks()`/`_stopPeriodicChecks()` (manage a `Timer.periodic`).
- **Dependency graph:** → `DetectionManager`, `PolicyManager`, `EventManager`, `ConfigurationManager`, `Lifecycle`, `Logger` (constructor-injected). **Deliberately holds no `NativeBridge` reference** — even though the frozen matrix lists it as allowed, this class has no legitimate use for one (all native communication happens inside `DetectionManager`).
- **Lifecycle:** SDK-lifetime — constructed at boot step 7 (last manager), its own `dispose()` stops the timer and cascades to `DetectionManager`/`PolicyManager`.
- **Who creates it:** `PluginInitializer._resolveOrRegisterSecurityManager()`.
- **Who owns it:** `ServiceContainer`; `DeviceShield` resolves it for every delegating call.
- **Who disposes it:** `PluginInitializer.shutdown()`.
- **State-transition ownership (important, verified against tests):** `pause()`/`resume()` transition `running ⇄ paused` themselves. `shutdown()` does **not** transition state to `stopped` — that belongs to `PluginInitializer` — this class only stops its own timer (verified by `default_security_manager_test.dart`'s "shutdown stops the timer but does not transition Lifecycle state" test).
- **Communication:** `checkNow()` calls `detectionManager.runAllChecks()`, then for each result: `policyManager.evaluate()` → `policyManager.executeAction()` → `eventManager.emit(SecurityEvent(...))` — all three per-result steps run sequentially, not in parallel, matching the architecture's "everything downstream of a single result is sequential" governing rule.
- **Design pattern:** Mediator, Observer (implements `SecurityLifecycleHandler` to receive lifecycle callbacks without holding a reference back to `LifecycleManager`).
- **SOLID:** SRP — coordination only. DIP — depends on the three manager *interfaces*, never `DefaultDetectionManager`/`DefaultPolicyManager` concretely.
- **Extension point:** no.
- **Future work:** event severity is hardcoded to `EventSeverity.info` for every `checkNow()` emission — deriving it from the detection result is explicitly out of scope for now (a policy-adjacent decision, deferred alongside `PolicyManager`'s own placeholder action resolution).

### `lib/src/managers/detection_manager.dart` (31 lines)
- **Why it exists:** the contract for the technique-agnostic framework that runs registered detectors and aggregates results.
- **Responsibility:** declare `runAllChecks()`, `runCheck(String type)`, `registerDetector(Detector)`.
- **Public classes:** `DetectionManager` (abstract, `implements Manager`).
- **Dependency graph:** → `models/detection_result.dart`, `registry/detector.dart`, `managers/manager.dart`.
- **Who depends on it:** `SecurityManager`, `api` (`DeviceShield.registerDetector`).
- **Design pattern:** Strategy contract, Registry consumer.
- **SOLID:** ISP; the extension point is explicitly `Detector`+`DetectorRegistry`, not this interface itself.
- **Extension point:** no (by design — see above).
- **Future work:** none at the contract level.

### `lib/src/managers/default_detection_manager.dart` (175 lines)
- **Why it exists:** the real, coordination-only implementation.
- **Responsibility:** delegate storage entirely to an injected `DetectorRegistry`; run enabled detectors through a bounded `ConcurrencyController`; per-detector timeout; optional TTL cache via `DetectionCache`; reentrancy guard so an overlapping `runAllChecks()` call reuses the in-flight batch rather than starting a second sweep.
- **Public classes:** `DefaultDetectionManager`.
- **Public methods:** `initialize()`, `dispose()`, `runAllChecks()`, `runCheck(String)`, `registerDetector(Detector)`.
- **Important private methods:** `_runAllChecks()` (the actual batch-execution logic `runAllChecks()` wraps with the in-flight guard), `_checkWithCache(Detector)` (cache-aware per-detector execution — a thrown/timed-out check is never cached, since the exception simply propagates to `ConcurrencyController`'s own `onError`).
- **Fields:** `logger`, `registry` (`DetectorRegistry`), `concurrencyController`, `detectionCache` (nullable — `null` disables caching entirely), `detectorTimeout` (default 5000ms), `_inFlight` (the reentrancy-guard `Future`).
- **Dependency graph:** → `core/logger.dart`, `models/detection_result.dart`, `models/device_shield_exception.dart` (`DetectionException`), `registry/detector.dart`, `registry/detector_registry.dart`, `concurrency_controller.dart`, `detection_cache.dart`.
- **Lifecycle:** SDK-lifetime, constructed as part of `SecurityManager`'s own construction at boot step 7.
- **Who creates it:** `PluginInitializer._resolveOrRegisterDetectionManager()` (reads `checkTimeout` off the already-registered `ConfigurationManager` as a plain primitive — never holds a `ConfigurationManager` reference itself, preserving the frozen dependency matrix exactly).
- **Who owns it:** `ServiceContainer`; composed into `DefaultSecurityManager`.
- **Who disposes it:** `DefaultSecurityManager.dispose()` → this class's own `dispose()` disposes the concurrency controller, clears the cache, disposes every registered detector, then clears the registry.
- **Who depends on it:** `SecurityManager`, `api`.
- **Communication:** `runAllChecks()` → `ConcurrencyController.run()` with `task: _checkWithCache`, `onError` logging+excluding a failed detector rather than failing the batch.
- **Design pattern:** Facade/Coordinator, Registry consumer, Decorator (caching wraps the raw `Detector.check()` call).
- **SOLID:** SRP — this class does not itself store detectors (delegated to `DetectorRegistry`, "Architecture correction (Phase 6)"), does not itself implement concurrency (delegated to `ConcurrencyController`), does not itself implement caching mechanics (delegated to `DetectionCache`/`MultiLevelCache`) — genuinely composed, not monolithic despite being the file with the most responsibility in `managers/`.
- **Extension point:** no (the extension point is `Detector`+`DetectorRegistry`).
- **Future work:** none structural — this is one of the most complete managers in the codebase, already including scope (`ConcurrencyController`, per-detector timeout, optional caching) `ROADMAP.md` originally assigned to a later M14 phase, delivered ahead of schedule per its own doc comments.

### `lib/src/managers/policy_manager.dart` (35 lines)
- **Why it exists:** the contract for turning a `DetectionResult` into a `SecurityAction`.
- **Responsibility:** declare `evaluate()`, `executeAction()`, `addRule()`, `removeRule()`, `calculateRiskScore()`.
- **Public classes:** `PolicyManager` (abstract, `implements Manager`).
- **Dependency graph:** → `models/detection_result.dart`, `models/security_action.dart`, `registry/rule.dart`, `managers/manager.dart`.
- **Who depends on it:** `SecurityManager`, `api` (`addRule`/`removeRule`).
- **Design pattern:** Strategy contract, Rule-engine consumer.
- **SOLID:** ISP; OCP — extension is `Rule` implementations + the reserved `SecurityAction.custom` action-handler slot, not this interface.
- **Extension point:** yes (documented) — new `Rule`s (FR-17) and new action handlers against `SecurityAction.custom`.
- **Future work:** none at the contract level.

### `lib/src/managers/default_policy_manager.dart` (86 lines)
- **Why it exists:** the real, coordination-only implementation — mirrors exactly how `DefaultDetectionManager` coordinates `Detector`s.
- **Responsibility:** invoke registered `Rule`s in priority order, return the first match's action; a broken rule is treated as "no match," never blocking others; placeholder `executeAction()` (logs only — no `ActionHandler` registry exists); real `calculateRiskScore()`.
- **Public classes:** `DefaultPolicyManager`.
- **Public methods:** `initialize()`, `dispose()`, `evaluate(DetectionResult)`, `executeAction(SecurityAction, DetectionResult)`, `addRule(Rule)`, `removeRule(String)`, `calculateRiskScore(List<DetectionResult>)`.
- **Fields:** `logger`, `_rules` (`List<Rule>`, private).
- **Dependency graph:** → `core/logger.dart`, `models/detection_result.dart`, `models/security_action.dart`, `registry/rule.dart`.
- **Lifecycle:** SDK-lifetime, constructed alongside `DetectionManager` as part of `SecurityManager`'s composition.
- **Who creates it:** `PluginInitializer._resolveOrRegisterPolicyManager()`.
- **Who owns it:** `ServiceContainer`; composed into `DefaultSecurityManager`.
- **Who disposes it:** `DefaultSecurityManager.dispose()` → own `dispose()` clears `_rules`.
- **`calculateRiskScore` semantics (verified against tests):** averages `confidence` across only the *detected* results, clamped 0.0–1.0; returns 0.0 if nothing was detected — matches `default_policy_manager_test.dart` exactly (`0.6` for a `[0.8, 0.4]` detected pair, `0.0` for all-undetected input).
- **Communication:** `evaluate()` sorts a copy of `_rules` by priority ascending, iterates, returns the first `matches()==true` rule's `action`, wrapped in try/catch per-rule.
- **Design pattern:** Chain of Responsibility (priority-ordered rule matching, first-match-wins), Strategy.
- **SOLID:** SRP — coordination only, zero rule *content*.
- **Extension point:** yes, inherited (`addRule`/`removeRule`).
- **Future work:** **the single largest content gap in the SDK** — zero default `Rule` implementations for any detection type exist; `executeAction()` is entirely a log-only placeholder (no `ActionHandler` dispatch of any kind); no `CustomRule` public class exists yet (FR-17's public surface); no 100-rule cap or circular-rule-dependency validation.

### `lib/src/managers/concurrency_controller.dart` (122 lines)
- **Why it exists:** the generic bounded-concurrency executor behind `DetectionManager.runAllChecks()`'s "detectors run in parallel, bounded" requirement — deliberately knows nothing about `Detector`/`DetectionResult`, generic over item/result types so it's reusable anywhere bounded, order-preserving, per-item-isolated concurrency is needed.
- **Responsibility:** run up to `maxConcurrent` tasks at once over a list of items; preserve **input order** in the returned results regardless of completion order; per-task timeout; per-task error isolation via a caller-supplied `onError` (whose `null` return excludes that item); cooperative dispose (no forced cancellation of an already-started task, but no not-yet-started item begins after `dispose()`).
- **Public classes:** `ConcurrencyController`.
- **Public methods:** `run<T, R>({items, task, onError, timeout})`, `dispose()`.
- **Important private mechanics:** a shared `nextIndex` cursor claimed by worker coroutines in a single synchronous block (no `await` between read and increment), so no two workers can ever claim the same index — the documented basis for this class's thread-safety claim under Dart's cooperative scheduling.
- **Dependency graph:** `dart:async` only — zero SDK-internal dependencies.
- **Lifecycle:** owned exclusively by whichever `DetectionManager` implementation constructs it.
- **Who creates it:** `DefaultDetectionManager`'s constructor (`concurrencyController ?? ConcurrencyController()`, default `maxConcurrent: 4`), or a test/caller supplying its own instance.
- **Who owns it:** `DefaultDetectionManager` exclusively.
- **Who disposes it:** `DefaultDetectionManager.dispose()`.
- **Design pattern:** Worker Pool / Bounded Producer-Consumer, generic Strategy.
- **SOLID:** SRP — scheduling mechanics only, held out of `DetectionManager` itself so that class's own file stays free of concurrency code.
- **Extension point:** no (it's infrastructure, not meant to be swapped).
- **Future work:** none identified — this class is exercised by a dedicated, thorough test file (`concurrency_controller_test.dart`, 12 tests) covering sequential/parallel execution, max-concurrency enforcement, timeout, exception isolation, deterministic ordering, and dispose-during-run cancellation.

### `lib/src/managers/cache_level.dart` (34 lines)
- **Why it exists:** the contract for one storage tier within a `MultiLevelCache`.
- **Responsibility:** `read`, `write`, `delete`, `has`, `wipe`, `keys` — pure storage, no TTL/eviction-policy knowledge beyond whatever a concrete level needs to enforce its own capacity.
- **Public classes:** `CacheLevel<K, V>` (abstract).
- **Dependency graph:** none — fully generic, detector-agnostic.
- **Who depends on it:** `MultiLevelCache`, `MemoryCacheLevel` (implements it).
- **Design pattern:** Strategy (pluggable storage tier).
- **SOLID:** ISP.
- **Extension point:** yes (implicitly) — a future disk-backed tier is "just another `CacheLevel` implementation."
- **Future work:** only one concrete implementation (`MemoryCacheLevel`) exists; a disk/persistent tier is designed-for but not built.

### `lib/src/managers/memory_cache_level.dart` (67 lines)
- **Why it exists:** the required in-memory `CacheLevel` — a bounded, LRU-evicting store.
- **Responsibility:** implement `CacheLevel` over a `LinkedHashMap`, using remove-then-reinsert to track recency (no separate linked list/counter needed); evict the least-recently-used entry once `maxCapacity` is exceeded.
- **Public classes:** `MemoryCacheLevel<K, V>`.
- **Public methods:** `read`, `write`, `delete`, `has`, `wipe`, `keys`.
- **Dependency graph:** → `dart:collection`, `cache_level.dart`.
- **Who creates it:** `MultiLevelCache`'s constructor by default (`levels ?? [MemoryCacheLevel(maxCapacity: maxCapacity)]`).
- **Who owns it:** `MultiLevelCache`, or a caller supplying a custom level list directly.
- **Design pattern:** LRU Cache (classic).
- **SOLID:** SRP, LSP (fully substitutable behind `CacheLevel`).
- **Extension point:** no (it *is* the default extension instance).
- **Future work:** none — verified thoroughly by `multi_level_cache_test.dart`'s dedicated "MemoryCacheLevel — construction and direct behavior" group.

### `lib/src/managers/multi_level_cache.dart` (129 lines)
- **Why it exists:** generic, reusable, detector-agnostic multi-tier cache — the engine `DetectionCache` sits on top of.
- **Responsibility:** own everything TTL-related (wraps every stored value with its storage time, once, here); check levels in order on `get`, promoting a hit from a slower level into every faster level ahead of it; `clearExpired()` for a proactive sweep independent of lazy per-read expiration.
- **Public classes:** `MultiLevelCache<K, V>`, `CacheEntry<V>` (public so a custom `CacheLevel` implementation can be typed against it).
- **Public methods:** `get(K)`, `put(K, V)`, `remove(K)`, `contains(K)`, `clear()`, `clearExpired()`.
- **Important private methods:** `_deleteFromEveryLevel(K)`, `_hasExpired(CacheEntry<V>)`.
- **Dependency graph:** → `cache_level.dart`, `memory_cache_level.dart` only — independent of `DetectionManager`, `Detector`, `PolicyManager`, `EventManager`, `NativeBridge`, and any Flutter type.
- **Who creates it:** `DetectionCache`'s constructor (as its internal storage engine).
- **Who depends on it:** `DetectionCache` exclusively at the framework level; usable standalone by anything needing a generic TTL cache.
- **Design pattern:** Multi-Level Cache (classic "L1/L2 with promotion"), Decorator (TTL wrapping over whatever `CacheLevel`s are supplied).
- **SOLID:** SRP, OCP (a disk-backed second level is additive — pass a longer `levels` list, no code change here).
- **Extension point:** yes — pluggable `levels` list.
- **Future work:** currently always configured with a single memory level in practice; promotion logic is real but exercised as a no-op until a second, slower level exists.

### `lib/src/managers/detection_cache.dart` (66 lines)
- **Why it exists:** stores the most recent `DetectionResult` per detector, honoring a configurable TTL — the "cache management" responsibility `ARCHITECTURE_CONTRACTS.md` names under `DetectionManager`'s Group D dependencies.
- **Responsibility:** a thin, detector-shaped public surface (`get`/`put`/`remove`/`clear`/`contains`) over `MultiLevelCache<String, DetectionResult>` — lazy, on-access invalidation, no `Timer` of its own to leak.
- **Public classes:** `DetectionCache`.
- **Public methods:** `get(String detectorId)`, `put(String, DetectionResult)`, `remove(String)`, `clear()`, `contains(String)`.
- **Dependency graph:** → `models/detection_result.dart`, `multi_level_cache.dart`.
- **Lifecycle:** optional, opt-in — `DefaultDetectionManager`'s `detectionCache` field defaults to `null` (disabled); when supplied, shares that manager's lifetime.
- **Who creates it:** a caller wiring `DefaultDetectionManager` with an explicit `DetectionCache` instance (not defaulted anywhere in `PluginInitializer` today — caching is opt-in even at the framework composition level).
- **Who owns it:** whichever `DefaultDetectionManager` it was supplied to.
- **Who disposes it:** `DefaultDetectionManager.dispose()` calls `detectionCache?.clear()`.
- **Design pattern:** Facade over `MultiLevelCache`, Cache-Aside.
- **SOLID:** SRP — detector-agnostic, knows only a `String` key and `DetectionResult` value.
- **Extension point:** no (its own storage engine, `MultiLevelCache`, is the extension point).
- **Future work:** none — its public contract intentionally stayed unchanged through the `MultiLevelCache` refactor, per its own doc comment.

### `lib/src/models/detection_result.dart` (87 lines)
- **Why it exists:** the shared result model for one `Detector.check()` invocation.
- **Responsibility:** immutable value object; `riskScore`/`isCritical` derived getters; hand-written `toJson`/`fromJson`.
- **Public classes:** `DetectionResult`. Public enum: `DetectionStatus` (`completed, failed`).
- **Fields:** `type` (`String`, deliberately open — not a closed enum, "so a custom detector never requires a framework change"), `detected`, `confidence`, `timestamp`, `evidence` (`Map`, compares by reference, not deep content — documented trade-off), `status`.
- **Dependency graph:** none — pure Dart, no imports beyond `dart:core`.
- **Design pattern:** Value Object/DTO.
- **SOLID:** SRP.
- **Extension point:** the open `type: String` field is itself the extension mechanism.
- **Future work:** `evidence` equality is by-reference, not deep — two results built from equivalent-but-distinct evidence maps are not `==`, a documented, intentional limitation (avoids adding the `collection` package dependency).

### `lib/src/models/device_shield_config.dart` (92 lines)
- **Why it exists:** SDK-wide configuration (SRS §7.1, generic fields only).
- **Responsibility:** immutable value object with `copyWith`/`toJson`/`fromJson`/equality.
- **Public classes:** `DeviceShieldConfig`.
- **Fields:** `debugLogging` (false), `runOnUIThread` (false), `periodicCheckInterval` (30000), `maxRetryAttempts` (3), `retryDelay` (1000), `checkTimeout` (5000) — all with documented defaults.
- **Dependency graph:** none.
- **Design pattern:** Value Object, Builder-lite (`copyWith`).
- **SOLID:** SRP — deliberately has no `validate()` method (that's `ConfigurationManager`'s/the validator's job, not the model's).
- **Extension point:** no.
- **Future work:** no detection/protection sub-config fields yet (deliberately deferred — additive, non-breaking once M7/M11 land); no `DeviceShieldConfigBuilder` fluent builder exists (SRS §7.2); no `ConfigurationPersistence` (SharedPreferences-backed save/load, §7.6) — `shared_preferences` isn't even a declared dependency in `pubspec.yaml`.

### `lib/src/models/device_shield_exception.dart` (107 lines)
- **Why it exists:** the base of the SDK's exception hierarchy (SRS §8.1).
- **Responsibility:** carry `code`/`message`/`details`/`stackTrace`; deliberately **not** value-equal (two exceptions are distinct occurrences even with matching fields).
- **Public classes:** `DeviceShieldException` (base, `implements Exception`), `ConfigurationException`, `PermissionException` (adds `missingPermissions`), `InitializationException`, `NativeBridgeException` (adds `method`/`nativeError`), `PolicyException`, `DetectionException` (adds nullable `type`).
- **Dependency graph:** none.
- **Who depends on it:** every layer of the codebase — the shared error vocabulary.
- **Design pattern:** Exception hierarchy (classic), Value carrier (though not value-equal).
- **SOLID:** SRP/OCP — each subtype adds only the fields its own thrower needs; no god-exception.
- **Extension point:** the base class is extensible; detector-specific subtypes (e.g. a hypothetical `RootDetectionException`) are explicitly out of scope until that detector exists.
- **Future work:** none structural.

### `lib/src/models/sdk_state.dart` (16 lines)
- **Why it exists:** the 8-value SDK status enum backing the entire state machine.
- **Responsibility:** pure enumeration — no logic, no transition rules (that's `Lifecycle`'s job).
- **Public classes:** `SDKState` (enum: `uninitialized, initializing, initialized, running, paused, stopped, failure, destroyed`).
- **Dependency graph:** none.
- **Design pattern:** State (the "state" half of the State pattern; `DefaultSecurityStateManager` is the "context"/machine half).
- **SOLID:** SRP.
- **Extension point:** no — the 8 values are frozen per `ARCHITECTURE_CONTRACTS.md` Part 3.
- **Future work:** none — its own doc comment (a leftover "Placeholder shell" note from an earlier phase) is now stale prose, since this enum is in full active use; harmless but worth a documentation touch-up.

### `lib/src/models/security_action.dart` (16 lines)
- **Why it exists:** the policy-response vocabulary every `Rule`/`PolicyManager` resolves to.
- **Responsibility:** pure enumeration.
- **Public classes:** `SecurityAction` (enum: `ignore, warn, block, logout, terminate, report, custom`).
- **Dependency graph:** none.
- **Design pattern:** enum-as-Strategy-selector; `custom` is the reserved open extension slot.
- **SOLID:** SRP.
- **Extension point:** yes — `custom`, paired with an `ActionHandler` registry that doesn't exist yet (see `default_policy_manager.dart`'s gap).
- **Future work:** naming note — `ARCHITECTURE_CONTRACTS.md`'s `Rule` contract entry names this dependency `PolicyAction`; the actual code name is `SecurityAction`. Functionally equivalent, but a real, traceable naming mismatch against the frozen document (still true, per direct comparison).

### `lib/src/models/security_event.dart` (72 lines)
- **Why it exists:** one event broadcast through `EventManager`.
- **Responsibility:** immutable value object; hand-written `toJson`/`fromJson`.
- **Public classes:** `SecurityEvent`. Public enum: `EventSeverity` (`debug, info, warning, high, critical` — ascending ordinal, compare via `.index`).
- **Fields:** `type` (`String`, open identifier, same rationale as `DetectionResult.type`), `timestamp`, `data` (`Map`, reference equality), `severity`, `source` (nullable).
- **Dependency graph:** none.
- **Design pattern:** Value Object.
- **SOLID:** SRP — deliberately no `matches(filter)` method on the class itself (filtering is expressed once, as `EventManager`'s `SecurityEventFilter` typedef, not duplicated here).
- **Extension point:** the open `type: String` field.
- **Future work:** naming note — the SRS (via `ROADMAP.md` M1) names this enum `SecuritySeverity`; the actual code name is `EventSeverity` — a real name difference from the SRS-derived name (informational, not a defect).

### `lib/src/models/security_profile.dart` (187 lines — largest model file)
- **Why it exists:** declarative per-app risk-posture configuration (SRS FR-14, §6.2).
- **Responsibility:** immutable value object aggregating `detectionConfigs`/`policyConfigs`/`protectionConfigs`; full `toJson`/`fromJson`/equality for itself and its three nested config types.
- **Public classes:** `SecurityProfile`, `DetectionConfig` (`type`, `enabled`, `confidenceThreshold`), `PolicyConfig` (`type`, `action`, `threshold`, `priority`), `ProtectionConfig` (`type`, `enabled`).
- **Dependency graph:** → `security_action.dart` only.
- **Who depends on it:** documented as a dependency of `PermissionManager`/`DetectionManager`/`PolicyManager` in `ARCHITECTURE_CONTRACTS.md`, but **not yet threaded through any actual method signature** — `Manager.initialize()` is deliberately parameterless (per Phase 2's frozen contract), so a profile would reach a manager via constructor injection at a later bootstrap phase, which hasn't been built.
- **Design pattern:** Value Object, Configuration Aggregate.
- **SOLID:** SRP — generic, open-identifier-based (`type: String`) sub-configs, never naming a specific detector/protection.
- **Extension point:** the open `type` fields on all three nested configs.
- **Future work:** **the model is complete; the wiring is not.** None of the five named factory presets (`fintech()`, `healthcare()`, `government()`, `enterprise()`, `consumer()`) exist; `DeviceShield.initialize()` takes only a `DeviceShieldConfig`, with no `profile` parameter at all — confirmed by direct reading of `api/device_shield.dart`.

### `lib/src/permission/permission_manager.dart` (39 lines)
- **Why it exists:** the contract for requesting/tracking OS permissions the active profile's detectors/protections require.
- **Responsibility:** declare `requestPermissions(Set<String>)`, `isGranted(String)`, `grantedPermissions`.
- **Public classes:** `PermissionManager` (abstract, `implements Manager`).
- **Design note:** the permission *set* itself is supplied at construction time, not through `initialize()`'s parameterless signature — the same pattern `ConfigurationManager` uses for its own per-boot input.
- **Dependency graph:** → `managers/manager.dart`.
- **Who depends on it:** `bootstrap` (`PluginInitializer`, boot step 2).
- **Design pattern:** Strategy contract.
- **SOLID:** ISP.
- **Extension point:** no.
- **Future work:** `SecurityProfile` is documented as this component's eventual source for a real required-permission set; nothing yet threads a profile through `initialize()`, so the only reachable input through the public API today is an empty set.
- **Note on prior findings:** `CURRENT_PROGRESS.md` (2026-07-24) found this contract had **no implementation anywhere** ("finding 2.1(b)"). **That finding is now resolved** — `DefaultPermissionManager` exists, is registered at boot step 2, and is directly tested (`test/permission/default_permission_manager_test.dart`, 9 tests).

### `lib/src/permission/default_permission_manager.dart` (56 lines)
- **Why it exists:** the real implementation of `PermissionManager`.
- **Responsibility:** trivially succeed for an empty required-permission set (today's only reachable scenario through the public API); **honestly throw `UnimplementedError`** for any non-empty request rather than silently auto-granting a permission this class never actually checked against the OS.
- **Public classes:** `DefaultPermissionManager`.
- **Public methods:** `initialize()` (delegates to `requestPermissions(requiredPermissions)`), `dispose()` (clears granted set), `requestPermissions(Set<String>)`, `isGranted(String)`, `grantedPermissions`.
- **Fields:** `requiredPermissions` (fixed at construction, default `{}`), `_granted` (private, always empty today).
- **Dependency graph:** → `permission_manager.dart` only.
- **Lifecycle:** SDK-lifetime, constructed at boot step 2.
- **Who creates it:** `PluginInitializer._resolveOrRegisterPermissionManager()`.
- **Who owns it:** `ServiceContainer`.
- **Who disposes it:** `PluginInitializer`'s `_unwind()` on a failed boot, or implicitly via `ServiceContainer.reset()` at full `dispose()`.
- **Design pattern:** Honest-stub/Not-Yet-Implemented boundary object (deliberately fails loud rather than fabricating success).
- **SOLID:** SRP.
- **Extension point:** no.
- **Documented reasoning for its own gap:** deliberately does **not** depend on `NativeBridge`, even though a real permission request is inherently native — the frozen Init Matrix places this at step 2, two steps before `NativeBridge` (step 4); requiring one now would force reordering past what a real implementation could consistently want. Deferred, not resolved by inventing a premature dependency.
- **Future work:** the actual OS-permission-request mechanism (needs a native bridge method that doesn't exist on either platform yet).

### `lib/src/platform/device_shield_platform_interface.dart` (39 lines)
- **Why it exists:** the pre-existing, Phase-1 federated-plugin platform interface — **legacy as of the Phase 7 architecture correction**, no longer part of the `NativeBridge` dependency chain.
- **Responsibility:** expose the abstract surface `MethodChannelDeviceShield` implements; token-verified singleton swap point.
- **Public classes:** `DeviceShieldPlatform` (abstract, `extends PlatformInterface`).
- **Public methods:** `instance` (getter/setter, token-verified), `getPlatformVersion()`.
- **Dependency graph:** → `plugin_platform_interface` package, `device_shield_method_channel.dart`.
- **Lifecycle:** **process lifetime** — the one component in the codebase that outlives individual `initialize()`/`shutdown()` cycles (a process-level singleton, not an SDK-lifetime one).
- **Who creates it:** package load time / a platform package's `registerWith()`.
- **Who depends on it:** `api/device_shield.dart`'s legacy instance method `getPlatformVersion()` only.
- **Design pattern:** Federated Plugin pattern (Platform Interface), token-verified Singleton.
- **SOLID:** the correct, standard Flutter federated-plugin shape.
- **Extension point:** public, so a platform package could register its own implementation — a capability that remains available even though nothing in the frozen bridge architecture currently exercises it.
- **Future work:** none — deliberately frozen/unchanged; superseded by `NativeBridge` (swappable via `ServiceContainer`) as the real "new platform" extension point for everything except the one legacy call this still backs.

### `lib/src/platform/device_shield_method_channel.dart` (19 lines)
- **Why it exists:** the concrete `MethodChannel`-based implementation of `DeviceShieldPlatform`.
- **Responsibility:** wrap the single legacy `device_shield` channel; `getPlatformVersion()`.
- **Public classes:** `MethodChannelDeviceShield` (`extends DeviceShieldPlatform`).
- **Public fields:** `methodChannel` (`@visibleForTesting`, `MethodChannel('device_shield')`).
- **Dependency graph:** → `flutter/services.dart`, `flutter/foundation.dart`, `device_shield_platform_interface.dart`.
- **Who creates it:** `DeviceShieldPlatform`'s own static field default (`_instance = MethodChannelDeviceShield()`).
- **Design pattern:** Adapter (federated-plugin default implementation).
- **SOLID:** SRP — one method, one channel.
- **Extension point:** no (it's the default instance, not itself extensible).
- **Future work:** none — trivial, complete, unchanged since Phase 1.

### `lib/src/registry/registry.dart` (34 lines)
- **Why it exists:** the generic registration/lookup base `DetectorRegistry` builds on.
- **Responsibility:** declare `register`, `unregister`, `find`, `list`.
- **Public classes:** `Registry<T>` (abstract).
- **Dependency graph:** none.
- **Who depends on it:** `DetectorRegistry` exclusively.
- **Design pattern:** Registry (generic base).
- **SOLID:** ISP.
- **Extension point:** no (a future registry adds domain-specific logic on top — it doesn't customize this base).
- **Documentation note (verified against the file's own comment):** a `ManagerRegistry`/`ActionRegistry` were once described as planned but were never approved architecture components and were never built; a `RuleRegistry` was deliberately never built as a separate component — `PolicyManager` owns its rule collection directly, an intentional asymmetry with `DetectorRegistry`.
- **Future work:** none for this base itself.

### `lib/src/registry/detector.dart` (44 lines)
- **Why it exists:** the contract every detection module implements.
- **Responsibility:** declare `type`, `priority`, `initialize()`, `check()`, `dispose()`.
- **Public classes:** `Detector` (abstract, **public** — host apps implement this directly for FR-18 custom detectors).
- **Dependency graph:** → `models/detection_result.dart`.
- **Who depends on it:** `DetectorRegistry`, `DetectorFactory`, `DetectionManager`, `EmulatorDetector`.
- **Design pattern:** Strategy (the core extension mechanism of the entire detection subsystem).
- **SOLID:** ISP (4 members), LSP (any implementation is substitutable — `DetectionManager` never inspects concrete type).
- **Extension point:** **yes — this contract is the FR-18 mechanism itself**, together with `DetectorRegistry`.
- **Future work:** none at the contract level — this is exactly the shape it needs to be for every future detector.

### `lib/src/registry/rule.dart` (34 lines)
- **Why it exists:** the contract every policy rule implements.
- **Responsibility:** declare `id`, `matches(DetectionResult)`, `action`, `priority`.
- **Public classes:** `Rule` (abstract, **public** — `CustomRule` (FR-17) would implement this directly, though `CustomRule` itself doesn't exist yet).
- **Dependency graph:** → `models/detection_result.dart`, `models/security_action.dart`.
- **Who depends on it:** `PolicyManager`.
- **Design pattern:** Strategy (the FR-17 extension mechanism).
- **SOLID:** ISP, LSP.
- **Extension point:** **yes — this contract is the FR-17 mechanism itself.**
- **Future work:** no concrete `Rule` implementation exists anywhere in the codebase yet (not even a default one) — only test-only fakes exercise this contract today.

### `lib/src/registry/detector_registry.dart` (50 lines)
- **Why it exists:** decouples "what detectors exist" from "how `DetectionManager` runs them" — the FR-18 extension mechanism's storage half.
- **Responsibility:** declare `register` (must throw on duplicate type), `contains`, `clear`, `getAll` (priority-ordered), `getById`.
- **Public classes:** `DetectorRegistry` (abstract, `implements Registry<Detector>`).
- **Dependency graph:** → `detector.dart`, `registry.dart`.
- **Who depends on it:** `DetectionManager` exclusively — nothing else is meant to hold a reference.
- **Design pattern:** Registry.
- **SOLID:** SRP, ISP.
- **Extension point:** no (it's infrastructure *behind* the extension point, not the point itself).
- **Future work:** none at the contract level.

### `lib/src/registry/default_detector_registry.dart` (69 lines)
- **Why it exists:** the real implementation of `DetectorRegistry`.
- **Responsibility:** type-keyed map plus an explicit insertion-order list used as the priority-sort tiebreak — `List.sort` isn't documented as stable in Dart, so registration order is tracked and compared explicitly rather than relied upon implicitly.
- **Public classes:** `DefaultDetectorRegistry`.
- **Public methods:** `register`, `unregister`, `find`, `list`, `contains`, `clear`, `getAll`, `getById`.
- **Fields:** `_detectors` (`Map<String, Detector>`), `_registrationOrder` (`List<String>`).
- **Dependency graph:** → `detector.dart`, `detector_registry.dart`.
- **Lifecycle:** scoped to its owning `DetectionManager` instance.
- **Who creates it:** `PluginInitializer._resolveOrRegisterDetectorRegistry()`.
- **Who owns it:** `DetectionManager` exclusively (via constructor injection).
- **Who disposes it:** `DefaultDetectionManager.dispose()` calls `registry.clear()`.
- **Verified behavior (against the 21-test suite):** duplicate registration throws `ArgumentError` without replacing the original; `getAll()`/`list()` return the same, immutable, priority-ascending view; unregistering and re-registering resets a detector's tiebreak position to the end (not its original slot).
- **Design pattern:** Registry (concrete), Repository.
- **SOLID:** SRP, LSP.
- **Extension point:** no.
- **Future work:** none — this is one of the most thoroughly tested files in the codebase (21 dedicated tests).

### `lib/src/registry/detector_factory.dart` (68 lines)
- **Why it exists:** constructs the SDK's built-in detectors by their `Detector.type` identifier.
- **Responsibility:** a `String`-keyed constructor map — **deliberately not** a `switch` over a closed `DetectionType` enum (which would contradict `Detector.type`'s open-identifier design); only ever constructs *built-in* detectors, never a host app's custom `Detector`.
- **Public classes:** `DetectorFactory`.
- **Public methods:** `availableTypes` (getter), `create(String type)`.
- **Important private methods:** `_register(String, Detector Function())` (called once per built-in in the constructor — today, exactly once, for `EmulatorDetector`).
- **Dependency graph:** → `bridge/native_bridge.dart`, `detectors/emulator_detector.dart`, `models/device_shield_exception.dart`, `detector.dart`.
- **Lifecycle:** standalone utility — **not** constructed by `PluginInitializer`'s boot sequence at all (deliberately: which built-ins should be enabled by default is a `SecurityProfile` decision that doesn't exist yet; auto-registering unconditionally here would preempt that not-yet-built policy).
- **Who creates it:** a test, a host app, or a future profile-driven step — explicitly, not the framework itself today.
- **Who depends on it:** `test/registry/detector_factory_test.dart` (5 tests) — no production code path constructs or calls this class yet.
- **Design pattern:** Factory (registration-map variant, not a switch-based factory).
- **SOLID:** OCP — a new built-in detector is one more `_register()` call in the constructor, never a change to `create()`'s logic.
- **Extension point:** no (it's a construction convenience for built-ins, not itself extensible by host apps — custom detectors bypass this entirely).
- **Note on prior findings:** `CURRENT_PROGRESS.md` (2026-07-24) found this class **did not exist anywhere**. **That finding is now resolved** — confirmed by direct reading; it exists, is tested, and constructs a real detector.
- **Future work:** will grow by one `_register()` call per future built-in detector; still entirely disconnected from the boot sequence until `SecurityProfile` wiring lands.

### `lib/src/state/lifecycle.dart` (78 lines)
- **Why it exists:** the contracts for SDK status and the callback shape that resolved the `SecurityManager`↔`LifecycleManager` circular dependency.
- **Responsibility:** declare `Lifecycle` (status contract), `SecurityLifecycleHandler` (the narrow 4-callback contract), `LifecycleManager` (the `WidgetsBinding`-observer contract).
- **Public classes:** `Lifecycle` (abstract), `SecurityLifecycleHandler` (abstract: `onResume/onInactive/onPause/onDetached`), `LifecycleManager` (abstract: `attach/detach`).
- **Dependency graph:** → `models/sdk_state.dart`.
- **Who depends on it:** `DefaultSecurityStateManager` (implements `Lifecycle`), `DefaultSecurityManager` (implements `SecurityLifecycleHandler`), `DefaultLifecycleManager` (implements `LifecycleManager`).
- **Design pattern:** Observer (narrow callback contract, resolving what would otherwise be a two-node ownership cycle), State (the `Lifecycle` half).
- **SOLID:** ISP — `SecurityLifecycleHandler` is exactly 4 methods, no more; DIP — `LifecycleManager` depends on this contract, never on `SecurityManager` concretely, the identical pattern it already uses on its `WidgetsBinding` side.
- **Extension point:** no.
- **Documented correction (verified as correctly implemented):** an implementer of `SecurityLifecycleHandler` (i.e. `SecurityManager`) *may* emit a `SecurityEvent` in response to a lifecycle callback — legitimate, since `SecurityManager` already owns `EventManager`. What must never happen — and doesn't, per direct code reading — is `LifecycleManager` itself constructing/emitting a `SecurityEvent` or holding any `EventManager` reference.
- **Future work:** none — this is a fully resolved, frozen contract.

### `lib/src/state/security_state_manager.dart` (69 lines)
- **Why it exists:** the real, complete implementation of `Lifecycle` — the SDK's single source of truth for status, and the **only writer** in the whole SDK.
- **Responsibility:** enforce exactly the 8-state transition table frozen in `ARCHITECTURE_CONTRACTS.md` Part 3; broadcast every transition.
- **Public classes:** `DefaultSecurityStateManager`.
- **Public methods:** `current` (getter), `stateStream` (getter), `transitionTo(SDKState)`, `dispose()`.
- **Important private state:** `_allowedTransitions` (`static const Map<SDKState, Set<SDKState>>` — the entire transition table as data, not branching logic).
- **Dependency graph:** → `models/sdk_state.dart`, `lifecycle.dart` (implements it), `dart:async`.
- **Lifecycle:** SDK-lifetime, created before anything that could fail and need to report `failure` (effectively "step 0b," alongside `ServiceContainer`).
- **Who creates it:** `PluginInitializer._resolveOrRegisterStateManager()`.
- **Who owns it:** `ServiceContainer`; read continuously by `SecurityManager`, `LifecycleManager` (indirectly), and publicly via `DeviceShield.status`.
- **Who disposes it:** `PluginInitializer.dispose()` calls its `dispose()` (closes the `StreamController`) only after transitioning to `destroyed` — never while a transition might still need to broadcast.
- **Verified transition table (matches the frozen contract exactly, state-for-state):**

| From | Allowed To |
|---|---|
| `uninitialized` | `initializing`, `destroyed` |
| `initializing` | `initialized`, `failure`, `destroyed` |
| `initialized` | `running`, `stopped`, `destroyed` |
| `running` | `paused`, `stopped`, `failure`, `destroyed` |
| `paused` | `running`, `stopped`, `destroyed` |
| `stopped` | `running`, `destroyed` |
| `failure` | `initialized`, `stopped`, `destroyed` |
| `destroyed` | *(terminal — no outgoing transitions)* |

- **Design pattern:** State Machine (Context half of the State pattern), Observer (broadcast `StreamController<SDKState>`).
- **SOLID:** SRP — a pure state machine, zero security/detection/policy content.
- **Extension point:** no.
- **Future work:** none — `CURRENT_PROGRESS.md`'s own assessment ("the only milestone this report calls essentially done") still holds; this class remains complete and gap-free.

### `lib/src/state/default_lifecycle_manager.dart` (62 lines)
- **Why it exists:** the only component in the entire SDK listening to Flutter's own app lifecycle.
- **Responsibility:** translate `AppLifecycleState` into calls on whatever `SecurityLifecycleHandler` is attached; holds nothing else.
- **Public classes:** `DefaultLifecycleManager` (`extends WidgetsBindingObserver`, `implements LifecycleManager`).
- **Public methods:** `attach(SecurityLifecycleHandler)`, `detach()`, `didChangeAppLifecycleState(AppLifecycleState)` (the `WidgetsBindingObserver` override).
- **Fields:** `_handler` (nullable `SecurityLifecycleHandler`), `_observing` (bool, idempotency guard for `WidgetsBinding.instance.addObserver/removeObserver`).
- **Mapping (verified against tests):** `resumed → onResume`; `inactive → onInactive`; `hidden → onInactive` (documented: `hidden` postdates the frozen 4-callback contract, `inactive` is the closest semantic match); `paused → onPause`; `detached → onDetached`.
- **Dependency graph:** → `flutter/widgets.dart`, `lifecycle.dart`.
- **Lifecycle:** from monitoring start (`attach()`, boot step 8) until `detach()` (shutdown step 1, or dispose).
- **Who creates it:** `PluginInitializer._resolveOrRegisterLifecycleManager()`.
- **Who owns it:** `ServiceContainer`; attached-to by `SecurityManager` (which implements the handler contract it's given).
- **Who disposes it:** never disposed per se — `detach()` stops observing and clears `_handler`; the object itself persists across a shutdown/reinitialize cycle (unregistered from `ServiceContainer` only at full `dispose()`).
- **Design pattern:** Observer (`WidgetsBindingObserver`), Adapter (translates Flutter's lifecycle vocabulary into the SDK's own narrow contract).
- **SOLID:** SRP — never constructs a `SecurityEvent`, never references `EventManager`, never calls `NativeBridge`; its entire job is the one translation.
- **Extension point:** no.
- **Future work:** none identified.

---

## 5. Architecture Flow

```
Application
   │  calls DeviceShield.initialize(config: ...)
   ▼
DeviceShield API  (lib/src/api/device_shield.dart)
   │  lazily creates a ServiceContainer + PluginInitializer (once), then
   │  delegates to initializer.initialize(config)
   ▼
Bootstrap  (PluginInitializer)
   │  validates config via DeviceShieldConfigValidator; runs the fixed
   │  9-step sequence, resolving-or-defaulting each service against the
   │  container as it goes
   ▼
ServiceContainer
   │  type-keyed register/resolve; the DependencyResolver guards every
   │  resolve<T>() call against re-entrant circular resolution
   ▼
Managers  (SecurityManager composes DetectionManager + PolicyManager;
   │        both are constructed by PluginInitializer itself, not split
   │        across a separate composition-root class)
   ▼
Registry  (DetectorRegistry, held privately by DetectionManager; a
   │        DetectorFactory exists as a standalone, not-yet-wired-in
   │        convenience for constructing built-ins by type string)
   ▼
Bridge  (NativeBridge / DefaultNativeBridge, composing
   │      MethodChannelService + EventChannelService)
   ▼
Native  (Android Kotlin / iOS Swift plugin classes)
```

**Step-by-step, as the code actually runs (verified against `plugin_initializer.dart`):**

1. **App → API.** The host app never sees anything below `DeviceShield`. `DeviceShield.initialize()` is idempotent at the container level (`_container ??= ServiceContainer()`, `_initializer ??= PluginInitializer(...)`) — a second call reuses the same container/initializer, and `PluginInitializer.initialize()` itself throws `ALREADY_INITIALIZING` if the state machine is already past `uninitialized`.
2. **API → Bootstrap.** `PluginInitializer.initialize(config)` runs the boot sequence documented in full in §4's `plugin_initializer.dart` entry and diagrammed in §7 below.
3. **Bootstrap → ServiceContainer.** Every step is a `_resolveOrRegisterX()` call: if the caller (a test, or a future profile-driven composition layer) already registered an implementation, it's used as-is and only `initialize()`d; otherwise a sensible built-in default is constructed and registered. This is true uniformly for `Logger`, `PermissionManager`, `ConfigurationManager`, `NativeBridge`, `EventManager`, `DetectorRegistry`, `DetectionManager`, `PolicyManager`, `SecurityManager`, and `LifecycleManager` — all ten now follow the identical pattern (as of this codebase state; `CURRENT_PROGRESS.md`, 2026-07-24, found the last four were **not** yet handled this way).
4. **Bootstrap → Managers.** `_resolveOrRegisterSecurityManager()` composes `DefaultSecurityManager` from a `DetectionManager` and `PolicyManager` it resolves-or-constructs first (in that order), plus the already-registered `EventManager`/`ConfigurationManager`/`Lifecycle`/`Logger`.
5. **Managers → Registry.** `DefaultDetectionManager` never stores detectors itself — it holds a `DetectorRegistry` (constructor-injected) and delegates every registration/lookup/ordering concern to it.
6. **Managers → Bridge.** Only `DetectionManager` (via the detectors it hosts) ever reaches `NativeBridge`. `SecurityManager` deliberately holds no `NativeBridge` reference; `PolicyManager` never reaches it at all.
7. **Bridge → Native.** `DefaultNativeBridge.invoke()` → `MethodChannelService.invoke()` → Flutter's `MethodChannel.invokeMethod()`, marshaled by the engine onto the platform thread, dispatched by `DeviceShieldPlugin.onMethodCall`/`.handle(_:result:)` on Android/iOS respectively.

---

## 6. Dependency Graph

```
DeviceShield (static facade)
│
├── PluginInitializer  (held statically, constructed once)
│    │
│    └── ServiceContainer  (held statically, independent lifecycle — Correction 1)
│         │
│         ├── Logger ◄─────────────────────────── (soft, optional, no hard edge back)
│         ├── PermissionManager
│         ├── ConfigurationManager
│         ├── NativeBridge
│         │    ├── MethodChannelService
│         │    └── EventChannelService
│         ├── EventManager
│         ├── DetectorRegistry
│         │    └── Detector (contract)
│         │         └── EmulatorDetector (the one concrete built-in)
│         ├── DetectionManager
│         │    ├── DetectorRegistry  (constructor-injected)
│         │    ├── ConcurrencyController
│         │    ├── DetectionCache (optional)
│         │    │    └── MultiLevelCache
│         │    │         └── CacheLevel (contract) → MemoryCacheLevel
│         │    └── Logger
│         ├── PolicyManager
│         │    ├── Rule (contract — zero concrete implementations yet)
│         │    └── Logger
│         ├── SecurityManager
│         │    ├── DetectionManager
│         │    ├── PolicyManager
│         │    ├── EventManager
│         │    ├── ConfigurationManager
│         │    ├── Lifecycle
│         │    └── Logger
│         └── LifecycleManager
│              └── SecurityLifecycleHandler (narrow callback — implemented by SecurityManager)
│
└── DeviceShieldPlatform (LEGACY — separate graph entirely)
     └── MethodChannelDeviceShield
          └── device_shield channel (getPlatformVersion only)
```

**Standalone, not yet wired into the graph above:**
```
DetectorFactory
├── NativeBridge (constructor-injected)
└── constructs: EmulatorDetector (only registered built-in)
```
`DetectorFactory` is a real, tested class that nothing in the boot sequence currently calls — a deliberate gap, pending `SecurityProfile` wiring (see §4/§17).

**Native-side graph (per platform, structurally identical):**
```
DeviceShieldPlugin (Kotlin / Swift)
├── legacy MethodChannel "device_shield"        → getPlatformVersion
├── bridge MethodChannel "device_shield/native_bridge" → checkEmulator, else notImplemented
│    └── EmulatorDetector (native heuristics / compile-time simulator check)
└── bridge EventChannel "device_shield/events"  → sendEvent() outbound helper
```

---

## 7. Lifecycle

All phases below are transcribed directly from `plugin_initializer.dart`'s actual control flow (not merely restated from the frozen architecture documents, which use slightly different step numbering — see the note at the end of this section).

### SDK Initialization (chronological)

1. **Idempotency guard.** `PluginInitializer.initialize()` resolves/creates `Lifecycle` first. If the current state is `initializing`/`initialized`/`running`/`paused`, throws `InitializationException(ALREADY_INITIALIZING)`. If `destroyed`, throws `InitializationException(ALREADY_DISPOSED)`. Only a fresh boot (`uninitialized`) transitions to `initializing` — a restart from `stopped` or `failure` skips that observable phase entirely, matching the frozen transition table's actual reachable edges.
2. **Config validation.** `DeviceShieldConfigValidator().validate(config)` runs *before* any service is touched — an invalid config throws `ConfigurationException` before step 1 (Logger) even begins.
3. **Step 1 — Logger.** Resolved or defaulted to `ConsoleLogger()`. Logs `"Bootstrap: Logger ready"`.
4. **Step 2 — PermissionManager.** Resolved or defaulted to `DefaultPermissionManager()`; `initialize()` called (trivially succeeds for today's only reachable case, an empty required-permission set). Logs `"Bootstrap: Permission ready"`.
5. **Step 3 — Configuration.** Resolves-or-registers `ConfigurationManager` with the already-validated config; if one already exists (persisted from a prior shutdown), `updateConfig()` is called in place instead of recreating it. `initialize()` called. Logs `"Bootstrap: Configuration ready"`.
6. **Step 4 — NativeBridge.** Resolved or defaulted to `DefaultNativeBridge()`. Logs `"Bootstrap: NativeBridge ready"`.
7. **Step 5 — EventManager.** Resolved or defaulted to `DefaultEventManager()`; `initialize()` called. Logs `"Bootstrap: EventManager ready"`.
8. **Step 6 — Registries.** `DetectorRegistry` resolved or defaulted to `DefaultDetectorRegistry()`. Logs `"Bootstrap: Registries ready"`.
9. **Step 7 — Managers.** `SecurityManager` resolved or composed (which itself resolves-or-composes `DetectionManager`/`PolicyManager` first); `initialize()` called (cascades to `DetectionManager.initialize()` → every registered detector's `initialize()`, then `PolicyManager.initialize()`, then starts the periodic-check `Timer`). Logs `"Bootstrap: Managers ready"`.
10. **Step 8 — Lifecycle.** `LifecycleManager` resolved or defaulted to `DefaultLifecycleManager()`; if the resolved `SecurityManager` implements `SecurityLifecycleHandler` (it does — `DefaultSecurityManager`), `lifecycleManager.attach(securityManager)` is called, which begins observing `WidgetsBinding`. Logs `"Bootstrap: Lifecycle attached"`.
11. **Step 9 — Ready.** State transitions: from `stopped`, a direct hop to `running`; from `uninitialized`/`failure`, `initialized` then `running` (mirroring the entry-side asymmetry). `EventManager.emit(SecurityEvent(type: 'initialized', ...))`. Logs `"Bootstrap complete in Nms"`.
12. **Any exception at any step** is caught; if state is `initializing` or `running`, transitions to `failure`; `_unwind(context)` runs a best-effort reverse-order teardown over every step that *did* complete (Permission → Configuration → NativeBridge → EventManager → Registries (left registered, pure storage) → Managers → Lifecycle); the original exception is rethrown, never masked by a teardown failure.

### Service Registration
Every service registers into `ServiceContainer` as its step completes — never all at once at the end. This means a failure at step 6 leaves steps 1–5's services still registered (and torn down by `_unwind`), never a half-populated container silently left inconsistent.

### Dependency Resolution
`ServiceContainer.resolve<T>()` runs through `DependencyResolver.guard<T>()`, which pushes `T` onto an in-progress resolution stack, runs the actual factory/lookup, then pops. A factory that re-enters `resolve<T>()` for the same `T` before its own construction completes throws `InitializationException(CIRCULAR_DEPENDENCY)` immediately, naming the full resolution chain in its message.

### Manager Initialization
Order is: `DetectionManager.initialize()` (cascades to every registered detector — but at fresh boot, the registry is empty, so this is a no-op until detectors are registered post-boot) → `PolicyManager.initialize()` (no-op today) → `SecurityManager._startPeriodicChecks()` (starts the `Timer.periodic` at `ConfigurationManager.current.periodicCheckInterval`).

### Detector Registration
Happens **after** boot completes, via `DeviceShield.registerDetector(detector)` → `DetectionManager.registerDetector(detector)` → `detector.initialize()` then `registry.register(detector)` (throws if the type is already registered). Nothing in the current boot sequence auto-registers any built-in detector — `DetectorFactory` exists but isn't called by `PluginInitializer`.

### Detection Execution
`SecurityManager.checkNow()` (called by the periodic timer or on demand) → `DetectionManager.runAllChecks()` → duplicate-execution guard (`_inFlight`) → `ConcurrencyController.run()` bounded-parallel over every registered detector, each individually timeout-bound and cache-aware → results aggregated in **input order** (registry priority order), not completion order.

### Policy Evaluation
For each `DetectionResult` in the aggregated batch, sequentially: `PolicyManager.evaluate(result)` (priority-ordered `Rule.matches()` scan, first match wins, a throwing rule treated as no-match, falls through to `SecurityAction.ignore` if nothing matches or no rules exist) → `PolicyManager.executeAction(action, result)` (today: logs only, no `ActionHandler` dispatch exists).

### Event Emission
`SecurityManager` constructs and emits one `SecurityEvent` per detection result (`type: result.type`, `severity: EventSeverity.info` — hardcoded, not derived from the result), regardless of whether the resolved action was `ignore`. `EventManager.emit()` runs it through the (empty, by default) processor chain, appends to bounded history, and — if not paused — broadcasts to every filtered subscriber, each wrapped in its own try/catch.

### Shutdown
1. `LifecycleManager.detach()` — stops observing `WidgetsBinding`.
2. `SecurityManager.dispose()` — stops the periodic timer, disposes `DetectionManager` (which disposes every registered detector then clears the registry) and `PolicyManager`; **then unregistered** from the container.
3. `DetectionManager`/`PolicyManager` unregistered (already disposed via `SecurityManager`'s own cascade — only unregistration, not a second dispose, is needed).
4. `EventManager.dispose()` — closes its `StreamController`; then unregistered.
5. `NativeBridge.dispose()` — closes both channel services, clears callbacks; then unregistered.
6. State transitions to `stopped`. `ConfigurationManager`/`PermissionManager`/`LifecycleManager` are **deliberately not disposed or unregistered** here — they persist so a subsequent `reinitialize()` can reuse/update them without losing continuity.

### Dispose (full teardown)
`PluginInitializer.dispose()`: calls `shutdown()` if still `running`/`paused`; transitions state to `destroyed` (terminal — no way back per the frozen table); closes `DefaultSecurityStateManager`'s own `StreamController`; calls `container.reset()`, clearing every remaining registration (including the ones `shutdown()` deliberately left behind). `DeviceShield.dispose()` additionally nulls its own static `_container`/`_initializer` references, so the *next* `initialize()` call starts with a genuinely fresh container and initializer, not a reused one.

### Reinitialize
Semantically identical to `initialize()` — `reinitialize(config)` is a named alias, since the transition guard inside `initialize()` already permits restarting from both `stopped` and `failure`. A fresh `DetectionManager`/`PolicyManager`/`SecurityManager`/`LifecycleManager` are constructed (the previous ones were unregistered by `shutdown()`), so a detector registered before shutdown is **not** silently retained — verified directly by `test/api/device_shield_test.dart`'s "reinitialize restarts with fresh managers" test.

> **Note on step-numbering vs. the frozen documents:** `ARCHITECTURE_CONTRACTS.md` Part 3 describes a 10-step Init Matrix (steps 0/0b through 10) with `DetectionManager`/`PolicyManager`/`SecurityManager`/`LifecycleManager` as separately-numbered steps 6–9. The actual code (`plugin_initializer.dart`) uses 9 named steps (`Logger, Permission, Configuration, NativeBridge, EventManager, Registries, Managers, Lifecycle, Ready`), collapsing the frozen document's steps 6–8 into one `"Managers"` step. This is a naming/granularity difference only — the *order* and *content* match exactly; nothing is skipped or reordered.

---

## 8. Milestone Breakdown

Each milestone below reflects this report's own direct-code assessment, not a copy of `CURRENT_PROGRESS.md`'s 2026-07-24 figures — several have moved materially since then (called out explicitly where they have).

### M0 — Decisions & Repo Setup — **Partial, ~57%** (up from ~35%)
- **Purpose:** lock folder structure, channel naming, platform floors, and MVP scope before any downstream milestone builds on them.
- **Features implemented:** layer-first `lib/src/{api,bootstrap,bridge,config,core,detectors,events,managers,models,permission,platform,registry,state,utilities}` structure; channel naming decided and implemented exactly as specified (`device_shield/native_bridge`, `device_shield/events`, legacy `device_shield` kept separate); **platform floors are now resolved** — iOS `18.0` (`podspec` + `Package.swift`), Android `minSdk 21` — this is a change since `CURRENT_PROGRESS.md` (2026-07-24) found both still mismatched.
- **Files added/modified:** all of `lib/src/`, `android/build.gradle.kts`, `ios/device_shield.podspec`, `ios/device_shield/Package.swift`.
- **Architecture changes:** the legacy `lib/features/*` scaffold from `CURRENT_STATE.md`'s snapshot is entirely gone.
- **Tests added:** N/A (structural milestone).
- **Remaining work:** placeholder identifiers are still unresolved (`com.example.device_shield` throughout Android, podspec `homepage: http://example.com` / `author: 'Your Company'`, `pubspec.yaml`'s `description: "A new Flutter plugin project."` and empty `homepage:`); no `test/unit/`/`test/integration/`/`test/native/` split (tests live in `test/{module}/` instead); native package skeletons exist only partially (`detection/` on both platforms; `protection/`, `bridge/`, `utils/` do not exist on either); no written MVP-scope decision document.
- **Status:** Partial, blocking items resolved, cosmetic items open.
- **Dependencies:** none (this is the root).
- **Next milestone:** M1 (already substantially underway in parallel).

### M1 — Foundation Layer — **Partial, ~70%** (unchanged)
- **Purpose:** the zero-dependency base every later milestone imports from.
- **Features implemented:** `SDKState` (8 values, exact match to the frozen table), `DetectionStatus`, `EventSeverity`, `SecurityAction`, `DetectionResult`, `SecurityEvent` (both immutable/serializable/value-equal), the full exception hierarchy, `Logger`/`ConsoleLogger` with a working `LogSink` extension point.
- **Files added:** all of `lib/src/models/`, `lib/src/core/`.
- **Remaining work:** no `NativeResult` model; no `DataFilter` (sensitive-field redaction — `ConsoleLogger` does not screen `password`/`token`/`key`/`secret`/`authorization`/`credit_card`/`ssn`/`pin`); no `DetectionType`/`PinningMode`/`HookFramework`/`DataSubjectRequestType` enums (not yet needed by any built milestone).
- **Tests:** exercised indirectly throughout the suite; no dedicated `test/models/` or `test/core/` directory exists.
- **Status:** Partial — solid, stable, unchanged since the last audit.
- **Dependencies:** none.
- **Next milestone:** feeds every other milestone.

### M2 — Configuration & Dependency Injection — **Partial, ~55%** (unchanged)
- **Purpose:** configuration storage/validation and the DI container.
- **Features implemented:** `DeviceShieldConfig` (6 fields, `copyWith`/`toJson`/`fromJson`/equality); `DeviceShieldConfigValidator` (4 bounds, all enforced and tested); `ConfigurationManager`/`DefaultConfigurationManager` (correctly validation-free); `ServiceContainer` (fully implemented, exceeds spec).
- **Remaining work:** no `DeviceShieldConfigBuilder` fluent builder; no `ConfigurationPersistence` (SharedPreferences-backed save/load — `shared_preferences` isn't a declared dependency); no detection/protection sub-config fields on `DeviceShieldConfig` (deliberately deferred).
- **Status:** Partial.
- **Dependencies:** M1.
- **Next milestone:** M3.

### M3 — Native Bridge & Platform Channels — **Partial, ~68%** (up from ~62%)
- **Purpose:** the transport layer to native code.
- **Features implemented:** `MethodChannelService` (full timeout/error-translation logic), `EventChannelService` (listen/dispose/re-listen), `NativeBridge`/`DefaultNativeBridge` (callback routing by name, dispose), channel names locked in on both platforms, both `DeviceShieldPlugin` classes registering all three channels; **`checkEmulator` is now a real, working end-to-end bridge method** on both platforms (new since the last audit) — `method_codes.dart` now exists with that one constant.
- **Files added since last audit:** `bridge/method_codes.dart`, `android/.../detection/EmulatorDetector.kt`, `ios/.../Detection/EmulatorDetector.swift`.
- **Tests added:** `detector_factory_test.dart`, `emulator_detector_test.dart` (Dart), `EmulatorDetectorTest.kt` (5 tests), `EmulatorDetectorTests.swift` (2 tests).
- **Remaining work:** `method_codes.dart` has only one constant — every future detector/protection still needs its own; no Android manifest permissions declared (`AndroidManifest.xml` contains only the package declaration); no iOS `Info.plist` entries; no native `protection/`/`bridge/`/`utils/` subpackages on either platform.
- **Status:** Partial, meaningfully advanced.
- **Dependencies:** M1, M2.
- **Next milestone:** M4 (already built in parallel).

### M4 — Event System — **Partial, ~85%** (unchanged)
- **Purpose:** the event bus.
- **Features implemented:** `emit`/`subscribe` (with filter)/`getRecentEvents`/`clearHistory`/`pause`+`resume` (in-order flush)/`addProcessor` extension point/bounded FIFO history (default 100)/per-subscriber exception isolation.
- **Remaining work:** **no built-in dedup `EventProcessor`** — a real, still-open deviation from `ARCHITECTURE.md` §5's own pipeline diagram (see §17); `SecurityEventFilter` remains a bare predicate typedef, not the richer type/severity/source-matching component the frozen contract describes.
- **Status:** Partial — the one recurring, unresolved gap across two audits.
- **Dependencies:** M1.
- **Next milestone:** M5 (built in parallel).

### M5 — State Machine & SDK Lifecycle — **Completed, ~95%** (unchanged)
- **Purpose:** SDK status + Flutter lifecycle integration.
- **Features implemented:** the full 8-state transition table (exact match), illegal transitions throw `StateError` synchronously, broadcast via `StreamController`; the narrow `SecurityLifecycleHandler` 4-callback contract (resolving the documented `SecurityManager`↔`LifecycleManager` cycle); `DefaultLifecycleManager` (all 5 current `AppLifecycleState` values including `hidden`, attach/detach both idempotent).
- **Remaining work:** none structural.
- **Status:** the only milestone either audit calls essentially done.
- **Dependencies:** M1.
- **Next milestone:** M6.

### M6 — PluginInitializer, SecurityManager & Detector/Rule Framework — **Partial, ~90%** (up sharply from ~65%)
- **Purpose:** the single most important milestone per `ROADMAP.md`'s own framing — proves the whole framework holds with zero concrete detectors.
- **Features implemented:** `PluginInitializer` (idempotency guard, try/catch unwind, `shutdown`/`dispose`/`reinitialize`); `DefaultSecurityManager` (periodic timer, `checkNow()` pipeline, `pause`/`resume`, implements `SecurityLifecycleHandler`); `Detector`/`Rule` contracts; `DetectorRegistry`/`DefaultDetectorRegistry` (priority ordering, duplicate rejection); `PolicyManager`/`DefaultPolicyManager` (real `evaluate`/`addRule`/`removeRule`/`calculateRiskScore`); `DetectionManager`/`DefaultDetectionManager` (bounded concurrency, per-detector timeout, in-flight guard, optional cache — delivered ahead of its originally-planned M14 slot); **`PermissionManager` now fully exists and is wired into boot as step 2**; **`PluginInitializer` now constructs every service itself**, including `DetectionManager`/`PolicyManager`/`SecurityManager`/`LifecycleManager` — this closes **both** of `CURRENT_PROGRESS.md`'s (2026-07-24) two "High priority" findings (2.1(a) construction-scope contradiction, 2.1(b) missing `PermissionManager`) in full; `DetectorFactory` now also exists.
- **Files added since last audit:** `permission/permission_manager.dart`, `permission/default_permission_manager.dart`, `registry/detector_factory.dart`.
- **Tests added:** `test/permission/default_permission_manager_test.dart` (9 tests), `test/registry/detector_factory_test.dart` (5 tests); `plugin_initializer_test.dart` grew substantially (now 15 tests, up from an earlier smaller set) to cover the PermissionManager step and the "boots to running from an entirely empty container" case.
- **Remaining work:** `ShutdownSequence` still not factored into its own class (inlined in `shutdown()`/`_unwind()`); `executeAction()` is still entirely a log-only placeholder (expected — that's M9's job, not M6's).
- **Status:** Partial but now near-complete — the two structural contradictions this report's predecessor recommended resolving *before* M7 have, in fact, been resolved.
- **Dependencies:** M1–M5.
- **Next milestone:** M7 (already started).

### M7 — Priority-0 Detectors — **Partial (started), ~17%** (up from 0%)
- **Purpose:** root, jailbreak, emulator, debugger, runtime-hook, app-integrity detection.
- **Features implemented:** **emulator detection is complete, end-to-end, on both platforms** — `EmulatorDetector` (Dart shim), `EmulatorDetector.kt` (Android, 7-signal heuristic: fingerprint, model, manufacturer, hardware, product, brand+device, QEMU pipe presence, confidence = signals fired / 7), `EmulatorDetector.swift` (iOS, exact compile-time `targetEnvironment(simulator)` check, not heuristic).
- **Files added:** `lib/src/detectors/emulator_detector.dart`, `android/.../detection/EmulatorDetector.kt`, `ios/.../Detection/EmulatorDetector.swift`, plus the 4 corresponding test files.
- **Tests added:** 8 Dart tests, 5 Kotlin tests, 2 Swift tests — 15 total, all passing.
- **Remaining work:** root detection (Android), jailbreak detection (iOS), debugger detection (both), runtime-hook detection (both, Frida/Xposed/Substrate/Magisk), app-integrity (Play Integrity / DeviceCheck) — **5 of 6 P0 detectors, 0% each**.
- **Status:** genuinely started, 1/6 complete — the proof-of-pattern `ROADMAP.md` called for has landed.
- **Dependencies:** M6 (native package skeleton — only partially satisfied, see M0).
- **Next milestone:** the remaining 5 P0 detectors, then M8.

### M8 — Priority-1 Detectors — **Not started, 0%** (unchanged)
- Developer-options detection (Android), mock-location detection (both) — neither exists.
- **Dependencies:** M7's pattern.

### M9 — Policy Engine Content & Custom Rules — **Partial, ~15%** (unchanged)
- **Implemented:** the generic mechanism (`addRule`/`removeRule`, priority-ordered evaluation, risk-score calculation) — real, working, tested infrastructure.
- **Missing:** zero default `Rule` content for any detection type; zero `ActionHandler` implementations (the enum values exist, nothing executes them); no public `CustomRule` class; no 100-rule cap or circular-rule-dependency validation.
- **Dependencies:** M7 (detectors must exist to have rules for).

### M10 — Security Profiles — **Partial, ~25%** (unchanged)
- **Implemented:** `SecurityProfile`/`DetectionConfig`/`PolicyConfig`/`ProtectionConfig` — complete, immutable, serializable, equatable value classes.
- **Missing:** none of the five named factory presets (`fintech()`, `healthcare()`, `government()`, `enterprise()`, `consumer()`); no wiring anywhere accepts or applies a profile — `initialize()` takes only a `DeviceShieldConfig`.
- **Dependencies:** none blocking (model is done); wiring blocked on product decisions about default detector/rule sets per profile.

### M11 — Protections — **Not started, 0%** (unchanged)
- Screenshot protection, screen-recording detection, overlay detection, clipboard protection, SSL/certificate pinning — none exist, Dart or native, either platform.
- **Dependencies:** M2, M3 (both already satisfied) — could start in parallel with M7/M8 any time.

### M12 — Public API & UI Components — **Partial, ~52%** (unchanged in scope, verified still accurate)
- **Implemented:** the `DeviceShield` static facade — `initialize`, `status`, `pause`, `resume`, `checkNow`, `shutdown`, `reinitialize`, `dispose`, `registerDetector`, `addRule`, `removeRule`, `registerCallback`/`unregisterCallback`, `subscribe`; legacy `getPlatformVersion()` preserved unchanged.
- **Missing:** `DeviceShieldWidget`, `SecurityAlertDialog`, `ScreenshotProtection` widget — none exist; no `profile` property/parameter; **the public export barrel (`lib/device_shield.dart`) still only exports `src/api/device_shield.dart`** — `Detector`, `Rule`, `SecurityEvent`, `DetectionResult`, `DeviceShieldConfig`, and the exception types are not re-exported, confirmed unchanged by direct reading of the 1-line barrel file.
- **Dependencies:** M9/M10 for alert content, M11 for the protection widget.

### M13 — Storage, Encryption & Security Utilities — **Not started, 0%** (unchanged)
- `SecureStorage`, `EncryptionUtils`, `KeyManager`, `IntegrityValidator`, `DataProtection` — none exist; `flutter_secure_storage` not a declared dependency.

### M14 — Performance & Caching — **Partial, ~35%** (unchanged)
- **Implemented:** `MultiLevelCache`/`CacheLevel`/`MemoryCacheLevel` (fully generic, TTL-based, LRU-evicting, promotion-on-hit, proactive `clearExpired` sweep); `DetectionCache` delegates to it; bounded concurrency (`ConcurrencyController`) already delivered as part of M6.
- **Missing:** `PerformanceMonitor` does not exist; no automated benchmark suite (no `test/performance/` directory); none of the SRS's §13.1 targets have ever been measured.

### M15 — Compliance Packs — **Not started, 0%** (unchanged)
- `GDPRCompliance`, `PCIDSSCompliance`, `HIPAACompliance` — none exist.

### M16 — Internationalization — **Not started, 0%** (unchanged)
- No `DeviceShieldLocalization`/`getLocalizedMessage()` (and no `SecurityAlertDialog` yet for it to localize).

### M17 — Logging & Error-Handling Hardening — **Partial, ~10%** (unchanged)
- **Implemented:** ad hoc error translation inside `MethodChannelService`; `PluginInitializer` unwinds cleanly on failure.
- **Missing:** `ProductionLogger`, `RecoveryStrategy`, `RetryLogic` — none exist; no configurable backoff/retry mechanism anywhere; no per-error-code recovery dispatch table wired into any manager's catch blocks.

### M18 — Testing Across All Modules — **Partial, ~40%** (up from ~38%)
- **Implemented:** **202 tests** (up from 177 at the last audit) across every implemented module, all passing; `flutter analyze` clean.
- **Missing:** no `test/unit/`/`test/integration/`/`test/native/` directory split; no performance tests; coverage percentage never measured (`flutter test --coverage` not run for this report either — the §16.5 targets remain unverified, not merely unmet); zero real-device validation (impossible until root/jailbreak/hook detectors exist).

### M19 — Documentation & Developer Experience — **Not started, 0%** (unchanged, re-verified)
- `example/lib/main.dart` confirmed **still** the default Flutter counter-app template — directly re-read for this report, unchanged. `README.md` confirmed still default boilerplate. No `DevelopmentTools`, no integration guide, no `DocGenerator`.

### M20 — Versioning & Deployment — **Not started, 0%** (unchanged, re-verified)
- No `.github/` directory at all (confirmed by direct filesystem check for this report). `CHANGELOG.md` still reads `## 0.0.1 \n * TODO: Describe initial release.` verbatim. `pubspec.yaml` version still `0.0.1`, `description` still the `flutter create` default, `homepage:` still blank.

### M21 — Edge Case & Resilience Hardening — **Not started, 0%** (unchanged)
- No `test/edge_cases/` directory; none of §26.1's ten named scenarios has a dedicated test.

### M22 — v1.0 Release — **Not started, 0%** (unchanged)
- Blocked on every milestone above; no release has ever been tagged or prepared; no git repository even exists at the current working directory (`git status` returns "not a git repository" — versioning is currently untracked entirely).

---

## 9. Detailed Component Documentation

This section adds cross-cutting integration detail on top of §4's per-file entries — it does not repeat what's already documented there.

**Logger** — the only component every other manager takes a hard, non-optional constructor dependency on (except `EventManager`, the one deliberate leaf). Boots *before* `ConfigurationManager` (step 1 vs. step 3) with a safe default level, so log output exists even if configuration itself fails to validate. `ConsoleLogger`'s documented "soft, one-time read of `ConfigurationManager`" (to pick up `debugLogging`) is **not actually implemented** — verified directly: `ConsoleLogger` has zero `ConfigurationManager` import or reference anywhere. This is a harmless simplification (not a cycle risk, since the edge never existed to begin with) but a real, checkable gap versus the frozen contract's own description.

**ConfigurationManager** — the only manager whose instance deliberately survives a shutdown/reinitialize cycle. Every other manager (`DetectionManager`, `PolicyManager`, `SecurityManager`, `EventManager`, `NativeBridge`) is disposed-and-unregistered on `shutdown()`; `ConfigurationManager` and `PermissionManager`/`LifecycleManager` are not, by explicit design (`plugin_initializer.dart`'s own `shutdown()` doc comment).

**LifecycleManager** — the only component in the codebase that touches `WidgetsBinding` — its own doc comment is explicit that it "never constructs a `SecurityEvent`, never references `EventManager`, never calls `NativeBridge`." This boundary is verified, not just claimed: `default_lifecycle_manager.dart` has zero imports beyond `flutter/widgets.dart` and its own `lifecycle.dart`.

**SecurityManager** — the single mediator every public write-path call reaches. Notably: it drives event emission for *every* detection result unconditionally (no confidence gate is actually implemented in code, despite `ARCHITECTURE.md` §4's diagram depicting one) — every `checkNow()` cycle emits one event per detector, regardless of `detected`/`confidence`.

**DetectionManager** — the most feature-complete manager relative to its own frozen scope; already includes concurrency bounding and caching that `ROADMAP.md` originally scheduled for M14, a genuine "ahead of schedule" delivery documented directly in the class's own comments.

**PolicyManager** — structurally complete, content-empty. `evaluate()`'s fallback to `SecurityAction.ignore` when nothing matches means that, **today, calling `checkNow()` with a detector that reports `detected: true` still results in `SecurityAction.ignore`** unless a host app has manually registered a matching `Rule` — there is no built-in rule content of any kind.

**EventManager** — the frozen architecture's proof that "depends on nothing structurally" is achievable; verified by its own import list (`dart:async`, `models/security_event.dart` only).

**DetectorRegistry** — private to `DetectionManager` by convention (constructor-injected, never resolved independently by anything else) even though `ServiceContainer` technically permits any code with container access to resolve it — an enforcement-by-convention gap, not a hard boundary (see §17).

**ServiceContainer** — the one piece of infrastructure explicitly documented (and tested) to have an independent lifecycle from `PluginInitializer` — "Architecture Correction 1."

**PluginInitializer** — see §4/§7 for full detail; the single largest and most-responsibility-bearing file in the codebase (501 lines), but decomposed into ~12 narrowly-named private methods, each handling exactly one service's resolve-or-default logic.

**NativeBridge** — the sole path to native code; its `dispose()` method was itself added via a documented "architecture correction" resolving a contradiction between the original contract (no `dispose()`) and the shutdown-order table requiring it — verified present and tested (`default_native_bridge_test.dart`'s dispose group).

**MethodChannelService / EventChannelService** — both scoped exclusively to `NativeBridge`, verified by grep: no other file in `lib/src/` imports either class.

**ConcurrencyController** — the one class in `managers/` with zero SDK-specific types anywhere in its signature (`run<T, R>`) — fully reusable outside this SDK's own domain.

**DetectionCache** — opt-in, not defaulted anywhere in the current boot sequence; `PluginInitializer` never constructs one, meaning **caching is off by default** in the running SDK today unless a caller manually composes `DefaultDetectionManager` with one.

**DeviceShield API** — see §4's entry; the one place two different "shapes" coexist deliberately (an instance method for the legacy call, a fully static surface for everything else).

**Platform layer (legacy)** — `DeviceShieldPlatform`/`MethodChannelDeviceShield` — entirely disconnected from the Bridge architecture; kept only for `getPlatformVersion()` backward compatibility.

**Models** — see §4; all leaf, dependency-free, hand-serialized (no `json_serializable`/code-gen anywhere in `pubspec.yaml`).

**Exceptions** — a flat, one-level hierarchy (`DeviceShieldException` base + 6 direct subtypes) — no further specialization exists (e.g., no `RootDetectionException` extending `DetectionException`).

---

## 10. Test Documentation

### Current Tests
**202 tests, 22 files, 100% passing** (verified for this report via `flutter test`). Per-file counts:

| File | Tests |
|---|---|
| `test/managers/default_detection_manager_test.dart` | 23 |
| `test/registry/default_detector_registry_test.dart` | 21 |
| `test/bootstrap/plugin_initializer_test.dart` | 15 |
| `test/api/device_shield_test.dart` | 14 |
| `test/managers/multi_level_cache_test.dart` | 14 |
| `test/managers/detection_cache_test.dart` | 13 |
| `test/managers/concurrency_controller_test.dart` | 12 |
| `test/bootstrap/service_container_test.dart` | 10 |
| `test/bridge/method_channel_service_test.dart` | 10 |
| `test/permission/default_permission_manager_test.dart` | 9 |
| `test/bridge/default_native_bridge_test.dart` | 8 |
| `test/managers/default_policy_manager_test.dart` | 8 |
| `test/detectors/emulator_detector_test.dart` | 8 |
| `test/config/device_shield_config_validator_test.dart` | 7 |
| `test/events/default_event_manager_test.dart` | 7 |
| `test/bridge/event_channel_service_test.dart` | 6 |
| `test/managers/default_security_manager_test.dart` | 5 |
| `test/registry/detector_factory_test.dart` | 5 |
| `test/state/default_lifecycle_manager_test.dart` | 3 |
| `test/device_shield_test.dart` | 2 |
| `test/device_shield_method_channel_test.dart` | 1 |
| `test/bootstrap/phase5_managers_integration_test.dart` | 1 |

### Coverage
**No `flutter test --coverage` run has ever been captured for this project**, as far as this review can confirm — neither the last audit nor this one ran it. The SRS-derived §16.5 per-module coverage targets (Core 90%, Detection Manager 85%, Policy Engine 85%, Event System 85%, Native Bridge 80%, Detectors 80%, Protections 75%) are **unverified**, not merely unmet. This report does not estimate a percentage, to avoid presenting a guess as a fact.

### Mock Strategy
- **Dart tests:** almost entirely hand-written fakes (`_FakeDetector`, `_FakeRule`, `_FakeNativeBridge`, `_FakeEventManager`, `_FakeSecurityManager`, `_FakeLifecycleManager`, `_FakePermissionManager`, `_ThrowingPermissionManager`, `_ControllableDetector`) implementing the real interfaces directly — no mocking framework (e.g. `mockito` for Dart) is used anywhere in `test/`.
- **Channel-level tests** use Flutter's own `TestDefaultBinaryMessengerBinding` + `setMockMethodCallHandler`/`setMockStreamHandler`/`MockStreamHandler.inline` — the standard, real Flutter-SDK-provided test surface, not a third-party mock.
- **Android (Kotlin):** uses real Mockito (`org.mockito:mockito-core:5.14.2`, bumped from `5.0.0` per `CURRENT_PROGRESS.md`'s note to resolve a JDK 21/ByteBuddy incompatibility — a test-tooling fix, not a production dependency change).
- **iOS (Swift):** plain `XCTest`, no mocking library — `@testable import device_shield` with direct construction and `expectation`-based async assertions.

### Integration Tests
- `test/bootstrap/plugin_initializer_test.dart` functions as the primary integration suite — exercises the full boot→running→shutdown→reinitialize→dispose cycle against a real `ServiceContainer`, with a mix of pre-registered fakes and framework-defaulted real services.
- `test/bootstrap/phase5_managers_integration_test.dart` (1 test) specifically proves the real Phase 5 managers and Phase 6 `DetectorRegistry` wire correctly through `PluginInitializer` end-to-end, including a real `DefaultNativeBridge` (registered but never invoked, since nothing in that test calls a channel method).
- `test/api/device_shield_test.dart` is effectively a black-box integration suite for the public facade, driving real detector registration → `checkNow()` → event delivery through the entire stack.
- No dedicated `integration_test/` directory exists at the package root (only `example/integration_test/plugin_integration_test.dart`, which is still the default, unmodified template).

### Platform Tests
- **Android:** 9 Kotlin tests total (4 in `DeviceShieldPluginTest.kt` covering the legacy path + notImplemented + `sendEvent`/`onListen`/`onCancel`/`onDetachedFromEngine`, plus the actual count is: `DeviceShieldPluginTest.kt` has 9 `@Test` methods, `EmulatorDetectorTest.kt` has 5 `@Test` methods — 14 total Kotlin tests). Confirmed runnable via Gradle (per prior documented work; not re-executed for this report).
- **iOS:** `DeviceShieldPluginTests.swift` (7 test methods) + `EmulatorDetectorTests.swift` (2 test methods) — 9 total Swift XCTest methods. **Cannot currently execute in a bare checkout** — `swift build`/`swift test` requires `../FlutterFramework`, a local SwiftPM package Flutter's own iOS build tooling generates, which does not exist outside a full Flutter iOS build context. This is a documented environment limitation, not a defect in the test code (re-confirmed for this report by checking `ios/device_shield/Package.swift`'s dependency on `path: "../FlutterFramework"`, which does not exist in this checkout).

### What Is Validated
State machine transition legality (every edge and every non-edge); DI container registration modes and circular-dependency detection; the full boot/shutdown/reinitialize/dispose cycle including config-persistence-across-reinit and fresh-manager-construction-after-shutdown; bounded concurrency (parallelism, ordering, timeout, exception isolation, dispose-during-run cancellation); TTL+LRU cache correctness (hit/miss/expiry/eviction/promotion); event pub-sub (filtering, pause/resume queuing, subscriber isolation, processor chain); detector registry priority ordering and duplicate rejection; native bridge error-code translation for every documented failure mode; one real detector's full behavior including its native heuristics on both platforms.

### Missing Tests
- No coverage measurement of any kind.
- No performance/benchmark tests (`test/performance/` doesn't exist).
- No `test/edge_cases/` covering the SRS's §26.1 resilience scenarios.
- No dedicated model-level test file for `DeviceShieldConfig`/`SecurityEvent`/`DetectionResult`/`SecurityProfile` (`toJson`/`fromJson`/equality) — only indirectly exercised elsewhere.
- No dedicated `Logger`/`ConsoleLogger` test file.
- No real-device (rooted/jailbroken) validation — impossible today, since no root/jailbreak detector exists yet.
- No widget tests (no widgets exist to test — `DeviceShieldWidget` etc. are all unbuilt).

### Future Tests (implied by remaining work)
One test suite per remaining P0/P1 detector, following `emulator_detector_test.dart`'s pattern; `Rule`/`ActionHandler` content tests once M9 has real rules; a benchmark suite once M14's `PerformanceMonitor` exists; an edge-case suite for M21.

---

## 11. Platform Layer

### Android
`android/src/main/kotlin/com/example/device_shield/DeviceShieldPlugin.kt` implements `FlutterPlugin`, `MethodChannelHandler`, and `EventChannel.StreamHandler` in one class. `onAttachedToEngine` constructs and registers all three channels: the legacy `device_shield` channel, the bridge `device_shield/native_bridge` `MethodChannel`, and the bridge `device_shield/events` `EventChannel`. `onMethodCall` dispatches on `call.method`: `"getPlatformVersion"` → `"Android ${Build.VERSION.RELEASE}"`; `"checkEmulator"` → `EmulatorDetector.check()`'s result map; anything else → `result.notImplemented()`. `sendEvent(callback, data)` is the outbound half of the callback-routing contract `DefaultNativeBridge` implements on the Dart side — shapes a `{"callback": ..., "data": ...}` map and pushes it through the currently-held `EventChannel.EventSink`, a no-op if nothing is listening. `onDetachedFromEngine` unregisters all three channel handlers and clears the event sink.

`android/.../detection/EmulatorDetector.kt` is a Kotlin `object` (no state) exposing `check(): Map<String, Any>`. Its decision logic is deliberately factored into an internal, pure `evaluate(...)` function taking every `Build.*` field as a parameter — this lets `EmulatorDetectorTest.kt` exercise every branch with synthetic inputs without Robolectric, since `android.os.Build`'s real fields are static and effectively unmockable in a plain JVM unit test. Seven independent signal categories (fingerprint, model, manufacturer, hardware, product, brand+device combined, QEMU pipe file existence); confidence = fired-signal-count / 7.0, capped at 1.0.

### iOS
`ios/device_shield/Sources/device_shield/DeviceShieldPlugin.swift` implements `FlutterPlugin` and `FlutterStreamHandler`. The static `register(with:)` factory method constructs the plugin instance and all three channels via `registrar.messenger()`, functionally mirroring Android's `onAttachedToEngine`. `handle(_:result:)` dispatches identically to Android's `onMethodCall` (`getPlatformVersion` → `"iOS " + UIDevice.current.systemVersion`; `checkEmulator` → `EmulatorDetector.check()`; else → `FlutterMethodNotImplemented`). `sendEvent` mirrors Android's helper exactly (`nil` data forwarded as `NSNull()`). `detachFromEngine(for:)` tears down both bridge channels and clears the event sink — the Android/iOS cleanup behavior is verified functionally identical by direct comparison of both files.

`ios/.../Detection/EmulatorDetector.swift` is a Swift `enum` (no cases — used purely as a namespace) exposing `static func check() -> [String: Any]`. Unlike Android's heuristic scoring, iOS uses a compile-time `#if targetEnvironment(simulator)` directive — an exact, Apple-provided signal, not a weighted heuristic — reporting full confidence (`1.0`) when compiled for the Simulator target, zero otherwise.

### MethodChannel
Both platforms use the identical two-channel naming scheme: legacy `device_shield` (Phase 1) and bridge `device_shield/native_bridge`. Every `invoke()` from Dart is marshaled by the Flutter engine onto the platform's native thread, dispatched synchronously into `onMethodCall`/`handle(_:result:)`, and the `result`/`FlutterResult` callback marshals the response back.

### EventChannel
Both platforms use `device_shield/events`. `onListen`/`onCancel` (Android) and `onListen(withArguments:eventSink:)`/`onCancel(withArguments:)` (iOS) capture/release the sink reference; `sendEvent` on both platforms is the only thing that ever writes to it, and both correctly no-op rather than crash when no sink is currently registered (verified by dedicated tests on both platforms: `sendEvent_withNoActiveListener_isANoOpRatherThanThrowing` / `testSendEventWithNoActiveListenerIsANoOpRatherThanCrashing`).

### NativeBridge (Dart-side integration)
`DefaultNativeBridge` is the sole consumer of both native channels from the Dart side. It never inspects native-pushed event *content* beyond the `{'callback': ..., 'data': ...}` routing envelope — matching both native implementations' payload shape exactly, verified end-to-end by `default_native_bridge_test.dart`'s callback-routing test group.

### Event Flow (native → Dart)
Native code calls `sendEvent(callback, data)` → `EventChannel.EventSink.success({"callback": name, "data": data})` → Flutter engine delivers to the Dart `EventChannelService.events` broadcast stream → `DefaultNativeBridge._routeNativeEvent` parses the `callback` key → dispatches to whatever handler was registered via `NativeBridge.registerCallback(name, handler)`. **No detector or protection currently calls `sendEvent`** — the transport is proven, but nothing yet uses it for a real push (all current native-Dart communication is request/response via `checkEmulator`).

### Method Invocation Flow (Dart → native)
`EmulatorDetector.check()` → `NativeBridge.invoke<Map>(method: MethodCodes.checkEmulator)` → `DefaultNativeBridge.invoke()` → `MethodChannelService.invoke()` → `MethodChannel.invokeMethod('checkEmulator', null).timeout(5s)` → native `onMethodCall`/`handle` → `EmulatorDetector.check()` (native) → response marshaled back → typed as `Map<Object?, Object?>` → shaped into a `DetectionResult` by the Dart `EmulatorDetector`.

### Lifecycle
Both plugins' registration (`onAttachedToEngine`/`register(with:)`) and teardown (`onDetachedFromEngine`/`detachFromEngine(for:)`) are driven entirely by the Flutter engine's own plugin lifecycle — independent of, and unrelated to, the Dart-side `SDKState` machine. A plugin instance can be attached to an engine well before `DeviceShield.initialize()` is ever called, and remains attached across an `SDKState` `stopped`/`running` cycle.

---

## 12. Sequence Diagrams

### Initialization
```
App          DeviceShield      PluginInitializer     ServiceContainer      Services
 │  initialize(config) │                   │                    │                │
 │─────────────────────►│                   │                    │                │
 │                       │ init(config)      │                    │                │
 │                       │──────────────────►│ validate(config)   │                │
 │                       │                   │────────────────────────────────────►│ (Validator)
 │                       │                   │ resolveOrRegister x9 (Logger …       │
 │                       │                   │  Lifecycle), each initialize()-d     │
 │                       │                   │──────────────────►│───────────────►│
 │                       │                   │ emit('initialized')                 │
 │                       │                   │─────────────────────────────────────►│ (EventManager)
 │                       │◄──────────────────│ state = running                     │
 │◄─────────────────────│                   │                    │                │
```

### Detection Flow
```
Timer/checkNow()   SecurityManager   DetectionManager   ConcurrencyController   Detector(s)   NativeBridge
      │───────────────►│                   │                     │                  │              │
      │                │ runAllChecks()    │                     │                  │              │
      │                │──────────────────►│ in-flight guard      │                  │              │
      │                │                   │─────────────────────►│ run(items, task) │              │
      │                │                   │                     │─────────────────►│ check()      │
      │                │                   │                     │                  │─────────────►│ invoke()
      │                │                   │                     │                  │◄─────────────│ result
      │                │                   │                     │◄─────────────────│ DetectionResult
      │                │                   │◄─────────────────────│ ordered results  │              │
      │                │◄──────────────────│ List<DetectionResult>│                  │              │
```

### Policy Evaluation
```
SecurityManager        PolicyManager          Rule(s)
      │  evaluate(result)   │                      │
      │─────────────────────►│ sorted by priority    │
      │                      │──────────────────────►│ matches(result)?
      │                      │◄──────────────────────│ true/false/throws→false
      │                      │  (first match wins)   │
      │◄─────────────────────│ SecurityAction        │
      │  executeAction(action, result)                │
      │─────────────────────►│ (placeholder: log only)│
```

### Bridge Communication
```
Detector       NativeBridge      MethodChannelService      MethodChannel(engine)      Native Plugin
   │  invoke()      │                    │                        │                       │
   │───────────────►│  invoke()          │                        │                       │
   │                │───────────────────►│ invokeMethod().timeout()│                       │
   │                │                    │───────────────────────►│ marshal → platform thread│
   │                │                    │                        │──────────────────────►│ onMethodCall/handle
   │                │                    │                        │◄──────────────────────│ result
   │                │                    │◄───────────────────────│                        │
   │                │◄───────────────────│ typed T or Exception    │                       │
   │◄───────────────│                    │                        │                       │
```

### Native Callback (event push — transport proven, unused by any current feature)
```
Native Plugin        EventChannel(engine)      EventChannelService      DefaultNativeBridge      Registered callback
    │  sendEvent(name, data)   │                        │                       │                        │
    │─────────────────────────►│ EventSink.success(map)  │                       │                        │
    │                          │─────────────────────────►│ forwarded unchanged   │                        │
    │                          │                          │──────────────────────►│ _routeNativeEvent(raw) │
    │                          │                          │                       │ dispatch by 'callback' │
    │                          │                          │                       │────────────────────────►│ callback(data)
```

### Shutdown
```
DeviceShield      PluginInitializer      LifecycleManager   SecurityManager   DetectionManager/PolicyManager   EventManager   NativeBridge
     │  shutdown()      │                        │                  │                    │                          │              │
     │─────────────────►│ detach()                │                  │                    │                          │              │
     │                  │────────────────────────►│                  │                    │                          │              │
     │                  │ dispose() + unregister   │                  │                    │                          │              │
     │                  │─────────────────────────────────────────────►│ dispose() (cascades)│                          │              │
     │                  │                          │                  │───────────────────►│                          │              │
     │                  │ dispose() + unregister    │                  │                    │                          │              │
     │                  │──────────────────────────────────────────────────────────────────────────────────────────►│              │
     │                  │ dispose() + unregister                                                                                     │
     │                  │────────────────────────────────────────────────────────────────────────────────────────────────────────►│
     │                  │ state → stopped           │                  │                    │                          │              │
     │◄─────────────────│                          │                  │                    │                          │              │
```

---

## 13. Design Patterns Used

| Pattern | Where | How |
|---|---|---|
| **Dependency Injection** | `ServiceContainer`, every manager's constructor | Constructor injection exclusively — no manager reaches into the container to resolve its own dependencies internally (verified across all 5 managers). |
| **Factory** | `DetectorFactory` | `String`-keyed constructor-function map, not a closed-enum switch — deliberately, to preserve `Detector.type`'s open-identifier design. |
| **Registry** | `Registry<T>` → `DetectorRegistry`/`DefaultDetectorRegistry` | Generic base + domain-specific priority-ordering/duplicate-prevention subtype. |
| **Strategy** | `Detector`, `Rule`, `NativeBridge`, `CacheLevel` | Every one of these is a narrow interface the framework programs against, with concrete implementations swapped in without the framework's own code changing. |
| **Observer** | `EventManager` (pub/sub), `LogSink` (fan-out), `WidgetsBindingObserver` (`DefaultLifecycleManager`), `SecurityLifecycleHandler` (narrow callback observer) | Four distinct applications of the same underlying pattern, at four different layers. |
| **Singleton (per-SDK-lifetime)** | Every service registered via `ServiceContainer.registerSingleton`/`registerLazySingleton` | Not a classic static-global singleton — scoped to one `ServiceContainer` instance, allowing multiple independent SDK "sessions" in theory (never exercised, since `DeviceShield` itself holds one static container). |
| **Composition (Composite-ish)** | `DefaultSecurityManager` composing `DetectionManager`+`PolicyManager`+`EventManager` | `SecurityManager` is a pure coordinator holding references to, never subclassing, its collaborators. |
| **Facade** | `DeviceShield` | Single static entry point hiding `PluginInitializer`/`ServiceContainer`/every manager from the host app entirely. |
| **Bridge (structural)** | `NativeBridge` module (`bridge/`) | Decouples the Dart-side abstraction (`invoke`/`registerCallback`) from the platform-channel implementation — literally the pattern this module is named after. |
| **Adapter** | `MethodChannelService`, `EventChannelService`, `EmulatorDetector` (Dart shim), `MethodChannelDeviceShield` | Each wraps a lower-level API (Flutter's raw channels, or a native heuristic response) into the SDK's own typed vocabulary. |
| **State** | `SDKState` (enum) + `DefaultSecurityStateManager` (context/machine) | Classic State pattern split across a pure-data enum and a single-writer machine enforcing the transition table. |
| **Chain of Responsibility** | `PolicyManager.evaluate()` (priority-ordered rule scan, first match wins), `EventManager`'s `_processors` chain | Both stop at the first success/apply-in-sequence shape. |
| **Decorator** | `_checkWithCache` in `DefaultDetectionManager` (wraps raw `Detector.check()` with cache-aside behavior), `MultiLevelCache` (wraps `CacheLevel`s with TTL) | Adds behavior around an existing call without changing its interface. |
| **Worker Pool / Bounded Producer-Consumer** | `ConcurrencyController` | Generic, SDK-agnostic bounded-parallel task runner. |
| **LRU Cache** | `MemoryCacheLevel` | Classic `LinkedHashMap`-based recency tracking + capacity eviction. |
| **Multi-Level Cache** | `MultiLevelCache` | Promotion-on-hit across ordered tiers, currently exercised with one tier. |
| **Circuit-breaker-adjacent (honest failure, not silent success)** | `DefaultPermissionManager` | Throws `UnimplementedError` for anything it can't genuinely fulfill, rather than fabricating a granted permission. |

---

## 14. SOLID Analysis

For every major class, evaluated against direct code reading (not the frozen documents' claims about themselves).

| Class | SRP | OCP | LSP | ISP | DIP |
|---|---|---|---|---|---|
| `ServiceContainer` | ✅ one job: type-keyed lookup | ✅ 3 registration modes, extensible without editing existing ones | N/A (not polymorphic itself) | ✅ | N/A (the DI mechanism itself) |
| `PluginInitializer` | ✅ (decomposed into ~12 single-purpose private methods despite 501 total lines) | ✅ new defaultable service = new private method, no edits to existing ones | N/A | N/A | ✅ depends on every service's abstract contract; concrete types named only inside each service's own default-construction method |
| `DefaultSecurityManager` | ✅ coordination only | ⚠ hardcoded `EventSeverity.info` for every emission — a policy-adjacent decision baked in, not configurable | ✅ substitutable behind `SecurityManager` | ✅ | ✅ depends on 3 manager interfaces + `ConfigurationManager`/`Lifecycle`/`Logger`, never a concrete class |
| `DefaultDetectionManager` | ✅ delegates storage (registry), concurrency (controller), caching (cache) — doesn't reimplement any of them | ✅ | ✅ | ✅ | ✅ |
| `DefaultPolicyManager` | ✅ (though currently near-empty of actual policy *content*, which is out of scope, not a violation) | ✅ `Rule`/`ActionHandler` extension points ready, unused | ✅ | ✅ | ✅ |
| `DefaultEventManager` | ✅ | ✅ `EventProcessor` chain is real and generic | ✅ | ✅ | ✅ (zero structural dependencies — the frozen architecture's own proof case) |
| `DefaultDetectorRegistry` | ✅ | ✅ | ✅ | ✅ | ✅ depends on `Detector` contract only |
| `DetectorFactory` | ✅ | ✅ registration-map, one `_register()` call per new built-in | N/A | ✅ | ✅ constructs against `Detector` return type, `NativeBridge` interface |
| `DefaultNativeBridge` | ✅ pure transport | ✅ | ✅ substitutable behind `NativeBridge` | ✅ | ✅ |
| `DefaultConfigurationManager` | ✅ (explicitly narrowed by "Architecture Correction 2" — validation removed) | ✅ | ✅ | ✅ | ✅ |
| `DefaultSecurityStateManager` | ✅ pure state machine | ✅ (though the transition table is frozen by design — "extensibility" here means adding a state, not swapping behavior) | ✅ | ✅ | ✅ |
| `DefaultLifecycleManager` | ✅ | N/A | ✅ | ✅ | ✅ depends on the narrow `SecurityLifecycleHandler` contract, never `SecurityManager` concretely — the resolved circular-dependency fix |
| `ConcurrencyController` | ✅ | ✅ generic over `<T, R>` | N/A | ✅ | N/A (infrastructure, not swapped) |
| `MultiLevelCache` | ✅ | ✅ pluggable `levels` list | ✅ | ✅ | ✅ depends on `CacheLevel` abstraction |
| `EmulatorDetector` | ✅ thin shim, all technique logic native | N/A (a leaf instance, not extended) | ✅ fully substitutable behind `Detector` | ✅ | ✅ depends on `NativeBridge` interface |
| `DeviceShield` (facade) | ✅ delegation only | ✅ new capability = new delegating static method | N/A | ⚠ one large class covering the whole public surface — arguably a fat interface by definition of being *the* facade, though each method individually is narrow and this is the documented, intentional shape of a facade | ✅ resolves everything through `ServiceContainer.resolve<T>()` against abstractions |

**Overall verdict:** SOLID holds cleanly through the framework layer. The one class worth flagging on ISP grounds (`DeviceShield`) is a facade by design — a large surface is the *point* of a facade, so this is not treated as a defect. The one class worth flagging on SRP/hardcoded-decision grounds (`DefaultSecurityManager`'s constant `EventSeverity.info`) is a documented, deliberate scope limitation (severity assignment is explicitly deferred as "a policy-adjacent decision... out of scope for this phase"), not an oversight.

---

## 15. Current Progress Analysis

### What Is Fully Complete
The dependency-injection container (`ServiceContainer`), the entire state machine (`SecurityStateManager`/`Lifecycle`), the event bus mechanism (`EventManager`, minus the built-in dedup stage), the boot/shutdown/reinitialize/dispose sequencing (`PluginInitializer`), bounded concurrent detector execution (`ConcurrencyController`), the generic TTL+LRU cache stack (`MultiLevelCache`/`CacheLevel`/`MemoryCacheLevel`/`DetectionCache`), the model/exception layer, the native bridge transport (`NativeBridge`/`MethodChannelService`/`EventChannelService`), OS permission tracking (`PermissionManager`, honest about what it can't yet do), the detector/rule extension contracts themselves (`Detector`/`Rule`), and one real, cross-platform, fully-tested built-in detector (`EmulatorDetector`).

### What Is Partially Complete
The manager orchestration layer runs correctly but two of its four managers (`PolicyManager`, and by extension `SecurityManager`'s downstream behavior) have real mechanism and zero content; `DetectorFactory` exists but is disconnected from boot; `SecurityProfile` is a complete model with no wiring; the public API is functionally rich but its export barrel is incomplete; the native platform layer has full transport parity but only one detector's worth of feature parity; testing is extensive in raw count (202) but has never been measured for coverage and has no performance/edge-case suites.

### What Is Missing
Every detector beyond emulator (5 of 6 P0, both P1); every protection (5 of 5); all policy content (default rules, action handlers, `CustomRule`); all five `SecurityProfile` factory presets and any wiring of `profile` into `initialize()`; storage/encryption utilities; compliance packs; internationalization; the widget layer (`DeviceShieldWidget`, `SecurityAlertDialog`, `ScreenshotProtection`); production logging/recovery/retry infrastructure; a rewritten example app and README; CI/CD; a version-controlled repository at all (confirmed: this directory is not a git repository).

### Technical Debt
- No coverage measurement has ever been taken — the §16.5 targets are aspirational, not verified.
- `pubspec.yaml`/native manifests still carry `flutter create` template placeholders this far into the project (package name, homepage, description, author).
- `CHANGELOG.md` still contains its literal `TODO` template text.
- No CI/CD pipeline exists — every check performed (this report's `flutter analyze`/`flutter test` included) has been run manually.
- `method_codes.dart` has exactly one constant — the "single source of truth" it's meant to be will need real discipline to maintain once 6+ more detectors each add their own bridge method.
- `DetectorFactory` is fully built and tested but entirely dead from a production-boot-path perspective — a real but low-severity form of unreachable-in-practice code (see §17).

### Architecture Risks
- The `PolicyManager` placeholder-decision behavior (`evaluate()` → `SecurityAction.ignore` unless a host app manually adds a matching rule) means **the SDK currently produces zero actionable security outcomes even when a detector correctly reports a threat** — this is an expected, documented gap for this phase, but it is the single biggest gap standing between "a well-tested skeleton" and "a security product."
- Root/jailbreak/hook detection is inherently the kind of code that can pass every mocked unit test while still being wrong on real hardware — zero real-device validation exists yet, and can't until those detectors are built.
- The public barrel-export gap (§4, `lib/device_shield.dart`) means FR-17/FR-18 (custom rules/detectors) are not actually usable by a host app through the *documented* public API today, only by reaching into `package:device_shield/src/...` directly.

### Known Limitations
- The iOS native test suite cannot execute in a bare checkout (missing `../FlutterFramework` local SwiftPM package) — an environment limitation of this specific working copy, not a defect in the test code.
- No SRS document exists in this repository — every SRS-derived requirement cited throughout the frozen documents (and, by extension, this report) is one level removed from its actual source text.
- This repository is not a git repository (confirmed directly) — there is no commit history to cross-reference any of this report's findings against, and no way to verify *when* specific changes (e.g. the `PermissionManager` addition) actually landed beyond this single point-in-time read.

---

## 16. Remaining Work

### Priority Order

| # | Task | Priority | Complexity | Depends on | Milestone |
|---|---|---|---|---|---|
| 1 | Replace placeholder identifiers (`com.example.device_shield`, podspec homepage/author, pubspec description/homepage) | High | Low | none | M0 |
| 2 | Export `Detector`, `Rule`, `SecurityEvent`, `DetectionResult`, `DeviceShieldConfig`, exceptions from `lib/device_shield.dart` | High | Low | none | M12 |
| 3 | Implement the remaining 5 P0 detectors (root, jailbreak, debugger, runtime-hook, app-integrity) following `EmulatorDetector`'s pattern | High | High (×5) | native package skeleton (`protection/`/`bridge/`/`utils/` still missing) | M7 |
| 4 | Implement default `Rule` content + `ActionHandler`s for each detection type as it lands | High | Medium | Task 3 | M9 |
| 5 | Add a built-in dedup `EventProcessor` matching `ARCHITECTURE.md` §5's pipeline diagram, or formally amend the diagram | High | Low | none | M4 |
| 6 | Implement the five `SecurityProfile` factory presets and wire `profile` into `initialize()` | High | Medium | `SecurityProfile` model (done) | M10 |
| 7 | Wire `DetectorFactory` into the boot path once `SecurityProfile` selection exists, or explicitly document why it stays standalone | Medium | Low | Task 6 | M6/M10 |
| 8 | Create native `protection/`/`bridge/`/`utils/` subpackages on both platforms | Medium | Low | none | M0/M3 |
| 9 | Implement the 2 P1 detectors | Medium | Medium | Task 3's pattern | M8 |
| 10 | Grow `method_codes.dart` alongside every new detector/protection (discipline item, not a milestone of its own) | Medium | Low | ongoing | M3 |
| 11 | Add required Android permissions / iOS `Info.plist` entries as specific detectors/protections need them | Medium | Low | Tasks 3, 12 | M3 |
| 12 | Implement the 5 protections | Medium | High | M2/M3 (done) — can run in parallel with detectors | M11 |
| 13 | Implement `DeviceShieldConfigBuilder` and `ConfigurationPersistence` | Medium | Medium | `shared_preferences` dependency | M2 |
| 14 | Implement `CustomRule` public class + 100-rule cap + circular-dependency validation | Medium | Medium | Task 4 | M9 |
| 15 | Implement `DeviceShieldWidget`, `SecurityAlertDialog`, `ScreenshotProtection` widget | Medium | Medium | Tasks 4/6 (alert content), Task 12 (protection widget) | M12 |
| 16 | Implement `DataFilter` and wire it into `Logger` | Medium | Low | none | M1 |
| 17 | Implement `SecureStorage`/`EncryptionUtils`/`KeyManager`/`IntegrityValidator`/`DataProtection` | Medium | Medium | crypto/secure-storage packages | M13 |
| 18 | Implement `ProductionLogger`/`RecoveryStrategy`/`RetryLogic`, wired into real catch blocks | Medium | Medium | none blocking | M17 |
| 19 | Restructure `test/` into `unit/`/`integration/`/`native/`; run and record `flutter test --coverage` against the §16.5 targets | Medium | Low | none blocking | M18 |
| 20 | Implement `PerformanceMonitor` and an automated benchmark suite | Low | Medium | a real detector set (Task 3) | M14 |
| 21 | Implement `GDPRCompliance`/`PCIDSSCompliance`/`HIPAACompliance` + legal sign-off | Low | Medium (High legal overhead) | Tasks 16, 17 | M15 |
| 22 | Implement `DeviceShieldLocalization`/`getLocalizedMessage()` | Low | Low | Task 15 | M16 |
| 23 | Rewrite the example app, README, integration guide, `DevelopmentTools` | Low | Medium | a feature-complete public API (Tasks 3–15 substantially done) | M19 |
| 24 | Set up `.github/workflows/release.yml`, finalize `pubspec.yaml`, document versioning/deprecation policy | Low | Low | Task 23 | M20 |
| 25 | Write and pass tests for the SRS's §26.1 edge-case rows | Low | High | nearly everything above | M21 |
| 26 | Run the full release checklist and tag v1.0 | Low | Low (gate), Critical (irreversible) | everything above | M22 |
| 27 | Initialize a git repository for this codebase if one is genuinely intended (currently absent) | High (process) | Low | none | pre-M0 |

### Blocked Work
Task 21 (compliance) is blocked on legal sign-off, not engineering — flagged as a process dependency, not a code dependency. Task 25 (edge-case hardening) is blocked on nearly the entire remaining roadmap by nature (it validates behavior that doesn't exist yet). Task 26 (v1.0 tag) is blocked on everything.

### Future Enhancements (explicitly out of v1.0 scope per `ROADMAP.md` M22)
AI-driven risk scoring, remote policy management, a remote kill switch, a device trust score, and a threat-intelligence feed — all named in the roadmap as a deliberate post-v1.0 backlog, not silently dropped scope.

---

## 17. Architecture Findings

Findings only — nothing here has been fixed, per this report's own scope.

### Dead / unused code
- **`lib/src/utilities/` is an empty directory** — no files, no subdirectories. Leftover structural scaffolding from the M0 folder-layout decision, never populated. Harmless but should either be populated (SRS's `utils` layer) or removed.
- **`DetectorFactory` (`registry/detector_factory.dart`) is fully implemented and tested but never called by any production code path.** `PluginInitializer` does not construct one; nothing in `bootstrap/` references it. It is reachable today only from `test/registry/detector_factory_test.dart`. This is deliberate per its own doc comment (waiting on `SecurityProfile` wiring), but is, in the interim, dead code from the perspective of the running SDK.
- **`method_codes.dart`'s `MethodCodes` class currently has exactly one constant** — not dead, but so minimal relative to its stated purpose ("single source of truth... once 15+ detectors share the channel") that it is effectively still-scaffolding rather than a populated registry.

### Architecture inconsistencies / contract violations
- **`ARCHITECTURE.md` §5's Event Pipeline diagram depicts a `DEDUP{Duplicate (type, source) in window?}` stage as intrinsic to `emit()`.** `DefaultEventManager.emit()` has no such stage — the generic `EventProcessor` extension point is real, but nothing registers a dedup processor anywhere in the codebase. Still open (was already flagged in `CURRENT_PROGRESS.md`, confirmed unresolved by direct re-reading).
- **`ARCHITECTURE_CONTRACTS.md`'s `LifecycleManager` entry states `SecurityManager` is the "Owner (creates it)."** In the actual code, `LifecycleManager` is resolved-or-defaulted by `PluginInitializer` (the same class that now constructs `SecurityManager` itself) — `DefaultSecurityManager` never references or constructs a `LifecycleManager`. The narrow `SecurityLifecycleHandler` callback-contract fix (resolving the documented circular-dependency risk) **is** correctly implemented; the *ownership* half of that same frozen contract entry is not literally true of the current code. Lower severity than `CURRENT_PROGRESS.md`'s original finding (a)/(c), since `PluginInitializer` constructing everything is now internally consistent — but the frozen document's specific wording ("`SecurityManager` creates it") still doesn't match.
- **`ConsoleLogger`'s documented "soft, one-time read of `ConfigurationManager` once available"** (`ARCHITECTURE_CONTRACTS.md` Group C, `Logger`'s dependency row) **does not exist in code.** `ConsoleLogger` has zero reference to `ConfigurationManager`. Not a cycle risk (the edge never existed either way), but a real, checkable gap between the frozen document's description and the implementation.
- **`ARCHITECTURE.md` §4's Runtime Execution Flow diagram depicts a `GATE{confidence ≥ threshold?}` stage before policy evaluation** ("a low-confidence detection is cached but never reaches Policy/Event"). `DefaultSecurityManager.checkNow()` has no such gate — every `DetectionResult` from every cycle is passed to `policyManager.evaluate()` and has an event emitted for it, regardless of `confidence`.
- **Naming mismatches versus frozen documents** (informational, not defects — both sides are internally consistent, just named differently): `PolicyAction` (docs) vs. `SecurityAction` (code); `SecuritySeverity` (SRS, via `ROADMAP.md`) vs. `EventSeverity` (code).

### Circular dependencies
**None found.** Every edge in the dependency graph (§6) was checked for a return path; the two potential cycles the frozen documents specifically call out as resolved (`SecurityManager`↔`LifecycleManager` via the narrow callback, `ConfigurationManager`⇢`Logger`'s one-directional soft read) are both correctly acyclic in the code as written — the second one trivially so, since that soft-read edge doesn't exist at all (see above).

### Duplicate implementations
None found. Android and iOS implement `EmulatorDetector` independently (as they must — no shared native code layer exists or is architected for), but this is platform-required duplication, not redundant duplication within one platform. No two Dart classes were found implementing overlapping responsibility.

### Refactoring opportunities (observations, not recommendations to act on)
- `plugin_initializer.dart` at 501 lines is the largest file in the codebase; it is already well-decomposed into small private methods, but the file itself could be split (e.g., one file per boot-step-group) if it continues to grow with future services.
- `ShutdownSequence` remains unfactored from `PluginInitializer.shutdown()`/`_unwind()` into its own class, as `ROADMAP.md` M6 names it — currently inlined; extracting it would make the reverse-order teardown logic independently testable and reusable.
- `DetectorFactory`'s dead-in-production status (above) means its actual integration shape (called from where, with what selection logic) is still an open design question, not just an implementation gap.

---

## 18. Final Summary

### Overall Project Health
**Solid foundation, no house built on it yet** — an accurate, not pessimistic, description directly supported by this review. The architecturally hardest work (acyclic dependency layering, a fully-enforced state machine, bounded concurrency, dependency injection, a working two-channel native bridge) is genuinely done and genuinely tested. The user-facing security capability the SDK exists to deliver (18 functional requirements per the roadmap's own FR numbering) is, today, **1 of 18 delivered** (emulator detection).

### Architecture Maturity
High for the framework layer, unstarted for the feature layer. Every extension point named in `ARCHITECTURE.md` §8 (`Detector`, `Rule`, `NativeBridge` via `ServiceContainer`, `LogSink`, `ActionHandler` slot) is real, tested, and exercised by at least a fake in the test suite — this is a codebase built extension-point-first, which is unusual discipline for a project this early and a genuine strength.

### Code Quality
High. `flutter analyze` is clean. No obvious code smells, no dead-simple bugs found during this full read-through. Documentation-as-comments is unusually thorough and specific (nearly every class's doc comment cites the exact architecture-document section and any correction applied to it) — a real asset for a new contributor, though it also means the source files themselves are doing double duty as living architecture documentation, which is worth being aware of as a maintenance surface.

### Testing Maturity
Moderate-to-high in raw coverage-by-count (202 tests, every implemented module exercised, meaningful edge cases like dispose-during-concurrent-run and reentrant-initialize covered) but genuinely immature in measurement (zero coverage runs ever recorded) and platform validation (iOS native tests can't execute in this environment; zero real-device testing for anything security-sensitive, though nothing security-sensitive exists yet to test).

### Maintainability
High. Consistent architectural vocabulary across every file (the same "Architecture Correction N" citation style, the same resolve-or-default pattern repeated identically across 10 boot steps, the same fake-not-mock testing style throughout). A new contributor reading this report plus 2–3 representative files (`plugin_initializer.dart`, `default_detection_manager.dart`, `emulator_detector.dart`) would have a materially complete mental model of the entire codebase's conventions.

### Scalability
The concurrency model is explicitly designed and tested for the "20+ detectors" scaling risk `ARCHITECTURE.md` §7 names — bounded parallelism, per-detector timeout, deterministic ordering, and exception isolation are all real today, not aspirational, even though only one detector currently exists to exercise them.

### Readiness Percentage
**~31% of the full v1.0 roadmap** (this report's own unweighted milestone average, up from `CURRENT_PROGRESS.md`'s ~28% on 2026-07-24). **~0% of production security readiness** — the SDK detects exactly one condition (emulator/simulator) and, even then, produces no policy action beyond logging unless a host app manually wires a rule.

### Recommended Next Milestone
**Continue M7** — implement the remaining 5 Priority-0 detectors, following `EmulatorDetector`'s now-proven Dart+Kotlin+Swift pattern, **in parallel with** closing the two remaining high-value, low-cost gaps: the public export barrel (§4/§17, ~1 line of work, unblocks FR-17/FR-18 for real host apps) and the event-pipeline dedup stage (§17, ~1 small class). Unlike the previous audit's recommendation (finish M6 before starting M7), M6 is now close enough to complete that no further blocking work remains there — the framework has proven itself with a real detector, and the next-highest-leverage work is squarely feature content (M7/M9), not more framework.

