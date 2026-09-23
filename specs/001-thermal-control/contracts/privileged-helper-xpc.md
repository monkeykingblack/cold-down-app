# Privileged Helper XPC Contract

## Service boundary

Mach service: resolved from the checked-in `THERMAL_HELPER_MACH_SERVICE` build setting and substituted consistently into the app, helper, launch-daemon plist, entitlements, and XPC client. App/helper bundle identifiers use the same configuration source, so development and distribution identifiers require no source edits.

The interface is Objective-C compatible and supports secure-coding/property-list-safe value objects only. It does not accept SMC key names, raw bytes, file paths, selectors, or generic dictionaries of commands.

## Operations

### `listFans(reply:)`

Returns independently discovered helper records containing fan index, name, current RPM, positive minimum RPM, maximum RPM, optional target RPM, and automatic/forced mode when readable.

### `setFanAuto(fanID:reply:)`

- Rediscover and validate the fan index.
- Restore the selected fan's mode to macOS Auto.
- Report success only after the write returns successfully.

### `setFanTargetRPM(fanID:rpm:reply:)`

- Require an active unexpired lease owned by the calling connection.
- Rediscover count and bounds.
- Reject unknown index, changed fan count/identity, missing or stale bounds, non-positive minimum, maximum below minimum, non-positive/unsupported step, or inconsistent telemetry.
- Clamp to positive hardware minimum...maximum; never encode zero.
- Apply the target and forced mode at the narrow Intel SMC layer.
- Return the actual clamped target.

### `restoreAllFansToAuto(reply:)`

- Does not require an active lease.
- Independently enumerates all current built-in fans.
- Attempts every restore even if an earlier restore fails.
- Returns aggregate success and non-private failure codes.

### `renewLease(reply:)`

- Require the accepted controlling connection.
- Extend expiry to eight seconds from the helper's monotonic clock.
- Return the expiry representation needed for diagnostics.

## Connection policy

- Only one controlling connection owns a lease at a time.
- Before activating its Mach-service listener in Release, the helper sets the expected app signing requirement.
- Development may omit the production identifier/team requirement, but registration remains code-signed as required by `SMAppService` and all command validation remains identical.
- A newly accepted controller begins with restore-all; it cannot inherit manual state.
- Interruption, invalidation, or replacement of the controlling connection triggers restore-all.

## Mandatory restoration triggers

- Client disconnect or application exit.
- Lease deadline reached without successful renewal.
- Invalid fan count, index, range, mode, or write result.
- Computer will sleep, did wake, or helper receives a termination signal.
- Explicit restore request from stale/missing selected Auto sensor, total Manual-mode sensor loss, or Critical policy.

The helper logs trigger category, fan index where relevant, and result code. It does not log usernames, device serial numbers, raw sensor history, or arbitrary client data.

## Launch daemon packaging

- Daemon plist path: app bundle `Contents/Library/LaunchDaemons/<service>.plist`.
- Executable path: app-bundle-relative `BundleProgram` entry, typically under `Contents/Library/HelperTools/`.
- `MachServices` contains exactly the service name.
- `AssociatedBundleIdentifiers` identifies the containing app for System Settings presentation.
- Registration uses `SMAppService.daemon(plistName:)`; status maps to not registered, enabled, requires approval, or not found.
- Monitoring never depends on successful registration or approval.
