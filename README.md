# Cold Down

Cold Down is a native SwiftUI macOS utility that reads temperatures through AppleSMC on both Intel and Apple Silicon Macs and drives a Flydigi BS-series cooler over HID from them. It is a universal `arm64`/`x86_64` app for macOS 14 or later.

Everything runs without root: sensor reads are unprivileged and the cooler is a plain HID device.

Sensor discovery follows [Stats](https://github.com/exelban/stats) (chip-specific SMC keys). The Flydigi protocol follows [THRM](https://github.com/TIANLI0/THRM).

## Interface

- **Fixed window** (560 × 460, not resizable) with a tab bar in the title bar: **Overview · Fans · Sensors · Settings** (⌘1–⌘4 in the View menu).
- **Overview**: hottest temperature with gauge, CPU/GPU/average, a recent-history chart (about twelve minutes at the default five-second refresh, and it says how long), the cooler's card, and a row per sensor group. The group rows take whatever height the cards above leave them and flow into a second or third column when that is not enough.
- **Fans**: the cooler as a full-width card. Status row (speed ring, name, live RPM, chart, Auto/Manual) with that mode's controls inline: Auto has the temperature source and boost threshold; Manual has the target slider with Min/Quiet/Balanced/Max presets. Both modes are the same height.
- **Sensors**: summary cards plus one collapsible card per group (count, average, max), each holding a grid of sensor tiles. Collapsed groups are remembered.
- **Menu-bar popover**: hottest temperature, CPU/GPU, chart, and the cooler's row with its mode switch; Open Cold Down (⌘O), Settings (⌘,) and Quit (⌘Q).
- **Notices**: problems (critical temperature, safety fallback, recovery after a crash) appear as a coloured icon in the title bar and popover. Clicking it shows the message, an action, and Dismiss where dismissing is allowed. Nothing in the layout shifts.
- **Smooth value animations** (**Settings › General**, off by default): rolls the digits, sweeps the gauge and eases the bars as readings change. Every reading changes on each refresh, so turning it on animates most of the window continuously; measured on an Intel Mac that is the difference between about 4% and 36% of a core on the Sensors tab.
- **Icons**: static Dock icon; the menu-bar fan is tinted by temperature, or monochrome (**Settings › General › Menu bar icon**). Regenerate the app icon with `swift Scripts/generate-app-icon.swift`; `Design/AppIcon/fan-layer-1024.png` is the transparent fan layer for building a layered (Liquid Glass) icon in Icon Composer.

Closing the main window keeps Cold Down monitoring from the menu bar and removes its Dock icon.

## Architecture

- `ColdDownApp`: SwiftUI window, menu-bar extra, view models, login-item registration, deterministic mock launch modes.
- `ThermalCore`: `CoolingCoordinator` actor, models, aggregation, cooling policy, persistence, clocks, logging, hardware protocols.
- `IntelSMC`: unprivileged AppleSMC discovery, chip detection, typed decoding, sensor catalogue.
- `FlydigiHID`: IOHID discovery, packet codec, serialized transactions, realtime-mode control of BS-series coolers.
- `ColdDownTests`, `ColdDownUITests`: hardware-independent tests (fake SMC key store, scripted HID transport) and mock UI journeys.

The coordinator owns readings, profiles, persistence, stale-data handling, and side-effect ordering. Overlapping refreshes collapse into one follow-up pass. Hardware access sits behind `SensorProvider`, `ExternalCoolerController`, and `ProfileStore`. Nothing in the app writes to AppleSMC.

## Platform behaviour

| Capability | Intel Mac | Apple Silicon |
|---|---|---|
| App, menu bar, mock mode, tests | Yes | Yes |
| SMC temperature sensors | Every `T…` key the SMC reports | Chip-specific keys (M1–M5 table from Stats) merged with HID die sensors; unknown chips use common keys + HID |
| Flydigi BS2/BS2 Pro/BS3/BS3 Pro | Yes (USB or Bluetooth HID) | Yes |

Apple Silicon is detected at runtime (`hw.optional.arm64` / `sysctl.proc_translated`), so the Intel slice under Rosetta is handled correctly; the chip generation comes from `machdep.cpu.brand_string`. Unknown future chips fall back to generic keys instead of failing.

No sensor value is fabricated when a service or key is missing.

## Safety model

- **Crash recovery**: a session marker records unclean exits. After a crash, force quit or power loss, a Manual profile starts as Auto (the manual target is kept) and the app explains why in a dismissible notice.
- **Quitting** waits (up to 3 s) to hand the Flydigi cooler back to its own gear.
- **Debounce**: profile edits show immediately but reach hardware only after ~0.5 s of quiet, and only the final state.
- **Cooling curve**: in Auto the cooler idles at its minimum below the threshold, ramps to maximum from the threshold to +10 °C, and holds maximum above that. Until a profile is saved it follows the CPU average (the hottest reading on Macs without CPU sensors) with the default threshold. When the controlling sensor is unavailable, or any fresh sensor reaches 95 °C, the cooler runs at full speed and a notice explains why. Manual holds its target but still yields to the 95 °C rule.

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
swift test                                    # package targets
xcodebuild -project ColdDown.xcodeproj -scheme ColdDownApp -testPlan ColdDown \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -only-testing:ColdDownTests -only-testing:ColdDownUITests test
```

`SessionMarkerTests` and `FanConfigurationViewModelTests` need the app module, so they run only in the Xcode suite. UI tests need the local account to allow Xcode's test runner Automation/Accessibility access.

See [quickstart.md](specs/001-thermal-control/quickstart.md) for Intel-slice, archive, and physical-hardware checks.

## Mock mode

```sh
open -n '/Applications/Cold Down.app' --args --mock
```

Fixtures: `--cooler-disconnected`, `--no-sensors`, `--capability-limited-cooler`. Mock mode keeps its profiles in memory, so every launch starts from the same state.

## Local DMG (no Apple account)

```sh
Scripts/archive-release.sh                         # unsigned universal archive
Scripts/validate-distribution.sh <archive>         # layout, plists, architectures, ad-hoc signability
Scripts/build-local-dmg.sh <archive> build/ColdDown-Local.dmg
```

Ad-hoc DMGs are not Developer ID signed or notarized, so Gatekeeper may warn. Everything else (the UI, mock mode, sensors, and Flydigi control) works without an Apple account.

## Uninstall

Run the script bundled with the app (administrator privileges are required to delete it from `/Applications`):

```sh
sh "/Applications/Cold Down.app/Contents/Resources/Scripts/uninstall.sh"
```

It quits the app first, so the cooler returns to its own gear, then deletes the app and removes its preferences. If the fan-control daemon from an earlier version is still registered, it is stopped too. The source is `Scripts/uninstall.sh`.

## Signing

Local development signing (a free Apple ID works) is enough to run on your own Mac; Developer ID plus notarization is required to distribute.

```sh
cp Configuration/LocalSigning.xcconfig.example Configuration/LocalSigning.xcconfig
```

Set `DEVELOPMENT_TEAM` and a unique reverse-DNS `THERMAL_APP_BUNDLE_ID`; the file is ignored by source control. Build the signed app with `-allowProvisioningUpdates` and put it in `/Applications`.

For a Developer ID archive:

```sh
SIGNING_MODE=developer-id \
DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)' \
DEVELOPMENT_TEAM=TEAMID \
THERMAL_APP_BUNDLE_ID=com.yourcompany.ColdDown \
ARCHIVE_PATH=/private/tmp/ColdDown-Signed.xcarchive Scripts/archive-release.sh

NOTARY_PROFILE=cold-down-notary Scripts/validate-distribution.sh /private/tmp/ColdDown-Signed.xcarchive
```

`archive-release.sh` refuses Developer ID archives that still use the `com.example.*` identifier or lack a valid team.

## Entitlements

The app disables App Sandbox (direct IOKit AppleSMC/HID access is incompatible with it). Release builds use Hardened Runtime.

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

- New SoCs need their sensor keys added to `AppleSiliconSMCSensorKeys` as Apple renames them.
- Flydigi limits, acknowledgement behaviour, and firmware identity still need validation against a physical BS3 Pro.
