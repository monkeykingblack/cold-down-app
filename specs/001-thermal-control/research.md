# Research: Cold Down

## Reference licensing and reuse boundary

**Decision**: Reimplement required behavior and protocols. Use the three repositories only as technical evidence, and preserve attribution in project documentation.

**Rationale**: `chenqianhe/Flydigi-BS` uses PolyForm Noncommercial 1.0.0, which is unsuitable as a source-code dependency for unrestricted direct distribution. `TIANLI0/THRM` and `exelban/stats` use MIT. Independent implementation avoids mixing license obligations and lets the project apply stricter safety boundaries.

**Alternatives considered**: Copy Flydigi-BS implementation (rejected because of its noncommercial license); vendor the Stats SMC source (rejected because a smaller Intel-only implementation is easier to audit); depend on command-line utilities (rejected because monitoring must be self-contained).

## AppleSMC transport and sensor discovery

**Decision**: Implement an Intel AppleSMC user-client wrapper using `IOServiceMatching("AppleSMC")`, key-info reads, indexed enumeration via `#KEY`, and typed decoding. Reads remain unprivileged. Probe available keys at startup and periodically reconcile disappeared keys. Compile the containing application universally; when `AppleSMC` is absent on Apple Silicon, publish an empty unavailable result rather than failing startup.

**Rationale**: Stats demonstrates that Intel machines expose different SMC key sets and that values require type-aware decoding. Runtime enumeration satisfies the requirement not to assume a fixed model table. Pure codec functions allow deterministic fixtures for signed fixed-point formats (`sp78` and related variants), unsigned integers, `fpe2`, and floats.

**Alternatives considered**: A fixed catalog only (misses model-specific keys); privileged reads (unnecessary); process execution of third-party tools (fragile and not native).

## Sensor classification and freshness

**Decision**: Use a compact curated map for known Intel temperature keys and deterministic prefix/name heuristics for unknown temperature keys, always retaining the raw key and classifying uncertain keys as Other. Assign a monotonic refresh generation before each asynchronous poll and discard late older generations. Within an accepted generation, ignore and diagnose samples older than the last committed timestamp; equal timestamp/value is idempotent, while equal timestamp/different value is rejected. A newer invalid or missing sample becomes invalid or unavailable rather than retaining an older value. A reading is stale after `max(3 × refresh interval, 6 seconds)`. Values must be finite and within -20...125 °C.

**Rationale**: A known-name map improves display quality, while preserving unknown valid keys prevents incomplete monitoring. Generation and timestamp rules prevent asynchronous completion from regressing value or freshness. The freshness rule tolerates a single delayed sample at the default interval.

**Alternatives considered**: Hide unknown keys (contradicts complete sensor display); infer aggressive semantic labels from prefixes alone (risks mislabeling); accept arrival order (can regress state); retain old values silently (unsafe).

## Built-in fan discovery and write boundary

**Decision**: Read fan count and status from the supported `FNum`, `F{n}Ac`, `F{n}Mn`, `F{n}Mx`, `F{n}Tg`, `F{n}Md`, and `FS! ` concepts when present. Missing bounds, built-in minimum at or below zero, maximum below minimum, non-positive/unsupported step, stale capability data, or inconsistent count/identity disable writes. Equal positive bounds represent a fixed valid capability. Keep all write encoding inside the helper. The helper independently repeats discovery and validation for every request and accepts only list, Auto, target RPM, restore-all, and lease-renew operations.

**Rationale**: Stats corroborates these Intel fan concepts. The helper can independently rediscover count and bounds before every write, clamp positive targets, and prevent the GUI from sending raw keys or payloads.

**Alternatives considered**: Raw SMC read/write XPC (unacceptably broad); cached fan limits supplied by the app (untrusted and potentially stale); running the entire app as root (excess privilege).

## Helper installation, packaging, and signing

**Decision**: Use `SMAppService.daemon(plistName:)` on macOS 13+. Place the daemon plist in `Contents/Library/LaunchDaemons`, refer to the embedded executable with `BundleProgram`, advertise one Mach service, and recommend installing the containing app in `/Applications`.

**Rationale**: The macOS 26.2 SDK states that `SMAppService` manages helpers inside the app bundle, launch daemons require administrator approval, apps using the API must be signed, daemon-containing apps must be notarized, and boot availability is best when the app is in `/Applications`.

**Alternatives considered**: Deprecated `SMJobBless` (superseded on macOS 13); manual copying into `/Library/PrivilegedHelperTools` (more installation surface and not the requested API); an XPC service inside the user session (insufficient privilege).

## XPC connection security

**Decision**: Use an Objective-C-compatible `NSXPCInterface` with value objects restricted to secure-coding/property-list-compatible types. For release, set the listener's connection code-signing requirement before activation and reject unexpected peers. Use interruption and invalidation handlers to trigger immediate Auto restoration.

**Rationale**: The current Foundation SDK provides `setConnectionCodeSigningRequirement(_:)` for Mach-service listeners on macOS 13+. The connection also exposes process and effective-user identifiers for audit logging, but identity authorization is based on code signing rather than PID or UID alone.

**Alternatives considered**: PID/UID-only validation (insufficient identity proof); accepting any local client (violates the spec); a broad dictionary command API (harder to secure and test).

## Helper lease and lifecycle safety

**Decision**: Use an 8-second lease renewed every 2 seconds while any built-in fan is influenced. Start and end every client session with restore-all. Restore on lease expiry, disconnect, invalid request/state, application termination signal, sleep, wake, and before accepting a new controlling client.

**Rationale**: The lease survives missed individual heartbeats but bounds unsafe fixed-control duration. Sleep/wake restoration avoids assuming retained SMC mode state. The helper, not the GUI, owns the deadline.

**Alternatives considered**: No lease (manual mode could persist after a crash); a refresh-length lease (too sensitive to scheduling jitter); a long lease (slower recovery).

## Flydigi identity and report framing

**Decision**: Match BS3 Pro by vendor ID `0x37D7` and product ID `0x1004`. Use product string and vendor usage page `0xFFA0` / usage `0x00FF` only as corroborating capability information. Encode a 25-byte HID output report: report ID `0x02`, `0x5A 0xA5`, command, length equal to payload count + 2, payload, additive low-byte checksum over command/length/payload, and zero padding.

**Rationale**: Flydigi-BS and THRM agree on vendor identity and the `5A A5` framing. THRM explicitly maps BS3 Pro to product `0x1004`; Flydigi-BS targets a neighboring BS3 product and provides useful macOS HID behavior, so PID selection follows the user's specified BS3 Pro and THRM's device matrix.

**Alternatives considered**: Product-string-only matching (can collide or localize); usage-only matching (could match another vendor interface); accepting multiple BS models in MVP (unrequested scope).

## Flydigi safe command subset

**Decision**: Permit only query RPM `0x22`, query work mode `0x25`, enter real-time RPM mode `0x23`, and set real-time RPM `0x21`. Treat acknowledgement status `0x01` as success and, for `0x23`, status `0x03` as already active. Hard-reject `0x05`, `0x06`, arbitrary commands, RGB, firmware, and raw report entry points.

**Rationale**: THRM's firmware analysis names `0x05` as clearing an initialization latch and `0x06` as factory reinitialization; `0x06` resets multiple runtime settings. This outweighs Flydigi-BS's conflicting power labels. Query and real-time RPM commands are corroborated by both sources and cover the MVP.

**Alternatives considered**: Use `0x05`/`0x06` for power (unsafe); send zero RPM as stop (not physically verified); use gear-setting commands (unnecessary for the requested real-time speed MVP).

## Acknowledgement, retry, and reconnect behavior

**Decision**: Serialize the full command/ACK transaction in an actor. Register the expected command before writing, accept only matching valid-checksum frames, use a 900 ms attempt timeout, and make at most three total attempts. Detach cancels the active transaction. Attach performs read-only capability/state queries before enabling controls.

**Rationale**: THRM uses a command-correlated response broker and a 900 ms response timeout. Register-before-write avoids losing fast acknowledgements, while the bounded attempt count satisfies the specification's five-second ceiling.

**Alternatives considered**: Fixed post-write sleeps (race-prone); concurrent writes (responses can be misattributed); unlimited reconnect/retry loops (command storms and poor failure visibility).

## Cooling policy details

**Decision**: Validate Auto thresholds as integral 45...85 °C values with a 72 °C default. Evaluate every active Auto profile into `(band rank, normalized progress, fan ID)` and use the lexicographic maximum as the non-critical system demand, with fan ID only as a deterministic tie-breaker. Before profile evaluation, scan every fresh valid physical and calculated reading; any value at or above 95 °C produces global Critical. Precedence is Critical, SafetyFallback, Hot, Warm, then Cool.

For selected temperature `T`, threshold `θ`, and verified device range `[minimum, maximum]`, Warm external progress is `clamp((T - θ) / 10, 0...1)`. Interpolate minimum-to-maximum, round to the supported positive step, then clamp. During Hot, hold the external cooler at verified maximum. For each eligible built-in Auto profile, use `hotStart = θ + 10` and `clamp((T - hotStart) / (95 - hotStart), 0...1)` to interpolate hardware minimum-to-maximum, round and clamp, then apply `max(currentRPM, interpolated)` so the application never intentionally reduces current cooling. A threshold of 85 °C has no non-critical Hot interval and therefore never evaluates a zero denominator.

When a verified controllable BS3 Pro is connected and write-ready, its maximum request must receive a matching acknowledgement before associated automatic built-in increases. When it is disconnected or capability-limited, treat it as unavailable without claiming cooling is active; eligible Hot built-in policy may proceed without an external acknowledgement. If a required maximum request fails, do not send the associated automatic built-in increase in that evaluation cycle. Critical requests verified external maximum when available, restores built-in Auto, and emits no built-in target. A stale or missing selected Auto source enters SafetyFallback: discard the stale value, request verified external maximum only from a write-ready cooler, emit no external write otherwise, and restore all built-in fans to Auto.

During Cool, use a physically verified stop command only when the capability explicitly advertises one. Otherwise request the lowest verified safe speed from a write-ready cooler. A capability-limited or disconnected cooler receives no mutating report in any Cool branch.

**Rationale**: One maximum demand prevents conflicting cooler commands while per-fan built-in targets still follow their own profiles. Explicit equations, tie-breaking, precedence, and the 85 °C guard make boundary fixtures reproducible and preserve external-first ordering without suppressing macOS safety.

**Alternatives considered**: Independent cooler commands per profile (conflicting output); hottest raw temperature for every non-critical decision (ignores profile intent); simultaneous external/internal ramping (violates ordering); discrete speed bands (not the specified linear ramp); safe-high built-in target during Critical (rejected by clarification).

## BS3 speed capability evidence

**Decision**: Represent a speed range with minimum, maximum, positive step, unit, and verification provenance: unverified, device-verified, audited-model, or deterministic-mock. Real `0x21` reports are permitted only for device-verified or audited-model capabilities. Deterministic-mock provenance is accepted only by the mock transport. Unverified or malformed ranges expose read-only state and a capability-limited write reason; clamping an inferred value never authorizes transmission. Audited ranges are keyed by VID, PID, and firmware/capability identity and cite a physical-validation record.

**Rationale**: Separating range values from the evidence authorizing their use prevents a guessed or user-entered limit from becoming a hardware command. Read-only queries still provide useful connection and operating state while validation is pending.

**Alternatives considered**: Immediately enable constants found in reference repositories (insufficient device-specific validation); let users enter a range (unsafe trust boundary); infer authorization from any numeric response (conflates parsing with verification).

## Deterministic acceptance measurements

**Decision**: Use the injected monotonic clock for repeatable acceptance measurements. SC-001 starts at coordinator launch and requires a snapshot exposing the hottest valid sensor plus all known fans by 10 seconds. SC-002 runs at least 100 scripted refresh cycles and requires at least 99% of valid batches to reach the published snapshot within configured interval +0.5 seconds. SC-007 counts direct user actions from selecting a fan through committing mode and target and requires no more than four while asserting slider/numeric agreement after each edit.

**Rationale**: Explicit start/end events, cycle count, and interaction definition turn outcome statements into stable automated assertions without depending on wall-clock scheduling or physical hardware.

**Alternatives considered**: Manual observation only (not repeatable); real-time sleeps (slow and flaky); a blanket test-run task without dedicated assertions (does not demonstrate the criteria).

## Distribution validation without credentials

**Decision**: Always create a universal `arm64`/`x86_64` Release archive with signing disabled and verify bundle structure, both app/helper slices, embedded helper placement, launch-daemon plist, entitlements, build settings, and documented inside-out signing commands. When Developer ID credentials are present, sign, verify with strict `codesign`, notarize, staple, and assess with Gatekeeper. When unavailable, record signing/notarization as a blocker and do not claim SC-010 fully exercised; no source change may be required between unsigned structural validation and credentialed distribution.

**Rationale**: Structural archive validation catches packaging defects in every environment while preserving an honest boundary around identity- and service-dependent evidence.

**Alternatives considered**: Skip release packaging until credentials exist (late integration risk); ad-hoc-sign and call distribution validated (does not prove Developer ID behavior); require credentials for normal tests (breaks hardware-independent development).

## Persistence and startup reapplication

**Decision**: Store a schema-versioned `Codable` preferences envelope in `UserDefaults`. Load into intent only. Start by restoring built-in Auto, collect fresh sensors and current capabilities, confirm helper health, validate every profile, and only then reapply eligible control.

**Rationale**: This preserves preferences without treating a crash-persisted manual choice as trusted active state. Validation handles changed fan counts, ranges, missing sensors, and future schema evolution.

**Alternatives considered**: Restore writes immediately at launch (unsafe); discard all profiles after every crash (poor usability); Core Data (unnecessary scale and complexity).

## UI composition

**Decision**: Translate the supplied HTML mockup into native SwiftUI using `NavigationSplitView`, compact control sizes, system typography/materials, a dense `Table` for sensors, a list/detail Fans page, block-spaced settings rows, and `MenuBarExtra`. Use AppKit only for window activation and lifecycle notifications that lack a suitable SwiftUI surface. The mockup is a visual hierarchy reference, not a behavioral contract: its 45...95 °C threshold control is replaced by the clarified 45...85 °C range and 72 °C default.

**Rationale**: This preserves the reference hierarchy without embedding web content or imitating its CSS. Native controls provide keyboard, VoiceOver, focus, appearance, and system-state behavior.

**Alternatives considered**: Web view or Catalyst (explicitly prohibited); custom-drawn controls (unnecessary accessibility and maintenance risk); dashboard cards (conflicts with the requested compact utility style).
