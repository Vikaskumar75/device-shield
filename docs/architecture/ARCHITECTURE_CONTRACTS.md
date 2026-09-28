# DeviceShield — Architecture Contract Verification

**Purpose of this document:** freeze every architecture component's contract before Phase 2 writes a single interface. Nothing here is implementation — no Dart classes, no method bodies. This is the specification implementation must not silently drift from. Once approved, Phase 2 implements exactly what's frozen here — no more, no less.

**Scope:** all 20 components from `ARCHITECTURE.md` — the 15 you named plus `DeviceShieldWidget`, `PermissionManager`, `SecurityStateManager`, and the two contracts (`Detector`, `Rule`), since the goal is a complete freeze, not a partial one.

**One correction identified during this verification** is called out inline where it occurs (§Circular Dependency Verification) — a real circular dependency was found between `SecurityManager` and `LifecycleManager` as previously described, and is resolved here before it reaches implementation.

---

## Part 1 — Per-Component Contracts

### Group A — Public Surface

#### `DeviceShield`
| Attribute | Definition |
|---|---|
| Purpose | Single entry point — the only symbol a host app ever imports |
| Responsibilities | Delegate every call 1:1 to `SecurityManager`; owns no logic of its own |
| Owner (creates it) | N/A — static class, never instantiated |
| Lifetime | Process lifetime (static) |
| Pattern | Stateless facade |
| Dependencies | `PluginInitializer` (calls once), `SecurityManager` (delegates every subsequent call) |
| Dependents | Host application code |
| Visibility | Public |
| Thread ownership | Dart main isolate |
| Initialization order | N/A — triggers boot, isn't itself a boot step |
| Disposal order | N/A — stateless, nothing to dispose |
| Failure behavior | Never catches — propagates exceptions to the caller's `try/catch` or the `onError` callback |
| Extension point | No — but it's the surface *through which* extensions are registered (`registerDetector`, `addRule`) |

#### `DeviceShieldWidget`
| Attribute | Definition |
|---|---|
| Purpose | Declarative alternative to manual `initialize()`/`shutdown()` |
| Responsibilities | Call `DeviceShield.initialize()` on mount; render loading/error/child by status; call `shutdown()` on unmount |
| Owner (creates it) | Host app's widget tree |
| Lifetime | Tied to Flutter widget lifecycle (mount → unmount) |
| Pattern | Scoped (one instance per mount point) |
| Dependencies | `DeviceShield` |
| Dependents | Host application code |
| Visibility | Public |
| Thread ownership | Dart main isolate (UI thread) |
| Initialization order | N/A |
| Disposal order | N/A — Flutter framework calls `State.dispose()` |
| Failure behavior | Catches `initialize()` failure internally, renders an error widget, forwards to `widget.onError` |
| Extension point | No |

---

### Group B — Bootstrap & Dependency Injection

#### `PluginInitializer`
| Attribute | Definition |
|---|---|
| Purpose | The only code path that constructs and wires every other service, in fixed order |
| Responsibilities | Validate config; construct + register each service in order; start monitoring; emit `initialized`; unwind to `failure` on any step's exception |
| Owner (creates it) | `DeviceShield.initialize()` |
| Lifetime | Transient — exists only for the duration of one `initialize()` call |
| Pattern | Factory-invoked, single-use — never a singleton, never reused |
| Dependencies | `ServiceContainer` + every service it constructs (§Part 3, Init Matrix) |
| Dependents | None — nothing holds a reference to it after boot completes |
| Visibility | Internal |
| Thread ownership | Dart main isolate |
| Initialization order | N/A — it *performs* the init order, it isn't a step within it |
| Disposal order | N/A — nothing outlives the boot call |
| Failure behavior | Any step's exception halts remaining steps, releases already-registered services, transitions state to `failure`, rethrows to the caller |
| Extension point | No |

#### `ServiceContainer`
| Attribute | Definition |
|---|---|
| Purpose | Type-keyed lookup decoupling construction from use |
| Responsibilities | `register<T>()`, `get<T>()`, `isRegistered<T>()`, `clear()` |
| Owner (creates it) | `PluginInitializer` |
| Lifetime | SDK lifetime — persists as an empty shell across initialize/shutdown cycles |
| Pattern | Singleton |
| Dependencies | None — foundation |
| Dependents | Every service listed below |
| Visibility | Internal |
| Thread ownership | Dart main isolate; written only during boot's single-threaded phase, read-only after |
| Initialization order | Step 0 |
| Disposal order | Last — `clear()` after every other service has released its resources |
| Failure behavior | `get<T>()` throws if the type was never registered; no failure state of its own |
| Extension point | No |

---

### Group C — Core Services

#### `Logger`
| Attribute | Definition |
|---|---|
| Purpose | The SDK's only sanctioned output path |
| Responsibilities | Level-gated debug/info/warning/error/exception logging; sensitive-field redaction; crash-report forwarding |
| Owner (creates it) | `PluginInitializer`, step 1 |
| Lifetime | SDK lifetime — first constructed, last disposed |
| Pattern | Singleton |
| Dependencies | None hard; soft one-time read of `ConfigurationManager` once available (see §Circular Dependency Verification) |
| Dependents | Every other component |
| Visibility | Internal |
| Thread ownership | Dart main isolate |
| Initialization order | Step 1 (boots with a safe default before `ConfigurationManager` exists) |
| Disposal order | Second-to-last (flushes buffered writes) |
| Failure behavior | Must never throw — a logging failure cannot be allowed to crash boot; internal I/O failures (e.g. file-write) are swallowed after a bounded retry |
| Extension point | Yes — `LogSink` registration (forwarding to a third-party monitoring service is a registered sink, not a Logger code change) |

#### `PermissionManager`
| Attribute | Definition |
|---|---|
| Purpose | Requests and tracks the OS permissions the active profile's detectors/protections require |
| Responsibilities | Derive required-permission set from `SecurityProfile`; request them; expose grant state |
| Owner (creates it) | `PluginInitializer`, step 2 |
| Lifetime | SDK lifetime |
| Pattern | Singleton |
| Dependencies | `SecurityProfile`, platform permission APIs |
| Dependents | `SecurityManager` |
| Visibility | Internal |
| Thread ownership | Dart main isolate (permission requests may hop to the native platform thread; result is marshaled back) |
| Initialization order | Step 2 |
| Disposal order | Bundled — no explicit teardown resource; released via `ServiceContainer.clear()` |
| Failure behavior | Denial throws `PermissionException` → state → `failure`; `RecoveryStrategy` re-requests |
| Extension point | No |

#### `ConfigurationManager`
| Attribute | Definition |
|---|---|
| Purpose | Sole owner of the validated, immutable active configuration |
| Responsibilities | Validate incoming config; hold the current value; apply runtime updates; notify dependents of changes |
| Owner (creates it) | `PluginInitializer`, step 3 |
| Lifetime | SDK lifetime |
| Pattern | Singleton |
| Dependencies | `DeviceShieldConfig` model, Validator, optional Persistence |
| Dependents | Every manager (read `.current` at point of use) |
| Visibility | Internal (the config *values* it holds surface publicly; the manager itself doesn't) |
| Thread ownership | Dart main isolate |
| Initialization order | Step 3 |
| Disposal order | Bundled — released via `ServiceContainer.clear()` |
| Failure behavior | Invalid update throws `ConfigurationException`; the replacement is rejected and the previous config is retained — a bad update never corrupts current state |
| Extension point | No |

---

### Group D — Managers (Orchestration Layer)

#### `SecurityManager`
| Attribute | Definition |
|---|---|
| Purpose | Runtime orchestrator — the one object every public call actually reaches |
| Responsibilities | Own references to the other three managers + Configuration/Permission/Logger; drive the periodic check timer; run the confidence-gate → Policy → Event pipeline |
| Owner (creates it) | `PluginInitializer`, final boot step |
| Lifetime | SDK's entire running lifetime |
| Pattern | Singleton |
| Dependencies | `DetectionManager`, `PolicyManager`, `EventManager`, `NativeBridge`, `ConfigurationManager`, `PermissionManager`, `Logger`, `SecurityStateManager` |
| Dependents | `DeviceShield`, `LifecycleManager` (via the inverted callback contract — see §Circular Dependency Verification) |
| Visibility | Internal — fully wrapped by `DeviceShield` |
| Thread ownership | Dart main isolate for orchestration; dispatches detector batches to the bounded-concurrency pool |
| Initialization order | Step 8 (last manager constructed) |
| Disposal order | First — pauses monitoring before any dependency is torn down |
| Failure behavior | Catches per-cycle exceptions from Detection/Policy/Event, logs, does not kill the periodic timer; an unrecoverable error transitions state → `failure` |
| Extension point | No |

#### `DetectionManager`
| Attribute | Definition |
|---|---|
| Purpose | Framework for running registered detectors and aggregating results — technique-agnostic |
| Responsibilities | Hold `DetectorRegistry`; run enabled detectors (bounded-parallel); per-detector timeout; cache management |
| Owner (creates it) | `PluginInitializer`, step 6 |
| Lifetime | SDK lifetime |
| Pattern | Singleton |
| Dependencies | `DetectorRegistry`, `Detector` contract, `NativeBridge`, `DetectionCache` |
| Dependents | `SecurityManager` |
| Visibility | Internal (`registerDetector` reachable publicly only via `DeviceShield` → `SecurityManager`) |
| Thread ownership | Dart main isolate; launches bounded-concurrency `Future`s for detector batches |
| Initialization order | Step 6 |
| Disposal order | Third (after `SecurityManager` pauses, before `EventManager`) — disposes each registered detector, then itself |
| Failure behavior | A single detector's exception is caught, logged, excluded from that cycle — never fails the whole batch |
| Extension point | No (the extension point is `DetectorRegistry`, listed separately) |

#### `PolicyManager`
| Attribute | Definition |
|---|---|
| Purpose | Turns a `DetectionResult` into a `PolicyAction` — no built-in opinion beyond the active profile's configuration |
| Responsibilities | Hold prioritized `Rule` list; `evaluate()`; `executeAction()` via registered handlers; risk scoring |
| Owner (creates it) | `PluginInitializer`, step 7 |
| Lifetime | SDK lifetime |
| Pattern | Singleton |
| Dependencies | `Rule` contract, `ActionHandler` registry, `EventManager` |
| Dependents | `SecurityManager` |
| Visibility | Internal (`addRule`/`removeRule` reachable publicly) |
| Thread ownership | Dart main isolate; sequential, in-memory rule evaluation (fast, no I/O) |
| Initialization order | Step 7 |
| Disposal order | Bundled with `DetectionManager`'s teardown step — released via `ServiceContainer.clear()` |
| Failure behavior | A rule's exception is treated as "no match" — never blocks other rules or other detections; unhandled action-execution errors throw `PolicyException`, fallback policy applied |
| Extension point | Yes — new `Rule` implementations (FR-17) and new `ActionHandler`s registered against the reserved `PolicyAction.custom` slot |

#### `EventManager`
| Attribute | Definition |
|---|---|
| Purpose | The single event bus every `SecurityEvent`, from any source, passes through |
| Responsibilities | `emit()` through processors; bounded history; filtered broadcast; pause/resume queuing |
| Owner (creates it) | `PluginInitializer`, step 5 |
| Lifetime | SDK lifetime — last internal service to stop accepting emissions during shutdown |
| Pattern | Singleton |
| Dependencies | None structurally — leaf service |
| Dependents | `SecurityManager`, `PolicyManager`, `EventChannelService` (native-pushed events reach it directly, not via `NativeBridge` → `DetectionManager`) |
| Visibility | Internal emit path; `DeviceShield.events` is the public read-only view |
| Thread ownership | Dart main isolate; broadcast `StreamController`, sequential per-subscriber delivery |
| Initialization order | Step 5 |
| Disposal order | Second (after `DetectionManager`, before `NativeBridge`) — closes its `StreamController` |
| Failure behavior | A subscriber handler's exception is caught per-invocation, logged, never rethrown to the emitting caller |
| Extension point | Indirectly — the `EventProcessor` chain (dedup, etc.) is a registrable pipeline stage |

---

### Group E — Registry & Extension Points

#### `DetectorRegistry`
| Attribute | Definition |
|---|---|
| Purpose | Decouples "what detectors exist" from "how `DetectionManager` runs them" — the FR-18 mechanism itself |
| Responsibilities | `register()`, priority-ordered `getOrderedDetectors()`, `isEnabled()` |
| Owner (creates it) | `DetectionManager`, during its own construction |
| Lifetime | Scoped to its owning `DetectionManager` instance |
| Pattern | Scoped (not a global singleton — one per `DetectionManager`) |
| Dependencies | `Detector` contract |
| Dependents | `DetectionManager` exclusively |
| Visibility | Internal — private to `DetectionManager` |
| Thread ownership | Dart main isolate; mutated only during boot/registration, read-only during check cycles |
| Initialization order | Populated as part of step 6 |
| Disposal order | Alongside `DetectionManager` |
| Failure behavior | Registering a duplicate/invalid detector surfaces an error synchronously to the caller of `registerDetector()` — does not affect already-registered detectors |
| Extension point | **Yes — this is the primary extension point** for new detectors (host-app custom detectors register here directly; built-in detectors also route through `DetectorFactory`) |

#### `Detector` *(contract)*
| Attribute | Definition |
|---|---|
| Purpose | The interface every detection module implements |
| Responsibilities | `initialize()`, `check()` → `DetectionResult`, `dispose()`, exposes `type` + `priority` |
| Owner (creates it) | N/A — contract; concrete instances are created by `DetectorFactory` (built-in) or the host app (custom) |
| Lifetime | N/A for the contract; concrete instances share `DetectionManager`'s lifetime |
| Pattern | N/A — interface. Concrete implementations are Factory-created, one per `DetectionType` |
| Dependencies | `DetectionResult` model, `NativeBridge` |
| Dependents | `DetectorRegistry`, `DetectorFactory`, `DetectionManager` |
| Visibility | Public — host apps implement this for custom detectors (FR-18) |
| Thread ownership | Dart-side `check()` on the main isolate (I/O-bound await); native-side implementation on native background threads |
| Initialization order | N/A (feature-level, out of scope for this framework-only phase) |
| Disposal order | N/A |
| Failure behavior | By convention, implementations catch their own native-call/timeout failures and return `DetectionStatus.failed` rather than throwing |
| Extension point | **Yes — the contract itself is the extension surface** |

#### `Rule` *(contract)*
| Attribute | Definition |
|---|---|
| Purpose | The interface every policy rule implements |
| Responsibilities | `matches(result)` → bool; exposes `action` + `priority` |
| Owner (creates it) | N/A — contract; concrete instances are profile-provided defaults or host-app `CustomRule`s |
| Lifetime | N/A for the contract; concrete instances share `PolicyManager`'s lifetime |
| Pattern | N/A — interface |
| Dependencies | `DetectionResult`, `PolicyAction` enum |
| Dependents | `PolicyManager` |
| Visibility | Public — `CustomRule` implements this (FR-17) |
| Thread ownership | Dart main isolate |
| Initialization order | N/A |
| Disposal order | N/A |
| Failure behavior | `matches()` throwing is treated as "no match" by `PolicyManager`'s evaluation loop |
| Extension point | **Yes — the contract itself is the extension surface** |

---

### Group F — Bridge & Platform

> **Correction (Phase 7 post-review, PlatformAdapter verification):** `PlatformAdapter` is removed from `NativeBridge`'s dependency chain below. `MethodChannelService`/`EventChannelService` construct their channels directly via Flutter's default binary messenger — the same pattern Phase 1's `MethodChannelDeviceShield` already used — rather than obtaining bindings through `DeviceShieldPlatform`. Full reasoning and the corrected dependency graph are in `ARCHITECTURE.md`'s Phase 7 correction note. `PlatformAdapter`'s entry is kept below, reclassified as legacy-only (§ below), rather than deleted, since `DeviceShieldPlatform`/`MethodChannelDeviceShield` still exist and still back the unrelated Phase 1 `getPlatformVersion()` path.

#### `NativeBridge`
| Attribute | Definition |
|---|---|
| Purpose | The sole path any Dart code takes to reach native code |
| Responsibilities | `invoke()` (timeout-bound request/response), `invokeAsync()`, `registerCallback()`/`unregisterCallback()` |
| Owner (creates it) | `PluginInitializer`, step 4 |
| Lifetime | SDK lifetime |
| Pattern | Singleton |
| Dependencies | `MethodChannelService`, `EventChannelService` |
| Dependents | `DetectionManager`, future `Protection` implementations |
| Visibility | Internal |
| Thread ownership | Dart main isolate for the call site; the underlying channel call is marshaled onto the platform thread by the Flutter engine |
| Initialization order | Step 4 |
| Disposal order | Fourth (after `EventManager`, before `Logger`) — closes both channels, unregisters callbacks |
| Failure behavior | `invoke()` failure/timeout throws `NativeBridgeException`; `RecoveryStrategy` reinitializes the bridge and retries within a bounded attempt count |
| Extension point | **Yes — `NativeBridge` itself, swapped via `ServiceContainer`** (Phase 4's DI pattern). This supersedes `PlatformAdapter` as the real "new platform" extension point — see the correction note above. |

#### `MethodChannelService`
| Attribute | Definition |
|---|---|
| Purpose | Request/response native calls |
| Responsibilities | Wrap `MethodChannel.invokeMethod` with timeout + typed error translation |
| Owner (creates it) | `NativeBridge` |
| Lifetime | Shares `NativeBridge`'s exact lifetime |
| Pattern | Scoped — owned exclusively by `NativeBridge`, never held elsewhere |
| Dependencies | Flutter's `MethodChannel` (constructed directly, via the default binary messenger), the resolved channel name |
| Dependents | `NativeBridge` exclusively |
| Visibility | Internal — private to `NativeBridge` |
| Thread ownership | Platform thread (channel marshaling is engine-managed) |
| Initialization order | Constructed as part of `NativeBridge`'s own step 4 |
| Disposal order | With `NativeBridge` |
| Failure behavior | `PlatformException` → translated to `NativeBridgeException`, surfaced to `NativeBridge`'s caller |
| Extension point | No |

#### `EventChannelService`
| Attribute | Definition |
|---|---|
| Purpose | Native-originated pushes |
| Responsibilities | Wrap `EventChannel.receiveBroadcastStream`; forward raw events generically. Does **not** know `EventManager` or `SecurityEvent` exist (Phase 7 Resolution 2 — supersedes the wording this row previously had). `NativeBridge.registerCallback`/`unregisterCallback` is the only integration seam back into the rest of the SDK; a later phase wires a registered callback to `EventManager.emit()`. |
| Owner (creates it) | `NativeBridge` |
| Lifetime | Shares `NativeBridge`'s exact lifetime |
| Pattern | Scoped — owned exclusively by `NativeBridge` |
| Dependencies | Flutter's `EventChannel` (constructed directly, via the default binary messenger) |
| Dependents | `NativeBridge` exclusively |
| Visibility | Internal — private to `NativeBridge` |
| Thread ownership | Platform thread on receipt; hands off to Dart main isolate for delivery to whatever callback `NativeBridge` routes it to |
| Initialization order | Constructed as part of `NativeBridge`'s own step 4 |
| Disposal order | With `NativeBridge` — cancels the underlying stream subscription |
| Failure behavior | A malformed native event is forwarded through unchanged — no content validation happens at this layer; channel-level errors are routed to `onError`, not swallowed |
| Extension point | No |

#### `PlatformAdapter` — legacy, non-load-bearing as of Phase 7
| Attribute | Definition |
|---|---|
| Purpose | Originally: the federated-plugin swap point `NativeBridge` would be built against. **As of the Phase 7 post-review, this purpose is obsolete** — see the correction note above and `ARCHITECTURE.md` for the full "why." Retained purpose today: backs the pre-existing, unrelated `getPlatformVersion()` call (Phase 1), kept unchanged for backward compatibility. |
| Responsibilities | Expose `DeviceShieldPlatform`'s abstract surface; `MethodChannelDeviceShield` constructs the one legacy channel |
| Owner (creates it) | Package load time, or a platform package's `registerWith()` |
| Lifetime | **Process lifetime** — the one component that outlives individual `initialize()`/`shutdown()` cycles |
| Pattern | Singleton — but a *process* singleton, not an SDK-lifetime singleton like everything else in this table |
| Dependencies | `plugin_platform_interface` package |
| Dependents | **None within the Bridge architecture.** `MethodChannelService`/`EventChannelService` do not depend on it (corrected this pass). Its only remaining caller is the legacy `DeviceShield.getPlatformVersion()` path, outside this component graph. |
| Visibility | Public — deliberately, so platform packages can register their own implementation, a capability that remains available even though nothing in the frozen architecture currently exercises it |
| Thread ownership | Platform thread (binary messenger, channel construction) |
| Initialization order | Not part of the numbered boot sequence |
| Disposal order | Never explicitly disposed |
| Failure behavior | A token-verification failure (wrong implementation registered) throws synchronously at registration time — a startup configuration error, not a runtime one |
| Extension point | No longer — see `NativeBridge`'s entry above for the mechanism that replaced it |

---

### Group G — State & Lifecycle

#### `SecurityStateManager`
| Attribute | Definition |
|---|---|
| Purpose | Single source of truth for SDK status |
| Responsibilities | Hold current `SecurityStatus`; validate + perform every transition; broadcast changes |
| Owner (creates it) | `PluginInitializer` — created before anything that could fail and need to report `failure` |
| Lifetime | SDK lifetime |
| Pattern | Singleton |
| Dependencies | `SecurityStatus` enum, transition-guard rules |
| Dependents | `SecurityManager` (owner), `LifecycleManager` (reads current state before acting), `RecoveryStrategy` (observes `failure`) |
| Visibility | Write: internal only. Read: public via `DeviceShield.status` |
| Thread ownership | Dart main isolate; broadcast `StreamController` |
| Initialization order | Effectively step 0b — alongside `ServiceContainer`, before `Logger` |
| Disposal order | Closes its `StreamController` as part of `SecurityManager`'s teardown |
| Failure behavior | An illegal transition request throws `StateError` synchronously to the caller; the manager's own state is never corrupted by a rejected request |
| Extension point | No |

#### `LifecycleManager`
| Attribute | Definition |
|---|---|
| Purpose | The only component listening to Flutter's own app lifecycle |
| Responsibilities | Translate `AppLifecycleState` into resume/inactive/pause/detached behavior |
| Owner (creates it) | `PluginInitializer`, resolved-or-defaulted at boot step 9 alongside every other boot-step service — **corrected this pass**; see the note below |
| Lifetime | From boot step 9 (`attach()`) until shutdown step 1 (`detach()`); the instance itself persists in `ServiceContainer` across a shutdown/reinitialize cycle, unlike `SecurityManager`/`EventManager`/`NativeBridge` |
| Pattern | Singleton (SDK-lifetime, one per boot cycle) |
| Dependencies | **A narrow `SecurityLifecycleHandler` callback contract** (see §Circular Dependency Verification — not a direct reference to `SecurityManager`), Flutter's `WidgetsBinding` |
| Dependents | None — nothing calls into `LifecycleManager` except Flutter's own binding |
| Visibility | Internal |
| Thread ownership | Dart main isolate, driven by `WidgetsBinding` callbacks |
| Initialization order | Step 9 — after `SecurityManager` exists |
| Disposal order | First, alongside `SecurityManager` (removes itself as observer before anything else tears down) |
| Failure behavior | An exception inside a lifecycle callback is caught and logged — must never crash Flutter's lifecycle dispatch |
| Extension point | No |

> **Correction (M6 completion pass):** the "Owner (creates it)" row above previously read `SecurityManager`, once boot completes and monitoring starts. That was never true of the implementation — `DefaultSecurityManager` holds no `LifecycleManager` reference in either direction, verified directly (zero occurrences in `managers/default_security_manager.dart`). Construction has always gone through `PluginInitializer`, the same as every other boot-step service — this row is corrected to match, closing a contradiction between this document and the code that `CURRENT_PROGRESS.md` (2026-07-24) first flagged as finding 2.1(c). This is a documentation fix only: no behavior changed, and the resolution to the real circular-dependency risk (the narrow `SecurityLifecycleHandler` contract, described in the Dependencies row above and in §Circular Dependency Verification below) was already correctly implemented and remains unchanged.

---

## Part 2 — Architecture Dependency Matrix

| Component | Depends On | Used By | Allowed Dependencies | Forbidden Dependencies |
|---|---|---|---|---|
| `DeviceShield` | `PluginInitializer`, `SecurityManager` | Host app | `SecurityManager` only | Any manager's internals, any concrete `Detector`/`Rule` |
| `DeviceShieldWidget` | `DeviceShield` | Host app | `DeviceShield` only | `SecurityManager` or below, directly |
| `PluginInitializer` | `ServiceContainer` + every service it constructs | `DeviceShield` (call site only) | Every service, `ServiceContainer` | Nothing — it's the one component allowed to see everything, once |
| `ServiceContainer` | Nothing | Every service | Nothing | Any service (would invert the lookup direction) |
| `Logger` | None hard; soft optional read of `ConfigurationManager` | Every component | `ConfigurationManager` (read-only, optional) | Any manager, any detector/rule |
| `PermissionManager` | `SecurityProfile`, platform permission APIs | `SecurityManager` | Platform permission APIs only | Any manager |
| `ConfigurationManager` | `DeviceShieldConfig`, Validator, Persistence | Every manager | Its own model/validator/persistence only | Any manager (would invert config ownership) |
| `SecurityManager` | `DetectionManager`, `PolicyManager`, `EventManager`, `NativeBridge`, `ConfigurationManager`, `PermissionManager`, `Logger`, `SecurityStateManager` | `DeviceShield` | The above only | Any concrete `Detector`/`Rule`, `DetectorRegistry` directly (must go through `DetectionManager`) |
| `DetectionManager` | `DetectorRegistry`, `Detector` contract, `NativeBridge`, `DetectionCache` | `SecurityManager` | `Detector` contract only, never a concrete detector type | `PolicyManager`, `EventManager` (must not reach past its own boundary) |
| `PolicyManager` | `Rule` contract, `ActionHandler` registry, `EventManager` | `SecurityManager` | `Rule` contract only, never a concrete rule type | `DetectionManager`, any concrete `Detector` |
| `EventManager` | Nothing structurally | `SecurityManager`, `PolicyManager`, `EventChannelService` | Its own `EventProcessor`/`SecurityEventFilter` collaborators | Any manager (must stay a leaf) |
| `DetectorRegistry` | `Detector` contract | `DetectionManager` exclusively | `Detector` contract only | `SecurityManager`, `PolicyManager`, `NativeBridge` directly |
| `Detector` *(contract)* | `DetectionResult` model, `NativeBridge` | `DetectorRegistry`, `DetectorFactory`, `DetectionManager` | `NativeBridge`, models | Any manager, any other detector |
| `Rule` *(contract)* | `DetectionResult`, `PolicyAction` enum | `PolicyManager` | Models only | Any manager, `NativeBridge`, any detector |
| `NativeBridge` | `MethodChannelService`, `EventChannelService` | `DetectionManager`, future `Protection`s | Its own channel services only | Any manager (must not know about Detection/Policy/Event), `PlatformAdapter` (obsolete for this component as of Phase 7 — see correction note) |
| `MethodChannelService` | Flutter `MethodChannel`, channel name | `NativeBridge` exclusively | Flutter SDK APIs only | `EventChannelService`, any manager, `PlatformAdapter` |
| `EventChannelService` | Flutter `EventChannel` | `NativeBridge` exclusively | Flutter SDK APIs only | Any manager, `EventManager`, `SecurityEvent`, `PlatformAdapter` |
| `PlatformAdapter` *(legacy)* | `plugin_platform_interface` | Nothing within the Bridge architecture — only the unrelated legacy `getPlatformVersion()` path | The federated-plugin package only | Anything above it — it must never know `NativeBridge` exists |
| `SecurityStateManager` | `SecurityStatus` enum, transition guard | `SecurityManager`, `LifecycleManager` (read), `RecoveryStrategy` | Its own enum/guard only | Any manager (must stay a pure state container) |
| `LifecycleManager` | `SecurityLifecycleHandler` callback contract (not `SecurityManager` directly), `WidgetsBinding` | Flutter's binding (callback dispatch only) | The narrow callback contract, `WidgetsBinding` | A direct reference to `SecurityManager` or any of its internals |

---

## Part 3 — Initialization Matrix

### Initialization Order

| Step | Component | Depends on (already available) |
|---|---|---|
| 0 | `ServiceContainer` created (empty) | — |
| 0b | `SecurityStateManager` created — state `uninitialized → initializing` | `ServiceContainer` |
| 1 | `Logger` — boots at safe default level | `ServiceContainer` |
| 2 | `PermissionManager` — requests required permissions | `Logger` |
| 3 | `ConfigurationManager` — validates + activates config; `Logger` re-reads its level | `PermissionManager` |
| 4 | `NativeBridge` — constructs `MethodChannelService` + `EventChannelService` directly (Phase 7 correction: not via `PlatformAdapter`) | `ConfigurationManager` |
| 5 | `EventManager` | `NativeBridge` |
| 6 | `DetectionManager` — builds `DetectorRegistry` | `EventManager`, `NativeBridge` |
| 7 | `PolicyManager` — builds `Rule` list from profile | `DetectionManager`, `EventManager` |
| 8 | `SecurityManager` — constructed from all of the above | Everything above |
| 9 | `LifecycleManager` — attaches as `WidgetsBindingObserver`, given the narrow callback contract | `SecurityManager` |
| 10 | `SecurityManager.startMonitoring()` — state `initializing → initialized → running`; `initialized` event emitted | Everything above |

### Shutdown Order

| Step | Action |
|---|---|
| 1 | `LifecycleManager` removes itself as `WidgetsBindingObserver` |
| 2 | `SecurityManager` pauses monitoring (stops the periodic timer) — state → `stopped` |
| 3 | `DetectionManager` disposed — disposes each registered detector, then `DetectorRegistry`, then itself |
| 4 | `EventManager` disposed — closes its `StreamController` |
| 5 | `NativeBridge` disposed — closes both channel services, unregisters callbacks |
| 6 | `Logger` flushes any buffered writes, then disposed |
| 7 | `ServiceContainer.clear()` — releases all remaining references (`PermissionManager`, `ConfigurationManager`, `PolicyManager`, `SecurityStateManager` bundled here — none hold external resources requiring individual teardown) |
| 8 | `stopped` event emitted; state → `stopped` confirmed (or `destroyed`, if this is a full disposal, not a resumable stop) |

### Failure Recovery

| Failure | Recovery action | Resulting state |
|---|---|---|
| `ConfigurationException` (invalid config) | Apply default profile's config, retry boot | `initialized` (on retry success) or `failure` (exhausted) |
| `PermissionException` (denied) | Re-request permissions, retry | `initialized` or `failure` |
| `NativeBridgeException` (bridge unavailable/timeout) | Reinitialize the bridge, retry | `initialized` or `failure` |
| `InitializationException` (generic boot failure) | Bounded retry with backoff | `initialized` or `failure` |
| Any unrecognized error code | Log failure, fall back to minimal `consumer` profile | `initialized` (degraded) or `failure` |
| Retries exhausted (any of the above) | No further automatic action | Remains in `failure` — only an explicit new `initialize()` call from the host app moves it further |

All retries are bounded — never an infinite loop. Exhausting them is a deliberate stop, not a silent hang.

---

## Part 4 — Circular Dependency Verification

### Finding: `SecurityManager` ↔ `LifecycleManager` — resolved

Walking every edge in Part 2's matrix for a return path turned up one real cycle, not previously drawn as an edge in `ARCHITECTURE.md`'s dependency graph but present in its prose: `SecurityManager` creates and owns `LifecycleManager` (a downward, ownership edge), while `LifecycleManager` was described as calling `pause()`/`resume()`/`checkNow()`/`shutdown()` directly on `SecurityManager` (an upward, behavioral edge back to the same node). Two edges between the same pair, in opposite directions, is a cycle by definition — even though it reads innocuously as "the lifecycle observer calls back into the manager that made it."

**Resolution, applied in Part 1/2 above:** `LifecycleManager` no longer depends on `SecurityManager` directly. It depends on a narrow `SecurityLifecycleHandler`-shaped callback contract (four callbacks: resume, inactive, pause, detached) supplied to it at construction. `SecurityManager` implements that contract and passes itself as the handler — but *implementing* a contract is not a dependency edge in the same sense as *holding a reference and calling arbitrary methods*: `LifecycleManager` only ever needs to know the four-callback shape exists, never that `SecurityManager` specifically does. This is the identical pattern `LifecycleManager` already uses on its other side — it doesn't hold a reference to `WidgetsBinding` and poll it; `WidgetsBinding` calls back into `LifecycleManager` through a narrow observer contract. The fix makes both sides of `LifecycleManager` symmetric: narrow contracts in, narrow contracts out, no concrete-class references either direction.

This is a genuine correction to what `ARCHITECTURE.md` described, made now — before Phase 2 turns it into a real interface — rather than after.

> **Addendum (M6 completion pass):** the phrase "`SecurityManager` creates and owns `LifecycleManager`" above describes the ownership edge as originally drafted, which the finding correctly identified as half of a cycle. In the implementation, construction ended up centralized differently than that draft assumed: `PluginInitializer` — not `SecurityManager` — constructs `LifecycleManager`, the same as every other boot-step service (see the `LifecycleManager` entry in Part 1, corrected this same pass). This doesn't reopen the cycle finding — `PluginInitializer → LifecycleManager` is a one-directional construction edge with no return path, same as `PluginInitializer → SecurityManager`, `PluginInitializer → EventManager`, etc. — it only means the *specific* node this analysis names as the "owner" half of the original two-edge cycle should be read as "whatever constructs `LifecycleManager`" (now `PluginInitializer`) rather than literally `SecurityManager`. The behavioral resolution (narrow `SecurityLifecycleHandler` contract, no concrete-class reference either direction) is unaffected and remains exactly as described above.

### Remaining edges — verified acyclic

Every other pair in Part 2's matrix was checked for a return path:

- `SecurityManager → {DetectionManager, PolicyManager, EventManager, ConfigurationManager, PermissionManager, Logger, SecurityStateManager}` — none of the seven hold a reference back to `SecurityManager`. Confirmed one-directional.
- `ConfigurationManager ⇢ Logger` (the one soft edge) — `Logger` has no hard dependency on `ConfigurationManager`; it boots with a default and does a single one-time, one-directional read once `ConfigurationManager` exists. Not a structural cycle — a bootstrap ordering nuance, already resolved in `ARCHITECTURE.md`.
- `NativeBridge → {MethodChannelService, EventChannelService}` — strictly downward; neither channel service knows `NativeBridge` exists beyond being constructed by it. **Correction (Phase 7 post-review):** this edge no longer continues to `PlatformAdapter` — both services construct their Flutter channels directly. `PlatformAdapter` is demoted to a legacy, non-load-bearing component (see its Part 1 entry); removing this edge doesn't introduce a cycle, since nothing depended on the reverse direction either.
- `EventChannelService → EventManager` — **this edge does not exist**, correcting an earlier draft of this document. Per Phase 7 Resolution 2, `EventChannelService` forwards raw native events generically with zero knowledge of `EventManager` or `SecurityEvent`. The actual seam is `NativeBridge.registerCallback`/`unregisterCallback`; a later phase registers a callback that calls `EventManager.emit()`, at which point the dependency lives in that later phase's integration code, not in the bridge package itself.
- `DetectorRegistry → Detector` contract, `PolicyManager → Rule` contract — registries/managers depend on the interface; interface implementations don't depend back on the registry that holds them.

**No other cycle exists in the graph.** The dependency direction rule from `ARCHITECTURE.md` — *a component may depend on anything below it, never anything above* — now holds without exception, including the one place it previously didn't.

### Clean Architecture / SOLID re-verification

| Principle | Verification |
|---|---|
| **Single Responsibility** | Each manager owns exactly one pipeline stage — `DetectionManager` runs detectors, `PolicyManager` decides actions, `EventManager` distributes events, `ConfigurationManager` owns config. No manager does another's job. |
| **Open/Closed** | Confirmed extension points: `DetectorRegistry` (new detectors), `Rule`/`PolicyManager` (new rules), `NativeBridge` swapped via `ServiceContainer` (new platforms — supersedes `PlatformAdapter`, see Phase 7 correction note), `Logger`/`LogSink` (new log destinations), `ActionHandler` against `PolicyAction.custom` (new actions). None require modifying the manager that hosts them. |
| **Liskov Substitution** | Any `Detector` implementation is substitutable without `DetectionManager` caring — the contract's return type (`DetectionResult`) is fixed regardless of implementation. Same for `Rule` → `PolicyAction`. |
| **Interface Segregation** | `Detector` and `Rule` are both minimal, single-purpose contracts (3–4 methods each) — no fat interfaces forcing unused method implementations. |
| **Dependency Inversion** | `DetectionManager` depends on `Detector` (interface), never a concrete detector. `PolicyManager` depends on `Rule` (interface), never a concrete rule. `LifecycleManager` now depends on a callback contract, never `SecurityManager` concretely (per the fix above). |

**Verdict: contracts frozen.** Zero circular dependencies remain. Every dependency direction matches the layering rule. Phase 2 may now define these as actual Dart interfaces without risk of the interface shape itself needing to change once real code depends on it.
