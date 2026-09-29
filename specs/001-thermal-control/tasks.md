---

description: "Dependency-ordered implementation tasks for Cold Down"
---

# Tasks: Cold Down

**Input**: Design documents from `/specs/001-thermal-control/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`, and Cold Down Constitution v1.0.0

**Tests**: Required. Within every user story, write the listed deterministic tests first and confirm they fail for the intended missing behavior before completing that story's production implementation.

**Organization**: Tasks are grouped by user story so each story can be implemented and validated as an independently useful increment. Requirement references use the identifiers from the current `spec.md`.

**Removed tasks**: Tasks marked *Removed 2026-09-29* covered components that were dropped when the app became cooler-only (see `spec.md`, Clarifications, Session 2026-09-29). Their identifiers are kept so history stays traceable; they are not to be implemented.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel with other `[P]` tasks in the same section after their shared prerequisites are complete.
- **[Story]**: Maps the task to a user story from `spec.md`.
- Every task includes an exact file path.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the native macOS project, targets, deterministic test surfaces, build identities, and packaged resources.

- [X] T001 Create the planned `Sources/`, `Tests/ColdDownTests/`, `Tests/ColdDownUITests/`, `Scripts/`, and `Configuration/` directory skeleton and add Xcode/Swift/macOS generated-file exclusions to `.gitignore`
- [X] T002 Create `ColdDown.xcodeproj/project.pbxproj` with ColdDownApp, ColdDownTests, and ColdDownUITests targets linking the `Package.swift` targets ThermalCore, IntelSMC, AppleSiliconHIDBridge, and FlydigiHID, using Swift 6 strict concurrency, macOS 14.0, and universal `arm64`/`x86_64` Debug/Release settings (FR-001)
- [X] T003 [P] Add shared app and UI-test schemes in `ColdDown.xcodeproj/xcshareddata/xcschemes/ColdDownApp.xcscheme` and `ColdDown.xcodeproj/xcshareddata/xcschemes/ColdDownUITests.xcscheme`
- [X] T004 Configure the centralized app bundle ID, deployment target, and signing substitutions in `Configuration/ProductIdentifiers.xcconfig`, `Configuration/LocalSigning.xcconfig.example`, `Configuration/Debug.xcconfig`, and `Configuration/Release.xcconfig` so distribution preparation needs no source edit (FR-012, SC-010)
- [X] T005 [P] Add app metadata, English localization baseline, and the sandbox-disabled application entitlements in `Sources/ColdDownApp/Resources/Info.plist`, `Sources/ColdDownApp/Resources/Localizable.xcstrings`, and `Sources/ColdDownApp/ColdDownApp.entitlements` (FR-001, FR-012, FR-025)
- [ ] ~~T006~~ Removed 2026-09-29: the component it packaged no longer exists (FR-012 now requires that nothing beyond the app itself is installed)
- [X] T007 Create the shared unit/UI test plan and mock launch configurations in `ColdDown.xcodeproj/xcshareddata/xctestplans/ColdDown.xctestplan` with normal tests independent of a physical cooler (FR-031, SC-008)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Define shared value types, protocol boundaries, clocks, diagnostics, actor scaffolding, and deterministic fixtures without implementing user-story behavior.

**Critical**: Complete this phase before beginning any user-story phase.

- [X] T008 Create sensor identity, reading, batch-generation, freshness, grouping, summary, and calculated-sensor value types in `Sources/ThermalCore/Models/SensorModels.swift` (FR-002–FR-005)
- [X] T009 [P] Create cooler identity, speed-capability provenance, connection, write-availability, profile, demand, cooling-decision, external-action, application-preference, overall-mode, and snapshot value types in `Sources/ThermalCore/Models/FanModels.swift` and `Sources/ThermalCore/Models/ApplicationModels.swift` (FR-015, FR-017–FR-024)
- [X] T010 Define `SensorProvider`, `FanDevice`, `ExternalCoolerController` (including `releaseControl`), and `ProfileStore` with `Sendable` value boundaries in `Sources/ThermalCore/Protocols/HardwareProtocols.swift` (FR-008, FR-013)
- [ ] ~~T011~~ Removed 2026-09-29: the inter-process interface it defined no longer exists
- [X] T012 [P] Add typed errors and privacy-safe OSLog categories for SMC, HID, policy, persistence, UI, and safety transitions in `Sources/ThermalCore/Support/ThermalControlError.swift` and `Sources/ThermalCore/Support/ThermalLog.swift` (FR-032)
- [X] T013 [P] Add injectable wall/monotonic clocks, refresh scheduling, timeout scheduling, and deterministic manual-clock primitives in `Sources/ThermalCore/Support/ThermalClock.swift`
- [X] T014 Create the dependency-injected `CoolingCoordinator` actor shell, immutable snapshot stream, and lifecycle entry points without policy behavior in `Sources/ThermalCore/Coordination/CoolingCoordinator.swift`
- [X] T015 Build deterministic sensor, cooler, profile-store, clock, ACK, and action-recording doubles in `Tests/ColdDownTests/Fixtures/HardwareMocks.swift` plus reusable fixtures in `Tests/ColdDownTests/Fixtures/Fixtures.swift` (FR-031, SC-008)
- [X] T016 [P] Define stable accessibility identifiers and the `--mock`, `--cooler-disconnected`, `--no-sensors`, and `--capability-limited-cooler` launch arguments shared by the app and UI tests in `Sources/ColdDownApp/Support/AccessibilityIdentifiers.swift` and `Tests/ColdDownUITests/UITestLaunchConfiguration.swift` (SC-001, SC-007, SC-009)

**Checkpoint**: Shared types and targets compile; deterministic tests can be authored without invoking real SMC or HID operations.

---

## Phase 3: User Story 1 — Monitor Thermal Health Without a Cooler (Priority: P1) 🎯 MVP

**Goal**: Launch without a BS3 Pro, discover available SMC sensors at runtime on Intel and Apple Silicon, reject invalid/late data, and present a compact read-only Overview and complete Sensors page.

**Independent Test**: Launch using `--mock --cooler-disconnected` and a no-recognized-sensor fixture; within 10 seconds verify the hottest/unavailable state and the dimmed disconnected BS3 Pro card, while all tabs remain navigable and write controls remain disabled.

### Tests for User Story 1

> Write these tests first and verify the intended assertions fail before implementing US1.

- [X] T017 [P] [US1] Add fixed-byte tests for `sp78`, `fpe2`, float, integer, invalid-length, non-finite, and out-of-range SMC decoding in `Tests/ColdDownTests/Unit/SMCCodecTests.swift` (FR-003–FR-004)
- [X] T018 [P] [US1] Add runtime-key, human-readable fallback, raw-key preservation, disappeared-key, and variable-key-set tests in `Tests/ColdDownTests/Unit/SMCDiscoveryTests.swift` (FR-002–FR-004)
- [X] T019 [P] [US1] Add newer/older generation, older timestamp, equal-idempotent, equal-conflicting, newer-invalid, newer-missing, and stale-deadline tests in `Tests/ColdDownTests/Unit/SensorOrderingAndAggregationTests.swift` (FR-003–FR-005, SC-003)
- [X] T020 [P] [US1] Add CPU/GPU/all averages, hottest/per-group hottest, empty-group, invalid-value, and current-generation-only tests in `Tests/ColdDownTests/Unit/SensorSummaryTests.swift` (FR-004–FR-005, SC-003)
- [ ] ~~T021~~ Removed 2026-09-29: the reader it tested no longer exists
- [X] T022 [P] [US1] Add 200-generation virtual-clock tests covering 1-, 2-, and 30-second refresh intervals, provider-to-snapshot latency, and explicit 197/200 fail versus 198/200 pass calculations in `Tests/ColdDownTests/Integration/RefreshLatencyTests.swift` (FR-006, SC-002)
- [X] T023 [P] [US1] Add a no-cooler/missing-key read-only journey test with a retained disconnected cooler, disabled writes, "Read only" overall mode, and all tabs in `Tests/ColdDownTests/Integration/ReadOnlyMonitoringTests.swift` (FR-008, FR-025–FR-027, SC-003, SC-008–SC-009)
- [X] T024 [P] [US1] Add mock UI launch tests that start timing immediately before launch and require hottest/unavailable accessibility state plus the cooler's card within 10 seconds in `Tests/ColdDownUITests/StartupReadinessUITests.swift` (SC-001, SC-009)

### Implementation for User Story 1

- [X] T025 [P] [US1] Implement type-aware AppleSMC byte conversion and temperature validation in `Sources/IntelSMC/Codec/SMCValueCodec.swift` (FR-003–FR-004)
- [X] T026 [US1] Implement the read-only IOKit AppleSMC connection, key-info cache, `#KEY` enumeration, and scoped resource cleanup with no write entry point in `Sources/IntelSMC/Transport/AppleSMCConnection.swift` (FR-002, FR-008)
- [X] T027 [P] [US1] Implement known-key names plus conservative CPU/GPU/heatsink/memory/PCH/battery/ambient/other heuristics in `Sources/IntelSMC/Discovery/SMCSensorCatalog.swift` (FR-002–FR-003)
- [X] T028 [US1] Implement monotonic-generation temperature probing, timestamp conflict rejection, explicit missing/invalid publication, and raw-key preservation in `Sources/IntelSMC/Discovery/AppleSMCSensorProvider.swift` (FR-002–FR-004)
- [X] T029 [US1] Implement runtime platform detection, the Apple Silicon chip-specific key table, and the HID die-sensor merge in `Sources/IntelSMC/Discovery/HardwarePlatform.swift`, `Sources/IntelSMC/Discovery/PlatformSensorProvider.swift`, `Sources/IntelSMC/Discovery/AppleSiliconSMCSensorKeys.swift`, `Sources/IntelSMC/AppleSilicon/AppleSiliconHIDSensorProvider.swift`, and `Sources/AppleSiliconHIDBridge/AppleSiliconHIDBridge.c` (FR-001–FR-002)
- [X] T030 [US1] Implement fresh-current-generation-only aggregation, calculated sensors, and explicit stale/unavailable state in `Sources/ThermalCore/Policy/SensorAggregator.swift` (FR-003–FR-005)
- [X] T031 [US1] Implement 1...30-second refresh scheduling with a 5-second default, generation commit ordering, snapshot publication, and latency instrumentation in `Sources/ThermalCore/Coordination/CoolingCoordinator.swift` (FR-006, SC-002–SC-003)
- [X] T032 [P] [US1] Implement deterministic changing sensor data plus the no-sensor and missing-key scenarios in `Sources/ColdDownApp/Services/MockSensorBackend.swift` (FR-031)
- [X] T033 [US1] Bridge immutable coordinator snapshots, readiness state, and tab/cooler navigation to the main actor in `Sources/ColdDownApp/Models/AppModel.swift`
- [X] T034 [US1] Build the fixed window with the title-bar tab bar and destination routing in `Sources/ColdDownApp/Views/RootView.swift`, following the supplied HTML mockup's hierarchy without using a web view (FR-025)
- [X] T035 [US1] Build Overview's hottest gauge, aggregate summary, recent-history chart, cooler card with dimmed disconnected state and concise message, sensor-group rows, and cooler-to-Fans navigation in `Sources/ColdDownApp/Views/OverviewView.swift` and `Sources/ColdDownApp/Views/Components/DashboardComponents.swift` (FR-026, SC-001)
- [X] T036 [US1] Build the compact complete sensor page and calculated summaries with raw keys, groups, temperatures, sentence-case headers, and fresh/stale/unavailable states in `Sources/ColdDownApp/Views/SensorsView.swift` (FR-027)

**Checkpoint**: US1 is a usable native read-only MVP that passes T017–T024 without physical hardware.

---

## Phase 4: User Story 2 — Apply Safe Automatic Cooling (Priority: P2)

**Goal**: Apply the single linear ramp, Critical precedence, and stale-source fallback through a capability-gated Flydigi transport.

**Independent Test**: Drive 45/65/85°C thresholds, 94.999/95°C boundaries, stale/missing data, connected/disconnected/capability-limited coolers, Manual under Critical, and ACK success/failure through mocks; verify exact targets, no forbidden reports, and no write to an unavailable cooler.

### Tests for User Story 2

> Write these tests first and verify the intended assertions fail before implementing US2.

- [X] T037 [P] [US2] Add 25-byte encode/decode fixtures, checksum and bounds cases, VID/PID/usage matching, allowed typed commands, and hard denial of `0x03`, `0x05`, `0x06`, raw, RGB, firmware, reset, power, and zero-speed-stop commands in `Tests/ColdDownTests/Unit/FlydigiPacketCodecTests.swift` (FR-013–FR-016)
- [X] T038 [P] [US2] Add serialized transaction, register-before-write, ACK correlation, corrupt/unrelated frame, 900 ms timeout, three-attempt/under-5-second bound, detach cancellation, and reconnect-without-replay tests in `Tests/ColdDownTests/Unit/FlydigiTransactionTests.swift` (FR-013–FR-014, SC-006)
- [X] T039 [P] [US2] Add unverified/device-verified/audited-model/mock-only provenance, malformed range/step, read-only attach query, capability-limited UI state, and zero-mutating-report tests in `Tests/ColdDownTests/Unit/FlydigiCapabilityTests.swift` and `Tests/ColdDownTests/Unit/SpeedCapabilitiesTests.swift` (FR-013, FR-015–FR-016)
- [X] T040 [P] [US2] Add exact 45/65/85°C boundary, interpolation, step-rounding, zero-width-Hot, any-sensor Critical, Critical-over-Manual, precedence, verified-stop Cool, no-stop verified-minimum Cool, disconnected/capability-limited no-action, suggested-profile, and stale-source SafetyFallback fixtures in `Tests/ColdDownTests/Unit/CoolingPolicyTests.swift` (FR-011, FR-017–FR-021, SC-004–SC-005)
- [X] T041 [P] [US2] Add coordinator tests proving the decision's action reaches the cooler once per refresh, overlapping refreshes coalesce, a failed write is logged and never reported active, a stale selected Auto source sets a write-ready cooler to maximum, and `shutdown` calls `releaseControl` in `Tests/ColdDownTests/Integration/CoolingCoordinatorSafetyTests.swift` (FR-011, FR-019–FR-020, FR-024, SC-004)
- [ ] ~~T042~~ Removed 2026-09-29: the component it tested no longer exists
- [ ] ~~T043~~ Removed 2026-09-29: the component it tested no longer exists
- [X] T088 [P] [US2] Add THRM-protocol tests for realtime entry once, re-entry after a `0xEF` mode change, the 50 RPM minimum change, measured RPM from status pushes, and `0x24` on release in `Tests/ColdDownTests/Unit/FlydigiTHRMProtocolTests.swift` (FR-013–FR-015, FR-024)

### Implementation for User Story 2

- [X] T044 [P] [US2] Implement the verified 25-byte report codec, typed command allowlist, checksum, ACK decoder, `0xEF` status decoding, and destructive/raw-command denial in `Sources/FlydigiHID/Protocol/FlydigiPacketCodec.swift` (FR-014, FR-016)
- [X] T045 [US2] Implement IOHIDManager matching for VID `0x37D7`, PIDs `0x1001`–`0x1004`, usage page `0xFFA0`, usage `0x00FF`, product/firmware inspection, status-push capture, and attach/detach callbacks in `Sources/FlydigiHID/Transport/FlydigiHIDTransport.swift` (FR-013)
- [X] T046 [US2] Implement the serialized actor transaction queue with register-before-write, matching ACK validation, 900 ms timeout, at most three attempts, and detach cancellation in `Sources/FlydigiHID/Transport/FlydigiTransactionExecutor.swift` (FR-014, SC-006)
- [X] T047 [US2] Implement read-only attach queries, automatic reconnect, operating state, capability provenance, verified-range gating for both `0x23` and `0x21`, realtime-once semantics, the 50 RPM change filter, no target replay, and `releaseControl` via `0x24` in `Sources/FlydigiHID/Device/BS3ProController.swift` (FR-013, FR-015–FR-016, FR-024)
- [X] T048 [P] [US2] Implement the pure `evaluate(summary:profiles:externalState:now:)` with the any-fresh-sensor Critical pre-pass, no-action for unavailable coolers, suggested-profile fallback, Manual clamping, stale-selected-source SafetyFallback, verified-stop/no-stop-minimum Cool, exact Warm interpolation with rounding/clamping, Hot maximum, and the threshold-85 guard in `Sources/ThermalCore/Policy/CoolingPolicy.swift` (FR-011, FR-017–FR-021)
- [ ] ~~T049~~ Removed 2026-09-29: the client it implemented no longer exists
- [ ] ~~T050~~ Removed 2026-09-29: the component it implemented no longer exists
- [ ] ~~T051~~ Removed 2026-09-29: the component it implemented no longer exists
- [ ] ~~T052~~ Removed 2026-09-29: the component it implemented no longer exists
- [ ] ~~T053~~ Removed 2026-09-29: the component it implemented no longer exists
- [ ] ~~T054~~ Removed 2026-09-29: the component it implemented no longer exists
- [ ] ~~T055~~ Removed 2026-09-29: the component it implemented no longer exists
- [ ] ~~T056~~ Removed 2026-09-29: the registration it implemented no longer exists
- [X] T057 [US2] Integrate policy evaluation and side effects into `Sources/ThermalCore/Coordination/CoolingCoordinator.swift`: apply `externalAction` after each refresh, coalesce overlapping refreshes, reconnect the cooler when it reappears and automatic reconnect is enabled, derive `overallMode`, release the cooler on `shutdown`, and write privacy-safe safety logs (FR-011, FR-017–FR-020, FR-024, FR-032)
- [X] T058 [P] [US2] Add deterministic ACK, disconnected, and capability-limited cooler scenarios in `Sources/ColdDownApp/Services/MockCoolingBackend.swift` (FR-031)

**Checkpoint**: US2 passes T037–T041 and T088 using mocks; no real transport can emit a mutating Flydigi report without verified capabilities, and an unavailable cooler is never driven.

---

## Phase 5: User Story 3 — Configure the Cooler Manually (Priority: P3)

**Goal**: Configure and persist a validated Auto or Manual cooler profile with synchronized controls, safe startup after unclean exits, capability-aware disabled states, and at most four direct interactions.

**Independent Test**: For the connected, write-ready mock cooler, complete Auto configuration in at most four semantic actions and Manual in at most three, verify slider/numeric synchronization and 45...85°C/default-65 validation, relaunch cleanly and uncleanly to validate persistence and the Manual-to-Auto recovery, and verify disconnected or capability-limited controls stay disabled without losing the profile.

### Tests for User Story 3

> Write these tests first and verify the intended assertions fail before implementing US3.

- [X] T059 [P] [US3] Add Codable round-trip, corrupt/versioned-data fallback, 45...85°C/default-65 validation, physical/CPU-average/GPU-average/all-average/hottest choices, CPU-average default with hottest fallback, all-average non-default, missing sensor, capability change, and manual-target validation tests in `Tests/ColdDownTests/Unit/ProfilePersistenceTests.swift` (FR-021, FR-022, FR-023, FR-024, FR-030)
- [X] T060 [P] [US3] Add Auto/Manual transition, intent-only load, `revertManualProfiles` recovery with retained target, clean-start reapply, invalid capability, and profile-retention tests in `Tests/ColdDownTests/Unit/FanProfileTransitionTests.swift` (FR-021–FR-024)
- [X] T061 [P] [US3] Add synchronized slider/numeric edits, one-degree threshold steps, typed clamping, fixed-range cooler, disconnected state, capability-limited state, debounce overlay, and concise message tests in `Tests/ColdDownTests/Unit/FanConfigurationViewModelTests.swift` (FR-015, FR-021–FR-023)
- [X] T062 [P] [US3] Add action-counted UI journeys for the connected, write-ready fixture cooler, requiring Auto configuration in at most four semantic actions and Manual in at most three with synchronized values; also assert connected capability-limited and disconnected fixtures stay visible but disabled and are excluded from configurability timing in `Tests/ColdDownUITests/FanConfigurationJourneyUITests.swift` (FR-015, FR-023, SC-007)
- [X] T089 [P] [US3] Add session-marker tests proving `begin()` reports an unclean previous session, `end()` clears it, and an injected suite isolates the real defaults in `Tests/ColdDownTests/Unit/SessionMarkerTests.swift` (FR-024, SC-004)

### Implementation for User Story 3

- [X] T063 [US3] Implement schema-versioned Codable UserDefaults persistence, corruption fallback, profile intent loading, all required Auto sensor choices, current-hardware validation, and capability-safe migration in `Sources/ThermalCore/Persistence/UserDefaultsProfileStore.swift` (FR-021, FR-022, FR-024, FR-030)
- [X] T064 [US3] Implement coordinator profile updates, persistence, `start(revertManualProfiles:)`, `applyNow`, and validated application without profile deletion in `Sources/ThermalCore/Coordination/CoolingCoordinator.swift` (FR-021–FR-024, FR-030)
- [X] T065 [P] [US3] Implement cooler selection and synchronized validated Auto/Manual editing state with the ~0.5 s hardware debounce and semantic action instrumentation in `Sources/ColdDownApp/Models/FanConfigurationViewModel.swift` (FR-021–FR-023, SC-007)
- [X] T066 [US3] Build the full-width cooler card with connection, live RPM, chart, mode, dimmed disconnected state, and concise connection/capability messages in `Sources/ColdDownApp/Views/FansView.swift` and `Sources/ColdDownApp/Views/FanControlCard.swift` (FR-015, FR-025)
- [X] T067 [US3] Build the inline Auto sensor/45...85°C threshold and Manual speed controls with synchronized sliders/numeric inputs, presets, fixed-range behavior, clamping, and disabled unavailable actions in `Sources/ColdDownApp/Views/FanControlCard.swift` and `Sources/ColdDownApp/Views/Components/ValueSlider.swift` (FR-021–FR-023, SC-007)
- [X] T068 [US3] Build Settings with General (login item, menu temperature, 1...30-second refresh, animations, menu-bar icon), Flydigi BS3 Pro (automatic reconnect, acceleration, sleep behavior), and Safety sections in `Sources/ColdDownApp/Views/SettingsView.swift` (FR-006, FR-028)
- [X] T069 [US3] Implement `SMAppService.mainApp` login-item registration and preference synchronization in `Sources/ColdDownApp/Services/LaunchAtLoginService.swift` (FR-028, FR-030)
- [X] T090 [US3] Implement the session marker, the unclean-exit recovery notice, and the bounded 3-second shutdown hand-back in `Sources/ColdDownApp/Support/SessionMarker.swift`, `Sources/ColdDownApp/Models/AppModel.swift`, and `Sources/ColdDownApp/Application/ColdDownApp.swift` (FR-024, SC-004)

**Checkpoint**: US3 passes T059–T062 and T089 and persists validated intent without blindly re-applying a crash-persisted Manual target.

---

## Phase 6: User Story 4 — Check Status From the Menu Bar (Priority: P4)

**Goal**: Provide an optional compact menu-bar temperature and native popover using the existing coordinator snapshot rather than a second hardware connection.

**Independent Test**: Toggle menu temperature, inject fresh/no-valid-temperature and connected/disconnected/capability-limited snapshots, and verify the label, hottest sensor, cooler row with mode switch, overall mode, and Open Cold Down action.

### Tests for User Story 4

> Write this test first and verify the intended assertions fail before implementing US4.

- [X] T070 [P] [US4] Add snapshot-to-menu presentation tests for preference toggling, no-valid-temperature fallback, connected/disconnected/capability-limited BS3 state, overall mode, and open-window action in `Tests/ColdDownTests/Unit/MenuBarPresentationTests.swift` (FR-029)

### Implementation for User Story 4

- [X] T071 [US4] Implement menu label and popover presentation state derived solely from shared coordinator snapshots in `Sources/ThermalCore/Models/PresentationModels.swift` and `Sources/ColdDownApp/Support/MenuBarIcon.swift` (FR-029)
- [X] T072 [US4] Build the compact native fan-icon MenuBarExtra popover with hottest sensor, CPU/GPU, chart, the cooler's row with its mode switch, overall mode, Open/Settings/Quit actions, and main-window activation in `Sources/ColdDownApp/Views/MenuBarContentView.swift` (FR-029)
- [X] T073 [US4] Compose WindowGroup, Settings, MenuBarExtra, one coordinator lifetime, mock/read-only launch fixtures, the bounded shutdown hand-back, close-to-menu-bar/Dock lifecycle, and Open Cold Down activation in `Sources/ColdDownApp/Application/ColdDownApp.swift` and `Sources/ColdDownApp/Views/RootView.swift` (FR-024, FR-025, FR-029, FR-031)

**Checkpoint**: US4 passes T070 and all status surfaces consume one immutable coordinator snapshot.

---

## Phase 7: Polish & Cross-Cutting Verification

**Purpose**: Complete accessibility, documentation, concurrency review, distribution tooling, builds, tests, and launch-mode evidence without expanding the MVP hardware surface.

- [X] T074 [P] Add English VoiceOver labels, accessibility identifiers, keyboard focus order, compact control sizing, and loading/empty/error states across `Sources/ColdDownApp/Views/RootView.swift`, `Sources/ColdDownApp/Views/OverviewView.swift`, `Sources/ColdDownApp/Views/FansView.swift`, `Sources/ColdDownApp/Views/FanControlCard.swift`, `Sources/ColdDownApp/Views/SensorsView.swift`, `Sources/ColdDownApp/Views/SettingsView.swift`, and `Sources/ColdDownApp/Views/MenuBarContentView.swift` (FR-001, FR-025)
- [X] T075 [P] Implement parameterized universal `arm64`/`x86_64` Release archive creation with unsigned and Developer ID modes, centralized identifier inputs, and no source rewriting in `Scripts/archive-release.sh` (SC-010)
- [X] T076 [P] Implement archive layout, architecture, deployment metadata, bundle-identifier, entitlement, ad-hoc signability rehearsal, strict codesign, optional notary, stapler, and Gatekeeper validation in `Scripts/validate-distribution.sh`, plus the local DMG path in `Scripts/build-local-dmg.sh` and the uninstaller in `Scripts/uninstall.sh` (FR-012, SC-010)
- [X] T077 [P] Document architecture, requirements-to-module mapping, universal Intel/Apple-Silicon build instructions, entitlements, identifiers, signing, notarization, hardware limitations, the safety model, mock mode, reference licenses, and the Flydigi `0x05`/`0x06` warning in `README.md`
- [X] T078 [P] Create completed-functionality, exact command evidence, test/build results, unresolved warnings, and physical hardware/signing blocker sections in `IMPLEMENTATION_REPORT.md`
- [X] T079 Audit actor isolation, `Sendable` boundaries, continuation cancellation, HID/SMC off-main execution, identifier substitution, and correctness/concurrency warnings across `Sources/`, `Tests/`, and `ColdDown.xcodeproj/project.pbxproj`, recording resolutions in `IMPLEMENTATION_REPORT.md`
- [X] T080 Run the complete ColdDownTests package and native hosted unit/integration suites, resolve failures, and record the exact commands and results in `IMPLEMENTATION_REPORT.md` (SC-002–SC-006, SC-008)
- [X] T081 Run the mock-backed ColdDownUITests suite from `ColdDown.xcodeproj`, resolve failures, and record startup timing and interaction-count results in `IMPLEMENTATION_REPORT.md` (SC-001, SC-007–SC-009)
- [X] T082 Build ColdDownApp for macOS x86_64 Debug from `ColdDown.xcodeproj`, resolve correctness/concurrency warnings, and record the command and result in `IMPLEMENTATION_REPORT.md` (FR-001)
- [ ] ~~T083~~ Removed 2026-09-29: the target it built no longer exists
- [X] T084 Execute the full mock-mode scenarios from `specs/001-thermal-control/quickstart.md`, including profiles, all three Cool branches, ramp boundaries, stale-source fallback, Critical over Auto and Manual, crash-recovery notice, capability-limited state, and all tabs, recording evidence in `IMPLEMENTATION_REPORT.md` (FR-031)
- [X] T085 Execute no-BS3-Pro and no-recognized-SMC-key launch checks from `specs/001-thermal-control/quickstart.md`, confirming read-only monitoring/navigation and recording evidence in `IMPLEMENTATION_REPORT.md` (FR-008, SC-009)
- [X] T086 Create and validate the unsigned universal `arm64`/`x86_64` Release archive plus temporary-copy ad-hoc signability rehearsal using `Scripts/archive-release.sh` and `Scripts/validate-distribution.sh`, recording bundle/layout results without claiming Developer ID validation in `IMPLEMENTATION_REPORT.md` (SC-010)
- [ ] T087 When Developer ID and notary credentials are available, run credentialed archive, strict signature checks, notarization, stapling, and Gatekeeper assessment through `Scripts/archive-release.sh` and `Scripts/validate-distribution.sh`; otherwise record the exact unavoidable blocker in `IMPLEMENTATION_REPORT.md` without marking credentialed validation complete (FR-012, SC-010)

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
                   ├→ US3 (P3 cooler configuration)
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

- T003 and T005 can proceed concurrently after T002 establishes target names.
- T009, T012, and T013 can proceed concurrently after T008 establishes shared sensor primitives.
- US1 tests T017–T024 can be authored concurrently; T025, T027, T029, and T032 touch separate modules.
- US2 tests T037–T041 and T088 can be authored concurrently; T044, T048, and T058 touch separate modules.
- US3 tests T059–T062 and T089 can be authored concurrently; T065 is isolated from persistence and view files.
- US4 presentation tests can be authored independently against fixture snapshots.
- T074–T078 can proceed concurrently after public behavior and paths stabilize.

## Parallel Examples

### User Story 1

```text
T017: Tests/ColdDownTests/Unit/SMCCodecTests.swift
T019: Tests/ColdDownTests/Unit/SensorOrderingAndAggregationTests.swift
T022: Tests/ColdDownTests/Integration/RefreshLatencyTests.swift
T024: Tests/ColdDownUITests/StartupReadinessUITests.swift
```

### User Story 2

```text
T037: Tests/ColdDownTests/Unit/FlydigiPacketCodecTests.swift
T039: Tests/ColdDownTests/Unit/FlydigiCapabilityTests.swift
T040: Tests/ColdDownTests/Unit/CoolingPolicyTests.swift
T088: Tests/ColdDownTests/Unit/FlydigiTHRMProtocolTests.swift
```

### User Story 3

```text
T059: Tests/ColdDownTests/Unit/ProfilePersistenceTests.swift
T060: Tests/ColdDownTests/Unit/FanProfileTransitionTests.swift
T061: Tests/ColdDownTests/Unit/FanConfigurationViewModelTests.swift
T062: Tests/ColdDownUITests/FanConfigurationJourneyUITests.swift
```

## Implementation Strategy

### MVP First

1. Complete Setup and Foundation.
2. Complete US1 tests before US1 implementation.
3. Complete US1 and run T017–T024 plus the independent checkpoint.
4. Demonstrate a native read-only app with mock or real SMC data and no BS3 Pro.

### Incremental Delivery

1. **US1**: Runtime monitoring and native Overview/Sensors UI.
2. **US2**: Verified automatic cooling of the Flydigi cooler.
3. **US3**: Validated cooler configuration, persistence, crash recovery, and Settings.
4. **US4**: Menu-bar status and window activation.
5. **Polish**: Accessibility, documentation, deterministic suites, x86_64 builds, archives, and launch-mode evidence.

## Notes

- `[P]` means different files and no unmet dependency within the indicated starting point; tasks modifying `CoolingCoordinator.swift` remain sequential.
- Test tasks precede story implementation as required by the constitution.
- Real Flydigi mutating commands remain disabled until capability evidence is device-verified or audited and physically validated; deterministicMock provenance never authorizes the real transport.
- Commands `0x03`, `0x05`, and `0x06`, raw reports, RGB, flash-writing gear commands, firmware, reset, power, and unverified zero-speed stop remain forbidden.
- The cooler's profile loads as intent only; after an unclean exit Auto is the startup baseline, and nothing in the app writes to AppleSMC.
- Missing hardware or signing credentials may block physical validation but never block deterministic tests, read-only operation, protocol implementation, or x86_64 compilation.
