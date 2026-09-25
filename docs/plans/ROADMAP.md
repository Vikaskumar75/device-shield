# DeviceShield — End-to-End Build Roadmap

This is the complete, dependency-ordered plan to build DeviceShield from the current empty scaffold to a shippable v1.0, covering every section of the SRS. Each milestone lists what it builds, what it depends on, and how you know it's done. A full traceability table at the bottom maps every SRS section (1–27 + Appendices A–D) to the milestone that covers it, so nothing gets missed.

**How to use this:** work top to bottom — each milestone assumes every milestone above it is done. Where noted, tasks *within* a milestone can be split across people/parallelized; milestones themselves mostly can't (each depends on the previous one existing).

## Status — checked against the repo on 2026-07-24

**Planning phase: ✅ Complete.** SRS read in full, project audited, architecture designed (`ARCHITECTURE.md`), this roadmap written.

**Build phase (M0–M22 below): ⬜ Not started.** Verified directly against the repo — `lib/` still contains only the 3 default plugin files (56 lines total), no `lib/src/`, no native `detection/protection/bridge` packages on either platform, no new tests beyond the default two. Every checkbox below is unchecked because nothing has been built yet, not as an oversight — marking anything ✅ here would misrepresent where the project actually is.

As implementation starts, come back to this file and check items off as they land — that's what turns this into a live progress tracker instead of a one-time plan.

---

## M0 — Decisions & Repo Setup ⬜ *Not started — blocking*
*Blocking. Nothing below builds correctly until these are settled.*

- [ ] **Decide folder structure**: adopt the SRS's layer-first `lib/src/{core,manager,bridge,detectors,protections,events,models,config,permission,utils}` layout; retire the current per-feature `lib/features/*/{data,domain,infrastructure}` scaffold.
- [x] **Resolve channel naming** — decided in Phase 7: `device_shield/native_bridge` (MethodChannel) + `device_shield/events` (EventChannel), implemented in `DefaultNativeBridge`. The pre-existing `device_shield` channel (Phase 1, `getPlatformVersion`) is kept unchanged, not merged or renamed.
- [ ] **Confirm platform floors**: verify iOS 18.0 / Android API 21 are the real intended minimums (current build config targets iOS 13.0 / API 24 — mismatch to resolve either direction).
- [ ] Set up native package skeletons: `android/.../detection/ protection/ bridge/ utils/` and `ios/Classes/detection/ protection/ bridge/ utils/`.
- [ ] Set up `test/unit/ test/integration/ test/native/` directories per the SRS's test layout.
- [ ] Update placeholder identifiers (`com.example.device_shield`, podspec author/homepage) to real values.
- [ ] Decide and scope a **v0.1 MVP** subset (recommended: P0 FRs only — root, jailbreak, emulator, debugger, hook, integrity — deferring P1 features to a later milestone) rather than committing the whole SRS to one release.

**Exit criteria:** repo restructured, both native skeletons in place, team has signed off on folder structure + channel names + platform floors + MVP scope.

---

## M1 — Foundation Layer ⬜ *Not started*
*SRS: §3.1 (Core), §8 (Error Handling), §9.1 (enum), §17 (Logging)*

- [ ] Enum Layer: `DetectionType`, `PolicyAction`, `SecurityStatus`, `SecurityEventType`, `SecuritySeverity`, `PinningMode`, `HookFramework`, `DetectionStatus`, `DataSubjectRequestType` (§23).
- [ ] Model Layer: `DetectionResult`, `SecurityEvent`, `NativeResult` — immutable value types.
- [ ] Exception Hierarchy: `DeviceShieldException` base + `ConfigurationException`, `PermissionException`, `InitializationException`, `DetectionException`, `PolicyException`, `NativeBridgeException`.
- [ ] `Logger`: level-gated debug/info/warning/error/exception logging, boots with a safe default (see ASD Part 4 note on the Logger/Config ordering).
- [ ] `DataFilter`: sensitive-field redaction (password, token, key, secret, authorization, credit_card, ssn, pin) — shared by Logging (§17.3) and later by Compliance (§23).

**Exit criteria:** zero external dependencies beyond Dart/Flutter SDK; every later milestone can import from here; unit tests for enum/model serialization and exception `toString()`.

---

## M2 — Configuration & Dependency Injection ⬜ *Not started*
*SRS: §7 (Configuration), §4.7 (DI)*

- [ ] `DeviceShieldConfig` (+ `DetectionModulesConfig`, `ProtectionModulesConfig` sub-configs).
- [ ] `DeviceShieldConfigValidator` — the exact validation rules from §7.4 (interval bounds, retry bounds, timeout bounds).
- [ ] `DeviceShieldConfigBuilder` — fluent builder (§7.2).
- [ ] `ConfigurationPersistence` — SharedPreferences-backed save/load (§7.6).
- [ ] `ConfigurationManager` — holds the single active config, exposes `updateConfig`/`updateDetectionConfig`/`updateProtectionConfig` (§7.5).
- [ ] `ServiceContainer` — `register<T>()` / `get<T>()` / `isRegistered<T>()` / `clear()` (§4.7).

**Exit criteria:** config validation covers every rule in §7.4; `ServiceContainer` round-trip tested (register → get → clear).

---

## M3 — Native Bridge & Platform Channels ⬜ *Not started*
*SRS: §3.4 (Native Bridge), §4.5 (Platform Channel Communication), §15 (Platform-Specific Implementation), §21.1–21.2*

- [ ] Dart: `PlatformChannel` wrapping `MethodChannel` (typed `invoke<T>()`, timeout, `PlatformException` → `NativeBridgeException` translation) and `EventChannel` (typed `Stream<SecurityEvent>`).
- [ ] Dart: `NativeBridge` — the single façade over both channels; `invoke()`, `invokeAsync()`, `registerCallback()`/`unregisterCallback()`.
- [ ] Android (Kotlin): `DeviceShieldPlugin` implementing `MethodCallHandler` **and** `EventChannel.StreamHandler`; a `SecurityManager` shell mirroring the Dart-side architecture.
- [ ] iOS (Swift): same shape — `DeviceShieldPlugin` implementing `FlutterStreamHandler`; a `SecurityManager` shell.
- [ ] `bridge/method_codes.dart` (and native equivalents) — a single source of truth for method-name constants, so nothing is a raw string literal (this matters more once 15+ detectors share the channel — see Roadmap note under M7).
- [ ] Required Android permissions declared (`INTERNET`, `ACCESS_NETWORK_STATE`, `READ_PHONE_STATE`, `SYSTEM_ALERT_WINDOW`, `FOREGROUND_SERVICE`) and iOS `Info.plist` entries (§15.1, §15.2).

**Exit criteria:** one round-trip method call and one event-channel push work end-to-end on both platforms, proven with a throwaway test method before any detector is built on top.

---

## M4 — Event System ⬜ *Not started*
*SRS: §3.5 (Event System Module), §4.4 (Event System Service), §10.3 (Platform Communication)*

- [ ] `SecurityEventFilter` (type / severity / source predicate).
- [ ] `EventProcessor` interface + a first concrete processor (dedup, per the ASD's event-pipeline design — not explicitly named in the SRS, but the extension point the SRS provides for it).
- [ ] `EventManager` (`EventSystemService`): `emit()`, `subscribe()`, `getRecentEvents()`, `clearHistory()`, pause/resume queuing.
- [ ] Bounded in-memory history (`maxHistorySize`, default 100).

**Exit criteria:** emit → filtered subscribe → receive works; a throwing subscriber handler doesn't break other subscribers or the emitting caller (see ASD Part 7).

---

## M5 — State Machine & SDK Lifecycle ⬜ *Not started*
*SRS: §9 (State Management), §4.10 (Lifecycle Handling)*

- [ ] `SecurityStateManager` + transition guard, enforcing the full 8-state table from §9.2.
- [ ] `LifecycleManager` (`WidgetsBindingObserver`): resume → resume monitoring + immediate check; inactive → limited background protections; paused → full background protections + pause monitoring; detached → shutdown.

**Exit criteria:** every transition in §9.2's table is reachable and tested; every transition *not* in the table throws `StateError`.

---

## M6 — PluginInitializer, SecurityManager & Detector/Rule Framework ⬜ *Not started*
*SRS: §3.2 (Detection Manager), §3.3 (Policy Engine — framework only), §4.4, §4.7–4.9, Appendix B*

- [ ] `PluginInitializer` — the fixed 8-step boot sequence (ASD Part 4), with the idempotency guard and failure teardown.
- [ ] `ShutdownSequence` — reverse-order teardown (§4.9).
- [ ] `SecurityManager` (`SecurityManagerService`) — orchestrator, periodic-check timer, `_processDetectionResults` pipeline.
- [ ] `Detector` interface (Appendix B.1: `type`, `priority`, `initialize()`, `check()`, `dispose()`).
- [ ] `DetectorRegistry` + `DetectorFactory` (register/enable/order by priority; factory `switch` over `DetectionType`).
- [ ] `Rule` interface + `PolicyManager` **framework only** — rule list, `evaluate()`, `executeAction()` dispatch table — no default rules yet, no detectors to evaluate yet.
- [ ] `DetectionManager` (`DetectionManagerService`) — `runAllChecks()`, `runCheck(type)`, `registerDetector()`, the `_isChecking` reentrancy guard.
- [ ] `DetectionCache` (TTL-based, §11.3).

**Exit criteria:** the whole boot → running → shutdown cycle works with **zero concrete detectors registered** — this milestone proves the framework holds before a single feature is built on it. This is the most important milestone to get right; everything from here on just plugs into it.

---

## M7 — Priority-0 Detectors ⬜ *Not started*
*SRS: FR-01, FR-02, FR-03, FR-04, FR-07, FR-08 · §5.1–5.6*

Each detector below is: one `Detector` implementation (Dart) + one native implementation (Kotlin + Swift where applicable) + its `*Config` class + registration in `DetectorFactory`.

- [ ] **Root Detection** (Android) — FR-01, §5.1. Techniques: su binary, superuser apps, writable system, BusyBox, Magisk, hiding-technique checks.
- [ ] **Jailbreak Detection** (iOS) — FR-02, §5.2. Techniques: Cydia/Substrate paths, writable filesystem, suspicious paths, jailbreak APIs.
- [ ] **Emulator Detection** (Android + iOS) — FR-03, §5.3.
- [ ] **Debugger Detection** (Android + iOS) — FR-04, §5.4.
- [ ] **Runtime Hook Detection** (Android + iOS) — FR-07, §5.5. Frameworks: Frida, Xposed, Substrate, Magisk modules.
- [ ] **App Integrity** (Android Play Integrity / iOS DeviceCheck) — FR-08, §5.6.

**Parallelizable:** these six are independent of each other — different people/platforms can build them concurrently once M6 is done, as long as each registers through the same `DetectorFactory`/`DetectorRegistry` from M6 rather than inventing its own path.

**Exit criteria:** each detector runs standalone via `runCheck(type)`; concurrency model from the ASD (bounded-parallel `runAllChecks()`) is validated once at least 3 of these exist together.

---

## M8 — Priority-1 Detectors ⬜ *Not started*
*SRS: FR-05, FR-06 · §5 (brief sections)*

- [ ] **Developer Options Detection** (Android) — FR-05.
- [ ] **Mock Location Detection** (Android + iOS) — FR-06.

**Exit criteria:** same as M7; both plug into the existing framework with no manager-level changes.

---

## M9 — Policy Engine Content & Custom Rules ⬜ *Not started*
*SRS: FR-16, FR-17 · §3.3, §6.4*

- [ ] Default rule set per detection type (priority-ordered `SecurityPolicy` entries — thresholds, blocking flags, cooldowns).
- [ ] Action handlers: `ignore`, `warn`, `block`, `logout`, `terminate`, `report`, and the `custom` slot (§3.3, §Extension Points in the ASD).
- [ ] Risk-score calculation (`calculateRiskScore`, weighted across results).
- [ ] `CustomRule` public class + `DeviceShield.addRule()`/`removeRule()` (FR-17, §6.4).
- [ ] Validation: max 100 rules, no circular rule dependencies (FR-16).

**Exit criteria:** a `DetectionResult` from any M7/M8 detector produces a correct `PolicyAction`; a runtime-added `CustomRule` is evaluated without restarting the SDK.

---

## M10 — Security Profiles ⬜ *Not started*
*SRS: FR-14 · §6.2*

- [ ] `SecurityProfile` class (`detectionConfigs`, `policyConfigs`, `protectionConfigs`).
- [ ] Five factory profiles: `fintech()`, `healthcare()`, `government()`, `enterprise()`, `consumer()` — exact detector/threshold/action combinations from §6.2's table.

**Exit criteria:** each profile initializes the SDK correctly with only its documented detectors enabled and its documented policy actions wired.

---

## M11 — Protections ⬜ *Not started*
*SRS: FR-09, FR-10, FR-11, FR-12, FR-13 · §5.7–5.8*

- [ ] **Screenshot Protection** — FR-09, §5.7. Android `FLAG_SECURE`; iOS detection + blur-on-background widget.
- [ ] **Screen Recording Detection** — FR-10. iOS `ReplayKit` monitoring; Android recording-API detection.
- [ ] **Overlay Detection** (Android) — FR-11. `SYSTEM_ALERT_WINDOW` monitoring.
- [ ] **Clipboard Protection** — FR-12. Auto-clear timeout, copy suppression on sensitive fields.
- [ ] **SSL Pinning** — FR-13, §5.8. Certificate/public-key/hash pinning, backup pins, `CertificatePinner`.

**Parallelizable:** independent of detectors and of each other; can start as soon as M3 (Native Bridge) and M2 (Configuration) exist — doesn't need to wait for M7/M8/M9/M10.

**Exit criteria:** each protection toggles on/off via its `ProtectionConfig`, consistent with how detectors toggle via `DetectionConfig`.

---

## M12 — Public API & UI Components ⬜ *Not started*
*SRS: §6 (Public API Documentation), §14 (UI Components)*

- [ ] `DeviceShield` static class: `initialize()`, `status`, `pause()`, `resume()`, `shutdown()`, `events`, `registerDetector()`, `profile`.
- [ ] `SecurityEvent`, `CustomRule` public surfaces finalized (already built in M4/M9 — this is where they're exposed through `DeviceShield` itself).
- [ ] `DeviceShieldWidget` — loading/error/child states around `initialize()` (§14.1).
- [ ] `SecurityAlertDialog` — severity-keyed alert UI (§14.2).
- [ ] `ScreenshotProtection` widget — background blur overlay (§14.3).

**Exit criteria:** the example app in M19 can run entirely through this layer without ever touching an internal manager directly — this is the real test of whether the public API is complete.

---

## M13 — Storage, Encryption & Security Utilities ⬜ *Not started*
*SRS: §11 (Storage), §12 (Security)*

- [ ] `SecureStorage` wrapper (flutter_secure_storage, namespaced keys) — §11.1.
- [ ] Shared-preferences typed getters/setters for non-sensitive config — §11.2.
- [ ] `EncryptionUtils` — AES-256-CBC encrypt/decrypt, key/IV generation, SHA-256 hashing — §12.1.
- [ ] `KeyManager` — lazy master key + device-specific key creation/persistence — §12.2.
- [ ] `IntegrityValidator` — app-signature allow-list check — §12.4.
- [ ] `DataProtection` — wraps sensitive strings with master-key encryption before persistence/transmission — §12.5.

**Exit criteria:** `CertificatePinner` (M11) and `App Integrity` (M7) both consume these utilities rather than duplicating crypto logic.

---

## M14 — Performance & Caching ⬜ *Not started*
*SRS: §13 (Performance)*

- [ ] Generic `MultiLevelCache` (TTL-based, auto-expiry sweep) — §13.4, backing `DetectionCache` from M6 and any other short-lived values.
- [ ] `PerformanceMonitor` — running average per named operation, warns above 100ms — §21.4.
- [ ] Automated benchmark tests validating §13.1's targets (startup <500ms, memory <20MB, CPU <5%, detection latency, event emission <10ms) and Appendix C's per-component figures.
- [ ] Concurrency model from the ASD (bounded-parallel detector execution) implemented and benchmarked against these targets specifically — this is where the scaling risk identified earlier gets closed out.

**Exit criteria:** benchmark suite passes against §13.1 and Appendix C targets with the full M7+M8 detector set enabled.

---

## M15 — Compliance Packs ⬜ *Not started*
*SRS: §23 (Compliance)*

- [ ] `GDPRCompliance` — recursive anonymization of personal-data fields; handler for the 5 `DataSubjectRequestType`s.
- [ ] `PCIDSSCompliance` — rejects raw card fields, masks card numbers, Luhn validation.
- [ ] `HIPAACompliance` — recursive PHI redaction; structured HIPAA audit-trail logging.

**⚠ Before shipping this milestone:** these carry real legal exposure once labeled "GDPR/PCI-DSS/HIPAA compliant" — get legal/security sign-off on the actual field lists and audit format before the label goes in any README or profile name (flagged in the earlier architecture review).

**Exit criteria:** each compliance helper has its field list and audit format explicitly reviewed and approved, not just implemented.

---

## M16 — Internationalization ⬜ *Not started*
*SRS: §24 (Internationalization)*

- [ ] `DeviceShieldLocalization` — en/es/fr/de strings for security-alert UI copy, fallback to English.
- [ ] `getLocalizedMessage()` — maps `SecurityEventType` → message key, with `{{placeholder}}` interpolation.

**Exit criteria:** `SecurityAlertDialog` (M12) renders correctly in all 4 locales.

---

## M17 — Logging & Error-Handling Hardening ⬜ *Not started*
*SRS: §8 (full), §17.2 (Production Logs)*

- [ ] `ProductionLogger` — warning-minimum default, file-writing, monitoring-service forwarding, crash-reporting forwarding for exception-level entries.
- [ ] `RecoveryStrategy` — the full dispatch table from §8.3, wired into every manager's actual catch blocks (not just designed, as in the ASD — implemented).
- [ ] `RetryLogic` — exponential backoff, configurable `retryOn` predicate — wired into Native Bridge calls and detector checks.
- [ ] `LogSink` extension point (ASD Part 10) — so the monitoring-service forwarding above is a registered sink, not hardcoded.

**Exit criteria:** every exception type from M1 has a corresponding recovery path exercised by a test; production log output contains no unredacted sensitive fields (test against the `DataFilter` list from M1).

---

## M18 — Testing Across All Modules ⬜ *Not started*
*SRS: §16 (Testing)*

- [ ] Unit tests reaching the §16.5 coverage targets: Core 90%, Detection Manager 85%, Policy Engine 85%, Event System 85%, Native Bridge 80%, Detectors 80%, Protections 75%.
- [ ] Integration tests: `DeviceShieldWidget` reaches `running` end-to-end; native-bridge round-trip tests.
- [ ] Native tests: Kotlin (`RootDetector`, etc.) and Swift equivalents, confidence-range assertions.
- [ ] Performance tests: startup <500ms, per-detector-check <100ms, via `Stopwatch`-based timing (ties back to M14).
- [ ] **Real-device validation**: root/jailbreak/hook detectors specifically need testing on genuinely rooted/jailbroken hardware, not just mocked file-system checks — this can't be satisfied by unit tests alone (flagged as a risk in the earlier architecture review).

**Exit criteria:** coverage targets met per component; at least one real rooted Android device and one real jailbroken iOS device have run the full detector suite.

---

## M19 — Documentation & Developer Experience ⬜ *Not started*
*SRS: §22 (Developer Experience), §25 (Documentation)*

- [ ] Example app: fintech profile, debug logging on, live status card, scrolling event list, critical-event alert dialog, pause/resume FAB (§22.1).
- [ ] `DevelopmentTools` (debug-only): `runSecurityScan()`, `simulateEvent()`, `dumpState()`, `resetSdk()` (§22.2).
- [ ] Integration guide: quick start, configuration options table, profile descriptions, best practices, troubleshooting table (§22.3).
- [ ] `DocGenerator` — Markdown skeleton generation for API reference (§25.1).
- [ ] Three canonical code snippets (basic usage, event handling, custom rules) shared across README / pub.dev / in-app help (§25.2).

**Exit criteria:** a developer unfamiliar with the SDK can integrate it using only the integration guide, without reading source code.

---

## M20 — Versioning & Deployment ⬜ *Not started*
*SRS: §18 (Versioning), §19 (Deployment)*

- [ ] Semantic versioning policy documented and applied from the first tagged release.
- [ ] `pubspec.yaml` finalized: real name/homepage/repository/issue-tracker (replacing M0's placeholders).
- [ ] CI/CD pipeline (`.github/workflows/release.yml` per §19.2): checkout → Flutter setup → `pub get` → `flutter test --coverage` → build → `pub publish`.
- [ ] Deprecation policy: 180-day window, console warning on deprecated-API use (§18.4).

**Exit criteria:** a tagged release triggers the full pipeline end-to-end against a test/staging pub.dev-equivalent target.

---

## M21 — Edge Case & Resilience Hardening ⬜ *Not started*
*SRS: §26 (Edge Cases and Error Scenarios)*

Explicitly test and handle each row of §26.1's table:

- [ ] App backgrounded → monitoring paused → resumes on foreground.
- [ ] Low memory → cache reduced, old data cleared.
- [ ] Network disconnected → local verification only, events queued.
- [ ] Permission denied → limited functionality, error logged, no crash.
- [ ] Platform version mismatch → graceful degradation to available features.
- [ ] Corrupted persisted configuration → fallback to defaults, warning logged.
- [ ] Concurrent `initialize()` calls → singleton guard prevents duplicate init (already built in M6 — verify here under real concurrency, not just the guard's logic).
- [ ] Multiple detectors firing simultaneously → processed in priority order (verify against M7–M9's actual behavior, not just designed intent).
- [ ] Native bridge failure → retry with backoff, fallback to last cached result.
- [ ] `ErrorRecovery`'s per-error-code dispatch (§26.2) exercised for each code, including the "unrecognized code → fallback to minimal consumer profile" default path.

**Exit criteria:** every row above has a corresponding automated test, not just documented behavior.

---

## M22 — v1.0 Release ⬜ *Not started*
*SRS: §27 (Conclusion), Appendix D (Deployment Checklist)*

- [ ] All tests passing (unit, integration, native, performance, edge-case).
- [ ] Documentation complete (M19).
- [ ] `CHANGELOG.md` updated, version incremented, `pubspec.yaml` finalized.
- [ ] `README.md` updated with the canonical snippets from M19.
- [ ] Example app tested on real devices (both platforms).
- [ ] Native code compiled and verified on both platforms.
- [ ] All required permissions declared (cross-check against M3).
- [ ] License file present.
- [ ] Release notes prepared (§19.3 style: what shipped, no known issues, or a clearly listed set).
- [ ] CI/CD pipeline green (M20).
- [ ] Publishing credentials ready.
- [ ] §20's Future Scope items (AI risk scoring, remote policy management, remote kill switch, device trust score, threat intelligence feed) explicitly logged as a **post-v1.0 backlog**, not silently dropped.

**Exit criteria:** every box above checked → tag and publish v1.0.

---

## Full SRS Section Traceability

Every section of the SRS, mapped to the milestone that covers it — nothing in the document is unaccounted for.

| SRS Section | Covered by |
|---|---|
| §1 Project Overview | Context only — informs M0 scoping decisions |
| §2 Functional Requirements (FR-01–18) | M7, M8, M9, M11 |
| §3.1 Core Module | M1, M6 |
| §3.2 Detection Manager Module | M6 |
| §3.3 Policy Engine Module | M6 (framework), M9 (content) |
| §3.4 Native Bridge Module | M3 |
| §3.5 Event System Module | M4 |
| §4 SDK Architecture (all subsections) | M1–M6 (see also `ARCHITECTURE.md`) |
| §5 Feature Documentation | M7, M8, M11 |
| §6 Public API Documentation | M12 |
| §7 Configuration | M2 |
| §8 Error Handling | M1, M17 |
| §9 State Management | M5 |
| §10 Data Flow | M6, M7, M9 (see also `ARCHITECTURE.md` runtime flow) |
| §11 Storage | M13 |
| §12 Security | M13 |
| §13 Performance | M14 |
| §14 UI Components | M12 |
| §15 Platform-Specific Implementation | M3, M7 |
| §16 Testing | M18 |
| §17 Logging | M1, M17 |
| §18 Versioning | M20 |
| §19 Deployment | M20 |
| §20 Future Scope | M22 (logged as backlog, not built in v1.0) |
| §21 Implementation Details | M3, M5, M14 |
| §22 Developer Experience | M19 |
| §23 Compliance | M15 |
| §24 Internationalization | M16 |
| §25 Documentation | M19 |
| §26 Edge Cases and Error Scenarios | M21 |
| §27 Conclusion | M22 |
| Appendix A: Glossary | Reference material — no build task |
| Appendix B: Reference Implementations | M6 (used as the Detector/Protection contract template) |
| Appendix C: Performance Benchmarks | M14 |
| Appendix D: Deployment Checklist | M22 |

---

## Sequencing Summary

```
M0 Decisions & Setup
 ↓
M1 Foundation → M2 Config/DI → M3 Native Bridge → M4 Event System → M5 State Machine
 ↓
M6 Bootstrap + Manager/Detector/Rule Framework  ← the single most important milestone
 ↓
 ├─ M7 P0 Detectors ─┐
 ├─ M8 P1 Detectors ─┤
 ├─ M9 Policy Content ┤→ M10 Security Profiles
 └─ M11 Protections ──┘   (can start as early as M3, parallel to M7–M10)
 ↓
M12 Public API & UI
 ↓
 ├─ M13 Storage/Encryption
 ├─ M14 Performance/Caching
 ├─ M15 Compliance
 ├─ M16 i18n
 └─ M17 Logging/Error hardening      (M13–M17 can run in parallel)
 ↓
M18 Testing → M19 Docs/DX → M20 Versioning/Deployment → M21 Edge Cases
 ↓
M22 v1.0 Release
```
