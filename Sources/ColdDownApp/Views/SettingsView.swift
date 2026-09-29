import SwiftUI
import ThermalCore
import FlydigiHID

/// Settings in the same card style as the other pages: one card per section, one row per setting
/// (title and description on the left, control on the right).
struct SettingsView: View {
    private static let refreshIntervals = [1, 2, 5, 10, 15, 30]

    @Environment(AppModel.self) private var model
    @AppStorage(Dashboard.smoothAnimationsKey) private var smoothAnimations = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Dashboard.spacing) {
                section("General", systemImage: "gearshape") {
                    row("Launch at login", "Open Cold Down automatically after you sign in.") {
                        Toggle("Launch at login", isOn: Binding(
                            get: { model.launchAtLogin.enabled },
                            set: { value in model.setLaunchAtLogin(value) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    if model.launchAtLogin.requiresApproval {
                        note("Approve Cold Down in System Settings › General › Login Items.")
                    }
                    if let message = model.launchAtLogin.errorMessage { note(message, isError: true) }
                    Divider()
                    row("Temperature in menu bar", "Show the hottest temperature next to the fan icon.") {
                        Toggle("Temperature in menu bar", isOn: Binding(
                            get: { model.preferences.showTemperatureInMenuBar },
                            set: { value in model.updatePreferences { $0.showTemperatureInMenuBar = value } }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    Divider()
                    row("Menu bar icon", "Colorful follows the temperature; monochrome matches other menu bar icons.") {
                        PillSegmentedControl(
                            label: "Menu bar icon",
                            options: [.init(value: true, title: "Colorful"), .init(value: false, title: "Monochrome")],
                            selection: Binding(get: { model.colorfulMenuBarIcon }, set: { model.colorfulMenuBarIcon = $0 }),
                            size: .small,
                            identifier: "thermal.settings.menubaricon"
                        )
                    }
                    Divider()
                    row("Refresh interval", "5 seconds keeps the app close to idle. Lower it to see the numbers move sooner; every reading redraws on each refresh.") {
                        Picker("Refresh interval", selection: Binding(
                            get: { Int(model.preferences.refreshInterval) },
                            set: { value in model.updatePreferences { $0.refreshInterval = TimeInterval(value) } }
                        )) {
                            ForEach(refreshIntervalOptions, id: \.self) { Text("\($0) s").tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Divider()
                    row(
                        "Smooth value animations",
                        "Sweep the gauge and roll the digits as readings change. Off keeps the app near idle: "
                        + "every reading changes each refresh, so animating them all keeps the window drawing."
                    ) {
                        Toggle("Smooth value animations", isOn: $smoothAnimations)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    Divider()
                    row("Reconnect Flydigi automatically", "Resume control when the BS3 Pro is attached again.") {
                        Toggle("Reconnect Flydigi automatically", isOn: Binding(
                            get: { model.preferences.automaticFlydigiReconnect },
                            set: { value in model.updatePreferences { $0.automaticFlydigiReconnect = value } }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }

                if model.supportsFlydigiSettings {
                    section("Flydigi BS3 Pro", systemImage: "snowflake") {
                        row("Gear speeds", "The cooler's own gears, used when Cold Down is not controlling it.") {
                            Text(gearSpeedsText)
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                        row("Fan acceleration", "How quickly the cooler changes speed. Stored in the cooler.") {
                            Menu(model.flydigiAcceleration?.title ?? "Not set") {
                                ForEach(FlydigiAcceleration.allCases, id: \.self) { level in
                                    Button(level.title) { model.setFlydigiAcceleration(level) }
                                }
                            }
                            .fixedSize()
                            .controlSize(.small)
                            .disabled(!model.flydigiConnected)
                        }
                        Divider()
                        row("When the Mac sleeps", "What the cooler does while the Mac is asleep. Stored in the cooler.") {
                            Menu(model.flydigiSleepBehavior?.title ?? "Not set") {
                                ForEach(FlydigiSleepBehavior.allCases, id: \.self) { behavior in
                                    Button(behavior.title) { model.setFlydigiSleepBehavior(behavior) }
                                }
                            }
                            .fixedSize()
                            .controlSize(.small)
                            .disabled(!model.flydigiConnected)
                        }
                        if !model.flydigiConnected { note("Connect the cooler to change these settings.") }
                        if let message = model.flydigiSettingError { note(message, isError: true) }
                    }
                    .task(id: model.flydigiConnected) { await model.refreshFlydigiGearSpeeds() }
                }

                section("Safety", systemImage: "checkmark.shield") {
                    row(
                        "Thermal safety",
                        "The cooler runs at full speed when the controlling temperature is unavailable or any sensor reaches 95 °C, and returns to its own gear when you quit."
                    ) {
                        Pill(text: "Always on", tint: .green).fixedSize()
                    }
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Building blocks

    private func section<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle(title: title, systemImage: systemImage)
                .padding(.leading, 4)
            DashboardCard {
                VStack(alignment: .leading, spacing: 10) { content() }
            }
        }
    }

    private func row<Control: View>(_ title: String, _ description: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            control()
        }
    }

    private func note(_ text: String, isError: Bool = false) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(isError ? Color.red : Color.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Always includes the stored value so the picker never shows an empty selection.
    private var refreshIntervalOptions: [Int] {
        let current = Int(model.preferences.refreshInterval)
        return Self.refreshIntervals.contains(current) ? Self.refreshIntervals : (Self.refreshIntervals + [current]).sorted()
    }

    private var gearSpeedsText: String {
        guard model.flydigiConnected else { return "—" }
        guard let speeds = model.flydigiGearSpeeds else { return "Reading…" }
        return speeds.map { $0.formatted() }.joined(separator: " · ") + " RPM"
    }
}
