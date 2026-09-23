# Cold Down

Cold Down is a native SwiftUI macOS utility for thermal monitoring and safe cooling control. It is a universal `arm64`/`x86_64` app for macOS 13 or later, reads temperatures and fans through AppleSMC on both Intel and Apple Silicon Macs, and can control a Flydigi BS-series cooler over HID.

The app is useful without its privileged helper: temperatures and fan speeds are read without root, and only built-in fan *writes* live in a narrowly scoped launch daemon.

Platform handling follows [Stats](https://github.com/exelban/stats) (chip-specific SMC keys, `FS! `/`F%dMd` fan modes, the `Ftst` unlock on Apple Silicon). The Flydigi protocol follows [THRM](https://github.com/TIANLI0/THRM).

## Interface

- **Fixed window** (560 × 460, not resizable) with a tab bar in the title bar: **Overview · Fans · Sensors · Settings** (⌘1–⌘4 in the View menu).
- **Overview**: hottest temperature with gauge, CPU/GPU/average, a five-minute chart, one card per fan, and one row per sensor group.
- **Fans**: one full-width card per fan. Status row (speed ring, name, live RPM, chart, Auto/Manual) with that mode's controls inline. Auto has the temperature source and boost threshold; Manual has the target slider with Min/Quiet/Balanced/Max presets. Both modes are the same height.
- **Sensors**: summary cards plus one collapsible card per group (count, average, max), each holding a grid of sensor tiles. Collapsed groups are remembered.
- **Menu-bar popover**: hottest temperature, CPU/GPU, chart, and a row per fan with a mode switch; Open Cold Down (⌘O), Settings (⌘,) and Quit (⌘Q).
- **Notices**: problems (critical temperature, safety fallback, helper needs approval, recovery after a crash) appear as a coloured icon in the title bar and popover. Clicking it shows the message, an action, and Dismiss where dismissing is allowed. Nothing in the layout shifts.
- **Icons**: static Dock icon; the menu-bar fan is tinted by temperature, or monochrome (**Settings › General › Menu bar icon**). Regenerate the app icon with `swift Scripts/generate-app-icon.swift`; `Design/AppIcon/fan-layer-1024.png` is the transparent fan layer for building a layered (Liquid Glass) icon in Icon Composer.

Closing the main window keeps Cold Down monitoring from the menu bar and removes its Dock icon.

## Architecture

- `ColdDownApp`: SwiftUI window, menu-bar extra, view models, helper/login registration, deterministic mock launch modes.
- `ThermalCore`: `CoolingCoordinator` actor, models, aggregation, cooling policy, persistence, clocks, logging, hardware protocols.
- `IntelSMC`: unprivileged AppleSMC discovery, chip detection, typed decoding, sensor catalogue, built-in fan telemetry.
- `FlydigiHID`: IOHID discovery, packet codec, serialized transactions, realtime-mode control of BS-series coolers.
- `ColdDownShared`: the narrow Objective-C-compatible XPC contract, secure records, and the client code-signing requirement.
- `ColdDownHelper` / `ColdDownHelperCore`: launch daemon with the only AppleSMC write implementation, request validation, lease watchdog, power-event and failure restoration. The `Core` package target exists so this logic can be tested without hardware.
- `ColdDownTests`, `ColdDownHelperTests`, `ColdDownUITests`: hardware-independent tests (fake SMC key store, scripted HID transport) and mock UI journeys.

The coordinator owns readings, profiles, persistence, stale-data handling, and side-effect ordering. Overlapping refreshes collapse into one follow-up pass. Hardware access sits behind `SensorProvider`, `BuiltInFanReader`, `BuiltInFanController`, `ExternalCoolerController`, `PrivilegedFanHelperClient`, and `ProfileStore`.

## Platform behaviour

| Capability | Intel Mac | Apple Silicon |
|---|---|---|
| App, menu bar, mock mode, tests | Yes | Yes |
| SMC temperature sensors | Every `T…` key the SMC reports | Chip-specific keys (M1–M5 table from Stats) merged with HID die sensors; unknown chips use common keys + HID |
| Built-in fan telemetry | `F%dAc/Mn/Mx/Tg`, mode from `FS! ` | Same keys (`flt`), mode from `F0md`/`F%dMd` (0 or 3 = Auto, 1 = forced) |
| Built-in fan writes | After signed helper approval | After signed helper approval; Stats-style `Ftst` unlock, **not yet verified on hardware by this project** |
| Flydigi BS2/BS2 Pro/BS3/BS3 Pro | Yes (USB or Bluetooth HID) | Yes |

Apple Silicon is detected at runtime (`hw.optional.arm64` / `sysctl.proc_translated`), so the Intel slice under Rosetta is handled correctly; the chip generation comes from `machdep.cpu.brand_string`. Unknown future chips fall back to generic keys instead of failing. Fan names use the SMC's own `F%dID` label when present ("Left fan"), else "Mac fan N". A fan whose limits cannot be read stays visible as read-only without blocking the others.

**Apple Silicon takeover** (`SMCFanWriter`): a direct forced-mode write is tried first (M5 and later); if the firmware rejects it, `Ftst` is set to 1 and the forced-mode write is retried every 100 ms until `thermalmonitord` yields (about 33 s budget). The little-endian `F%dTg` target follows. Restoring Auto clears forced fans (modes 0 and 3 are left alone), zeroes their target, and, unlike Stats, resets `Ftst` to 0; the result is verified by read-back and retried by the lease watchdog. A restoration cancels an in-flight unlock, so it can never re-force a fan afterwards. Taking control can take a few seconds, which the UI shows as "Taking control…".

No sensor value is fabricated when a service or key is missing. An unavailable helper always leaves built-in fans under macOS Auto control.

## Safety model

- **Helper restores Auto** on disconnect, lease expiry (8 s lease, renewed every 2 s), invalid state, termination, sleep, wake, and at its own startup. Restoration never depends on fan limits being readable.
- **Crash recovery**: a session marker records unclean exits. After a crash, force quit or power loss, every Manual profile starts as Auto (manual targets are kept) and the app explains why in a dismissible notice.
- **Quitting** waits (up to 3 s) for fans to return to macOS Auto, and hands the Flydigi cooler back to its own gear.
- **Debounce**: profile edits show immediately but reach hardware only after ~0.5 s of quiet, and only the final state, so quick Auto ↔ Manual flips never start a takeover.
- **Never stops a built-in fan**: targets are clamped to the fan's reported range; zero targets are rejected.

## Build

Open `ColdDown.xcodeproj`, or:

```sh
xcodebuild -project ColdDown.xcodeproj -scheme ColdDownApp \
  -configuration Debug -destination 'generic/platform=macOS' \
  -derivedDataPath /private/tmp/ColdDownDerived \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO build
```

Tests:

```sh
swift test                                    # package targets (94 tests)
xcodebuild -project ColdDown.xcodeproj -scheme ColdDownApp -testPlan ColdDown \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -only-testing:ColdDownTests -only-testing:ColdDownUITests test   # 86 tests
```

`SessionMarkerTests`, `HelperAutoRegistrationTests`, and `FanConfigurationViewModelTests` need the app module, so they run only in the Xcode suite. UI tests need the local account to allow Xcode's test runner Automation/Accessibility access.

See [quickstart.md](specs/001-thermal-control/quickstart.md) for Intel-slice, archive, and physical-hardware checks, and [AUDIT_REPORT.md](AUDIT_REPORT.md) for the 2026-09-22 security/UI audit and how each finding was resolved.

## Mock mode

```sh
open -n '/Applications/Cold Down.app' --args --mock
```

Fixtures: `--helper-unavailable`, `--cooler-disconnected`, `--no-sensors`, `--capability-limited-cooler`, `--two-fans` (preview the dual-fan layout). Mock mode keeps its profiles in memory, so every launch starts from the same state.

## Local DMG (no Apple account)

```sh
Scripts/archive-release.sh                         # unsigned universal archive
Scripts/validate-distribution.sh <archive>         # layout, plists, architectures, ad-hoc signability
Scripts/build-local-dmg.sh <archive> build/ColdDown-Local.dmg
```

Ad-hoc DMGs are not Developer ID signed or notarized: Gatekeeper may warn, and **built-in fan control does not work**, because the helper refuses connections that are not signed by the expected team. The UI, mock mode, sensors, fan telemetry, and Flydigi control do not need an Apple account.

## Signing

Local development signing (a free Apple ID works) is enough to run the helper on your own Mac; Developer ID plus notarization is required to distribute.

```sh
cp Configuration/LocalSigning.xcconfig.example Configuration/LocalSigning.xcconfig
```

Set `DEVELOPMENT_TEAM` and unique reverse-DNS identifiers (`THERMAL_APP_BUNDLE_ID`, `THERMAL_HELPER_BUNDLE_ID`, `THERMAL_HELPER_MACH_SERVICE`); the file is ignored by source control. Build the signed app with `-allowProvisioningUpdates`, put it in `/Applications`, and launch it: Cold Down registers the helper on first launch, then macOS asks you to approve it in **System Settings › General › Login Items**. Settings also offers Install / Approve / Reinstall.

For a Developer ID archive:

```sh
SIGNING_MODE=developer-id \
DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)' \
DEVELOPMENT_TEAM=TEAMID \
THERMAL_APP_BUNDLE_ID=com.yourcompany.ColdDown \
THERMAL_HELPER_BUNDLE_ID=com.yourcompany.ColdDown.Helper \
THERMAL_HELPER_MACH_SERVICE=com.yourcompany.ColdDown.Helper \
ARCHIVE_PATH=/private/tmp/ColdDown-Signed.xcarchive Scripts/archive-release.sh

NOTARY_PROFILE=cold-down-notary Scripts/validate-distribution.sh /private/tmp/ColdDown-Signed.xcarchive
```

`archive-release.sh` refuses Developer ID archives that still use `com.example.*` identifiers or lack a valid team, and `validate-distribution.sh` checks that the helper's embedded team pin matches the app's signing team.

## Entitlements and helper security

Both targets disable App Sandbox (direct IOKit AppleSMC/HID access plus a privileged helper are incompatible with it). Release builds use Hardened Runtime.

The XPC surface accepts only: list fans, set a fan to Auto, set a validated target RPM, restore all fans to Auto, renew the lease. No SMC keys, raw payloads, or arbitrary writes. Only one client session exists at a time; a new connection invalidates the previous one.

Release connections must be Apple-anchored **and** carry the expected app identifier and team (`certificate leaf[subject.OU]`, from `DEVELOPMENT_TEAM`). A Release helper built without a valid team refuses every connection. Debug builds pin the team when configured and otherwise fall back to an identifier-only check; all other rules stay active.

## Flydigi BS-series

Matched by vendor `0x37D7` and product `0x1001`–`0x1004` (BS2, BS2 Pro, BS3, BS3 Pro), on the HID collection that accepts the 25-byte output report (ID `0x02`, 24 data bytes). Replies arrive on input report ID `0x01`; the device also pushes `0xEF` status frames, which supply the live measured RPM and mode.

Control follows THRM: realtime mode (`0x23`) is entered once and re-entered only when the device reports it left; targets (`0x21`, 1,000–4,000 RPM) are skipped when they change by less than 50 RPM; quitting sends `0x24` so the cooler returns to its own gear. Acknowledgement status bytes are checked and rejections are not retried.

Not exposed: maintenance commands `0x03`/`0x05`/`0x06` (init, clear latch, factory reset), flash-writing gear/RGB commands, firmware update, raw payloads, and zero-RPM stop.

## Reference repositories and licences

- [Stats](https://github.com/exelban/stats) — MIT.
- [THRM](https://github.com/TIANLI0/THRM) — MIT.
- [Flydigi-BS](https://github.com/chenqianhe/Flydigi-BS) — PolyForm Noncommercial. No PolyForm source was copied.

Protocols, safety model, and architecture were reimplemented here.

## Known hardware-dependent limitations

- Intel AppleSMC fan writes need a compatible Intel Mac; Apple Silicon writes follow Stats' community-tested sequence but have not been exercised on hardware by this project.
- New SoCs need their sensor keys added to `AppleSiliconSMCSensorKeys` as Apple renames them.
- Helper installation, signed-client rejection, and sleep/wake restoration need a signed build on real hardware.
- Flydigi limits, acknowledgement behaviour, and firmware identity still need validation against a physical BS3 Pro.
