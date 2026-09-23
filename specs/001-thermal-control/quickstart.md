# Quickstart Validation Guide

Normal automated tests require neither physical hardware nor an installed helper.

## Prerequisites

- macOS 13 or later.
- Xcode with the macOS SDK and command-line tools selected.
- Intel hardware for physical AppleSMC monitoring and built-in fan write validation.
- Apple Silicon or Intel hardware for the native UI, mock mode, persistence, policy tests, and Flydigi discovery.
- Developer ID credentials only for production helper installation, signing, and notarization.

## Build the universal application

```sh
xcodebuild -project ThermalControl.xcodeproj \
  -scheme ThermalControlApp \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath /private/tmp/ThermalControlDerived \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO \
  build
```

Expected: both the app and embedded helper contain native `arm64` and `x86_64` slices and target macOS 13. Signing-disabled builds stay read-only for built-in fan control.

## Prove the Intel slices explicitly

```sh
xcodebuild -quiet -project ThermalControl.xcodeproj \
  -scheme ThermalControlApp -configuration Debug \
  -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath /private/tmp/ThermalControlIntelApp \
  ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO build

xcodebuild -quiet -project ThermalControl.xcodeproj \
  -scheme ThermalControlHelper -configuration Debug \
  -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath /private/tmp/ThermalControlIntelHelper \
  ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO build
```

## Run deterministic tests

On an Apple Silicon development Mac, run the native test slice:

```sh
xcodebuild -quiet -project ThermalControl.xcodeproj \
  -scheme ThermalControlApp -testPlan ThermalControl \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/ThermalControlTests \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:ThermalControlTests test
```

The deterministic suite covers SMC decoding, invalid/stale filtering, sensor aggregates, policy ramps, external-first ordering, capability gating, Flydigi packet fixtures and ACK retries, fan clamping, helper leases/disconnects, persistence validation, and disconnected-cooler presentation. `swift test` provides a second package-level gate for the shared modules.

## Run mock mode

Launch the app with:

```sh
open -n '/path/to/Cold Down.app' --args \
  --mock --helper-unavailable --cooler-disconnected
```

Other deterministic fixtures are `--no-sensors` and `--capability-limited-cooler`. Validate all four sidebar destinations, menu-bar state, synchronized slider/numeric fields, disabled unavailable controls, sensor aggregates, and retained disconnected devices.

## Read-only degradation

Run without `--mock`, with no registered helper and no BS3 Pro.

- The app and every destination remain usable.
- On compatible Intel Macs, discovered AppleSMC sensors and built-in fan telemetry appear.
- On Apple Silicon, Intel AppleSMC sensors/fans remain unavailable without a crash; Flydigi discovery and the rest of the app continue to work.
- Missing keys never create fabricated or reused values.
- Built-in write controls explain that control is unavailable.
- BS3 Pro remains visible as disconnected.

## UI acceptance tests

The mock-backed UI target is run with:

```sh
xcodebuild -quiet -project ThermalControl.xcodeproj \
  -scheme ThermalControlApp -testPlan ThermalControl \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/ThermalControlUITests \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:ThermalControlUITests test
```

The local macOS account must grant Xcode's UI-test runner Automation/Accessibility permission. A timeout while enabling automation is an environment permission blocker, not a test assertion failure.

## Archive and structural validation

```sh
ARCHIVE_PATH=/private/tmp/ColdDown-Unsigned.xcarchive \
  Scripts/archive-release.sh

Scripts/validate-distribution.sh \
  /private/tmp/ColdDown-Unsigned.xcarchive
```

The validator checks macOS 13 metadata, both architecture slices, helper and launch-daemon placement, resolved identifiers/Mach service, and helper-first/app-last ad-hoc signability on a temporary copy. It does not claim Developer ID or notarization success.

For a credentialed archive:

```sh
SIGNING_MODE=developer-id \
DEVELOPER_ID_APPLICATION='Developer ID Application: Example (TEAMID)' \
DEVELOPMENT_TEAM=TEAMID \
ARCHIVE_PATH=/private/tmp/ColdDown-Signed.xcarchive \
  Scripts/archive-release.sh

NOTARY_PROFILE=thermal-control-notary \
  Scripts/validate-distribution.sh \
  /private/tmp/ColdDown-Signed.xcarchive
```

Install the resulting app in `/Applications`, request daemon registration from Settings, approve it in System Settings if required, and verify helper state. Production validation must also prove mismatched-client rejection and Auto restoration on lease expiry, termination, sleep, and wake.

## Physical hardware validation

On Intel hardware, validate AppleSMC discovery, missing-key behavior, fan limits, and actual Auto/target writes only after production signing and helper approval.

For BS3 Pro, first verify VID `0x37D7`, PID `0x1004`, usage page `0xFFA0`, usage `0x00FF`, attach/detach, and read-only queries. Do not enable real target writes until a safe range is device-reported or an audited firmware-specific range has been physically validated. Commands `0x05` and `0x06` must never appear in output reports.
