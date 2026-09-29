# Research: Cold Down

## Reference licensing and reuse boundary

**Decision**: Reimplement required behavior and protocols. Use the three repositories only as technical evidence, and preserve attribution in project documentation.

**Rationale**: `chenqianhe/Flydigi-BS` uses PolyForm Noncommercial 1.0.0, which is unsuitable as a source-code dependency for unrestricted direct distribution. `TIANLI0/THRM` and `exelban/stats` use MIT. Independent implementation avoids mixing license obligations and lets the project apply stricter safety boundaries.

**Alternatives considered**: Copy Flydigi-BS implementation (rejected because of its noncommercial license); vendor the Stats SMC source (rejected because a smaller read-only implementation is easier to audit); depend on command-line utilities (rejected because monitoring must be self-contained).

## AppleSMC transport and sensor discovery

**Decision**: Implement a read-only AppleSMC user-client wrapper using `IOServiceMatching("AppleSMC")`, key-info reads, indexed enumeration via `#KEY`, and typed decoding. Reads need no elevated rights and the wrapper exposes no write entry point. On Intel, probe every `T…` key at startup and periodically reconcile disappeared keys. On Apple Silicon, read the chip-specific key table (M1–M5, derived from Stats) and merge it with HID die sensors from the IOHID bridge; unknown chips use the common keys plus HID. `PlatformSensorProvider` picks the backend at runtime from `hw.optional.arm64` and `sysctl.proc_translated`, so the Intel slice under Rosetta is handled correctly. A missing service or key publishes an unavailable result rather than failing startup.

**Rationale**: Stats demonstrates that different machines expose different SMC key sets and that values require type-aware decoding. Runtime enumeration satisfies the requirement not to assume a fixed model table. Pure codec functions allow deterministic fixtures for signed fixed-point formats (`sp78` and related variants), unsigned integers, `fpe2`, and floats.

**Alternatives considered**: A fixed catalog only (misses model-specific keys); root-level reads (unnecessary); process execution of third-party tools (fragile and not native).

## Sensor classification and freshness

**Decision**: Use a compact curated map for known temperature keys and deterministic prefix/name heuristics for unknown temperature keys, always retaining the raw key and classifying uncertain keys as Other. Assign a monotonic refresh generation before each asynchronous poll and discard late older generations. Within an accepted generation, ignore and diagnose samples older than the last committed timestamp; equal timestamp/value is idempotent, while equal timestamp/different value is rejected. A newer invalid or missing sample becomes invalid or unavailable rather than retaining an older value. A reading is stale after `max(3 × refresh interval, 6 seconds)`. Values must be finite and within -20...125 °C.

**Rationale**: A known-name map improves display quality, while preserving unknown valid keys prevents incomplete monitoring. Generation and timestamp rules prevent asynchronous completion from regressing value or freshness. The freshness rule tolerates a single delayed sample at the default interval.

**Alternatives considered**: Hide unknown keys (contradicts complete sensor display); infer aggressive semantic labels from prefixes alone (risks mislabeling); accept arrival order (can regress state); retain old values silently (unsafe).

## Control surface

**Decision**: The Flydigi cooler is the only device the app drives. The Mac's own thermal management is left entirely to macOS; the app requests no elevated rights, registers no background service, and has no entitlement beyond disabled App Sandbox.

**Rationale**: Everything the product needs runs as the interactive user: AppleSMC temperature reads need no elevated rights and the cooler is a plain HID device. Keeping the app out of the Mac's own cooling removes the entire root-level attack surface and the fail-safe restoration machinery it would require.

**Alternatives considered**: A root-level component for writing to the Mac's own cooling (dropped as unnecessary scope and risk); running the entire app as root (excess privilege).

## Flydigi identity and report framing

**Decision**: Match BS-series devices by vendor ID `0x37D7` and product IDs `0x1001`–`0x1004` (BS2, BS2 Pro, BS3, BS3 Pro), on the HID collection that accepts the 25-byte output report. Use product string and vendor usage page `0xFFA0` / usage `0x00FF` only as corroborating capability information. Encode a 25-byte HID output report: report ID `0x02`, `0x5A 0xA5`, command, length equal to payload count + 2, payload, additive low-byte checksum over command/length/payload, and zero padding. Replies arrive on input report `0x01`; the device also pushes `0xEF` status frames carrying the measured RPM and mode.

**Rationale**: Flydigi-BS and THRM agree on vendor identity and the `5A A5` framing. THRM explicitly maps BS3 Pro to product `0x1004` and documents the `0xEF` status push; Flydigi-BS targets a neighboring BS3 product and provides useful macOS HID behavior.

**Alternatives considered**: Product-string-only matching (can collide or localize); usage-only matching (could match another vendor interface).

## Flydigi safe command subset

**Decision**: Permit only query RPM `0x22`, query work mode `0x25`, enter real-time RPM mode `0x23`, leave real-time mode `0x24`, and set real-time RPM `0x21`. Treat acknowledgement status `0x01` as success and, for `0x23`, status `0x03` as already active. Hard-reject `0x03`, `0x05`, `0x06`, arbitrary commands, RGB, flash-writing gear commands, firmware, and raw report entry points.

**Rationale**: THRM's firmware analysis names `0x05` as clearing an initialization latch and `0x06` as factory reinitialization; `0x06` resets multiple runtime settings. This outweighs Flydigi-BS's conflicting power labels. Query and real-time RPM commands are corroborated by both sources and cover the MVP; `0x24` is what lets the cooler return to its own gear when the app quits.

**Alternatives considered**: Use `0x05`/`0x06` for power (unsafe); send zero RPM as stop (not physically verified); close the handle on quit and leave the last realtime target running (what THRM does; rejected because the cooler would stay at a fixed speed).

## Acknowledgement, retry, and reconnect behavior

**Decision**: Serialize the full command/ACK transaction in an actor. Register the expected command before writing, accept only matching valid-checksum frames, use a 900 ms attempt timeout, and make at most three total attempts. Detach cancels the active transaction. Attach performs read-only capability/state queries before enabling controls. Enter realtime mode once and re-enter only after the device reports it left (a `0xEF` push with the mode bit clear, or a `0x21` answering "not realtime"); skip target writes that change by less than 50 RPM; take measured RPM from the `0xEF` pushes rather than assuming the target was reached.

**Rationale**: THRM uses a command-correlated response broker and a 900 ms response timeout. Register-before-write avoids losing fast acknowledgements, while the bounded attempt count satisfies the specification's five-second ceiling. Re-sending `0x23` on every tick interrupts the control session.

**Alternatives considered**: Fixed post-write sleeps (race-prone); concurrent writes (responses can be misattributed); unlimited reconnect/retry loops (command storms and poor failure visibility).

## Cooling policy details

**Decision**: Validate Auto thresholds as integral 45...85 °C values with a 65 °C default. Before the profile is consulted, scan every fresh valid physical and calculated reading; any value at or above 95 °C produces global Critical with the cooler at its verified maximum. Precedence is Critical, SafetyFallback, Hot, Warm, then Cool.

When the cooler is absent, disconnected, or capability-limited, the decision carries no external action and the overall mode is Read only. Otherwise the cooler's profile is evaluated; until one is saved, `FanProfile.suggested` follows the CPU average, or the hottest reading when no CPU sensor exists. A Manual profile holds its target clamped to the cooler's range.

For selected temperature `T`, threshold `θ`, and verified device range `[minimum, maximum]`, Warm progress is `clamp((T - θ) / 10, 0...1)`. Interpolate minimum-to-maximum, round to the supported positive step, then clamp. At or above `θ + 10` (Hot) the cooler holds its verified maximum; a threshold of 85 °C reaches Critical at its Hot boundary. During Cool, use a physically verified stop command only when the capability explicitly advertises one; otherwise request the lowest verified safe speed.

A stale or missing selected Auto source enters SafetyFallback: discard the stale value and request the verified maximum from the write-ready cooler. Failed cooler writes are logged and never reported as active cooling.

**Rationale**: Explicit equations, precedence, and the 85 °C guard make boundary fixtures reproducible. Running the cooler at maximum whenever visibility is lost is the conservative choice for a supplemental device that cannot harm the Mac.

**Alternatives considered**: Hottest raw temperature for every non-critical decision (ignores profile intent); discrete speed bands (not the specified linear ramp); idling the cooler on sensor loss (loses cooling exactly when the situation is unknown).

## BS3 speed capability evidence

**Decision**: Represent a speed range with minimum, maximum, positive step, unit, and verification provenance: unverified, device-verified, audited-model, or deterministic-mock. Real `0x21` reports are permitted only for device-verified or audited-model capabilities. Deterministic-mock provenance is accepted only by the mock transport. Unverified or malformed ranges expose read-only state and a capability-limited write reason; clamping an inferred value never authorizes transmission. The audited BS3 Pro range is 1,000–4,000 RPM in 50 RPM steps, taken from THRM's realtime control range and the top factory gear.

**Rationale**: Separating range values from the evidence authorizing their use prevents a guessed or user-entered limit from becoming a hardware command. Read-only queries still provide useful connection and operating state while validation is pending.

**Alternatives considered**: Immediately enable constants found in reference repositories without audit (insufficient device-specific validation); let users enter a range (unsafe trust boundary); infer authorization from any numeric response (conflates parsing with verification).

## Crash recovery and shutdown hand-back

**Decision**: Persist a session marker in `UserDefaults` that is set when a session begins and cleared only after a normal quit has released the cooler. On launch, if the marker is still set, switch every Manual profile to Auto (keeping the manual target) before any hardware is touched and show a dismissible notice. On quit, call `releaseControl()` so the cooler leaves realtime mode (`0x24`) and returns to its own gear, delaying termination by at most 3 seconds. Debounce profile edits for about 0.5 seconds so only the final state reaches hardware.

**Rationale**: A crash-persisted Manual choice is not trusted active state; reverting to Auto is safe and the user's target survives for re-enabling. The bounded delay keeps quit responsive when the device is unresponsive. Debouncing avoids a burst of HID writes while a slider is dragged.

**Alternatives considered**: Restore writes immediately at launch (unsafe); discard all profiles after every crash (poor usability); block quit indefinitely on the hand-back (hangs when the device is gone).

## Deterministic acceptance measurements

**Decision**: Use the injected monotonic clock for repeatable acceptance measurements. SC-001 starts at coordinator launch and requires a snapshot exposing the hottest valid sensor plus the cooler by 10 seconds. SC-002 runs at least 100 scripted refresh cycles and requires at least 99% of valid batches to reach the published snapshot within configured interval +0.5 seconds. SC-007 counts direct user actions from selecting the cooler through committing mode and target and requires no more than four while asserting slider/numeric agreement after each edit.

**Rationale**: Explicit start/end events, cycle count, and interaction definition turn outcome statements into stable automated assertions without depending on wall-clock scheduling or physical hardware.

**Alternatives considered**: Manual observation only (not repeatable); real-time sleeps (slow and flaky); a blanket test-run task without dedicated assertions (does not demonstrate the criteria).

## Distribution validation without credentials

**Decision**: Always create a universal `arm64`/`x86_64` Release archive with signing disabled and verify bundle structure, both slices, plists, entitlements (App Sandbox disabled and nothing else), build settings, and documented signing commands. When Developer ID credentials are present, sign, verify with strict `codesign`, notarize, staple, and assess with Gatekeeper. When unavailable, record signing/notarization as a blocker and do not claim SC-010 fully exercised; a local ad-hoc DMG remains available for personal use. No source change may be required between unsigned structural validation and credentialed distribution.

**Rationale**: Structural archive validation catches packaging defects in every environment while preserving an honest boundary around identity-dependent evidence.

**Alternatives considered**: Skip release packaging until credentials exist (late integration risk); ad-hoc-sign and call distribution validated (does not prove Developer ID behavior); require credentials for normal tests (breaks hardware-independent development).

## Persistence and startup reapplication

**Decision**: Store a schema-versioned `Codable` preferences envelope in `UserDefaults`. Load into intent only. Start by checking the session marker, collect fresh sensors and current cooler capabilities, validate the profile against them, and only then apply it.

**Rationale**: This preserves preferences without treating a crash-persisted manual choice as trusted active state. Validation handles changed capabilities, missing sensors, and future schema evolution.

**Alternatives considered**: Apply writes immediately at launch (unsafe); discard all profiles after every crash (poor usability); Core Data (unnecessary scale and complexity).

## UI composition

**Decision**: Translate the supplied HTML mockup into native SwiftUI using a fixed window with a title-bar tab bar, compact control sizes, system typography/materials, a dense sensor layout, a full-width cooler card on the Fans page, block-spaced settings rows, and `MenuBarExtra`. Use AppKit only for window activation and lifecycle notifications that lack a suitable SwiftUI surface. The mockup is a visual hierarchy reference, not a behavioral contract: its 45...95 °C threshold control is replaced by the clarified 45...85 °C range and 65 °C default.

**Rationale**: This preserves the reference hierarchy without embedding web content or imitating its CSS. Native controls provide keyboard, VoiceOver, focus, appearance, and system-state behavior.

**Alternatives considered**: Web view or Catalyst (explicitly prohibited); custom-drawn controls (unnecessary accessibility and maintenance risk); dashboard cards (conflicts with the requested compact utility style).
