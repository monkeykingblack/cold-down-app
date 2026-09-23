# Implementation Plan: Cold Down

**Branch**: `001-thermal-control` | **Date**: 2026-09-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-thermal-control/spec.md`

## Summary

Build a native, directly distributed universal macOS 13+ utility for Intel and Apple Silicon Macs. On compatible Intel hardware it monitors runtime-discovered AppleSMC temperature sensors, displays built-in fan telemetry without privilege, and safely controls built-in fans through a narrowly scoped launch daemon. On Apple Silicon the unavailable Intel AppleSMC backend degrades safely while the UI, mock mode, persistence, and Flydigi discovery remain usable. A separate Flydigi HID module discovers BS3 Pro devices, serializes verified real-time RPM commands, requires matching acknowledgements, and never exposes undocumented or destructive commands. A central `CoolingCoordinator` actor owns current readings, profiles, persistence, highest-demand arbitration, the two-stage external-first ramp, stale-data handling, and fail-safe transitions. Real BS3 Pro speed writes remain capability-disabled until a safe range is verified. Hardware protocols are replaceable by deterministic mocks so the UI and normal test suite run without physical devices or an installed helper.

## Technical Context

**Language/Version**: Swift 6 with strict concurrency checking; Xcode 26.2 toolchain; deployment target macOS 13.0

**Primary Dependencies**: SwiftUI, AppKit, Foundation, ServiceManagement, IOKit/IOKit.hid, Security, OSLog; no third-party runtime libraries

**Storage**: Versioned `Codable` preference document stored in `UserDefaults`; no history database or cloud storage

**Testing**: XCTest unit, integration, and presentation tests using deterministic clocks, fake sensor/fan providers, mock XPC clients, scripted HID transports, latency-cycle accounting, and interaction-count fixtures

**Target Platform**: Native universal macOS application (`arm64` + `x86_64`), Intel AppleSMC as the primary hardware-control target, minimum macOS 13, direct distribution outside the Mac App Store

**Project Type**: Xcode desktop application with library targets, a privileged command-line launch-daemon target, an XCTest unit/integration target, and a mock-backed UI-test target

**Performance Goals**: Default 2-second sampling; at least 99% of deterministic cycles publish new valid values within refresh interval +0.5 seconds; initial mock/read-only state is identifiable within 10 seconds; no hardware I/O on `MainActor`; all HID writes serialized; UI remains responsive during timeouts and reconnects

**Constraints**: Read-only operation without helper; AppleSMC keys discovered at runtime; built-in fan writes restricted to validated high-level operations; all critical and sensor-loss paths restore macOS Auto; Auto thresholds are 45...85 °C in 1 °C steps with a 72 °C default; any fresh valid sensor at 95 °C triggers global Critical; BS3 Pro commands `0x05` and `0x06` are forbidden; real external speed writes require a verified range; production helper connections require matching signatures; development retains the same operation and lease restrictions

**Scale/Scope**: One local interactive user, one BS3 Pro, typically 1–3 built-in fans, hundreds of probed SMC keys, four main destinations, one menu-bar surface, and no network service

## Constitution Check

*GATE: PASS before Phase 0 research. PASS again after Phase 1 design.*

The ratified Cold Down Constitution v1.0.0 is authoritative. Pre-design gate status:

- **I. Fail Safe to System Control — PASS**: Critical, stale control data, total Manual sensor loss, helper loss, disconnect, expiry, invalid state, sleep, wake, and termination all restore built-in fans to macOS Auto before new targets.
- **II. Least Privilege and Narrow Protocols — PASS**: AppleSMC reads remain unprivileged; helper and HID contracts expose typed allowlisted operations only; Release validates the expected signed client; logs exclude private data.
- **III. Separated Native Architecture — PASS**: UI, coordination/policy, persistence, AppleSMC, HID, shared XPC, and helper writes are isolated; one actor owns mutable cooling state; hardware I/O stays off `MainActor`.
- **IV. Deterministic Test-First Delivery — PASS**: each story receives failing deterministic tests before its implementation, using mock hardware, scripted time, and fixed protocol fixtures.
- **V. Evidence Before Hardware Enablement — PASS**: licenses are recorded; the PolyForm source is not copied; commands `0x05`/`0x06` remain forbidden; unverified BS3 speed ranges disable writes rather than being guessed.
- **Platform and quality gates — PASS**: native Swift/SwiftUI, macOS 13+, universal `arm64`/`x86_64` output, read-only degradation, explicit per-architecture build/test gates, and documented hardware/signing blockers are retained.

Post-design re-check: PASS. The revised data model and contracts define global arbitration, Critical precedence, exact ramp math, capability provenance, malformed-range handling, test-first acceptance measurements, narrow helper operations, and distribution validation without weakening any constitutional rule.

## Architecture and Execution Model

- `CoolingCoordinator` is an actor and the sole owner of mutable cooling state. It samples providers, validates readings, creates one immutable snapshot per cycle, evaluates policy, persists profile changes, and sequences device actions.
- AppleSMC and HID work execute outside `MainActor`. The SwiftUI model receives immutable snapshots on `MainActor`.
- Sensor batches carry a monotonic sequence and sample time. The coordinator rejects batches older than the last accepted sequence/time and never lets out-of-order input replace a newer reading.
- The policy calculates desired actions without performing I/O. Non-critical system demand is the highest band produced by all fresh active Auto-profile sources; any fresh valid physical or calculated sensor at or above 95 °C overrides it with global Critical.
- Warm maps normalized progress from 0...1 across threshold...threshold+10 °C to the verified external minimum...maximum. Hot holds a write-ready external cooler at maximum and maps progress across threshold+10...95 °C to each built-in minimum...maximum, rounds to the supported step, clamps to capabilities, and never requests less than current RPM. The coordinator requires a matching maximum-cooling acknowledgement before a built-in increase only when the connected BS3 Pro is write-ready; a disconnected or capability-limited cooler is unavailable, is never reported active, and does not block an otherwise eligible validated built-in Hot increase.
- A missing or stale selected Auto source produces `SafetyFallback`: never reuse the reading, request verified external maximum only when the BS3 Pro is write-ready, send no external write otherwise, and restore every built-in fan to macOS Auto.
- The helper owns an independent safety lease. Disconnect, expiry, invalid state, sleep, wake, or termination triggers best-effort restoration of every discovered built-in fan to macOS Auto.
- Real hardware implementations conform to the same protocols as deterministic mocks. Mock mode is selected by a launch argument and cannot open SMC write or HID transports. Real BS3 speed controls remain disabled with a capability-limited state until a runtime-reported or audited and physically validated range is available.

## Project Structure

### Documentation (this feature)

```text
specs/001-thermal-control/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── coordinator-protocols.md
│   ├── flydigi-hid.md
│   └── privileged-helper-xpc.md
└── tasks.md                     # Regenerated after this plan by $speckit-tasks
```

### Source Code (repository root)

```text
ThermalControl.xcodeproj/
Configuration/
├── ProductIdentifiers.xcconfig
├── Debug.xcconfig
└── Release.xcconfig
Sources/
├── ThermalCore/
│   ├── Models/
│   ├── Protocols/
│   ├── Policy/
│   ├── Persistence/
│   ├── Coordination/
│   └── Support/
├── IntelSMC/
│   ├── Codec/
│   ├── Transport/
│   └── Discovery/
├── FlydigiHID/
│   ├── Protocol/
│   ├── Transport/
│   └── Device/
├── ThermalControlShared/
│   └── XPC/
├── ThermalControlApp/
│   ├── Application/
│   ├── Models/
│   ├── Views/
│   ├── Services/
│   ├── Support/
│   ├── Resources/
│   └── ThermalControlApp.entitlements
└── ThermalControlHelper/
    ├── Service/
    ├── Resources/
    └── ThermalControlHelper.entitlements
Tests/
├── ThermalControlTests/
│   ├── Fixtures/
│   ├── Unit/
│   └── Integration/
└── ThermalControlUITests/
    ├── StartupReadinessUITests.swift
    └── FanConfigurationJourneyUITests.swift
Scripts/
├── archive-release.sh
└── validate-distribution.sh
README.md
IMPLEMENTATION_REPORT.md
```

**Structure Decision**: One Xcode project will contain `ThermalControlApp`, `ThermalCore`, `IntelSMC`, `FlydigiHID`, `ThermalControlShared`, `ThermalControlHelper`, `ThermalControlTests`, and `ThermalControlUITests`. Static library targets keep hardware and policy replaceable without introducing package-management complexity. `FanDevice`, `BuiltInFanReader`, `BuiltInFanController`, `ExternalCoolerController`, `PrivilegedFanHelperClient`, and `ProfileStore` are distinct contracts: the reader is unprivileged, the controller is high-level and contains no raw SMC surface, and the helper client implements the controller through narrow XPC. The helper owns its private AppleSMC write adapter and shares only safe value codecs/types where required; the app never links helper-only write entry points. Parameterized scripts own repeatable Release archive and distribution validation commands.

## Build and Distribution Design

- App and helper deployment target: macOS 13.0; supported architectures: `arm64` and `x86_64`. Intel remains the only AppleSMC backend; absence of `AppleSMC` on Apple Silicon is a supported unavailable state.
- The app bundle identifier, helper bundle identifier, and Mach-service name come from one checked-in build configuration and are substituted into plists/entitlements; development and distribution identities change through build settings without source edits.
- App Sandbox is disabled because direct AppleSMC and HID access are incompatible with the intended hardware behavior. Hardened Runtime is enabled for distribution.
- The helper executable is embedded inside the application bundle; its launchd property list lives at `Contents/Library/LaunchDaemons` and uses `BundleProgram` with an app-bundle-relative executable path plus a single `MachServices` name.
- `SMAppService.daemon(plistName:)` registers the helper. The app presents `notRegistered`, `enabled`, `requiresApproval`, and `notFound` states without blocking monitoring.
- Both app and helper are signed with the same team for release, and the Mach-service listener sets a code-signing requirement before activation. Development may relax the expected production identifier but cannot relax command validation, fan bounds, lease expiry, or restoration.
- Distribution documentation covers Developer ID Application signing, nested-code signing order, notarization, stapling, `/Applications` placement, registration, System Settings approval, and verification.
- Without Developer ID credentials, CI/development produces an unsigned Release archive, verifies the embedded helper and launch-daemon paths, checks resolved signing requirements and entitlements, and records signing/notarization as an explicit blocker. With credentials, the same archive workflow signs nested code inside-out, validates with `codesign --verify --deep --strict`, notarizes, staples, and performs `spctl` assessment without source changes.

## Verification Strategy

1. Run deterministic XCTest coverage for codecs, out-of-order and stale filtering, aggregation, exact ramp boundaries and interpolation, all Cool external branches (verified stop, no-stop verified minimum, and capability-limited no-transmit), global demand arbitration, stale-source external-maximum fallback, malformed fan capabilities, persistence, XPC lease behavior, ACK retries, capability gating, and view-state derivation.
2. Prove SC-001 with a mock UI launch test that starts its clock immediately before process launch and waits at most 10 seconds for accessibility elements representing the hottest state and every fixture fan, including a disconnected cooler; repeat with no recognized sensors and require the unavailable state plus all known fans.
3. Prove SC-002 over 200 virtual refresh generations covering 1-, 2-, and 30-second intervals; record provider availability and presentation-snapshot publication instants and require at least 198/200 within interval +0.5 seconds, with separate metric fixtures proving 197 fails and 198 passes. Use no wall-clock sleeps.
4. Prove SC-007 with mock UI journeys and semantic action counting: fan-row activation, mode selection, sensor selection, and one committed slider/numeric edit each count once, while keystrokes within one committed numeric edit do not. Require every connected, write-ready fixture fan to complete Auto configuration in at most four actions and Manual in at most three, with synchronized controls after each edit; disconnected and capability-limited fixtures must remain visible but are excluded from configurability timing.
5. Build both app and helper explicitly for `x86_64` Debug, run native `arm64` tests, build universal Debug output, then create an unsigned universal Release archive and validate bundle/helper/plist/entitlement structure. Rehearse signability on a temporary archive copy by ad-hoc signing helper-first and app-last and running strict `codesign` verification; do not represent that as Developer ID validation.
6. When credentials are present, use the same parameterized archive scripts to apply Developer ID identities and bundle settings without source edits, check designated requirements, notarize, staple, and validate. Otherwise record the exact signing/notary blocker without claiming SC-010 fully exercised.
7. Run the app in mock mode and verify all four destinations plus the menu bar, full profile editing, policy transitions, and capability-limited BS3 state.
8. Run the app without the helper and BS3 Pro to prove read-only degradation and verify no recognized SMC keys still yields a navigable UI.
9. On Intel hardware, verify missing SMC keys do not fail startup and read-only monitoring remains available. On Apple Silicon, verify native launch with unavailable AppleSMC and full mock/read-only navigation.
10. Treat helper installation, signed-client rejection, actual SMC writes, BS3 Pro attach/ACK behavior, sleep/wake restoration, and exact device RPM limits as hardware/signing smoke tests documented for later physical validation.
