# Feature Specification: Cold Down

**Feature Branch**: `001-thermal-control`

**Created**: 2026-09-19

**Status**: Approved for implementation

**Input**: User description: "Build a native macOS application that runs on Intel and Apple Silicon, monitors temperature sensors through AppleSMC, and safely drives a Flydigi BS3 Pro cooler from them. Sensor access needs no elevated rights and is read-only; nothing in the app writes to AppleSMC."

## Clarifications

### Session 2026-09-19

- Q: How should the single Auto threshold determine the warm, hot, and critical temperature bands? → A: Warm starts at the configured threshold, Hot starts 10 °C above it, and Critical always starts at 95 °C.
- Q: What range should the Auto ramp-up threshold allow? → A: Allow 45–85 °C in 1 °C steps. The default was originally 72 °C and is now 65 °C (FR-017).
- Q: How should the single-threshold linear ramp translate temperature into a cooler target? → A: Below the threshold the cooler idles at its lowest verified safe speed (or a verified stop); from the threshold to threshold +10 °C it ramps linearly from its lowest verified safe speed to its verified maximum; above that it holds maximum.
- Q: How should real BS3 Pro speed controls behave until its safe RPM range is physically verified? → A: Keep real-device speed controls disabled until the device reports a verified range or an audited model-specific range is added; show a capability-limited message while mock mode remains fully controllable.
- Q: What should happen to the BS3 Pro when the selected Auto sensor becomes stale or unavailable? → A: Request the verified maximum when the cooler is write-ready, otherwise send nothing, and never use the stale reading.

### Session 2026-09-20

- Q: Must the application also run on the current Apple Silicon development Mac? → A: Yes. Ship universal `arm64` and `x86_64` binaries. Apple Silicon must launch and retain the native UI, mock mode, persistence, and Flydigi discovery; AppleSMC monitoring must degrade safely to unavailable wherever a key or service is missing.

### Session 2026-09-29

- Built-in fan control and the privileged helper were removed on 2026-09-29; the app now reads sensors only and controls the Flydigi cooler alone.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Monitor thermal health without a cooler (Priority: P1)

A Mac user can open Cold Down and immediately see available temperature sensors and the cooler's status even when the external cooler is absent or AppleSMC exposes no recognized keys.

**Why this priority**: Read-only monitoring is the safe baseline and must remain useful on every supported system.

**Independent Test**: Launch on a supported Mac with no external cooler, then verify that available sensors appear, unavailable items are clearly labeled, the cooler is shown as disconnected, and the interface remains usable.

**Acceptance Scenarios**:

1. **Given** supported temperature sensors exist, **When** the application refreshes, **Then** every valid reading shows a human-readable name, raw key, group, temperature, timestamp-derived freshness state, and aggregate values.
2. **Given** no cooler is connected, **When** the user views Fans, **Then** the cooler's card remains visible, dimmed, and described with one concise connection message, and the overall mode reads "Read only".
3. **Given** no recognized temperature key exists, **When** the application starts, **Then** it stays navigable, shows an unavailable state, and fabricates no values.

---

### User Story 2 - Apply safe automatic cooling (Priority: P2)

A Mac user can select a physical or calculated temperature source and a single ramp-up threshold for the cooler, and the cooler follows the resulting demand without any elevated access.

**Why this priority**: Automatic cooling delivers the primary control value while leaving the Mac's own thermal management untouched.

**Independent Test**: Feed deterministic cool, warm, hot, critical, missing, and stale readings through a simulated cooler and verify the exact cooler targets and the fallback behavior.

**Acceptance Scenarios**:

1. **Given** the selected sensor is below the threshold, **When** policy evaluation occurs, **Then** the cooler idles at its lowest verified safe speed, or is stopped only when a verified stop command exists.
2. **Given** the selected sensor is warm, **When** policy evaluation occurs, **Then** the cooler ramps linearly from its lowest verified safe speed at the threshold to its verified maximum at threshold +10 °C.
3. **Given** the selected sensor is at or above threshold +10 °C, **When** policy evaluation occurs, **Then** the cooler holds its verified maximum.
4. **Given** any fresh valid sensor reaches 95 °C, **When** policy evaluation occurs, **Then** global Critical takes precedence over the profile, including a Manual profile, and a write-ready cooler is set to its verified maximum.
5. **Given** the selected Auto sensor becomes stale or unavailable, **When** policy evaluation occurs, **Then** the stale reading is not used, a write-ready cooler is set to its verified maximum, a disconnected or capability-limited cooler receives no write, and the overall mode reads "Safety fallback".
6. **Given** no profile has been saved for the cooler, **When** it becomes controllable, **Then** it follows Auto on the CPU average (or the hottest reading when no CPU sensor exists) with the default threshold.

---

### User Story 3 - Configure the cooler manually (Priority: P3)

A Mac user can choose Auto or Manual for the cooler when its write availability is ready and enter a target using synchronized slider and numeric controls constrained to the device's supported range.

**Why this priority**: Direct control is valuable but must be layered on top of safe discovery, monitoring, and failure handling.

**Independent Test**: Use deterministic cooler capabilities, edit slider and numeric values in both modes, restart the application cleanly and uncleanly, and verify validated preferences and safe startup behavior.

**Acceptance Scenarios**:

1. **Given** a connected write-ready cooler, **When** the user changes the slider or numeric field, **Then** the other control updates and the value is clamped to the supported range; Auto thresholds use 45–85 °C in 1 °C steps and default to 65 °C.
2. **Given** a saved Manual profile, **When** the application starts after an unclean exit, **Then** the profile starts as Auto, its manual target is retained, and a dismissible notice explains why.
3. **Given** a saved Manual profile, **When** the application starts after a clean exit, **Then** the profile is reapplied once the cooler is connected and write-ready.
4. **Given** the cooler disconnects, **When** the user selects it, **Then** configuration controls are disabled without removing its saved profile.
5. **Given** a real BS3 Pro is connected but no verified speed range is available, **When** the user selects it, **Then** speed controls remain disabled, the interface shows one concise capability-limited message, and no speed-setting report is transmitted.
6. **Given** the user quits the application, **When** the cooler is connected, **Then** it is handed back to its own gear before the process exits, waiting at most 3 seconds.

---

### User Story 4 - Check status from the menu bar (Priority: P4)

A Mac user can see the hottest current temperature and a compact cooler summary without opening the full window.

**Why this priority**: Thermal status should be glanceable during sustained workloads.

**Independent Test**: Enable and disable temperature display, exercise connected and disconnected cooler states, and verify the menu content and main-window action.

**Acceptance Scenarios**:

1. **Given** menu temperature display is enabled and a fresh sensor exists, **When** the menu bar item updates, **Then** it shows a fan symbol and hottest temperature.
2. **Given** the menu opens, **When** the cooler is connected or disconnected, **Then** it shows the hottest sensor, the cooler's row with its mode switch, the overall control mode, and a working action to open the main application.

### Edge Cases

- No temperature keys are available, a discovered key disappears, or all readings become invalid.
- A reading is non-finite, below -20 °C, above 125 °C, unchanged beyond its freshness deadline, or arrives out of order.
- The cooler reports inverted, missing, or inconsistent minimum and maximum speeds.
- The Mac sleeps or wakes while a Manual profile is active.
- The external cooler detaches during a command, reports no verified speed range, sends a corrupt or unrelated acknowledgement, does not acknowledge within the bounded retry window, or leaves realtime mode because the user pressed a physical gear button.
- The previous session ended in a crash, force quit, or power loss while a Manual profile was active.
- Saved settings contain unknown sensor identifiers or values outside current device capabilities.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The product MUST ship native `arm64` and `x86_64` slices, support Macs running macOS 14 or later, and use English interface text. AppleSMC monitoring MAY be partially or wholly unavailable on a given Mac, but startup, navigation, mock mode, persistence, read-only degradation, and Flydigi discovery MUST remain functional.
- **FR-002**: The product MUST discover available temperature sensors at runtime and MUST NOT assume a fixed set of sensors.
- **FR-003**: Each sensor MUST retain its raw hardware key, human-readable name, group, value, sample time, and fresh, stale, or unavailable state.
- **FR-004**: The product MUST reject non-finite and implausible temperatures and MUST mark missing or expired samples rather than silently reusing them.
- **FR-005**: The product MUST calculate CPU average, GPU average, all-valid-sensor average, hottest valid sensor, and hottest valid sensor per group using only current valid readings.
- **FR-006**: The default refresh interval MUST be 5 seconds and users MUST be able to select a supported interval from 1 through 30 seconds.
- **FR-007**: Removed 2026-09-29 (see Clarifications). The Flydigi cooler is the only controllable fan.
- **FR-008**: Sensor access MUST run as the ordinary user and be read-only; the product MUST NOT write to AppleSMC. Monitoring and the complete interface MUST remain usable in read-only mode when no cooler is connected or controllable.
- **FR-009**: Removed 2026-09-29 (see Clarifications).
- **FR-010**: Removed 2026-09-29 (see Clarifications).
- **FR-011**: When the selected Auto sensor is missing or stale, the product MUST enter safety fallback: it MUST NOT use the stale reading, MUST request the verified maximum from a write-ready cooler, and MUST send no external write when the cooler is disconnected or capability-limited.
- **FR-012**: The product MUST require no root-level component, no background service registration, and no entitlement beyond disabled App Sandbox. Distribution builds MUST be signable with Hardened Runtime and notarizable without changing application source.
- **FR-013**: The product MUST discover the Flydigi BS3 Pro using verified hardware identity and capability information, react to attach and detach, and reconnect automatically when enabled.
- **FR-014**: External cooler commands MUST be serialized, validate responses, time out, and retry no more than two additional times after the first attempt.
- **FR-015**: The product MUST support external cooler connection state, current operating state when available, and capability-gated fan-speed control. A physical device's speed controls MUST remain disabled and no speed-setting report may be transmitted until the device reports a verified safe range or an audited model-specific range has been added and physically validated. The interface MUST show a concise capability-limited state when connected without a verified range. Mock mode MUST expose a deterministic verified range. Lighting, firmware updates, and unverified power/reset behavior are out of scope.
- **FR-016**: The product MUST NOT transmit command values `0x05` or `0x06`, arbitrary commands, or arbitrary byte payloads to a physical external cooler.
- **FR-017**: The Auto threshold MUST use the inclusive 45–85 °C range in 1 °C steps and default to 65 °C. It MUST define the start of Warm; below it conditions are Cool. During Cool the cooler MUST be off only if a verified stop command exists, otherwise held at its lowest verified safe speed.
- **FR-018**: Hot MUST begin 10 °C above the selected Auto threshold. During Warm the cooler target MUST interpolate linearly from its lowest verified safe speed at the threshold to its verified maximum at threshold +10 °C, rounded to the supported step and clamped to its capabilities.
- **FR-019**: During Hot the cooler MUST remain at its verified maximum. The product MUST NOT claim external cooling is active when its request failed or the cooler is disconnected or capability-limited, and it MUST NOT drive a disconnected or capability-limited cooler.
- **FR-020**: Any fresh valid physical or calculated sensor at or above 95 °C MUST trigger system-wide Critical regardless of profile mode, profile selection, or configured threshold, and Critical MUST take precedence over every other band. During Critical, the product MUST stop using stale data and MUST set a write-ready cooler to its verified maximum.
- **FR-021**: The cooler MUST retain an Auto or Manual profile with selected sensor, threshold, and manual target, validated against current capabilities before use. Until a profile is saved, the cooler MUST follow Auto on the CPU average, or on the hottest reading when no CPU sensor exists, with the default threshold. A Manual profile MUST hold its target, clamped to the cooler's range, and still yield to Critical.
- **FR-022**: Auto profiles MUST offer physical sensors, CPU average, GPU average, all-sensor average, and hottest sensor; all-sensor average MUST NOT be the default source.
- **FR-023**: Auto and Manual editors MUST pair a slider with synchronized numeric entry, clamp typed values, and disable unavailable actions. Edits MUST appear immediately but reach hardware only after about 0.5 seconds of quiet, and only the final state is written.
- **FR-024**: The product MUST record whether the previous session ended cleanly. After an unclean exit every Manual profile MUST start as Auto with its manual target retained, and the interface MUST explain why in a dismissible notice. On a clean quit the product MUST hand the cooler back to its own gear before exiting, waiting at most 3 seconds.
- **FR-025**: The main interface MUST include Overview, Fans, Sensors, and Settings destinations using compact controls and native system styling.
- **FR-026**: Overview MUST show the cooler's card and a short important-sensor summary; selecting the cooler MUST navigate to its full configuration.
- **FR-027**: Sensors MUST show all discovered temperature sensors and the required aggregates in compact rows with sentence-case headings.
- **FR-028**: Settings MUST expose General (launch-at-login, menu temperature, refresh interval), Flydigi BS3 Pro (automatic reconnect and device settings), and Safety sections.
- **FR-029**: The menu bar interface MUST provide the hottest reading, the cooler's row with its mode switch, the overall mode, and an action that opens the main window.
- **FR-030**: The product MUST persist preferences locally and MUST validate all restored values against current sensors and device capabilities.
- **FR-031**: The product MUST include a deterministic demonstration mode that exercises monitoring, cooler state, profiles, safety transitions, and the full interface without physical hardware.
- **FR-032**: Safety transitions MUST be recorded with enough context for diagnosis without recording private user data.

### Key Entities

- **Sensor reading**: A temperature sample identified by raw key and display name, with group, value, sample time, and availability state.
- **Calculated sensor**: A current value derived from valid physical readings, including CPU average, GPU average, all-sensor average, hottest sensor, and group hottest values.
- **Fan device**: The external cooler, with stable identity, connection state, capabilities, current state, write availability, and supported target range.
- **Fan profile**: The cooler's Auto or Manual configuration including sensor choice, threshold, and manual target.
- **Cooling snapshot**: The coordinated point-in-time view of readings, the cooler, profiles, latest decision, and overall control mode shown by the user interfaces.
- **Session marker**: A persisted flag that records whether the previous session ended cleanly and drives the Manual-to-Auto recovery.
- **Application preferences**: Refresh, menu bar, launch, reconnect, and validated profile settings retained between launches.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can launch the application and identify the hottest valid sensor and the cooler's state within 10 seconds, without installing anything else.
- **SC-002**: New valid temperature samples appear within one configured refresh interval plus 0.5 seconds in at least 99% of deterministic refresh cycles.
- **SC-003**: Invalid, missing, or expired readings are excluded from every aggregate and visibly marked within one refresh cycle in 100% of deterministic test cases.
- **SC-004**: In 100% of simulated stale-sensor and critical cases a write-ready cooler is set to its verified maximum, and in 100% of simulated unclean exits a Manual profile starts as Auto.
- **SC-005**: In 100% of simulated threshold crossings the cooler target equals the specified ramp value after step rounding and clamping.
- **SC-006**: External cooler commands either receive a matching valid acknowledgement or stop after three total attempts within 5 seconds, without sending destructive or undocumented commands.
- **SC-007**: Users can configure a connected write-ready cooler in no more than four direct interactions, with slider and numeric values always agreeing.
- **SC-008**: All normal automated tests run without a physical cooler and pass on the supported development environment.
- **SC-009**: The application starts and remains navigable with no external cooler and no recognized temperature keys.
- **SC-010**: A signed distribution build can be prepared from documented steps without changing application source code.

## Assumptions

- The first release is an English-only, directly distributed universal desktop utility. Intel Macs read every `T…` SMC key; Apple Silicon Macs read chip-specific SMC keys merged with HID die sensors. Mac App Store distribution is outside MVP scope.
- One active desktop user controls the application at a time; no cloud account, telemetry upload, or remote control is required.
- Temperatures from -20 °C through 125 °C are treated as physically plausible, while freshness expires after the greater of three refresh intervals or 6 seconds.
- Automatic control uses the CPU average by default, falling back to the hottest valid sensor when no CPU reading exists.
- The single linear ramp defined by FR-017 through FR-019 is sufficient; a multi-point curve editor is outside MVP scope. Interpolation uses normalized progress clamped to 0...1 and rounds to the device's supported step before final capability clamping.
- External zero-speed or power-off behavior remains unavailable until verified on physical BS3 Pro hardware; the lowest supported safe speed is used instead.
- Physical validation, production signing identity, and final hardware-specific speed limits depend on the target Mac and cooler; absence of verified limits keeps only real external speed writes disabled and does not reduce monitoring, discovery, or mock-mode coverage.

## Scope Boundaries and Dependencies

- AppleSMC monitoring depends on the Mac exposing compatible system-management data; the product never needs write access to it.
- The external cooler must be paired or connected so the operating system exposes its supported device interface.
- Control of the Mac's own cooling, RGB control, firmware maintenance, firmware updates, arbitrary hardware commands, history charts beyond the in-memory recent chart, and remote access are excluded from this release.
- Hardware commands lacking corroborated protocol evidence are represented only in deterministic simulation and capability-disabled production paths.
