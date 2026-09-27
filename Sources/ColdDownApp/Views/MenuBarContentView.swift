import SwiftUI
import ThermalCore

/// The menu-bar popover, styled as a compact version of the dashboard.
/// Rendered with `.menuBarExtraStyle(.window)` so it updates live while open.
struct MenuBarContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            fans
            footer
        }
        .padding(10)
        .frame(width: 280)
        .accessibilityIdentifier(AccessibilityID.menuBarPopover)
    }

    // MARK: Header

    private var hottest: Double? { model.snapshot.sensors.hottestReading?.valueCelsius }

    /// Two compact rows, no gauge: the number already says it all in this small space.
    /// A notice (if any) is a small icon beside the mode pill, so the popover never changes height.
    private var header: some View {
        DashboardCard(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Text(DisplayFormat.temperature(hottest, placeholder: "—"))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Dashboard.temperatureColor(hottest))
                        .lineLimit(1)
                        .fixedSize()
                        .numericTransition(value: hottest)
                        .accessibilityIdentifier(AccessibilityID.menuBarHottest)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Hottest").font(.caption.weight(.semibold))
                        Text(model.snapshot.sensors.hottestReading?.identity.name ?? "No valid temperature")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    if let banner = StatusBanner.current(for: model) {
                        NoticeToolbarButton(banner: banner) { showMainWindow(at: .settings) }
                            .buttonStyle(.plain)
                    }
                    Pill(text: Dashboard.shortModeName(model.snapshot.overallMode), tint: Dashboard.modeTint(model.snapshot.overallMode))
                        .fixedSize()
                        .help(model.snapshot.overallMode.rawValue)
                }
                HStack(alignment: .center, spacing: 14) {
                    StatChip(title: "CPU", celsius: model.snapshot.sensors.calculated[.cpuAverage])
                    StatChip(title: "GPU", celsius: model.snapshot.sensors.calculated[.gpuAverage])
                    Spacer(minLength: 8)
                    Sparkline(values: model.temperatureHistory, tint: Dashboard.temperatureColor(hottest), minimumSpan: 5)
                        .frame(width: 96, height: 26)
                }
            }
        }
    }

    // MARK: Fans

    @ViewBuilder
    private var fans: some View {
        if model.snapshot.fans.isEmpty {
            DashboardCard(padding: 10) {
                Label("No fans detected", systemImage: "fan.slash").font(.callout).foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 6) {
                ForEach(model.snapshot.fans) { fan in
                    MenuBarFanRow(fan: fan, history: model.fanSpeedHistory[fan.id] ?? [])
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            Button { showMainWindow(at: nil) } label: {
                Label("Open Cold Down", systemImage: "macwindow")
            }
            .keyboardShortcut("o")
            .accessibilityIdentifier(AccessibilityID.menuBarOpen)
            Spacer(minLength: 0)
            Button { showMainWindow(at: .settings) } label: {
                Image(systemName: "gearshape").accessibilityLabel("Settings")
            }
            .keyboardShortcut(",")
            Button { NSApp.terminate(nil) } label: {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q")
            .accessibilityIdentifier(AccessibilityID.menuBarQuit)
        }
        .buttonStyle(HoverHighlightButtonStyle())
        .labelStyle(.titleAndIcon)
    }

    /// Activating the app makes the popover resign key, which dismisses it.
    private func showMainWindow(at destination: AppTab?) {
        if let destination { model.destination = destination }
        model.prepareToShowMainWindow()
        openWindow(id: AppModel.mainWindowID)
    }
}

private struct MenuBarFanRow: View {
    @Environment(AppModel.self) private var model
    let fan: FanDeviceState
    let history: [Double]

    private var profile: FanProfile { model.profile(for: fan) }
    private var connected: Bool { fan.connection == .connected }
    private var controllable: Bool { connected && fan.writeAvailability == .ready }
    private var unit: String { fan.capabilities?.unit ?? "RPM" }
    private var tint: Color { fan.kind == .builtIn ? .accentColor : .cyan }

    var body: some View {
        DashboardCard(padding: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ZStack {
                        SpeedRing(fraction: connected ? Dashboard.speedFraction(fan) : nil, tint: tint, lineWidth: 3)
                        Image(systemName: fan.kind == .builtIn ? "fan" : "snowflake")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(connected ? tint : .secondary)
                    }
                    .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(fan.name).font(.caption.weight(.medium)).lineLimit(1)
                        HStack(spacing: 4) {
                            Text(connected ? DisplayFormat.speed(fan.currentSpeed, unit: unit) : "Disconnected")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .numericTransition(value: fan.currentSpeed.map(Double.init))
                            if let activity = Dashboard.activity(
                                fan: fan, profile: model.snapshot.profiles[fan.id], decision: model.snapshot.lastDecision
                            ) {
                                FanActivityLine(activity: activity, compact: true)
                            }
                        }
                    }
                    Spacer(minLength: 6)
                    if connected {
                        Sparkline(values: history, tint: tint, minimumSpan: 200)
                            .frame(width: 52, height: 16)
                    }
                }
                if connected {
                    PillSegmentedControl.fanMode(
                        modeBinding, fanName: fan.name, identifier: AccessibilityID.menuBarFanModePrefix + fan.id,
                        size: .small, fillsWidth: true
                    )
                    .disabled(!controllable)
                    if !controllable, let message = fan.statusMessage {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .opacity(connected ? 1 : 0.6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.menuBarFanPrefix + fan.id)
    }

    private var modeBinding: Binding<FanControlMode> {
        Binding(
            get: { profile.mode },
            set: { mode in
                var updated = profile
                updated.mode = mode
                model.updateProfile(fanID: fan.id, profile: updated)
            }
        )
    }
}

/// Plain footer buttons with a subtle rounded highlight under the pointer, like native menu items.
struct HoverHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverHighlightBody(configuration: configuration)
    }

    private struct HoverHighlightBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.caption)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : (hovering && isEnabled ? 0.08 : 0)))
                )
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}
