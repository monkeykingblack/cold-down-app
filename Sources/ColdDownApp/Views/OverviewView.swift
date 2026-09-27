import SwiftUI
import ThermalCore

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel


    /// A fixed page, not a scroll view: everything is laid out to fit the fixed window.
    var body: some View {
        VStack(alignment: .leading, spacing: Dashboard.spacing) {
            temperatureCard
            fansSection
            sensorsCard
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Temperature

    private var temperatureCard: some View {
        DashboardCard {
            HStack(alignment: .center, spacing: 14) {
                TemperatureGauge(
                    celsius: hottest,
                    valueIdentifier: hottest == nil ? AccessibilityID.unavailableTemperature : AccessibilityID.hottest
                )
                .frame(width: 84, height: 84)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hottest temperature").font(.subheadline.weight(.semibold))
                        Text(model.snapshot.sensors.hottestReading?.identity.name ?? "No valid temperature")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 16) {
                        StatChip(title: "CPU", celsius: model.snapshot.sensors.calculated[.cpuAverage])
                        StatChip(title: "GPU", celsius: model.snapshot.sensors.calculated[.gpuAverage])
                        StatChip(title: "Average", celsius: model.snapshot.sensors.calculated[.allAverage])
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Pill(text: model.snapshot.overallMode.rawValue, tint: Dashboard.modeTint(model.snapshot.overallMode))
                        .fixedSize()
                    Sparkline(values: model.temperatureHistory, tint: Dashboard.temperatureColor(hottest), minimumSpan: 5)
                        .frame(width: 140, height: 38)
                    Text(model.temperatureHistory.count >= 2 ? "Last \(historyMinutes) min" : "Collecting history…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var hottest: Double? { model.snapshot.sensors.hottestReading?.valueCelsius }

    private var historyMinutes: Int {
        let seconds = Double(model.temperatureHistory.count) * model.preferences.refreshInterval
        return max(1, Int((seconds / 60).rounded()))
    }

    // MARK: Fans

    private var fansSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle(title: "Fans", systemImage: "fan")
                .padding(.leading, 4)
            if model.snapshot.fans.isEmpty {
                DashboardCard {
                    Label("No fans detected", systemImage: "fan.slash").foregroundStyle(.secondary)
                }
            } else {
                BalancedGrid(minItemWidth: 200) {
                    ForEach(model.snapshot.fans) { fan in
                        Button { model.openFan(fan.id) } label: {
                            FanCard(fan: fan, profile: model.snapshot.profiles[fan.id], history: model.fanSpeedHistory[fan.id] ?? [])
                        }
                        .buttonStyle(CardButtonStyle())
                        .accessibilityIdentifier(AccessibilityID.fanPrefix + fan.id)
                    }
                }
            }
        }
    }

    // MARK: Sensors

    /// One row per sensor group in a fixed order, showing that group's hottest reading. Rows never reorder;
    /// only the values (and, occasionally, which sensor is hottest within a group) change. The section takes
    /// whatever height the cards above leave it and flows its rows into extra columns to fit, so a Mac with
    /// two built-in fans (one fan row more than a single-fan Mac) does not push the page past the window.
    private var sensorsCard: some View {
        let hottestByGroup = model.snapshot.sensors.hottestByGroup
        let groups = SensorGroup.allCases.filter { hottestByGroup[$0] != nil }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                CardTitle(title: "Temperatures by group", systemImage: "thermometer.medium")
                Spacer()
                Button("All sensors") { model.destination = .sensors }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            .padding(.horizontal, 4)
            DashboardCard(padding: 10, fillHeight: true) {
                if groups.isEmpty {
                    Label("No temperature sensors available", systemImage: "thermometer.medium.slash")
                        .foregroundStyle(.secondary)
                } else {
                    SensorGroupColumns(groups: groups, hottestByGroup: hottestByGroup)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Sensor group rows

/// The group rows, in one column while the page has room for them and in as many columns as it takes when it
/// does not. `ViewThatFits` measures the real rows, so the choice follows the actual text metrics instead of
/// an assumed row height. The canonical group order still reads top-to-bottom down each column, so a row
/// never moves because a value changed.
private struct SensorGroupColumns: View {
    let groups: [SensorGroup]
    let hottestByGroup: [SensorGroup: SensorReading]

    private static let rowSpacing: CGFloat = 8
    private static let columnSpacing: CGFloat = 14

    var body: some View {
        ViewThatFits(in: .vertical) {
            columns(1)
            columns(2)
            columns(3)
        }
    }

    private func columns(_ requested: Int) -> some View {
        let count = max(1, min(requested, groups.count))
        let perColumn = Int((Double(groups.count) / Double(count)).rounded(.up))
        return HStack(alignment: .top, spacing: Self.columnSpacing) {
            ForEach(0..<count, id: \.self) { column in
                VStack(spacing: Self.rowSpacing) {
                    ForEach(slice(column: column, perColumn: perColumn), id: \.self) { group in
                        SensorGroupRow(group: group, reading: hottestByGroup[group], compact: count > 1)
                    }
                    // Keeps a short last column aligned with the top of the others.
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func slice(column: Int, perColumn: Int) -> [SensorGroup] {
        let start = min(column * perColumn, groups.count)
        return Array(groups[start..<min(start + perColumn, groups.count)])
    }
}

private struct SensorGroupRow: View {
    let group: SensorGroup
    let reading: SensorReading?
    /// Trims the fixed label and value columns when the rows share the card's width.
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            Text(group.rawValue)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(width: compact ? 56 : 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                TemperatureBar(celsius: reading?.valueCelsius)
                Text(reading?.identity.name ?? "")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Text(DisplayFormat.temperature(reading?.valueCelsius))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Dashboard.temperatureColor(reading?.valueCelsius))
                .frame(width: compact ? 52 : 58, alignment: .trailing)
                .numericTransition(value: reading?.valueCelsius, animated: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Fan card

struct FanCard: View {
    let fan: FanDeviceState
    let profile: FanProfile?
    let history: [Double]

    private var connected: Bool { fan.connection == .connected }
    private var unit: String { fan.capabilities?.unit ?? "RPM" }
    private var tint: Color { fan.kind == .builtIn ? .accentColor : .cyan }

    var body: some View {
        DashboardCard(padding: 10, fillHeight: true) {
            HStack(spacing: 10) {
                ZStack {
                    SpeedRing(fraction: connected ? Dashboard.speedFraction(fan) : nil, tint: tint)
                    Image(systemName: fan.kind == .builtIn ? "fan" : "snowflake")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(connected ? tint : .secondary)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fan.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if connected {
                        HStack(alignment: .lastTextBaseline, spacing: 3) {
                            Text(fan.currentSpeed.map { $0.formatted() } ?? "—")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .numericTransition(value: fan.currentSpeed.map(Double.init), animated: true)
                            Text(unit).font(.caption2).foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .fixedSize()
                    } else {
                        Text("Disconnected").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 6)
                if connected {
                    Sparkline(values: history, tint: tint, minimumSpan: 200)
                        .frame(width: 48, height: 22)
                }
                Pill(text: modeText, tint: profile?.mode == .manual ? .blue : .secondary)
                    .fixedSize()
            }
        }
        .opacity(connected ? 1 : 0.6)
    }

    private var modeText: String {
        guard let profile else { return "Auto" }
        return profile.mode == .manual ? "Manual" : "Auto"
    }
}

/// Lets a whole card act as a button with a gentle press/hover response.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CardButtonBody(configuration: configuration)
    }

    private struct CardButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .brightness(hovering ? 0.015 : 0)
                .overlay(
                    RoundedRectangle(cornerRadius: Dashboard.cornerRadius, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(hovering ? 0.35 : 0), lineWidth: 1)
                )
                .animation(.easeOut(duration: 0.15), value: hovering)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
                .contentShape(RoundedRectangle(cornerRadius: Dashboard.cornerRadius, style: .continuous))
                .onHover { hovering = $0 }
        }
    }
}
