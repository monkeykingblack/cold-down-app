---

description: "Dependency-ordered implementation tasks for Cold Down"
---

# Tasks: Cold Down

**Input**: Design documents from `/specs/001-thermal-control/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`, and Cold Down Constitution v1.0.0

**Tests**: Required. Within every user story, write the listed deterministic tests first and confirm they fail for the intended missing behavior before completing that story's production implementation.

**Organization**: Tasks are grouped by user story so each story can be implemented and validated as an independently useful increment. Requirement references use the identifiers from the current `spec.md`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel with other `[P]` tasks in the same section after their shared prerequisites are complete.
- **[Story]**: Maps the task to a user story from `spec.md`.
- Every task includes an exact file path.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the native macOS project, targets, deterministic test surfaces, build identities, and packaged resources.

- [X] T001 Create the planned `Sources/`, `Tests/ThermalControlTests/`, `Tests/ThermalControlUITests/`, `Scripts/`, and `Configuration/` directory skeleton and add Xcode/Swift/macOS generated-file exclusions to `.gitignore`
- [X] T002 Create `ThermalControl.xcodeproj/project.pbxproj` with ThermalControlApp, ThermalCore, IntelSMC, FlydigiHID, ThermalControlShared, ThermalControlHelper, ThermalControlTests, and ThermalControlUITests targets using Swift 6 strict concurrency, macOS 13.0, and universal `arm64`/`x86_64` Debug/Release settings (FR-001)
- [X] T003 [P] Add shared app, helper, unit-test, and UI-test schemes in `ThermalControl.xcodeproj/xcshareddata/xcschemes/ThermalControlApp.xcscheme`, `ThermalControl.xcodeproj/xcshareddata/xcschemes/ThermalControlHelper.xcscheme`, and `ThermalControl.xcodeproj/xcshareddata/xcschemes/ThermalControlUITests.xcscheme`
- [X] T004 Configure centralized app bundle ID, helper bundle ID, Mach-service name, deployment target, and signing substitutions in `Configuration/ProductIdentifiers.xcconfig`, `Configuration/Debug.xcconfig`, and `Configuration/Release.xcconfig` so distribution preparation needs no source edit (FR-012, SC-010)
- [X] T005 [P] Add app metadata, English localization baseline, helper usage descriptions, and application entitlements in `Sources/ThermalControlApp/Resources/Info.plist`, `Sources/ThermalControlApp/Resources/Localizable.xcstrings`, and `Sources/ThermalControlApp/ThermalControlApp.entitlements` (FR-001, FR-025)
- [X] T006 [P] Add helper metadata, substituted Mach service, launch-daemon packaging, and helper entitlements in `Sources/ThermalControlHelper/Resources/Info.plist`, `Sources/ThermalControlHelper/Resources/ThermalControlHelper.plist`, and `Sources/ThermalControlHelper/ThermalControlHelper.entitlements` (FR-012)
- [X] T007 Create the shared unit/UI test plan and mock launch configurations in `ThermalControl.xcodeproj/xcshareddata/xctestplans/ThermalControl.xctestplan` with normal tests independent of a physical cooler or installed helper (FR-031, SC-008)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Define shared value types, protocol boundaries, clocks, diagnostics, actor scaffolding, and deterministic fixtures without implementing user-story behavior.

**Critical**: Complete this phase before beginning any user-story phase.

- [X] T008 Create sensor identity, reading, batch-generation, freshness, grouping, summary, and calculated-sensor value types in `Sources/ThermalCore/Models/SensorModels.swift` (FR-002–FR-005)
- [X] T009 [P] Create fan identity, capability provenance, connection, write-availability, profile, demand, cooling-decision, application-preference, helper-health, and snapshot value types in `Sources/ThermalCore/Models/FanModels.swift` and `Sources/ThermalCore/Models/ApplicationModels.swift` (FR-007, FR-015, FR-017–FR-024)
- [X] T010 Define `SensorProvider`, `FanDevice`, `BuiltInFanReader`, `BuiltInFanController`, `ExternalCoolerController`, `PrivilegedFanHelperClient`, and `ProfileStore` with `Sendable` value boundaries in `Sources/ThermalCore/Protocols/HardwareProtocols.swift` (FR-008–FR-009)
- [X] T011 [P] Define the Objective-C-compatible narrow XPC methods plus NSSecureCoding request, response, fan-record, and error types in `Sources/ThermalControlShared/XPC/PrivilegedFanHelperProtocol.swift` (FR-009–FR-012)
- [X] T012 [P] Add typed errors and privacy-safe OSLog categories for SMC, HID, policy, persistence, UI, XPC, and safety transitions in `Sources/ThermalCore/Support/ThermalControlError.swift` and `Sources/ThermalCore/Support/ThermalLog.swift` (FR-032)
- [X] T013 [P] Add injectable wall/monotonic clocks, refresh scheduling, timeout scheduling, and deterministic manual-clock primitives in `Sources/ThermalCore/Support/ThermalClock.swift`
- [X] T014 Create the dependency-injected `CoolingCoordinator` actor shell, immutable snapshot stream, and lifecycle entry points without policy behavior in `Sources/ThermalCore/Coordination/CoolingCoordinator.swift`
- [X] T015 Build deterministic sensor, reader, controller, cooler, helper, profile-store, clock, ACK, and action-recording doubles in `Tests/ThermalControlTests/Fixtures/HardwareMocks.swift` plus reusable fixtures in `Tests/ThermalControlTests/Fixtures/Fixtures.swift` (FR-031, SC-008)
- [X] T016 [P] Define stable accessibility identifiers and mock/read-only launch arguments shared by the app and UI tests in `Sources/ThermalControlApp/Support/AccessibilityIdentifiers.swift` and `Tests/ThermalControlUITests/UITestLaunchConfiguration.swift` (SC-001, SC-007, SC-009)

**Checkpoint**: Shared types and targets compile; deterministic tests can be authored without invoking real SMC, HID, XPC, or privileged operations.

---

## Phase 3: User Story 1 — Monitor Thermal Health Without Control Access (Priority: P1) 🎯 MVP

**Goal**: Launch without a helper or BS3 Pro, discover available Intel SMC sensors and fans at runtime, reject invalid/late data, and present a compact read-only Overview and complete Sensors page.

**Independent Test**: Launch using `--mock --helper-unavailable` and a no-recognized-sensor fixture; within 10 seconds verify the hottest/unavailable state and every known fan, including a dimmed disconnected BS3 Pro, while all destinations remain navigable and write controls remain disabled.

### Tests for User Story 1

> Write these tests first and verify the intended assertions fail before implementing US1.

- [X] T017 [P] [US1] Add fixed-byte tests for `sp78`, `fpe2`, float, integer, invalid-length, non-finite, and out-of-range SMC decoding in `Tests/ThermalControlTests/Unit/SMCCodecTests.swift` (FR-003–FR-004)
- [X] T018 [P] [US1] Add runtime-key, human-readable fallback, raw-key preservation, disappeared-key, and variable-key-set tests in `Tests/ThermalControlTests/Unit/SMCDiscoveryTests.swift` (FR-002–FR-004)
- [X] T019 [P] [US1] Add newer/older generation, older timestamp, equal-idempotent, equal-conflicting, newer-invalid, newer-missing, and stale-deadline tests in `Tests/ThermalControlTests/Unit/SensorOrderingAndAggregationTests.swift` (FR-003–FR-005, SC-003)
- [X] T020 [P] [US1] Add CPU/GPU/all averages, hottest/per-group hottest, empty-group, invalid-value, and current-generation-only tests in `Tests/ThermalControlTests/Unit/SensorSummaryTests.swift` (FR-004–FR-005, SC-003)
- [X] T021 [P] [US1] Add fan-count, optional target/mode, missing-bound, inverted-bound, zero/negative-minimum, equal-positive-bound, inconsistent-telemetry, and changed-identity tests in `Tests/ThermalControlTests/Unit/BuiltInFanReaderTests.swift` (FR-007)
- [X] T022 [P] [US1] Add 200-generation virtual-clock tests covering 1-, 2-, and 30-second refresh intervals, provider-to-snapshot latency, and explicit 197/200 fail versus 198/200 pass calculations in `Tests/ThermalControlTests/Integration/RefreshLatencyTests.swift` (FR-006, SC-002)
- [X] T023 [P] [US1] Add a no-helper/no-cooler/missing-key read-only journey test with retained disconnected devices, disabled writes, and all destinations in `Tests/ThermalControlTests/Integration/ReadOnlyMonitoringTests.swift` (FR-008, FR-025–FR-027, SC-003, SC-008–SC-009)
- [X] T024 [P] [US1] Add mock UI launch tests that start timing immediately before launch and require hottest/unavailable accessibility state plus every fixture fan within 10 seconds in `Tests/ThermalControlUITests/StartupReadinessUITests.swift` (SC-001, SC-009)

### Implementation for User Story 1

- [X] T025 [P] [US1] Implement type-aware AppleSMC byte conversion and temperature/RPM validation in `Sources/IntelSMC/Codec/SMCValueCodec.swift` (FR-003–FR-004)
- [X] T026 [US1] Implement the read-only IOKit AppleSMC connection, key-info cache, `#KEY` enumeration, and scoped resource cleanup in `Sources/IntelSMC/Transport/AppleSMCConnection.swift` (FR-002, FR-007)
- [X] T027 [P] [US1] Implement known-key names plus conservative CPU/GPU/heatsink/memory/PCH/battery/ambient/other heuristics in `Sources/IntelSMC/Discovery/SMCSensorCatalog.swift` (FR-002–FR-003)
- [X] T028 [US1] Implement monotonic-generation temperature probing, timestamp conflict rejection, explicit missing/invalid publication, and raw-key preservation in `Sources/IntelSMC/Discovery/AppleSMCSensorProvider.swift` (FR-002–FR-004)
- [X] T029 [US1] Implement unprivileged built-in fan discovery and current/min/max/target/mode telemetry with malformed-capability write disablement in `Sources/IntelSMC/Discovery/AppleSMCFanReader.swift` (FR-007–FR-008)
- [X] T030 [US1] Implement fresh-current-generation-only aggregation, calculated sensors, and explicit stale/unavailable state in `Sources/ThermalCore/Policy/SensorAggregator.swift` (FR-003–FR-005)
- [X] T031 [US1] Implement 1...30-second refresh scheduling with a 2-second default, generation commit ordering, snapshot publication, and latency instrumentation in `Sources/ThermalCore/Coordination/CoolingCoordinator.swift` (FR-006, SC-002–SC-003)
- [X] T032 [P] [US1] Implement deterministic changing sensor/fan data, no-sensor, missing-key, disconnected-cooler, and helper-unavailable scenarios in `Sources/ThermalControlApp/Services/MockMonitoringBackend.swift` (FR-031)
- [X] T033 [US1] Bridge immutable coordinator snapshots, readiness state, and destination/fan navigation to the main actor in `Sources/ThermalControlApp/Models/AppModel.swift`
- [X] T034 [US1] Build the compact native `NavigationSplitView` sidebar and destination routing in `Sources/ThermalControlApp/Views/RootView.swift`, following the supplied HTML mockup's hierarchy without using a web view (FR-025)
- [X] T035 [US1] Build Overview's read-only all-fan summary, important-sensor list, dimmed disconnected state, concise messages, and fan-to-Fans navigation in `Sources/ThermalControlApp/Views/OverviewView.swift` (FR-026, SC-001)
- [X] T036 [US1] Build the compact complete sensor table and calculated summaries with raw keys, groups, temperatures, sentence-case headers, and fresh/stale/unavailable states in `Sources/ThermalControlApp/Views/SensorsView.swift` (FR-027)

**Checkpoint**: US1 is a usable native read-only MVP that passes T017–T024 without physical hardware or privileged installation.

---

## Phase 4: User Story 2 — Apply Safe Automatic Cooling (Priority: P2)

**Goal**: Apply deterministic maximum-demand arbitration and the two-stage external-first ramp through a capability-gated Flydigi transport and fail-safe privileged helper.

**Independent Test**: Drive multiple profiles, 45/72/85°C thresholds, 94.999/95°C boundaries, stale/missing data, connected/disconnected/capability-limited coolers, ACK success/failure, helper disconnect, lease expiry, sleep, and wake through mocks; verify exact targets, no forbidden reports, external ACK ordering, and built-in Auto restoration.

### Tests for User Story 2

> Write these tests first and verify the intended assertions fail before implementing US2.

- [X] T037 [P] [US2] Add 25-byte encode/decode fixtures, checksum and bounds cases, VID/PID/usage matching, allowed typed commands, and hard denial of `0x05`, `0x06`, raw, RGB, firmware, reset, power, and zero-speed-stop commands in `Tests/ThermalControlTests/Unit/FlydigiPacketCodecTests.swift` (FR-013–FR-016)
- [X] T038 [P] [US2] Add serialized transaction, register-before-write, ACK correlation, corrupt/unrelated frame, 900 ms timeout, three-attempt/under-5-second bound, detach cancellation, and reconnect-without-replay tests in `Tests/ThermalControlTests/Unit/FlydigiTransactionTests.swift` (FR-013–FR-014, SC-006)
- [X] T039 [P] [US2] Add unverified/device-verified/audited-model/mock-only provenance, malformed range/step, read-only attach query, capability-limited UI state, and zero-mutating-report tests in `Tests/ThermalControlTests/Unit/FlydigiCapabilityTests.swift` (FR-013, FR-015–FR-016)
- [X] T040 [P] [US2] Add exact 45/72/85°C boundary, interpolation, step-rounding, current-RPM-floor, zero-width-Hot, lexicographic demand tie, any-sensor Critical, precedence, verified-stop Cool, no-stop verified-minimum Cool, and disconnected/capability-limited Cool no-transmit fixtures in `Tests/ThermalControlTests/Unit/CoolingPolicyTests.swift` (FR-017, FR-018, FR-019, FR-020, SC-005)
- [X] T041 [P] [US2] Add coordinator tests proving write-ready connected-cooler maximum ACK precedes internal increases, failed required ACK suppresses that cycle's increase, disconnected/capability-limited coolers do not block otherwise eligible validated Hot built-in increases and are never reported active, stale selected Auto sources request verified external maximum only when write-ready and restore built-ins to Auto, plus helper-loss and Critical restoration cases in `Tests/ThermalControlTests/Integration/CoolingCoordinatorSafetyTests.swift` (FR-011, FR-018–FR-020, SC-004–SC-005)
- [X] T042 [P] [US2] Add helper tests for narrow-method enforcement, fan-count/index validation, missing/stale/inverted/zero ranges, clamping, no-stop, lease expiry, disconnect, invalid state, app exit, sleep, wake, and restore-before-next-target ordering in `Tests/ThermalControlTests/Unit/PrivilegedHelperSafetyTests.swift` (FR-009, FR-010, FR-011, SC-004)
- [X] T043 [P] [US2] Add release expected-identity rejection, development validation retention, secure-class allowlist, single-controller lease ownership, and XPC invalidation tests in `Tests/ThermalControlTests/Unit/HelperXPCSecurityTests.swift` (FR-009, FR-012)

### Implementation for User Story 2

- [X] T044 [P] [US2] Implement the verified 25-byte report codec, typed command allowlist, checksum, ACK decoder, and destructive/raw-command denial in `Sources/FlydigiHID/Protocol/FlydigiPacketCodec.swift` (FR-014, FR-016)
- [X] T045 [US2] Implement IOHIDManager matching for VID `0x37D7`, PID `0x1004`, usage page `0xFFA0`, usage `0x00FF`, product/firmware inspection, and attach/detach callbacks in `Sources/FlydigiHID/Transport/FlydigiHIDTransport.swift` (FR-013)
- [X] T046 [US2] Implement the serialized actor transaction queue with register-before-write, matching ACK validation, 900 ms timeout, at most three attempts, and detach cancellation in `Sources/FlydigiHID/Transport/FlydigiTransactionExecutor.swift` (FR-014, SC-006)
- [X] T047 [US2] Implement read-only attach queries, automatic reconnect, operating state, capability provenance, verified-range gating for both `0x23` and `0x21`, and no target replay in `Sources/FlydigiHID/Device/BS3ProController.swift` (FR-013, FR-015–FR-016)
- [X] T048 [P] [US2] Implement pure maximum-demand arbitration, verified-stop/no-stop-minimum/capability-limited-no-transmit Cool branches, any-fresh-sensor Critical pre-pass, stale-selected-source SafetyFallback, exact two-stage interpolation, rounding/clamping, current-RPM floor, threshold-85 guard, and write-ready-only external ACK prerequisites in `Sources/ThermalCore/Policy/CoolingPolicy.swift` (FR-011, FR-017–FR-020)
- [X] T049 [P] [US2] Implement typed NSXPCConnection setup, secure allowed classes, helper status, interruption/invalidation handling, lease heartbeat, and restore-on-shutdown calls in `Sources/ThermalControlApp/Services/PrivilegedHelperClient.swift` (FR-008–FR-012)
- [X] T050 [US2] Implement helper-private AppleSMC discovery and only validated Auto/target-RPM writes with independent identity/range/step checks in `Sources/ThermalControlHelper/Service/HelperSMCFanController.swift` (FR-009–FR-011)
- [X] T051 [P] [US2] Implement the 8-second lease renewed every 2 seconds with single-controller ownership, deterministic expiry, and restore-all callback in `Sources/ThermalControlHelper/Service/HelperLeaseManager.swift` (FR-011)
- [X] T052 [US2] Implement the exported helper service with operation allowlist, rediscovery, fan-index validation, range validation, RPM clamping, no-stop enforcement, request serialization, and invalid-state restoration in `Sources/ThermalControlHelper/Service/PrivilegedFanHelperService.swift` (FR-009–FR-011)
- [X] T053 [US2] Implement Release expected-app signing validation from centralized identifiers and the documented development identity exception in `Sources/ThermalControlHelper/Service/HelperXPCListener.swift` (FR-012)
- [X] T054 [US2] Implement XPC disconnect, controlling-client replacement, SIGTERM, app exit, sleep, and wake handling with restore-all-before-reuse in `Sources/ThermalControlHelper/Service/HelperLifecycleMonitor.swift` (FR-011, FR-032)
- [X] T055 [US2] Wire the launch-daemon listener, lease, lifecycle monitor, and best-effort termination restoration in `Sources/ThermalControlHelper/main.swift` (FR-009–FR-012)
- [X] T056 [US2] Implement SMAppService.daemon registration, status observation, approval states, and non-fatal unavailable-helper behavior in `Sources/ThermalControlApp/Services/HelperRegistrationService.swift` (FR-008, FR-028)
- [X] T057 [US2] Integrate policy evaluation and side effects into `Sources/ThermalCore/Coordination/CoolingCoordinator.swift`, enforcing external ACK prerequisites only for write-ready coolers, failed-cycle suppression, unavailable coolers that never block otherwise eligible Hot built-in increases or appear active, stale-source external-maximum-if-ready plus built-in-Auto fallback, global restoration, and privacy-safe safety logs (FR-011, FR-017–FR-020, FR-032)
- [X] T058 [P] [US2] Add deterministic ACK, timeout, reconnect, capability provenance, lease expiry, helper interruption, and ordered fan-write scenarios in `Sources/ThermalControlApp/Services/MockCoolingBackend.swift` (FR-031)

**Checkpoint**: US2 passes T037–T043 using mocks; no real transport can emit a mutating Flydigi report without verified capabilities, and every privileged failure path restores macOS Auto.

---

## Phase 5: User Story 3 — Configure Individual Fans Manually (Priority: P3)

**Goal**: Configure and persist validated per-fan Auto or Manual profiles with synchronized controls, safe startup, capability-aware disabled states, and at most four direct interactions.

**Independent Test**: For every connected, write-ready mock fan, complete Auto configuration in at most four semantic actions and Manual in at most three, verify slider/numeric synchronization and 45...85°C/default-72 validation, relaunch to validate persistence and safe built-in Auto startup, and verify disconnected or capability-limited external controls stay disabled without losing profiles.

### Tests for User Story 3

> Write these tests first and verify the intended assertions fail before implementing US3.

- [X] T059 [P] [US3] Add Codable round-trip, corrupt/versioned-data fallback, 45...85°C/default-72 validation, physical/CPU-average/GPU-average/all-average/hottest choices, hottest-CPU default/fallback, all-average non-default, missing sensor/fan, capability change, and manual-target validation tests in `Tests/ThermalControlTests/Unit/ProfilePersistenceTests.swift` (FR-021, FR-022, FR-023, FR-024, FR-030)
- [X] T060 [P] [US3] Add Auto/Manual transition, safe startup intent-only load, explicit healthy reapply, stale/all-unusable sensor suspension, helper loss, invalid capability, and profile-retention tests in `Tests/ThermalControlTests/Unit/FanProfileTransitionTests.swift` (FR-011, FR-021–FR-024)
- [X] T061 [P] [US3] Add synchronized slider/numeric edits, one-degree threshold steps, typed clamping, fixed-range fan, disconnected state, capability-limited state, and concise message tests in `Tests/ThermalControlTests/Unit/FanConfigurationViewModelTests.swift` (FR-015, FR-021–FR-023)
- [X] T062 [P] [US3] Add action-counted UI journeys for every connected, write-ready fixture fan, requiring Auto configuration in at most four semantic actions and Manual in at most three with synchronized values; also assert connected capability-limited and disconnected fixtures stay visible but disabled and are excluded from configurability timing in `Tests/ThermalControlUITests/FanConfigurationJourneyUITests.swift` (FR-015, FR-023, SC-007)

### Implementation for User Story 3

- [X] T063 [US3] Implement schema-versioned Codable UserDefaults persistence, corruption fallback, profile intent loading, all required Auto sensor choices, current-hardware validation, hottest-CPU default/fallback, all-average non-default enforcement, and capability-safe migration in `Sources/ThermalCore/Persistence/UserDefaultsProfileStore.swift` (FR-021, FR-022, FR-024, FR-030)
- [X] T064 [US3] Implement coordinator profile updates, persistence, macOS Auto startup, fresh-sensor/helper-health gates, explicit validated reapplication, and suspension without profile deletion in `Sources/ThermalCore/Coordination/CoolingCoordinator.swift` (FR-011, FR-021–FR-024, FR-030)
- [X] T065 [P] [US3] Implement fan selection and synchronized validated Auto/Manual editing state with semantic action instrumentation in `Sources/ThermalControlApp/Models/FanConfigurationViewModel.swift` (FR-021–FR-023, SC-007)
- [X] T066 [US3] Build the complete fan list with type, connection, current speed, mode, selected state, dimmed disconnected rows, and concise connection/capability messages in `Sources/ThermalControlApp/Views/FansView.swift` (FR-015, FR-025)
- [X] T067 [US3] Build compact Auto sensor/45...85°C threshold and Manual speed panels with synchronized sliders/numeric inputs, fixed-range behavior, clamping, and disabled unavailable actions in `Sources/ThermalControlApp/Views/FanConfigurationView.swift` (FR-021–FR-023, SC-007)
- [X] T068 [US3] Build Settings controls with separated title/description blocks for login item, menu temperature, 1...30-second refresh, reconnect, helper status, and mandatory non-disableable Auto restoration in `Sources/ThermalControlApp/Views/SettingsView.swift` (FR-006, FR-028)
- [X] T069 [US3] Implement SMAppService login-item registration and preference synchronization in `Sources/ThermalControlApp/Services/LaunchAtLoginService.swift` (FR-028, FR-030)

**Checkpoint**: US3 passes T059–T062 and persists validated intent without blindly restoring unsafe hardware state.

---

## Phase 6: User Story 4 — Check Status From the Menu Bar (Priority: P4)

**Goal**: Provide an optional compact menu-bar temperature and native popover using the existing coordinator snapshot rather than a second hardware connection.

**Independent Test**: Toggle menu temperature, inject fresh/no-valid-temperature and connected/disconnected/capability-limited snapshots, and verify the label, hottest sensor, all internal RPM summaries, BS3 state, overall mode, and Open Cold Down action.

### Tests for User Story 4

> Write this test first and verify the intended assertions fail before implementing US4.

- [X] T070 [P] [US4] Add snapshot-to-menu presentation tests for preference toggling, no-valid-temperature fallback, multiple built-in fans, connected/disconnected/capability-limited BS3 state, overall mode, and open-window action in `Tests/ThermalControlTests/Unit/MenuBarPresentationTests.swift` (FR-029)

### Implementation for User Story 4

- [X] T071 [US4] Implement menu label and popover presentation state derived solely from shared coordinator snapshots in `Sources/ThermalControlApp/Models/MenuBarViewModel.swift` (FR-029)
- [X] T072 [US4] Build the compact native fan-icon MenuBarExtra with hottest sensor, built-in RPMs, external state, overall mode, plain Open/Quit actions, and main-window activation in `Sources/ThermalControlApp/Views/MenuBarContentView.swift` (FR-029)
- [X] T073 [US4] Compose WindowGroup, Settings, MenuBarExtra, one coordinator lifetime, mock/read-only launch fixtures, termination restoration, close-to-menu-bar/Dock lifecycle, and Open Cold Down activation in `Sources/ThermalControlApp/Application/ThermalControlApp.swift` and `Sources/ThermalControlApp/Views/RootView.swift` (FR-025, FR-029, FR-031)

**Checkpoint**: US4 passes T070 and all status surfaces consume one immutable coordinator snapshot.

---

## Phase 7: Polish & Cross-Cutting Verification

**Purpose**: Complete accessibility, documentation, concurrency review, distribution tooling, builds, tests, and launch-mode evidence without expanding the MVP hardware surface.

- [X] T074 [P] Add English VoiceOver labels, accessibility identifiers, keyboard focus order, compact control sizing, and loading/empty/error states across `Sources/ThermalControlApp/Views/RootView.swift`, `Sources/ThermalControlApp/Views/OverviewView.swift`, `Sources/ThermalControlApp/Views/FansView.swift`, `Sources/ThermalControlApp/Views/FanConfigurationView.swift`, `Sources/ThermalControlApp/Views/SensorsView.swift`, `Sources/ThermalControlApp/Views/SettingsView.swift`, and `Sources/ThermalControlApp/Views/MenuBarContentView.swift` (FR-001, FR-025)
- [X] T075 [P] Implement parameterized universal `arm64`/`x86_64` Release archive creation with unsigned and Developer ID modes, centralized identifier inputs, and no source rewriting in `Scripts/archive-release.sh` (SC-010)
- [X] T076 [P] Implement archive layout, architecture, deployment metadata, helper/plist/Mach-service, entitlement, helper-first/app-last ad-hoc rehearsal, strict codesign, optional notary, stapler, and Gatekeeper validation in `Scripts/validate-distribution.sh` (FR-012, SC-010)
- [X] T077 [P] Document architecture, requirements-to-module mapping, universal Intel/Apple-Silicon and macOS 13+ build instructions, current SDK verification boundary, entitlements, identifiers, helper signing/installation, notarization, hardware limitations, mock mode, reference licenses, and Flydigi `0x05`/`0x06` warning in `README.md`
- [X] T078 [P] Create completed-functionality, exact command evidence, test/build results, unresolved warnings, and physical hardware/signing blocker sections in `IMPLEMENTATION_REPORT.md`
- [X] T079 Audit actor isolation, `Sendable` boundaries, continuation cancellation, HID/SMC off-main execution, identifier substitution, and correctness/concurrency warnings across `Sources/`, `Tests/`, and `ThermalControl.xcodeproj/project.pbxproj`, recording resolutions in `IMPLEMENTATION_REPORT.md`
- [X] T080 Run the complete ThermalControlTests package and native hosted unit/integration suites, resolve failures, and record the exact commands and results in `IMPLEMENTATION_REPORT.md` (SC-002–SC-006, SC-008)
- [X] T081 Run the mock-backed ThermalControlUITests suite from `ThermalControl.xcodeproj`, resolve failures, and record startup timing and interaction-count results in `IMPLEMENTATION_REPORT.md` (SC-001, SC-007–SC-009)
- [X] T082 Build ThermalControlApp for macOS x86_64 Debug from `ThermalControl.xcodeproj`, resolve correctness/concurrency warnings, and record the command and result in `IMPLEMENTATION_REPORT.md` (FR-001)
- [X] T083 Build ThermalControlHelper for macOS x86_64 Debug from `ThermalControl.xcodeproj`, verify launch-daemon bundle placement, and record the command and result in `IMPLEMENTATION_REPORT.md`
- [X] T084 Execute the full mock-mode scenarios from `specs/001-thermal-control/quickstart.md`, including profiles, arbitration, all three Cool branches, ramp boundaries, write-ready ACK ordering, unavailable-cooler Hot behavior, stale-source fallback, Critical, capability-limited state, and all UI destinations, recording evidence in `IMPLEMENTATION_REPORT.md` (FR-031)
- [X] T085 Execute no-BS3-Pro, no-helper, and no-recognized-SMC-key launch checks from `specs/001-thermal-control/quickstart.md`, confirming read-only monitoring/navigation and recording evidence in `IMPLEMENTATION_REPORT.md` (FR-008, SC-009)
- [X] T086 Create and validate the unsigned universal `arm64`/`x86_64` Release archive plus temporary-copy ad-hoc signability rehearsal using `Scripts/archive-release.sh` and `Scripts/validate-distribution.sh`, recording bundle/layout results without claiming Developer ID validation in `IMPLEMENTATION_REPORT.md` (SC-010)
- [ ] T087 When Developer ID and notary credentials are available, run credentialed archive, strict signature/designated-requirement checks, notarization, stapling, and Gatekeeper assessment through `Scripts/archive-release.sh` and `Scripts/validate-distribution.sh`; otherwise record the exact unavoidable blocker in `IMPLEMENTATION_REPORT.md` without marking credentialed validation complete (FR-012, SC-010)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies; start here.
- **Foundational (Phase 2)**: Depends on Setup and blocks all user stories.
- **US1 (Phase 3)**: Depends on Foundation and delivers the read-only MVP.
- **US2 (Phase 4)**: Depends on Foundation; its policy/transport tests run with mocks, while final coordinator integration uses the snapshot shell established in Foundation and monitoring behavior from US1.
- **US3 (Phase 5)**: Depends on Foundation; profile tests are independently mockable, while final UI integration builds on US1 navigation and US2 safety behavior.
- **US4 (Phase 6)**: Depends on Foundation and consumes mock coordinator snapshots independently; final scene composition integrates completed destinations.
- **Polish (Phase 7)**: Depends on all stories selected for release.

### User Story Dependency Graph

```text
Setup → Foundation → US1 (P1 read-only MVP)
                   ├→ US2 (P2 safe automatic cooling)
                   ├→ US3 (P3 per-fan configuration)
                   └→ US4 (P4 menu-bar status)

Release verification requires US1 + US2 + US3 + US4.
```

### Within Each User Story

1. Author the story's tests and confirm they fail for the expected missing behavior.
2. Implement codecs/models before transports and services.
3. Implement services before coordinator and UI integration.
4. Run all story tests and its independent checkpoint before moving on.
5. Never enable hardware behavior merely to make a mock or UI test pass.

### Parallel Opportunities

- T003, T005, and T006 can proceed concurrently after T002 establishes target names.
- T009 and T011–T013 can proceed concurrently after T008 establishes shared sensor primitives.
- US1 tests T017–T024 can be authored concurrently; T025, T027, and T032 touch separate modules.
- US2 tests T037–T043 can be authored concurrently; T044, T048, T049, T051, and T058 touch separate modules.
- US3 tests T059–T062 can be authored concurrently; T065 is isolated from persistence and view files.
- US4 presentation tests can be authored independently against fixture snapshots.
- T074–T078 can proceed concurrently after public behavior and paths stabilize.

## Parallel Examples

### User Story 1

```text
T017: Tests/ThermalControlTests/Unit/SMCCodecTests.swift
T019: Tests/ThermalControlTests/Unit/SensorOrderingAndAggregationTests.swift
T022: Tests/ThermalControlTests/Integration/RefreshLatencyTests.swift
T024: Tests/ThermalControlUITests/StartupReadinessUITests.swift
```

### User Story 2

```text
T037: Tests/ThermalControlTests/Unit/FlydigiPacketCodecTests.swift
T039: Tests/ThermalControlTests/Unit/FlydigiCapabilityTests.swift
T040: Tests/ThermalControlTests/Unit/CoolingPolicyTests.swift
T042: Tests/ThermalControlTests/Unit/PrivilegedHelperSafetyTests.swift
```

### User Story 3

```text
T059: Tests/ThermalControlTests/Unit/ProfilePersistenceTests.swift
T060: Tests/ThermalControlTests/Unit/FanProfileTransitionTests.swift
T061: Tests/ThermalControlTests/Unit/FanConfigurationViewModelTests.swift
T062: Tests/ThermalControlUITests/FanConfigurationJourneyUITests.swift
```

## Implementation Strategy

### MVP First

1. Complete Setup and Foundation.
2. Complete US1 tests before US1 implementation.
3. Complete US1 and run T017–T024 plus the independent checkpoint.
4. Demonstrate a native read-only app with mock or real SMC data, no helper, and no BS3 Pro.

### Incremental Delivery

1. **US1**: Runtime monitoring and native Overview/Sensors UI.
2. **US2**: Verified external-first automatic cooling and fail-safe privileged control.
3. **US3**: Validated per-fan configuration, persistence, and Settings.
4. **US4**: Menu-bar status and window activation.
5. **Polish**: Accessibility, documentation, deterministic suites, x86_64 builds, archives, and launch-mode evidence.

## Notes

- `[P]` means different files and no unmet dependency within the indicated starting point; tasks modifying `CoolingCoordinator.swift` remain sequential.
- Test tasks precede story implementation as required by the constitution.
- Real Flydigi mutating commands remain disabled until capability evidence is device-verified or audited and physically validated; deterministicMock provenance never authorizes the real transport.
- Commands `0x05` and `0x06`, raw reports, RGB, firmware, reset, power, and unverified zero-speed stop remain forbidden.
- Built-in fan profiles load as intent only; macOS Auto is the startup and failure baseline.
- Missing hardware or signing credentials may block physical validation but never block deterministic tests, read-only operation, protocol implementation, or x86_64 compilation.
