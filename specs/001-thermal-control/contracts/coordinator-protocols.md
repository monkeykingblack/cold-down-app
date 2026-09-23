# Coordinator and Hardware Contracts

## SensorProvider

```text
readSensors() async throws -> SensorBatch
```

- Performs no work on `MainActor`.
- Returns a complete batch with one timestamp/sequence boundary.
- May return no readings without terminating the application.
- Does not reuse values from an earlier batch; staleness belongs to the coordinator.
- Assigns a monotonic generation before polling. The coordinator discards a completed batch older than the latest committed generation and applies the timestamp conflict rules from `data-model.md`.

## FanDevice

```text
state() async -> FanDeviceState
```

- Provides common identity, connection, capabilities, current state, and write availability.
- Does not imply that writes are supported.

## BuiltInFanReader

```text
listFans() async throws -> [FanDeviceState]
```

- Requires no privileged helper.
- Returns only discovered fans and available fields.
- Missing target/mode keys produce optional values, not fabricated defaults.

## BuiltInFanController

```text
listFans() async throws -> [FanDeviceState]
setAuto(fanID) async throws
setTargetRPM(fanID, rpm) async throws -> appliedRPM
restoreAllToAuto() async
```

- Exposes coordinator-facing high-level operations only; no SMC key or byte API exists.
- Implementations independently validate identity and capabilities and never accept zero RPM.
- The production implementation is backed by `PrivilegedFanHelperClient`; deterministic mocks implement the same boundary.

## ExternalCoolerController: FanDevice

```text
state() async -> FanDeviceState
connect() async
setTarget(speed) async throws -> AcknowledgedTarget
```

- Owns attach/detach handling, reconnect, serialized commands, ACK matching, and capability gating.
- A successful result means a matching valid acknowledgement was received.
- It cannot expose a raw-command method to the application layer.
- `setTarget` is unavailable for unverified, malformed, stale, or deterministic-mock-only capabilities on a real transport and must emit no mutating report.

## PrivilegedFanHelperClient: BuiltInFanController

```text
status() async -> HelperStatus
listFans() async throws -> [HelperFanRecord]
setAuto(fanID) async throws
setTargetRPM(fanID, rpm) async throws -> appliedRPM
restoreAllToAuto() async
renewLease() async throws -> leaseExpiry
```

- XPC failures map to unavailable status and trigger coordinator restoration handling.
- The app treats timeout or disconnect as failure; it never assumes a write succeeded.

## CoolingPolicy

```text
evaluate(summary, fanStates, profiles, helperStatus, externalState, now) -> CoolingDecision
```

- Is a pure function and performs no I/O.
- Checks every fresh valid physical and calculated reading for the 95 °C Critical override before evaluating profile demand.
- Evaluates active Auto profiles independently and selects the maximum `(band rank, normalized progress, fanID)` as system non-critical demand.
- Uses the exact interpolation, rounding, clamping, current-RPM floor, and threshold-85 guard defined in `data-model.md`.
- Generates a built-in target only for that fan's own Hot profile and records whether external acknowledgement is a prerequisite.
- In Cool, selects verified stop only when explicitly supported; otherwise selects the lowest verified safe speed. Disconnected or capability-limited external state produces no external write.
- A stale or missing selected Auto source produces SafetyFallback with verified external maximum only for a write-ready cooler and Auto restoration for every built-in fan.

## ProfileStore

```text
load() async -> AppPreferences
save(preferences) async throws
```

- `load` returns validated defaults for absent/corrupt data.
- Hardware-specific profile validation happens after discovery, not inside storage.

## CoolingCoordinator

```text
start() async
snapshot() async -> CoolingSnapshot
updateProfile(fanID, profile) async
updatePreferences(preferences) async
refreshNow() async
shutdown() async
```

- Sole owner of mutable sensor, device, profile, and policy state.
- Publishes immutable snapshots; does not expose hardware transports.
- Applies external-first ordering and all global safety overrides.
- When a verified controllable cooler is connected and write-ready, applies its maximum request first and sends related automatic built-in increases only after a matching acknowledgement. A failed required request suppresses those increases for the cycle. A disconnected or capability-limited cooler is treated as unavailable and not active, but does not block an otherwise eligible validated built-in Hot increase.
- When a selected Auto source becomes stale or missing, discards the reading, requests verified external maximum only if the cooler is write-ready, emits no external write otherwise, and restores every built-in fan to Auto.
- `shutdown` requests restore-all and never blocks application termination indefinitely.

## Deterministic test doubles

- `TestClock` controls wall and monotonic time.
- `MockSensorProvider` emits scripted batches, errors, and missing-key transitions.
- `MockBuiltInFanReader` exposes arbitrary fan counts and incomplete capabilities.
- `MockBuiltInFanController` records high-level target/Auto operations and restoration order.
- `MockExternalCoolerController` records call order and scripts ACK, timeout, reject, attach, and detach.
- `MockPrivilegedFanHelperClient` records validation, lease, disconnect, and restore behavior.
- `MemoryProfileStore` supports round-trip and corrupt-data fixtures without touching user defaults.
