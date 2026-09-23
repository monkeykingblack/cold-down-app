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

## FanCapabilities

| Field | Type | Rules |
|-------|------|-------|
| `minimum` | Int | Built-in minimum must be greater than zero |
| `maximum` | Int | Must be greater than or equal to minimum |
| `step` | Int | Positive supported increment; required for adjustable writes |
| `unit` | SpeedUnit | RPM or discrete level |
| `verification` | CapabilityVerification | Unverified, deviceVerified, auditedModel, or deterministicMock |
| `supportsAuto` | Bool | Built-in true; external true only for application policy, not device firmware mode |
| `supportsSafeStop` | Bool | False for BS3 Pro until physically verified |
| `canReadTarget` | Bool | Reflects current hardware capability |

Missing bounds, a non-positive built-in minimum, maximum below minimum, a non-positive or unsupported step, stale capability data, or inconsistent fan identity/count disable writes while retaining read-only state. Equal positive minimum and maximum is a valid fixed capability with no adjustable slider. Real external writes require deviceVerified or auditedModel provenance; deterministicMock is accepted only by mock transport, and unverified produces a capabilityLimited state.

## FanDeviceState

| Field | Type | Rules |
|-------|------|-------|
| `id` | Stable string | Built-in uses discovered index plus hardware domain; BS3 Pro uses model identity |
| `name` | String | Human-readable English name |
| `kind` | FanKind | Built-in or external |
| `connection` | ConnectionState | Connected, disconnected, or unavailable |
| `capabilities` | FanCapabilities | Required when writes are enabled |
| `currentSpeed` | Optional Int | RPM or level using capability unit |
| `targetSpeed` | Optional Int | Present only when readable/known |
| `reportedMode` | Optional mode | macOS Auto, forced, external real-time, or unknown |
| `writeAvailability` | WriteAvailability | Ready or a reason such as helper missing, disconnected, capabilityLimited, invalid capabilities, or awaiting ACK |
| `updatedAt` | Date | Used for presentation freshness |

Disconnected known external devices remain in the snapshot and retain their profile.

## FanProfile

| Field | Type | Rules |
|-------|------|-------|
| `fanID` | String | References a FanDeviceState identity |
| `mode` | ProfileMode | Auto or Manual |
| `sensorSelection` | SensorSelection | Physical ID, CPU average, GPU average, all average, or hottest |
| `thresholdCelsius` | Int | Inclusive 45...85 in 1 °C steps; default 72; starts Warm |
| `manualTarget` | Int | Clamped to current fan capabilities before use |

Default selection is the hottest fresh valid physical CPU sensor, falling back to the hottest fresh valid sensor when no CPU sensor exists. All-sensor average is selectable but never the default.

State transitions: `Auto ↔ Manual` by explicit user action. A built-in Manual profile becomes `suspended` on startup, helper loss, total sensor loss, sleep/wake, invalid capabilities, or critical policy; suspension restores hardware Auto but does not erase the saved profile.

## AppPreferences

| Field | Type | Default / validation |
|-------|------|----------------------|
| `schemaVersion` | Int | Current known version only; migrate or fall back safely |
| `profiles` | Map fanID → FanProfile | Validate against current devices and sensors |
| `refreshIntervalSeconds` | Double | Default 2; clamp to 1...30 |
| `showTemperatureInMenuBar` | Bool | Default true |
| `launchAtLogin` | Bool | Mirrors registered main-app service status |
| `automaticFlydigiReconnect` | Bool | Default true |

Corrupt envelopes produce defaults and a non-private diagnostic log entry.

## ThermalBand and CoolingDecision

`ThermalBand`: Cool, Warm, Hot, Critical, or SafetyFallback.

- Cool: selected temperature below its threshold.
- Warm: threshold through less than threshold +10 °C.
- Hot: threshold +10 °C through less than 95 °C, except threshold 85 has no non-critical Hot interval.
- Critical: any fresh valid physical or calculated reading at 95 °C or above, regardless of profile selection.
- SafetyFallback: controlling reading unusable, total sensor loss during built-in Manual, or control-channel failure. A missing or stale selected Auto source discards the unusable reading, requests verified external maximum only when the cooler is write-ready, sends no external write otherwise, and restores all built-in fans to Auto.

Precedence is `Critical > SafetyFallback > Hot > Warm > Cool`.

## ProfileDemand

| Field | Type | Rules |
|-------|------|-------|
| `fanID` | String | Deterministic final tie-breaker |
| `sensorID` | SensorIdentity.ID | Must resolve to a fresh valid selected source |
| `temperatureCelsius` | Double | The accepted current value |
| `thresholdCelsius` | Int | Validated 45...85 |
| `band` | ThermalBand | Cool, Warm, or Hot before global overrides |
| `normalizedProgress` | Double | Finite value clamped to 0...1 within the active ramp |

The system non-critical demand is the lexicographic maximum of `(band rank, normalizedProgress, fanID)` across active Auto profiles. External supplemental cooling follows that winning demand. Built-in targets remain profile-specific and are generated only for built-in profiles whose own demand is Hot.

`CoolingDecision` contains all evaluated demands, the winning demand, global override reason, external target and capability provenance, required external acknowledgement, per-built-in target actions, safety reason, and timestamp. It never contains raw SMC keys for writes or arbitrary HID bytes.

For selected temperature `T`, threshold `θ`, and verified `[minimum, maximum]` with a positive step:

- Warm external progress is `clamp((T - θ) / 10, 0...1)`; interpolate minimum-to-maximum, round to step, then clamp.
- Hot holds external maximum. For an eligible built-in profile with `hotStart = θ + 10`, progress is `clamp((T - hotStart) / (95 - hotStart), 0...1)`; interpolate, round, clamp, then floor the request at current RPM.
- Threshold 85 reaches Critical at its Hot boundary, so the built-in denominator is never evaluated.
- If a verified controllable cooler is connected and write-ready, its acknowledged maximum is an ordering prerequisite for related built-in increases. A failed required acknowledgement suppresses those increases for the cycle. A disconnected or capability-limited cooler is unavailable, is never recorded as active, and does not block an otherwise eligible validated built-in Hot increase.

## ExternalCommandTransaction

| Field | Type | Rules |
|-------|------|-------|
| `command` | Allowed command enum | Only 0x21, 0x22, 0x23, 0x25 |
| `payload` | Typed payload | Created by encoder, never supplied by UI |
| `attempt` | Int | 1...3 |
| `deadline` | Monotonic instant | 900 ms per attempt |
| `expectedResponse` | Command ID | Must match received frame |
| `state` | TransactionState | Queued, sent, acknowledged, timedOut, rejected, cancelled |

Only one transaction may be active. Detach cancels it. Bad marker, length, checksum, command, or status frames cannot acknowledge it.

## HelperLease

| Field | Type | Rules |
|-------|------|-------|
| `clientIdentity` | Validated connection identity | Release must satisfy signing requirement |
| `issuedAt` | Monotonic instant | Set after accepted connection and initial restore |
| `expiresAt` | Monotonic instant | Eight seconds after last accepted renewal |
| `state` | LeaseState | Inactive, active, expired, disconnected, invalidated |

Any transition away from Active invokes restore-all before another target request may succeed. A new client cannot inherit the previous client's lease or manual state.

## CoolingSnapshot

The coordinator's immutable UI projection containing SensorSummary, ordered fan states, validated profiles, helper status, external transaction status, overall mode, and latest safety message. Overview, Fans, Sensors, Settings, and MenuBarExtra read the same snapshot to avoid inconsistent displays.
