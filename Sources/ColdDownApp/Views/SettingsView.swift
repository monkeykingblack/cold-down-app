import SwiftUI
import ThermalCore

/// Settings in the same card style as the other pages: one card per section, one row per setting
/// (title and description on the left, control on the right).
struct SettingsView: View {
    private static let refreshIntervals = [1, 2, 5, 10, 15, 30]

    @EnvironmentObject private var model: AppModel

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
                            selection: $model.colorfulMenuBarIcon,
                            size: .small,
                            identifier: "thermal.settings.menubaricon"
                        )
                    }
                    Divider()
                    row("Refresh interval", "2 seconds balances freshness and overhead.") {
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

                section("Fan control", systemImage: "fan") {
                    row("Built-in fan control", model.helperDisplayStatus.explanation) {
                        HStack(spacing: 8) {
                            Pill(text: model.helperDisplayStatus.settingsText, tint: model.helperDisplayStatus.tint)
                                .fixedSize()
                            if let action = helperAction {
                                Button(action.title) { perform(action) }
                                    .controlSize(.small)
                            }
                        }
                    }
                    if let message = model.helperRegistration.errorMessage { note(message, isError: true) }
                }

                section("Safety", systemImage: "checkmark.shield") {
                    row(
                        "Restore system Auto mode",
                        "Built-in fans return to macOS control when the app disconnects or stops responding, around sleep and wake, when a controlling temperature is unavailable, after a helper error, and when you quit."
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

    private enum HelperAction {
        case install, reinstall, approve
        var title: String {
            switch self {
            case .install: "Install…"
            case .reinstall: "Reinstall…"
            case .approve: "Approve…"
            }
        }
    }

    private var helperAction: HelperAction? {
        switch model.helperDisplayStatus {
        case .available: nil
        case .requiresApproval: .approve
        case .notResponding: .reinstall
        case .notInstalled, .unavailable: .install
        }
    }

    private func perform(_ action: HelperAction) {
        switch action {
        case .approve: model.helperRegistration.openApprovalSettings()
        case .install: Task { await model.helperRegistration.register() }
        case .reinstall: Task { await model.helperRegistration.reinstall() }
        }
    }
}
