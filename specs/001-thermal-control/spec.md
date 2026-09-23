# Feature Specification: Cold Down

**Feature Branch**: `001-thermal-control`

**Created**: 2026-09-19

**Status**: Approved for implementation

**Input**: User description: "Build a native macOS application that runs on Intel and Apple Silicon, monitors temperature sensors, and safely controls built-in fans and a Flydigi BS3 Pro cooler. Intel AppleSMC hardware remains the primary control target."

## Clarifications

### Session 2026-09-19

- Q: During a critical-temperature fallback, what must happen to built-in Mac fans? → A: Always restore built-in fans to macOS Auto.
- Q: Should real built-in fan writes be completely unavailable unless both the app and privileged helper have valid matching signatures? → A: Validate matching signatures in release builds; development builds may use the same narrow helper interface without the production identity check.
- Q: How should the single Auto threshold determine the warm, hot, and critical temperature bands? → A: Warm starts at the configured threshold, Hot starts 10 °C above it, and Critical always starts at 95 °C.
- Q: When the BS3 Pro is connected and write-ready, must it be raised to high cooling before any built-in Auto profile may request a higher RPM? → A: Yes; the BS3 Pro high-cooling request must be acknowledged before an automatic built-in fan increase is allowed.
- Q: Should built-in Manual mode remain active when every temperature sensor is stale or unavailable? → A: No; restore every built-in fan to macOS Auto when no fresh valid temperature remains.
- Q: When different fan profiles follow different sensors, how should the coordinator determine the system-wide cooling demand? → A: Use the highest demand from all selected profile sensors, while any fresh valid sensor at or above 95 °C immediately triggers global Critical fallback.
- Q: What range should the Auto ramp-up threshold allow? → A: Allow 45–85 °C in 1 °C steps, defaulting to 72 °C.
- Q: How should the single-threshold linear ramp translate temperature into external and built-in fan targets? → A: Use a two-stage external-first linear ramp: external minimum-to-maximum during Warm, then external maximum plus built-in minimum-to-maximum during Hot, with Critical restoring built-in Auto.
- Q: How should real BS3 Pro speed controls behave until its safe RPM range is physically verified? → A: Keep real-device speed controls disabled until the device reports a verified range or an audited model-specific range is added; show a capability-limited message while mock mode remains fully controllable.
- Q: May eligible Hot-mode built-in fan policies proceed when a physically connected BS3 Pro is capability-limited because its safe speed range is unverified? → A: Yes. Treat the cooler as unavailable for control, allow validated built-in Hot-mode increases without a BS3 acknowledgement, and never report external cooling as active.
- Q: What should happen to the BS3 Pro when a selected Auto sensor becomes stale or unavailable? → A: Request the verified external maximum when the cooler is write-ready, otherwise send nothing; restore every built-in fan to macOS Auto and never use the stale reading.

### Session 2026-09-20

- Q: Must the application also run on the current Apple Silicon development Mac? → A: Yes. Ship universal `arm64` and `x86_64` app/helper binaries. Apple Silicon must launch and retain the native UI, mock mode, persistence, and Flydigi discovery; Intel-only AppleSMC monitoring/control must degrade safely to unavailable.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Monitor thermal health without control access (Priority: P1)

A Mac user can open Cold Down and immediately see available temperature sensors and fan status even when the external cooler is absent, AppleSMC is unsupported, and privileged fan control is unavailable.

**Why this priority**: Read-only monitoring is the safe baseline and must remain useful on every supported system.

**Independent Test**: Launch on a supported Mac with no external cooler and no privileged helper, then verify that available sensors and built-in fan status appear, unavailable items are clearly labeled, and the interface remains usable.

**Acceptance Scenarios**:

1. **Given** supported temperature sensors exist, **When** the application refreshes, **Then** every valid reading shows a human-readable name, raw key, group, temperature, timestamp-derived freshness state, and aggregate values.
2. **Given** the privileged helper is unavailable, **When** the user views built-in fans, **Then** current fan information remains visible and write controls clearly indicate read-only status.
3. **Given** a previously known external cooler is disconnected, **When** the user views Overview or Fans, **Then** the cooler remains visible, dimmed, and described with one concise connection message.

---

### User Story 2 - Apply safe automatic cooling (Priority: P2)

A Mac user can select a physical or calculated temperature source and a single ramp-up threshold for each available fan, with supplemental external cooling engaged before built-in fan intervention.

**Why this priority**: Automatic cooling delivers the primary control value while preserving the Mac's own safety authority.

**Independent Test**: Feed deterministic cool, warm, hot, critical, missing, and stale readings through simulated devices and verify the external-first decisions and built-in fallback behavior.

**Acceptance Scenarios**:

1. **Given** a valid selected sensor is warm, **When** policy evaluation occurs, **Then** the external cooler ramps linearly from its lowest verified safe speed at the threshold to maximum at threshold +10 °C while built-in fans remain under system automatic control.
2. **Given** one or more valid selected profile sensors demand different cooling bands, **When** policy evaluation occurs, **Then** the highest selected-profile demand controls supplemental cooling and each eligible built-in fan ramps from no lower than its current RPM toward hardware maximum between threshold +10 °C and 95 °C; a write-ready connected BS3 Pro must first acknowledge maximum cooling, while a disconnected or capability-limited BS3 Pro is treated as unavailable and does not block the built-in increase.
3. **Given** any fresh valid sensor reaches 95 °C, **When** policy evaluation occurs, **Then** global Critical takes precedence over profile demand, external cooling requests high speed when available, and every built-in fan returns to macOS Auto.
4. **Given** a selected Auto sensor becomes stale or unavailable, **When** policy evaluation occurs, **Then** the stale reading is not used, a write-ready BS3 Pro is requested to run at its verified maximum while a disconnected or capability-limited cooler receives no write, and every built-in fan returns to macOS Auto.
5. **Given** control authorization or the helper connection fails, **When** a built-in fan had been manually influenced, **Then** the fan is restored to system automatic control.

---

### User Story 3 - Configure individual fans manually (Priority: P3)

A Mac user can choose Auto or Manual for each connected fan whose write availability is ready and enter a target using synchronized slider and numeric controls constrained to the device's supported range.

**Why this priority**: Direct control is valuable but must be layered on top of safe discovery, monitoring, and failure handling.

**Independent Test**: Use deterministic fan capabilities, edit slider and numeric values in both modes, restart the application, and verify validated preferences and safe startup behavior.

**Acceptance Scenarios**:

1. **Given** a connected fan, **When** the user changes the slider or numeric field, **Then** the other control updates and the value is clamped to the supported range; Auto thresholds use 45–85 °C in 1 °C steps and default to 72 °C.
2. **Given** a saved built-in manual profile, **When** the application starts after an unclean exit, **Then** the fan begins in system automatic mode and the profile is reapplied only after fresh sensor data and helper health are confirmed.
3. **Given** an external cooler disconnects, **When** the user selects it, **Then** configuration controls are disabled without removing its saved profile.
4. **Given** built-in Manual mode is active, **When** all temperature readings become stale, invalid, or unavailable, **Then** every built-in fan returns to macOS Auto and remains there until thermal visibility is restored.
5. **Given** a real BS3 Pro is connected but no verified speed range is available, **When** the user selects it, **Then** speed controls remain disabled, the interface shows one concise capability-limited message, and no speed-setting report is transmitted.

---

### User Story 4 - Check status from the menu bar (Priority: P4)

A Mac user can see the hottest current temperature and a compact fan summary without opening the full window.

**Why this priority**: Thermal status should be glanceable during sustained workloads.

**Independent Test**: Enable and disable temperature display, exercise connected and disconnected device states, and verify the menu content and main-window action.

**Acceptance Scenarios**:

1. **Given** menu temperature display is enabled and a fresh sensor exists, **When** the menu bar item updates, **Then** it shows a fan symbol and hottest temperature.
2. **Given** the menu opens, **When** devices are connected or disconnected, **Then** it shows hottest sensor, built-in RPM summaries, external cooler state, overall control mode, and a working action to open the main application.

### Edge Cases

- No temperature keys are available, a discovered key disappears, or all readings become invalid.
- A reading is non-finite, below -20 °C, above 125 °C, unchanged beyond its freshness deadline, or arrives out of order.
- Fan count changes between launches or saved fan identifiers no longer exist.
- Hardware reports inverted, missing, or inconsistent minimum and maximum fan speeds.
- The helper rejects the caller, disconnects mid-command, misses its lease deadline, or sees an invalid fan index.
- The Mac sleeps or wakes while manual control is active.
- The external cooler detaches during a command, reports no verified speed range, sends a corrupt or unrelated acknowledgement, or does not acknowledge within the bounded retry window.
- Saved settings contain unknown sensor identifiers or values outside current device capabilities.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The product MUST ship native `arm64` and `x86_64` slices, support Macs running macOS 13 or later, and use English interface text. AppleSMC monitoring and built-in fan control MAY be unavailable on Apple Silicon, but startup, navigation, mock mode, persistence, read-only degradation, and Flydigi discovery MUST remain functional.
- **FR-002**: The product MUST discover available temperature sensors at runtime and MUST NOT assume a fixed set of sensors.
- **FR-003**: Each sensor MUST retain its raw hardware key, human-readable name, group, value, sample time, and fresh, stale, or unavailable state.
- **FR-004**: The product MUST reject non-finite and implausible temperatures and MUST mark missing or expired samples rather than silently reusing them.
- **FR-005**: The product MUST calculate CPU average, GPU average, all-valid-sensor average, hottest valid sensor, and hottest valid sensor per group using only current valid readings.
- **FR-006**: The default refresh interval MUST be 2 seconds and users MUST be able to select a supported interval from 1 through 30 seconds.
- **FR-007**: The product MUST discover each built-in fan and expose current, minimum, maximum, target, and control-mode information when the hardware supplies it without requiring control authorization.
- **FR-008**: Built-in fan write access MUST be optional; monitoring and the complete interface MUST remain usable in read-only mode when control access is absent.
- **FR-009**: Built-in write requests MUST accept only listing, automatic-mode restoration, validated target-speed setting, and lease renewal operations.
- **FR-010**: Built-in write requests MUST validate fan identity, clamp speed between known hardware minimum and maximum, and MUST never permit a built-in fan to stop.
- **FR-011**: Every built-in fan MUST return to macOS Auto when the controlling client disconnects or exits, the lease expires, invalid state is detected, the computer sleeps or wakes, the selected Auto sensor is missing or stale, all temperature readings are unusable during Manual mode, or policy enters critical fallback. When a selected Auto sensor becomes missing or stale, the coordinator MUST also request verified maximum cooling from a write-ready BS3 Pro; it MUST send no external write when the cooler is disconnected or capability-limited and MUST NOT use the stale reading.
- **FR-012**: Release builds MUST reject privileged control requests unless the client has the expected signed application identity. Development builds MAY omit the production identity check, but MUST retain the same narrow operation allowlist, validation, lease expiry, and automatic-restoration safeguards.
- **FR-013**: The product MUST discover the Flydigi BS3 Pro using verified hardware identity and capability information, react to attach and detach, and reconnect automatically when enabled.
- **FR-014**: External cooler commands MUST be serialized, validate responses, time out, and retry no more than two additional times after the first attempt.
- **FR-015**: The product MUST support external cooler connection state, current operating state when available, and capability-gated fan-speed control. A physical device's speed controls MUST remain disabled and no speed-setting report may be transmitted until the device reports a verified safe range or an audited model-specific range has been added and physically validated. The interface MUST show a concise capability-limited state when connected without a verified range. Mock mode MUST expose a deterministic verified range. Lighting, firmware updates, and unverified power/reset behavior are out of scope.
- **FR-016**: The product MUST NOT transmit command values `0x05` or `0x06`, arbitrary commands, or arbitrary byte payloads to a physical external cooler.
- **FR-017**: A selected Auto threshold MUST use the inclusive 45–85 °C range in 1 °C steps and default to 72 °C. It MUST define the start of Warm; below it conditions are Cool. During Cool, built-in fans MUST remain in system automatic mode and external cooling MUST be off only if a verified stop command exists, otherwise at the lowest verified safe speed.
- **FR-018**: Hot MUST begin 10 °C above the selected Auto threshold. During Warm, the external target MUST be the linearly interpolated value from its lowest verified safe speed at the threshold to its verified maximum at threshold +10 °C, clamped to verified capabilities; built-in fans MUST remain in macOS Auto.
- **FR-019**: The system-wide non-critical cooling demand MUST be the highest band demanded by any fresh valid sensor selected by an active Auto profile. During Hot, a write-ready external cooler MUST remain at its verified maximum and each eligible built-in Auto-profile target MUST interpolate linearly from hardware minimum at threshold +10 °C to hardware maximum immediately below 95 °C, be clamped to hardware capabilities, and never be lower than the fan's current RPM. When the BS3 Pro is connected and write-ready, the product MUST receive acknowledgement of the maximum-cooling request before applying any automatic built-in fan target increase. If the cooler is disconnected or capability-limited, the product MUST treat external cooling as unavailable, MUST NOT claim that it is active, and MUST allow otherwise eligible validated built-in Hot-mode increases without its acknowledgement. If a required maximum-cooling request to a write-ready cooler fails, the product MUST treat external cooling as unavailable for that evaluation cycle, MUST NOT claim that it is active, and MUST suppress the associated automatic built-in increase for that cycle; macOS retains independent built-in safety control.
- **FR-020**: Any fresh valid physical or calculated sensor at or above 95 °C MUST trigger system-wide Critical regardless of profile selection or configured threshold, and Critical MUST take precedence over every other band. During Critical, the product MUST stop using stale data, request high external cooling when available, and always restore every built-in fan to macOS Auto.
- **FR-021**: Every fan MUST retain an Auto or Manual profile with selected sensor, threshold, and appropriate manual target, validated against current capabilities before use.
- **FR-022**: Auto profiles MUST offer physical sensors, CPU average, GPU average, all-sensor average, and hottest sensor; all-sensor average MUST NOT be the default source.
- **FR-023**: Auto and Manual editors MUST pair a slider with synchronized numeric entry, clamp typed values, and disable unavailable actions.
- **FR-024**: Saved built-in manual profiles MUST NOT be applied at startup until at least one fresh valid temperature and control-channel health are confirmed, and MUST be suspended whenever no fresh valid temperature remains.
- **FR-025**: The main interface MUST include Overview, Fans, Sensors, and Settings destinations using compact controls and native system styling.
- **FR-026**: Overview MUST show a read-only summary of every known fan and a short important-sensor list; selecting a fan MUST navigate to its full configuration.
- **FR-027**: Sensors MUST show all discovered temperature sensors and the required aggregates in compact rows with sentence-case headings.
- **FR-028**: Settings MUST expose launch-at-login, menu temperature, refresh interval, external reconnect, helper status, and mandatory built-in automatic-restoration behavior.
- **FR-029**: The menu bar interface MUST provide the hottest reading, built-in fan summaries, external cooler state, overall mode, and an action that opens the main window.
- **FR-030**: The product MUST persist preferences locally and MUST validate all restored values against current sensors and device capabilities.
- **FR-031**: The product MUST include a deterministic demonstration mode that exercises monitoring, device state, profiles, safety transitions, and the full interface without physical hardware or privileged control access.
- **FR-032**: Safety transitions MUST be recorded with enough context for diagnosis without recording private user data.

### Key Entities

- **Sensor reading**: A temperature sample identified by raw key and display name, with group, value, sample time, and availability state.
- **Calculated sensor**: A current value derived from valid physical readings, including CPU average, GPU average, all-sensor average, hottest sensor, and group hottest values.
- **Fan device**: A built-in or external cooling device with stable identity, connection state, capabilities, current state, and supported target range.
- **Fan profile**: Per-device Auto or Manual configuration including sensor choice, threshold, and manual target.
- **Cooling snapshot**: The coordinated point-in-time view of readings, devices, helper availability, and overall control mode shown by the user interfaces.
- **Safety lease**: A time-limited authorization for built-in fan influence that requires renewal and triggers automatic restoration on expiry.
- **Application preferences**: Refresh, menu bar, launch, reconnect, and validated profile settings retained between launches.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can launch the application and identify the hottest valid sensor and every known fan within 10 seconds, without installing control access.
- **SC-002**: New valid temperature samples appear within one configured refresh interval plus 0.5 seconds in at least 99% of deterministic refresh cycles.
- **SC-003**: Invalid, missing, or expired readings are excluded from every aggregate and visibly marked within one refresh cycle in 100% of deterministic test cases.
- **SC-004**: In 100% of simulated helper disconnect, lease expiry, sleep, wake, stale-sensor, and critical-fallback cases, built-in fans receive automatic-restoration behavior before further manual targets are accepted.
- **SC-005**: In 100% of cool-to-warm simulated transitions, external cooling is requested before any built-in fan target increase.
- **SC-006**: External cooler commands either receive a matching valid acknowledgement or stop after three total attempts within 5 seconds, without sending destructive or undocumented commands.
- **SC-007**: Users can configure any connected fan whose write availability is ready in no more than four direct interactions, with slider and numeric values always agreeing.
- **SC-008**: All normal automated tests run without a physical cooler or installed control helper and pass on the supported development environment.
- **SC-009**: The application starts and remains navigable with no external cooler, no helper, and no recognized temperature keys.
- **SC-010**: A signed distribution build can be prepared from documented steps without changing application source code.

## Assumptions

- The first release is an English-only, directly distributed universal desktop utility. Intel Macs are the primary AppleSMC monitoring/control target; Apple Silicon support covers native launch, UI, mock/persistence behavior, safe unsupported-SMC degradation, and Flydigi discovery. Mac App Store distribution is outside MVP scope.
- One active desktop user controls the application at a time; no cloud account, telemetry upload, or remote control is required.
- Temperatures from -20 °C through 125 °C are treated as physically plausible, while freshness expires after the greater of three refresh intervals or 6 seconds.
- Automatic control uses the hottest valid CPU sensor by default, falling back to the hottest valid sensor when no CPU reading exists.
- The two-stage external-first linear ramp defined by FR-018 and FR-019 is sufficient; a multi-point curve editor is outside MVP scope. Interpolation uses normalized progress clamped to 0...1 and rounds to the device's supported step before final capability clamping.
- External zero-speed or power-off behavior remains unavailable until verified on physical BS3 Pro hardware; the lowest supported safe speed is used instead.
- Physical validation, production signing identity, helper installation approval, and final hardware-specific speed limits depend on the target Mac and cooler; absence of verified limits keeps only real external speed writes disabled and does not reduce monitoring, discovery, or mock-mode coverage.

## Scope Boundaries and Dependencies

- Real AppleSMC monitoring and built-in fan writes depend on an Intel Mac exposing compatible system-management data and, for writes, a separately approved privileged component.
- The external cooler must be paired or connected so the operating system exposes its supported device interface.
- RGB control, firmware maintenance, firmware updates, arbitrary hardware commands, history charts, remote access, and Apple-Silicon-specific internal sensor/fan backends are excluded from this release.
- Hardware commands lacking corroborated protocol evidence are represented only in deterministic simulation and capability-disabled production paths.
