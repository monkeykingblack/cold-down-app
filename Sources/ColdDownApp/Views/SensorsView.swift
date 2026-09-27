import SwiftUI
import ThermalCore

/// Summary cards, then one collapsible section per sensor group with a compact grid of sensor tiles.
struct SensorsView: View {
    @EnvironmentObject private var model: AppModel
    /// Comma-separated group names the user collapsed; remembered across launches.
    @AppStorage("ColdDown.sensors.collapsedGroups") private var collapsedStorage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Dashboard.spacing) {
                BalancedGrid(minItemWidth: 120) {
                    summaryCard("CPU average", .cpuAverage)
                    summaryCard("GPU average", .gpuAverage)
                    summaryCard("All sensors", .allAverage)
                    summaryCard("Hottest", .hottest)
                }
                if model.snapshot.sensors.readings.isEmpty {
                    DashboardCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("No temperature sensors available", systemImage: "thermometer.medium.slash").font(.headline)
                            Text("This Mac did not return any readable temperature services.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ForEach(groups, id: \.group) { entry in
                        groupSection(entry.group, readings: entry.readings)
                    }
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Data

    private var groups: [(group: SensorGroup, readings: [SensorReading])] {
        let grouped = Dictionary(grouping: model.snapshot.sensors.readings, by: \.identity.group)
        return SensorGroup.allCases.compactMap { group in
            guard let readings = grouped[group], !readings.isEmpty else { return nil }
            return (group, readings.sorted {
                let order = $0.identity.name.localizedStandardCompare($1.identity.name)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            })
        }
    }

    private var collapsed: Set<String> {
        Set(collapsedStorage.split(separator: ",").map(String.init))
    }

    private func toggle(_ group: SensorGroup) {
        var set = collapsed
        if set.contains(group.rawValue) { set.remove(group.rawValue) } else { set.insert(group.rawValue) }
        collapsedStorage = set.sorted().joined(separator: ",")
    }

    // MARK: Views

    private func summaryCard(_ title: String, _ kind: CalculatedSensorKind) -> some View {
        let value = model.snapshot.sensors.calculated[kind]
        return DashboardCard(padding: 10, fillHeight: true) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(DisplayFormat.temperature(value, placeholder: "—"))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Dashboard.temperatureColor(value))
                    .numericTransition(value: value, animated: true)
                TemperatureBar(celsius: value)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Each group is a card: the header row alone when collapsed, the tile grid inside it when expanded.
    private func groupSection(_ group: SensorGroup, readings: [SensorReading]) -> some View {
        let isCollapsed = collapsed.contains(group.rawValue)
        let values = readings.filter(\.isValid).compactMap(\.valueCelsius)
        let average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let hottest = values.max()
        return DashboardCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { toggle(group) } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: Self.symbol(for: group))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Dashboard.temperatureColor(hottest))
                            .frame(width: 26, height: 26)
                            .background(Dashboard.temperatureColor(hottest).opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(group.rawValue).font(.callout.weight(.semibold))
                            Text("\(readings.count) sensor\(readings.count == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 3) {
                            HStack(spacing: 8) {
                                if let average {
                                    Text("avg \(DisplayFormat.temperature(average))").foregroundStyle(.secondary)
                                }
                                if let hottest {
                                    Text("max \(DisplayFormat.temperature(hottest))")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Dashboard.temperatureColor(hottest))
                                }
                            }
                            .font(.caption)
                            .monospacedDigit()
                            TemperatureBar(celsius: hottest).frame(width: 120)
                        }
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(group.rawValue), \(readings.count) sensors")
                .accessibilityHint(isCollapsed ? "Expands the group" : "Collapses the group")

                if !isCollapsed {
                    Divider().padding(.horizontal, 12)
                    BalancedGrid(minItemWidth: 165, spacing: 10) {
                        ForEach(readings) { reading in
                            SensorTile(reading: reading)
                        }
                    }
                    .padding(12)
                    .transition(.opacity)
                }
            }
        }
    }

    private static func symbol(for group: SensorGroup) -> String {
        switch group {
        case .cpu: "cpu"
        case .gpu: "square.grid.3x3.fill"
        case .heatsink: "fan"
        case .memory: "memorychip"
        case .pch: "rectangle.3.group"
        case .battery: "battery.75"
        case .ambient: "thermometer.sun"
        case .other: "thermometer.medium"
        }
    }
}

private struct SensorTile: View {
    let reading: SensorReading

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if reading.state != .fresh {
                    Circle().fill(reading.state == .stale ? Color.orange : Color.secondary)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                }
                Text(Self.shortName(reading.identity.name))
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(DisplayFormat.temperature(reading.valueCelsius, placeholder: "—"))
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(reading.isValid ? .primary : .secondary)
                    .fixedSize()
                    .numericTransition(value: reading.valueCelsius, animated: true)
            }
            TemperatureBar(celsius: reading.isValid ? reading.valueCelsius : nil)
        }
        .help("\(reading.identity.name) · \(reading.identity.rawKey)\(reading.state == .fresh ? "" : " · \(reading.state.rawValue)")")
        .accessibilityElement(children: .combine)
    }

    /// Shortens the verbose SMC names ("CPU efficiency core 1" → "E-core 1") so tiles stay one line.
    static func shortName(_ name: String) -> String {
        name.replacingOccurrences(of: "CPU efficiency core", with: "E-core")
            .replacingOccurrences(of: "CPU performance core", with: "P-core")
            .replacingOccurrences(of: "CPU super core", with: "S-core")
    }
}
