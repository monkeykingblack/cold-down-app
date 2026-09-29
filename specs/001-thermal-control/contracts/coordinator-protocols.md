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
- Is read-only. `PlatformSensorProvider` selects `AppleSMCSensorProvider` (Intel) or `AppleSiliconHIDSensorProvider` (Apple Silicon) at runtime; neither exposes a write entry point.

## FanDevice

```text
state() async -> FanDeviceState
```

- Provides common identity, connection, capabilities, current state, and write availability.
- Does not imply that writes are supported.

## ExternalCoolerController: FanDevice

```text
state() async -> FanDeviceState
connect() async
setTarget(speed) async throws -> AcknowledgedTarget
releaseControl() async
```

- Owns attach/detach handling, reconnect, serialized commands, ACK matching, and capability gating.
- A successful `setTarget` result means a matching valid acknowledgement was received.
- It cannot expose a raw-command method to the application layer.
- `setTarget` is unavailable for unverified, malformed, stale, or deterministic-mock-only capabilities on a real transport and must emit no mutating report.
- `releaseControl` returns the device to its own control mode (`0x24`) and is called on shutdown; the default implementation does nothing so mocks need not override it.
- The production implementation is `BS3ProController`; deterministic mocks implement the same boundary.

## CoolingPolicy

```text
evaluate(summary, profiles, externalState, now) -> CoolingDecision
```

- Is a pure function and performs no I/O.
- Checks every fresh valid physical and calculated reading for the 95 °C Critical override before evaluating the profile; Critical sets a write-ready cooler to its verified maximum and overrides Manual.
- Returns `externalAction: .none` and band Cool when the cooler is absent, disconnected, capability-limited, or structurally invalid.
- Uses the saved profile for the cooler's `id`, or `FanProfile.suggested` until one is saved.
- Manual returns `.target` of the manual target clamped to the cooler's range.
- A stale or missing selected Auto source produces SafetyFallback with `.target(maximum)`.
- Auto uses the exact interpolation, rounding, clamping, and threshold-85 guard defined in `data-model.md`: Cool selects verified stop only when explicitly supported and otherwise the lowest verified safe speed; Warm ramps; Hot holds maximum.

## ProfileStore

```text
load() async -> AppPreferences
save(preferences) async throws
```

- `load` returns validated defaults for absent/corrupt data.
- Hardware-specific profile validation happens after discovery, not inside storage.

## CoolingCoordinator

```text
init(sensorProvider, externalController?, profileStore, clock, policy)
start(revertManualProfiles) async -> Bool
snapshot() -> CoolingSnapshot
snapshotUpdates() -> AsyncStream<CoolingSnapshot>
updateProfile(fanID, profile, applyNow) async
updatePreferences(preferences) async
currentPreferences() -> AppPreferences
refreshNow() async
shutdown() async
```

- Sole owner of mutable sensor, device, profile, and policy state.
- Publishes immutable snapshots; does not expose hardware transports.
- `start(revertManualProfiles: true)` is passed after an unclean exit: every Manual profile is switched to Auto and saved before any hardware is touched, and the return value tells the UI whether to show the recovery notice.
- `refreshNow` coalesces: while a refresh is running, further requests schedule exactly one follow-up pass instead of interleaving hardware writes.
- `updateProfile` validates against the current cooler state, saves, publishes the new profile immediately, and applies it on the next refresh; `applyNow: false` only saves (used while shutting down).
- `updatePreferences` ignores the caller's copy of `profiles`; profiles are owned by `updateProfile`.
- Applies the decision's `externalAction` to the cooler and logs, but never hides, a failed write.
- `shutdown` cancels refreshing and calls `releaseControl()`; the app bounds the wait at 3 seconds and never blocks termination indefinitely.

## Deterministic test doubles

- `TestClock` controls wall and monotonic time.
- `MockSensorProvider` emits scripted batches, errors, and missing-key transitions.
- `MockExternalCoolerController` records call order and scripts ACK, timeout, reject, attach, detach, and release.
- `MemoryProfileStore` supports round-trip and corrupt-data fixtures without touching user defaults.
- `SessionMarker` accepts an injected `UserDefaults` suite so recovery tests never touch the real one.
