# Cold Down audit report

Date: 2026-09-22
Scope: every source file in `Sources/` (helper daemon, XPC contract and client, SMC read and write paths, coordinator and policy, Flydigi HID, the C HID bridge, the SwiftUI app and its view models), the release scripts, and the tests.
Method: I read all of the code by hand and ran `swift test` once. Nothing was run on real Intel SMC or BS3 Pro hardware. Findings that depend on real hardware are marked **likely**.

## Summary

| Area | High | Medium | Low |
|---|---:|---:|---:|
| Privileged helper / XPC / SMC | 3 | 4 | 4 |
| UI (SwiftUI app) | 2 | 6 | 7 |

- **Tests:** `swift test` passes 41 of 41. A clean `swift build --build-tests` shows 0 warnings, including none from Swift 6 concurrency checks.
- **Coverage:** the helper code has no tests.
- **Fix first:** B1 (who can connect to the helper), B2 (the restore-to-Auto safety path), U1 (fan settings screen never updates) and U2 (every slider tick writes to hardware).

---

## Part 1 — Backend: privileged helper, XPC and hardware

### High

#### B1. Any Developer ID app can drive the root helper
`Sources/ColdDownHelper/main.swift:11-13`

The helper only accepts clients that match this requirement:

```
identifier "<app id>" and anchor apple generic
```

That checks the app's identifier but not which developer signed it. Any Developer ID team can sign its own app as `com.example.ColdDown` (or whatever the final ID is), connect, and set fan targets. The helper also lets any accepted connection take the lease, so such an app can take control away from the real one.

In `DEBUG` builds there is no check at all (`#if !DEBUG`). Any local process can talk to a Debug helper that has been registered.

**Fix:** pin the team, e.g. `anchor apple generic and identifier "<id>" and certificate leaf[subject.OU] = "<TEAMID>"`. Feed the team ID in from a build setting. Keep a check in Debug too, using a development-certificate requirement instead of none.

#### B2. The restore-to-Auto safety path can silently do nothing
`Sources/ColdDownHelper/Service/HelperSMCFanController.swift:42-43`

`restoreAll()` first calls `validatedFans()`. That call requires every fan to have a well-formed ID and a valid min/max RPM, with min > 0. If any fan read fails, or the fan count changes, `restoreAll()` returns `false` without clearing any "forced" bit. Fans that are in manual control stay pinned at their last target, which could be the minimum.

The lease watchdog makes this worse (`PrivilegedFanHelperService.swift:32-36`). When the lease expires, it tries to restore once, clears the lease, and `return`s. There is no retry, even if the restore failed.

**Fix:** restore without any validation. Clear the mode mask (`FS! = 0`, or `F*Md = 0` on T2 Macs) directly. Retry with backoff until a read-back confirms Auto mode.

#### B3. Likely broken on T2 Intel Macs (2018–2020)
`Sources/IntelSMC/Codec/SMCValueCodec.swift:32-40`, `Sources/ColdDownHelper/Service/HelperSMCWriteConnection.swift:39-54`

On T2 models, the fan keys `F*Ac`, `F*Mn`, `F*Mx` and `F*Tg` use the 4-byte `flt` type, and manual mode is set per fan through `F*Md` instead of `FS! `. The current code doesn't handle either:

- `decodeRPM` has no `flt` case. Min and max come back as `nil`, so `validatedFans()` throws and the helper's `listFans` fails.
- `setTarget` only encodes `fpe2`, so the size check throws. `setForced` reads `FS! `, which doesn't exist on these models.
- Result: no built-in fan telemetry or control on most recent Intel Macs. Each failure also triggers the helper's fail-safe and a reconnect (see B5).

**Fix:** support `flt` for reads and writes, and pick the mode key by probing (`F0Md` vs `FS! `). This needs testing on a T2 Mac.

### Medium

#### B4. Sleep/wake restore never runs
`Sources/ColdDownHelper/Service/HelperLifecycleMonitor.swift:11-16`

`NSWorkspace` sleep and wake notifications are not delivered to a root launch daemon, which has no GUI session. The monitor is also created lazily, only on the first XPC connection.

**Fix:** use `IORegisterForSystemPower` (and `IOAllowPowerChange`), and create the monitor at startup.

#### B5. Manual control can keep resetting to Auto on reconnect
`Sources/ColdDownApp/Services/PrivilegedHelperClient.swift:117`, `PrivilegedFanHelperService.swift:23-26`, `102-106`

- `markUnavailable()` sets `connection = nil` without calling `invalidate()`, so old connections are leaked.
- Each new connection creates a helper session that runs `restoreAll()` at startup. The replaced session also runs `restoreAll()` when it disconnects.
- Any helper-side error runs `invalidState()`, which clears the lease. The next renewal fails and the client reconnects.
- Net effect: after any error, manual and hot-band targets keep snapping back to Auto, and connections pile up.

**Fix:** invalidate before reconnecting. Let a session take the lease again instead of only reconnecting. Don't restore at session startup when the same client reconnects.

#### B6. Single-owner handling in the listener is loose
`Sources/ColdDownHelper/Service/HelperXPCListener.swift:7-14`

- Any accepted connection takes over from the current owner.
- The old connection is not invalidated, so it can still call `setFanAuto` and `restoreAllFansToAuto`.
- `activeService` is changed without synchronisation on the XPC queue (the class is marked `@unchecked Sendable`).

#### B7. Flydigi input grows without limit, and replies can be mismatched
`Sources/FlydigiHID/Transport/FlydigiHIDTransport.swift:107`, `FlydigiTransactionExecutor.swift:53`

- Input reports are appended to `buffer` whenever no request is waiting, and the buffer is never trimmed.
- The buffer isn't cleared before a send. A late reply to an earlier attempt that timed out can be accepted as the reply to the current one.

**Fix:** drain the buffer before each send, cap its size, and match replies by sequence number or payload where the protocol allows.

### Low

- **B8.** Fan speed only ratchets up in the hot band: the target is `max(currentSpeed, interpolated)` (`CoolingPolicy.swift:100`), so it never comes down until the temperature leaves the band.
- **B9.** The shutdown restore is fire-and-forget: `AppModel.stop()` starts a Task and the app exits right away (`AppModel.swift:91`). It is called twice, from `ColdDownApp.swift:13-15` and `RootView.swift:57`. It depends on the helper's disconnect path, which depends on B2.
- **B10.** Busy-wait lock in the Flydigi executor: `while busy { sleep 5ms }` (`FlydigiTransactionExecutor.swift:27`).
- **B11.** Placeholder settings: identifiers are `com.example.*` and `DEVELOPMENT_TEAM` is empty in both xcconfigs.

---

## Part 2 — UI (SwiftUI app)

### High

#### U1. The fan settings screen never updates after it opens
`Sources/ColdDownApp/Views/FanConfigurationView.swift:6-10`, `FansView.swift:42-43`, `Models/FanConfigurationViewModel.swift:6`

`FanConfigurationViewModel` is a `@StateObject` created once per fan ID (`.id(fan.id)`), and `fan` is a `let` copy of the snapshot. After the screen appears, the following never change:

- "Current speed", "Connection" and the status message
- `controlsEnabled`
- the slider range and step

In practice:

- After installing or approving the helper, the controls stay disabled until the user picks another fan.
- If the device disconnects, the controls stay enabled.
- The RPM shown is out of date.

**Fix:** read the live `FanDeviceState` from `appModel.snapshot` on each render. Keep only the editable draft values (mode, sensor, threshold, target) in the view model.

#### U2. Every slider tick saves, refreshes the hardware, and writes to the fan
`FanConfigurationView.swift:70`, `88`, `AppModel.swift:116-118`, `CoolingCoordinator.swift:118-126`

`.onChange(of: model.manualTarget)` and `.onChange(of: model.threshold)` call `persist()` for every intermediate slider value. Each call starts an unstructured `Task` that:

1. writes UserDefaults
2. runs a full `refreshNow()`: sensor sweep, XPC `listFans`, policy evaluation, then an SMC or HID write

One drag therefore sends dozens of hardware writes. These refreshes also interleave with the periodic refresh on the actor, so a decision computed from an older profile can be applied after a newer one.

**Fix:** commit on `Slider(onEditingChanged:)` when the drag ends, and on TextField submit. Or debounce (≈300 ms) and coalesce updates in the coordinator. Guard `refreshNow()` against running twice at once, e.g. with a single in-flight refresh.

### Medium

#### U3. "Open Cold Down" likely fails once the window is closed
`AppModel.swift:126-130`, `RootView.swift:51-55`

After Cmd-W, SwiftUI normally releases a `WindowGroup` window. `openMainWindow()` searches `NSApp.windows` for the title "Cold Down" and finds nothing, so it only switches the Dock icon back without showing a window. Matching windows by their title is also brittle.

**Fix:** give the WindowGroup an `id` and use `@Environment(\.openWindow)` (macOS 13+). Or keep the window alive with `NSWindow.isReleasedWhenClosed = false` and an app-delegate-managed controller. Check the Cmd-W → menu bar → Open flow by hand. The existing UI tests don't cover it.

#### U4. Two helper status indicators can disagree
`RootView.swift:19-67`, `SettingsView.swift:45-101`

- The sidebar shows `snapshot.helperStatus`, which reflects whether the lease is working.
- Settings shows `helperRegistration.status`, which reflects `SMAppService` registration.
- They can show "Read-only mode" and "Available" at the same time.
- When registration is `.enabled` but the XPC connection fails (B1, B5), Settings shows "Available" and hides the action button, leaving the user no way to recover.

**Fix:** derive one status from both, e.g. "Installed, not responding", with a reinstall option.

#### U5. The "Launch at login" toggle can show the wrong state
`Services/LaunchAtLoginService.swift:8-13`, `SettingsView.swift:13-18`

- `setEnabled` swallows errors (`catch { }`).
- The preference is saved as the requested value whether or not registration worked.
- The toggle reads `preferences.launchAtLogin` rather than `SMAppService.mainApp.status`, so it drifts if the user changes login items in System Settings.

**Fix:** bind the toggle to the real status and show any error.

#### U6. The Safety section promises more than the code delivers
`SettingsView.swift:66-71`

It shows "Always enabled" and "Mandatory after disconnect, expiry, sleep, wake, stale sensors, invalid state, or application exit". Sleep and wake are not handled (B4), and the restore can silently fail (B2). A safety claim in the UI should match what the code actually guarantees. Fix B2 and B4, or soften the text.

#### U7. Unlabelled controls for VoiceOver
`SettingsView.swift:27`, `80`

`Toggle("", …)` and `Picker("", …)` rely on a separate `LabeledContent` label. VoiceOver usually announces them as an unnamed switch or pop-up.

**Fix:** use `Toggle(title, isOn:).labelsHidden()` and `Picker(title, …).labelsHidden()`. Related: `.controlSize(.small)` on the whole window (`RootView.swift:38`, forms) shrinks click targets. The sliders also lack an `accessibilityValue` with units.

#### U8. The whole UI re-renders every second
`AppModel.swift:82-99`

- A 1 s poll reassigns `snapshot` whether or not it changed, which re-renders every view.
- It also calls `helperRegistration.refresh()` each time, and each refresh is an `SMAppService.status` IPC call.
- The UI can lag a refresh by up to 1 s. With a 30 s refresh interval it still wakes every second.

**Fix:** have the coordinator push snapshots through an `AsyncStream`, only publish when the value changes, and refresh helper status on activation or change only.

### Low

- **U9.** A missing value renders as "Unavailable RPM" in the menu bar (`PresentationModels.swift:35`). The external cooler's speed has no unit (`:39`).
- **U10.** The Fans empty state always says "Built-in Apple Silicon fans are not exposed through the Intel SMC interface" (`FansView.swift:70`). Intel users see it too when SMC reads fail (e.g. B3).
- **U11.** The sensor picker can show a blank selection when the saved physical sensor is missing from the current readings (`FanConfigurationView.swift:45-54`). The refresh interval picker has the same problem when the stored value isn't in `[1,2,5,10,15,30]` (`SettingsView.swift:27-31`), because the load step clamps to 1–30 rather than to that list.
- **U12.** When the selected fan disappears, `FansView.selectedFan` falls back to `fans.first` (`FansView.swift:62-64`). The detail pane then shows a fan the list doesn't highlight.
- **U13.** Selection state is duplicated. `RootView` and `FansView` each mirror model state in `@State` and keep it in sync with two `onChange` handlers. It works but is fragile; bind to the model directly.
- **U14.** Formatting is hard-coded: `String(format: "%.1f °C")` everywhere, with no locale-aware `MeasurementFormatter` and no °F option. `Localizable.xcstrings` exists, but interpolated strings like "\(kind) · Connected" are hard to localise.
- **U15.** `MenuBarViewModel` is never used (`Models/MenuBarViewModel.swift`).

---

## Part 3 — Tests and documentation

- **The helper has no tests.** `PrivilegedFanHelperService`, `HelperSMCFanController`, `HelperSMCWriteConnection` and the listener aren't package targets and have no tests. B2, B5 and B6 would all be caught by a small fake-SMC test of the service.
- **`HelperXPCSecurityTests` checks nothing about security.** It only asserts that the interface builds and that the service name equals the `com.example` placeholder.
- **The lease test is loose.** In `PrivilegedHelperSafetyTests`, `catch { }` accepts any error, not specifically a wrong-owner rejection.
- **Some tests only run in Xcode.** `FanConfigurationViewModelTests.swift` is excluded from `swift test` (`Package.swift`) and runs only in the Xcode-hosted suite.
- **The UI tests use mock data only.** They cover startup and control presentation. They don't cover the U1 live-update issue or the U3 reopen flow.
- **The docs overstate one guarantee.** `IMPLEMENTATION_REPORT.md` claims "signed-client validation", which B1 shows is weaker than stated.

## Suggested order of work

1. B1 (pin the team ID) and B2 (restore without validation, and retry): small changes that close the security hole and the main safety gap.
2. U1 and U2: make the fan screen live and debounce commits.
3. B5 and B6: connection and lease lifecycle, plus helper service tests with a fake SMC.
4. B4 (power notifications) and U6 (make the UI claim match).
5. B3: T2 support, verified on hardware.
6. The remaining medium and low items.

---

## Resolution status (2026-09-22)

All findings above have been addressed in code. Verification:

- `swift test`: **61 passed, 0 failed**. A clean build shows 0 warnings.
- Xcode Debug app build succeeded. Hosted `ColdDownTests`: **58 passed**. `ColdDownUITests`: **4 passed**.
- Xcode Release build of the helper succeeded.

| ID | Fix |
|---|---|
| B1 | `HelperClientRequirement` pins `certificate leaf[subject.OU]` to `DEVELOPMENT_TEAM` (added to the helper Info.plist). A Release build without a valid team refuses all connections. Debug falls back to an identifier-only requirement instead of none. |
| B2 | `restoreAll()` no longer validates fans. It clears `FS! ` or each `F*Md` directly and verifies by read-back. The watchdog keeps retrying until restoration succeeds. The helper also restores Auto at daemon start. |
| B3 | `flt` (little-endian) decode and encode for fan keys and temperatures. Target encoding follows the key's reported type and size. The mode key is chosen by probing (`FS! ` vs `F*Md`). **Needs validation on T2 hardware.** |
| B4 | `IORegisterForSystemPower` replaces NSWorkspace. Sleep is acknowledged only after the restore runs. The monitor is created at startup. |
| B5 | The client invalidates dropped connections and ignores late callbacks from old ones. Helper-returned errors no longer drop the connection. After a fail-safe clear, the session re-acquires the lease on renewal. **New:** each XPC call now resumes its continuation on transport error or after a 5 s timeout. Previously a lost connection could hang a refresh forever. |
| B6 | Accepting a new connection invalidates the previous one. A replaced session only restores Auto if it still owned the lease. Listener state is lock-protected. |
| B7 | Pending reports are drained before each send, and the buffer is capped at 32. A device is registered only after `IOHIDDeviceOpen` succeeds. |
| B8 | The current speed only acts as a floor while macOS Auto is in control (`reportedMode != .manual`). The reader now derives the mode from `FS! ` when present. |
| B9 | `applicationShouldTerminate` returns `.terminateLater` until the shutdown restore finishes (3 s cap). The duplicate termination handlers are gone. |
| B10 | FIFO continuation queue replaces the 5 ms spin. |
| B11 | `archive-release.sh` rejects `com.example.*` IDs and invalid team IDs in Developer ID mode. `validate-distribution.sh` checks that the helper's embedded team pin matches the app's signing team. Real identifiers remain the owner's choice. |
| U1 | The fan settings view model refreshes `fan` from every snapshot (`updateFan`), re-clamping the target if limits change. |
| U2 | Slider and field input is committed when a drag ends, on submit, or after 400 ms idle. The coordinator merges overlapping `refreshNow()` calls into one follow-up pass. |
| U3 | A single `Window` scene with an ID is opened via `openWindow(id:)`. The Dock icon now follows the window's lifetime rather than a title match. |
| U4 | One `HelperDisplayStatus` feeds both the sidebar and Settings. It adds "Installed, not responding" with a Reinstall action (unregister, then register). |
| U5 | The toggle is bound to `SMAppService.mainApp.status`. Errors and pending approval are shown. The preference is kept in sync. |
| U6 | The Safety text now matches the guarantees above. |
| U7 | Toggles and pickers have real labels, sliders have accessibility values, and decorative images are hidden. The window-wide `.controlSize(.small)` is removed. |
| U8 | The coordinator pushes snapshots through `snapshotUpdates()`, which replaces the 1 s poll. SMAppService is queried on activation and when the helper status changes. |
| U9–U15 | Units in the menu bar. Architecture-specific empty-state text. Pickers always include the current value. The model keeps the fan selection valid. Selection is bound directly to the model. `DisplayFormat` does locale-aware formatting. `MenuBarViewModel` is deleted. |
| Tests | New `ColdDownHelperCore` package target plus `ColdDownHelperTests`, using a fake SMC writer and covering B2, B5 and B6. Also new tests for the requirement builder, T2 codec, hot-band policy, Flydigi drain and serialisation, coordinator merging and the snapshot stream, and the view model's live updates. |

**Still needs real hardware:** T2 `flt`/`F*Md` behaviour (B3), sleep/wake acknowledgement timing (B4), the reopen flow after Cmd-W (U3), and the `launchctl plist` output format used by `validate-distribution.sh` on a Developer ID archive.
