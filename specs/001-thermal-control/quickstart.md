# Quickstart Validation Guide

Normal automated tests require no physical hardware. The app needs nothing installed besides itself: sensor reads need no elevated rights and the cooler is a plain HID device.

## Prerequisites

- macOS 14 or later.
- Xcode with the macOS SDK and command-line tools selected.
- Intel or Apple Silicon hardware for physical AppleSMC monitoring; both read temperatures, through different key sets.
- Any Mac for the native UI, mock mode, persistence, policy tests, and Flydigi discovery.
- Developer ID credentials only for signing and notarization.

## Build the universal application

```sh
xcodebuild -project ColdDown.xcodeproj \
  -scheme ColdDownApp \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath /private/tmp/ColdDownDerived \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO \
  build
```

Expected: the app contains native `arm64` and `x86_64` slices and targets macOS 14. Signing-disabled builds behave exactly like signed ones; no capability depends on the signature.

## Prove the Intel slice explicitly

```sh
xcodebuild -quiet -project ColdDown.xcodeproj \
  -scheme ColdDownApp -configuration Debug \
  -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath /private/tmp/ColdDownIntelApp \
  ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO build
```

## Run deterministic tests

On an Apple Silicon development Mac, run the native test slice:

```sh
swift test

xcodebuild -quiet -project ColdDown.xcodeproj \
  -scheme ColdDownApp -testPlan ColdDown \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/ColdDownTests \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:ColdDownTests test
```

The deterministic suite covers SMC decoding, invalid/stale filtering, sensor aggregates, policy ramps, Critical precedence, stale-source fallback, capability gating, Flydigi packet fixtures and ACK retries, cooler clamping, session-marker recovery, persistence validation, and disconnected-cooler presentation. `swift test` runs the package targets; `SessionMarkerTests` and `FanConfigurationViewModelTests` need the app module and run only in the Xcode-hosted suite.

## Run mock mode

Launch the app with:

```sh
open -n '/path/to/Cold Down.app' --args \
  --mock --cooler-disconnected
```

Other deterministic fixtures are `--no-sensors` and `--capability-limited-cooler`. Mock mode keeps its profiles in memory, so every launch starts from the same state. Validate all four tabs, menu-bar state, synchronized slider/numeric fields, disabled unavailable controls, sensor aggregates, the retained disconnected cooler, and the crash-recovery notice (force quit with a Manual profile, then relaunch).

## Read-only degradation

Run without `--mock` and with no BS3 Pro.

- The app and every tab remain usable and the overall mode reads "Read only".
- On Intel Macs, every discovered `T…` AppleSMC sensor appears.
- On Apple Silicon, the chip-specific SMC keys and HID die sensors appear; unknown chips fall back to common keys without a crash.
- Missing keys never create fabricated or reused values.
- The cooler's card remains visible as disconnected and its controls explain why they are unavailable.

## UI acceptance tests

The mock-backed UI target is run with:

```sh
xcodebuild -quiet -project ColdDown.xcodeproj \
  -scheme ColdDownApp -testPlan ColdDown \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/ColdDownUITests \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:ColdDownUITests test
```

The local macOS account must grant Xcode's UI-test runner Automation/Accessibility permission. A timeout while enabling automation is an environment permission blocker, not a test assertion failure.

## Archive and structural validation

```sh
ARCHIVE_PATH=/private/tmp/ColdDown-Unsigned.xcarchive \
  Scripts/archive-release.sh

Scripts/validate-distribution.sh \
  /private/tmp/ColdDown-Unsigned.xcarchive
```

The validator checks macOS 14 metadata, both architecture slices, the resolved bundle identifier, the entitlements (App Sandbox disabled and nothing else), and ad-hoc signability on a temporary copy. It does not claim Developer ID or notarization success. `Scripts/build-local-dmg.sh <archive> <dmg>` produces an ad-hoc DMG for personal use without an Apple account.

For a credentialed archive:

```sh
SIGNING_MODE=developer-id \
DEVELOPER_ID_APPLICATION='Developer ID Application: Example (TEAMID)' \
DEVELOPMENT_TEAM=TEAMID \
THERMAL_APP_BUNDLE_ID=com.example.ColdDown \
ARCHIVE_PATH=/private/tmp/ColdDown-Signed.xcarchive \
  Scripts/archive-release.sh

NOTARY_PROFILE=cold-down-notary \
  Scripts/validate-distribution.sh \
  /private/tmp/ColdDown-Signed.xcarchive
```

Install the resulting app in `/Applications` and, if wanted, enable launch at login from Settings. Nothing else needs registering or approving.

## Physical hardware validation

On any Mac, validate AppleSMC discovery and missing-key behavior; there are no writes to validate.

For BS3 Pro, first verify VID `0x37D7`, PID `0x1004`, usage page `0xFFA0`, usage `0x00FF`, attach/detach, and read-only queries. Then verify that a saved Manual target is acknowledged, that the `0xEF` status pushes update the measured RPM, that pressing a physical gear button ends realtime control and the app re-enters it, and that quitting sends `0x24` and the cooler returns to its own gear within 3 seconds. Do not enable real target writes outside the audited 1,000–4,000 RPM range until a wider range is device-reported or physically validated. Commands `0x05` and `0x06` must never appear in output reports.
