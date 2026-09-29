# Implementation Plan: Cold Down

**Branch**: `001-thermal-control` | **Date**: 2026-09-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-thermal-control/spec.md`

## Summary

Build a native, directly distributed universal macOS 14+ utility for Intel and Apple Silicon Macs. It monitors runtime-discovered AppleSMC temperature sensors as the ordinary user (every `T…` key on Intel; chip-specific keys merged with HID die sensors on Apple Silicon) and drives a Flydigi BS3 Pro cooler from them over HID. Nothing in the app writes to AppleSMC and no root-level component exists. A separate Flydigi HID module discovers BS-series devices, serializes verified real-time RPM commands, requires matching acknowledgements, and never exposes undocumented or destructive commands. A central `CoolingCoordinator` actor owns current readings, the cooler's profile, persistence, the single linear ramp, stale-data handling, crash recovery, and the shutdown hand-back. Real BS3 Pro speed writes remain capability-disabled until a safe range is verified. Hardware protocols are replaceable by deterministic mocks so the UI and normal test suite run without physical devices.

## Technical Context

**Language/Version**: Swift 6 with strict concurrency checking; Xcode 26.2 toolchain; deployment target macOS 14.0

**Primary Dependencies**: SwiftUI, AppKit, Foundation, ServiceManagement (login item only), IOKit/IOKit.hid, OSLog; no third-party runtime libraries

**Storage**: Versioned `Codable` preference document stored in `UserDefaults`, plus a session marker flag; no history database or cloud storage

**Testing**: XCTest unit, integration, and presentation tests using deterministic clocks, fake sensor providers, mock cooler controllers, scripted HID transports, latency-cycle accounting, and interaction-count fixtures

**Target Platform**: Native universal macOS application (`arm64` + `x86_64`), minimum macOS 14, direct distribution outside the Mac App Store

**Project Type**: Xcode desktop application with Swift package library targets, an XCTest unit/integration target, and a mock-backed UI-test target

**Performance Goals**: Default 5-second sampling; at least 99% of deterministic cycles publish new valid values within refresh interval +0.5 seconds; initial mock/read-only state is identifiable within 10 seconds; no hardware I/O on `MainActor`; all HID writes serialized; UI remains responsive during timeouts and reconnects

**Constraints**: Read-only operation without a cooler; AppleSMC keys discovered at runtime and never written; Auto thresholds are 45...85 °C in 1 °C steps with a 65 °C default; any fresh valid sensor at 95 °C triggers global Critical; a missing or stale controlling sensor triggers safety fallback; BS3 Pro commands `0x05` and `0x06` are forbidden; real external speed writes require a verified range; an unclean exit reverts Manual to Auto; quitting hands the cooler back within 3 seconds

**Scale/Scope**: One local interactive user, one BS3 Pro, hundreds of probed SMC keys, four main destinations, one menu-bar surface, and no network service

## Constitution Check

*GATE: PASS before Phase 0 research. PASS again after Phase 1 design.*

The ratified Cold Down Constitution v1.0.0 is authoritative. Pre-design gate status:

- **I. Fail Safe to System Control — PASS**: the app never takes over the Mac's own cooling; Critical and a stale controlling sensor push a write-ready cooler to maximum, an unclean exit reverts Manual to Auto, and termination hands the cooler back to its own gear.
- **II. Least Privilege and Narrow Protocols — PASS**: AppleSMC reads run as the ordinary user and are read-only; the HID contract exposes typed allowlisted operations only; no background service or extra entitlement exists; logs exclude private data.
- **III. Separated Native Architecture — PASS**: UI, coordination/policy, persistence, AppleSMC, and HID are isolated; one actor owns mutable cooling state; hardware I/O stays off `MainActor`.
- **IV. Deterministic Test-First Delivery — PASS**: each story receives failing deterministic tests before its implementation, using mock hardware, scripted time, and fixed protocol fixtures.
- **V. Evidence Before Hardware Enablement — PASS**: licenses are recorded; the PolyForm source is not copied; commands `0x05`/`0x06` remain forbidden; unverified BS3 speed ranges disable writes rather than being guessed.
- **Platform and quality gates — PASS**: native Swift/SwiftUI, macOS 14+, universal `arm64`/`x86_64` output, read-only degradation, explicit per-architecture build/test gates, and documented hardware/signing blockers are retained.

Post-design re-check: PASS. The revised data model and contracts define Critical precedence, exact ramp math, capability provenance, malformed-range handling, crash recovery, test-first acceptance measurements, and distribution validation without weakening any constitutional rule.

## Architecture and Execution Model

- `CoolingCoordinator` is an actor and the sole owner of mutable cooling state. It samples the sensor provider, validates readings, creates one immutable snapshot per cycle, evaluates policy, persists profile changes, and applies the cooler action. Overlapping refresh requests collapse into one follow-up pass so hardware writes never interleave.
- AppleSMC and HID work execute outside `MainActor`. The SwiftUI model receives immutable snapshots on `MainActor`.
- Sensor batches carry a monotonic sequence and sample time. The coordinator rejects batches older than the last accepted sequence/time and never lets out-of-order input replace a newer reading.
- `CoolingPolicy.evaluate(summary:profiles:externalState:now:)` is pure and returns a `CoolingDecision` with `band`, `demand`, `externalAction` (`.none`, `.stop`, or `.target(Int)`), and `reason`. Any fresh valid physical or calculated sensor at or above 95 °C produces Critical with the cooler at maximum before the profile is consulted. When the cooler is absent, disconnected, or capability-limited the action is `.none` and the overall mode is "Read only".
- Auto maps normalized progress from 0...1 across threshold...threshold+10 °C to the verified minimum...maximum, rounds to the supported step, and clamps. Below the threshold the cooler idles at its minimum (or a verified stop); at or above threshold +10 °C it holds maximum. Until a profile is saved, `FanProfile.suggested` follows the CPU average, or the hottest reading when no CPU sensor exists.
- Manual holds its target, clamped to the cooler's range, and still yields to Critical.
- A missing or stale selected Auto source produces `SafetyFallback`: never reuse the reading and request the verified maximum from the write-ready cooler.
- Crash recovery: a session marker is set when a session begins and cleared only after a clean quit. When the next launch finds it still set, every Manual profile is switched to Auto (targets kept) before any hardware is touched, and the UI shows a dismissible notice.
- Shutdown calls `releaseControl()` on the cooler, which leaves realtime mode (`0x24`) so the cooler returns to its own gear; the app delays termination for at most 3 seconds for this.
- Profile edits are shown immediately but debounced for about 0.5 seconds before the coordinator writes the final state to hardware.
- Real hardware implementations conform to the same protocols as deterministic mocks. Mock mode is selected by a launch argument and cannot open HID transports. Real BS3 speed controls remain disabled with a capability-limited state until a runtime-reported or audited and physically validated range is available.

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
│   └── flydigi-hid.md
└── tasks.md                     # Regenerated after this plan by $speckit-tasks
```

### Source Code (repository root)

```text
ColdDown.xcodeproj/
Package.swift
Configuration/
├── ProductIdentifiers.xcconfig
├── LocalSigning.xcconfig.example
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
│   ├── Discovery/
│   └── AppleSilicon/
├── AppleSiliconHIDBridge/
├── FlydigiHID/
│   ├── Protocol/
│   ├── Transport/
│   └── Device/
└── ColdDownApp/
    ├── Application/
    ├── Models/
    ├── Views/
    ├── Services/
    ├── Support/
    ├── Resources/
    └── ColdDownApp.entitlements
Tests/
├── ColdDownTests/
│   ├── Fixtures/
│   ├── Unit/
│   └── Integration/
└── ColdDownUITests/
    ├── StartupReadinessUITests.swift
    ├── FanConfigurationJourneyUITests.swift
    └── UITestLaunchConfiguration.swift
Scripts/
├── archive-release.sh
├── validate-distribution.sh
├── build-local-dmg.sh
└── uninstall.sh
README.md
IMPLEMENTATION_REPORT.md
```

**Structure Decision**: One Xcode project contains `ColdDownApp`, `ColdDownTests`, and `ColdDownUITests`, and links the Swift package targets `ThermalCore`, `IntelSMC`, `AppleSiliconHIDBridge`, and `FlydigiHID`. Static library targets keep hardware and policy replaceable without introducing package-management complexity. `SensorProvider`, `FanDevice`, `ExternalCoolerController`, and `ProfileStore` are the only hardware-facing contracts: the sensor provider needs no elevated rights and is read-only, and the cooler controller is high-level and contains no raw HID surface. The app links no AppleSMC write entry point at all. Parameterized scripts own repeatable Release archive and distribution validation commands.

## Build and Distribution Design

- Deployment target: macOS 14.0; supported architectures: `arm64` and `x86_64`. `PlatformSensorProvider` selects `AppleSMCSensorProvider` on Intel and `AppleSiliconHIDSensorProvider` on Apple Silicon at runtime; any missing service or key is a supported unavailable state.
- The app bundle identifier comes from one checked-in build configuration (`Configuration/ProductIdentifiers.xcconfig`, overridable by the ignored `LocalSigning.xcconfig`); development and distribution identities change through build settings without source edits.
- App Sandbox is disabled because direct AppleSMC and HID access are incompatible with the intended hardware behavior; no other entitlement is requested. Hardened Runtime is enabled for distribution.
- `SMAppService.mainApp` handles launch-at-login only. No background service is registered and no System Settings approval beyond the login item is required.
- Distribution documentation covers Developer ID Application signing, notarization, stapling, `/Applications` placement, and verification; a local ad-hoc DMG path exists for machines without an Apple account.
- Without Developer ID credentials, CI/development produces an unsigned Release archive, verifies the bundle layout, both slices, plists, entitlements, and build settings, rehearses ad-hoc signability on a temporary copy, and records signing/notarization as an explicit blocker. With credentials, the same archive workflow signs, validates with `codesign --verify --deep --strict`, notarizes, staples, and performs `spctl` assessment without source changes.

## Verification Strategy

1. Run deterministic XCTest coverage for codecs, out-of-order and stale filtering, aggregation, exact ramp boundaries and interpolation, all Cool branches (verified stop, no-stop verified minimum, and capability-limited no-transmit), Critical precedence over Auto and Manual, stale-source maximum fallback, malformed capabilities, persistence, session-marker recovery, ACK retries, capability gating, and view-state derivation.
2. Prove SC-001 with a mock UI launch test that starts its clock immediately before process launch and waits at most 10 seconds for accessibility elements representing the hottest state and the cooler, including a disconnected cooler; repeat with no recognized sensors and require the unavailable state plus the cooler's card.
3. Prove SC-002 over 200 virtual refresh generations covering 1-, 2-, and 30-second intervals; record provider availability and presentation-snapshot publication instants and require at least 198/200 within interval +0.5 seconds, with separate metric fixtures proving 197 fails and 198 passes. Use no wall-clock sleeps.
4. Prove SC-007 with mock UI journeys and semantic action counting: cooler-card activation, mode selection, sensor selection, and one committed slider/numeric edit each count once, while keystrokes within one committed numeric edit do not. Require the connected, write-ready fixture cooler to complete Auto configuration in at most four actions and Manual in at most three, with synchronized controls after each edit; disconnected and capability-limited fixtures must remain visible but are excluded from configurability timing.
5. Build the app explicitly for `x86_64` Debug, run native `arm64` tests, build universal Debug output, then create an unsigned universal Release archive and validate bundle/plist/entitlement structure. Rehearse signability on a temporary archive copy by ad-hoc signing and running strict `codesign` verification; do not represent that as Developer ID validation.
6. When credentials are present, use the same parameterized archive scripts to apply Developer ID identities and bundle settings without source edits, notarize, staple, and validate. Otherwise record the exact signing/notary blocker without claiming SC-010 fully exercised.
7. Run the app in mock mode and verify all four destinations plus the menu bar, full profile editing, policy transitions, crash-recovery notice, and capability-limited BS3 state.
8. Run the app without a BS3 Pro to prove read-only degradation and verify no recognized SMC keys still yields a navigable UI.
9. On Intel hardware, verify missing SMC keys do not fail startup and read-only monitoring remains available. On Apple Silicon, verify native launch with the chip-specific key set and HID die sensors, and full mock/read-only navigation.
10. Treat BS3 Pro attach/ACK behavior, the `0x24` hand-back on quit, physical gear-button interaction, sleep/wake reconnect, and exact device RPM limits as hardware smoke tests documented for later physical validation.
