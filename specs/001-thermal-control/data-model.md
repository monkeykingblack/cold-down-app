# Data Model: Cold Down

## SensorIdentity

Represents a physical or calculated temperature source.

| Field | Type | Rules |
|-------|------|-------|
| `id` | Stable string | Physical sensors use raw SMC key; calculated sensors use reserved identifiers |
| `displayName` | String | Non-empty English label |
| `rawKey` | Optional four-character string | Required for physical SMC sensors; absent for calculated sensors |
| `group` | SensorGroup | CPU, GPU, Heatsink, Memory, PCH, Battery, Ambient, Other, or Calculated |
| `kind` | SensorKind | Physical or calculated |

Identity is unique by `id`. The raw key is always preserved even when the friendly label is heuristic.

## SensorReading

| Field | Type | Rules |
|-------|------|-------|
| `sensor` | SensorIdentity | Required |
| `celsius` | Optional Double | Valid only when finite and within -20...125 |
| `sampledAt` | Date | Must not be materially in the future |
| `sourceGeneration` | UInt64 | Monotonic provider generation that produced the sample |
| `state` | ReadingState | Fresh, stale, unavailable, or invalid |
| `failureReason` | Optional enum | Missing key, decode failure, out of range, non-finite, expired, or transport failure |

State transitions: `unavailable → fresh` on a valid sample; `fresh → stale` after `max(3 × refresh interval, 6 seconds)`; any newer malformed sample → `invalid`; a previously known but missing key in a newer accepted generation → `unavailable`. A generation older than the latest committed generation is discarded. Within an accepted generation, a sample older than the last committed sample for that sensor is ignored; equal timestamp/value is idempotent, while equal timestamp/different value is ignored and diagnosed. Stale, unavailable, and invalid readings never contribute to aggregates or policy.

## SensorBatch

| Field | Type | Rules |
|-------|------|-------|
| `generation` | UInt64 | Assigned monotonically before polling; older completed polls cannot replace newer state |
| `sampledAt` | Date | Common batch boundary used for freshness and latency measurement |
| `readings` | Array of SensorReading | Complete result for keys observed in this generation |
| `missingSensorIDs` | Set of SensorIdentity.ID | Known keys absent from this generation become unavailable |

Only the latest acceptable generation is committed. Aggregates and policy use one committed generation, never a mixture of late and current batches.

## SensorSummary

An immutable aggregation generated for one refresh cycle:

- All known physical readings, including stale and unavailable entries.
- CPU average, GPU average, all-valid-sensor average.
- Hottest valid sensor and hottest valid sensor per physical group.
- Generation timestamp and source refresh sequence.

Each average uses only fresh valid members. An empty member set yields no calculated reading rather than zero.

## SpeedCapabilities

| Field | Type | Rules |
|-------|------|-------|
| `minimum` | Int | Greater than zero unless a verified stop is supported, in which case zero is allowed |
| `maximum` | Int | Must be greater than or equal to minimum |
| `step` | Int | Positive supported increment; required for adjustable writes |
| `unit` | String | RPM by default |
| `provenance` | CapabilityProvenance | Unverified, deviceVerified, auditedModel, or deterministicMock |
| `supportsVerifiedStop` | Bool | False for BS3 Pro until physically verified |

Missing bounds, a non-positive minimum, maximum below minimum, or a non-positive or unsupported step make the capability structurally invalid: writes are disabled while read-only state is retained. Equal positive minimum and maximum is a valid fixed capability with no adjustable slider. Real writes require deviceVerified or auditedModel provenance; deterministicMock is accepted only by the mock transport, and unverified produces a capabilityLimited state. `clamped(_:)` bounds a value, rounds it to the step from the minimum, and bounds it again.

The audited BS3 Pro capability is 1,000–4,000 RPM in 50 RPM steps.

## FanDeviceState

| Field | Type | Rules |
|-------|------|-------|
| `id` | Stable string | BS3 Pro uses vendor and product identity, e.g. `flydigi:37d7:1004` |
| `name` | String | Human-readable English name |
| `connection` | ConnectionState | Connected or disconnected |
| `currentSpeed` | Optional Int | Measured RPM from the device's status pushes |
| `targetSpeed` | Optional Int | Present only when a target has been acknowledged |
| `reportedMode` | Optional FanControlMode | Auto when the device runs one of its own gears, Manual when the host holds realtime control |
| `capabilities` | Optional SpeedCapabilities | Required when writes are enabled |
| `writeAvailability` | WriteAvailability | Ready, disconnected, capabilityLimited, invalidCapabilities, or awaitingAcknowledgement |
| `statusMessage` | Optional String | One concise connection or capability message for the interface |

A disconnected cooler remains in the snapshot and retains its profile.

## FanProfile

| Field | Type | Rules |
|-------|------|-------|
| `mode` | FanControlMode | Auto or Manual |
| `selectedSensor` | SensorSelection | Physical ID, CPU average, GPU average, all average, or hottest |
| `thresholdCelsius` | Int | Inclusive 45...85 in 1 °C steps; default 65; starts Warm |
| `manualTarget` | Int | Clamped to current cooler capabilities before use |

Profiles are stored in `AppPreferences.profiles` keyed by the cooler's `FanDeviceState.id`. `validated(for:)` re-clamps the threshold and manual target against the current capabilities. `suggested(for:summary:)` is what the cooler follows until a profile is saved: Auto on the CPU average, or the hottest reading when no CPU sensor exists, with the current speed (or the minimum) as the Manual starting point. All-sensor average is selectable but never the default.

State transitions: `Auto ↔ Manual` by explicit user action. On a launch that follows an unclean exit every Manual profile becomes Auto with its target retained (see SessionMarker). Disconnection, capability limitation, or critical policy does not change the saved profile.

## AppPreferences

| Field | Type | Default / validation |
|-------|------|----------------------|
| `schemaVersion` | Int | Current known version only; migrate or fall back safely |
| `profiles` | Map fanID → FanProfile | Validate against current devices and sensors |
| `refreshInterval` | TimeInterval | Default 2; clamp to 1...30 |
| `showTemperatureInMenuBar` | Bool | Default true |
| `launchAtLogin` | Bool | Mirrors the registered main-app login-item status |
| `automaticFlydigiReconnect` | Bool | Default true |

Corrupt envelopes produce defaults and a non-private diagnostic log entry. `updatePreferences` never writes back the caller's copy of `profiles`; profiles are owned by `updateProfile`.

## SessionMarker

| Field | Type | Rules |
|-------|------|-------|
| `sessionActive` | Bool in `UserDefaults` | Set when a session begins; cleared only after a normal quit has released the cooler |

`begin()` returns whether the previous session ended uncleanly and sets the flag; `end()` clears it. A crash, force quit, or power loss leaves it set, which makes the next `CoolingCoordinator.start(revertManualProfiles: true)` switch every Manual profile to Auto before any hardware is touched.

## ThermalBand and CoolingDecision

`ThermalBand`: Cool, Warm, Hot, SafetyFallback, or Critical.

- Cool: selected temperature below its threshold.
- Warm: threshold through less than threshold +10 °C.
- Hot: threshold +10 °C and above, except threshold 85 has no non-critical Hot interval.
- SafetyFallback: the controlling reading is unusable. The unusable reading is discarded and a write-ready cooler is set to its verified maximum.
- Critical: any fresh valid physical or calculated reading at 95 °C or above, regardless of profile mode or selection.

Precedence is `Critical > SafetyFallback > Hot > Warm > Cool`.

## ProfileDemand

| Field | Type | Rules |
|-------|------|-------|
| `fanID` | String | The cooler's identity |
| `temperatureCelsius` | Double | The accepted current value |
| `thresholdCelsius` | Int | Validated 45...85 |
| `band` | ThermalBand | Cool, Warm, or Hot before global overrides |
| `normalizedProgress` | Double | Finite value clamped to 0...1 within the Warm ramp |

`ExternalCoolingAction` is `none`, `stop`, or `target(Int)`.

`CoolingDecision` contains the `band`, the optional `demand`, the `externalAction`, an optional human-readable `reason`, and `evaluatedAt`. It never contains SMC keys or arbitrary HID bytes.

For selected temperature `T`, threshold `θ`, and verified `[minimum, maximum]` with a positive step:

- When the cooler is absent, disconnected, or capability-limited the action is `none`.
- Critical: `target(maximum)` for a write-ready cooler.
- Manual: `target(clamped(manualTarget))`.
- SafetyFallback: `target(maximum)`.
- Cool: `stop` only when `supportsVerifiedStop`, otherwise `target(minimum)`.
- Warm: progress is `clamp((T - θ) / 10, 0...1)`; interpolate minimum-to-maximum, round to step, then clamp.
- Hot: `target(maximum)`.

## ExternalCommandTransaction

| Field | Type | Rules |
|-------|------|-------|
| `command` | Allowed command enum | Only 0x21, 0x22, 0x23, 0x24, 0x25 |
| `payload` | Typed payload | Created by encoder, never supplied by UI |
| `attempt` | Int | 1...3 |
| `deadline` | Monotonic instant | 900 ms per attempt |
| `expectedResponse` | Command ID | Must match received frame |
| `state` | TransactionState | Queued, sent, acknowledged, timedOut, rejected, cancelled |

Only one transaction may be active. Detach cancels it. Bad marker, length, checksum, command, or status frames cannot acknowledge it.

## OverallControlMode

`readOnly` ("Read only") when the cooler is absent, disconnected, or capability-limited; `automatic` or `manual` from the cooler's profile mode; `safetyFallback` whenever the decision band is Critical or SafetyFallback.

## CoolingSnapshot

The coordinator's immutable UI projection containing `sensors` (SensorSummary), `fans` (the cooler only, or empty), `profiles`, `overallMode`, `lastDecision`, and `generatedAt`. Overview, Fans, Sensors, Settings, and the menu-bar popover read the same snapshot to avoid inconsistent displays.
