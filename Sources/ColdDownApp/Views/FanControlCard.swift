import SwiftUI
import ThermalCore

/// One fan as a full-width card: live status row with the Auto/Manual switch, and that mode's controls inline.
/// Holds the user's draft settings; see `FanConfigurationViewModel` for how live device state is merged in.
struct FanControlCard: View {
    /// Short: this only groups keystrokes and drag ticks. The real "end of action" debounce lives in AppModel.
    private static let commitDelay: Duration = .milliseconds(150)

    @Environment(AppModel.self) private var appModel
    @State private var model: FanConfigurationViewModel
    @State private var pendingCommit: Task<Void, Never>?
    @State private var editing = false
    private let fanID: String
    var highlighted = false

    init(fan: FanDeviceState, profile: FanProfile, highlighted: Bool = false) {
        fanID = fan.id
        self.highlighted = highlighted
        _model = State(initialValue: FanConfigurationViewModel(fan: fan, profile: profile))
    }

    private var modeBinding: Binding<FanControlMode> {
        Binding(get: { model.mode }, set: { model.mode = $0 })
    }

    private var sensorBinding: Binding<SensorSelection> {
        Binding(get: { model.selectedSensor }, set: { model.selectedSensor = $0 })
    }

    private var liveFan: FanDeviceState? { appModel.snapshot.fans.first { $0.id == fanID } }
    private var unit: String { model.fan.capabilities?.unit ?? "RPM" }
    private var connected: Bool { model.fan.connection == .connected }
    private var tint: Color { model.fan.kind == .builtIn ? .accentColor : .cyan }

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                statusRow
                if connected {
                    Divider()
                    Group {
                        if model.mode == .auto { autoControls } else { manualControls }
                    }
                    .disabled(!model.controlsEnabled)
                }
                footnote
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Dashboard.cornerRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(highlighted ? 0.6 : 0), lineWidth: 1.5)
                .animation(.easeOut(duration: 0.4), value: highlighted)
        )
        .opacity(connected ? 1 : 0.7)
        .onAppear { if let liveFan { model.updateFan(liveFan) } }
        .onChange(of: liveFan) { fan in if let fan { model.updateFan(fan) } }
        .onChange(of: appModel.snapshot.profiles[fanID]) { external in
            // Follow changes made in the popover, but never clobber an edit in progress here.
            guard let external, pendingCommit == nil, !editing else { return }
            model.adopt(external)
        }
        .onDisappear { if pendingCommit != nil { commitNow() } }
    }

    // MARK: Status row

    private var statusRow: some View {
        HStack(spacing: 12) {
            ZStack {
                SpeedRing(fraction: connected ? Dashboard.speedFraction(model.fan) : nil, tint: tint, lineWidth: 4)
                Image(systemName: model.fan.kind == .builtIn ? "fan" : "snowflake")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(connected ? tint : .secondary)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.fan.name).font(.headline).lineLimit(1)
                // Activity takes the subtitle's place so the card never changes height.
                if let activity {
                    FanActivityLine(activity: activity)
                } else {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            if connected {
                Sparkline(values: appModel.fanSpeedHistory[fanID] ?? [], tint: tint, minimumSpan: 200)
                    .frame(width: 72, height: 22)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(model.fan.currentSpeed.map { $0.formatted() } ?? "—")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .numericTransition(value: model.fan.currentSpeed.map(Double.init), animated: true)
                    Text(unit).font(.caption2).foregroundStyle(.secondary)
                }
                .fixedSize()
            }
            PillSegmentedControl.fanMode(modeBinding, fanName: model.fan.name, identifier: AccessibilityID.fanMode(fanID))
                .disabled(!model.controlsEnabled)
            .onChange(of: model.mode) { _, _ in commitNow() }
        }
    }

    private var activity: Dashboard.FanActivity? {
        Dashboard.activity(fan: model.fan, profile: appModel.snapshot.profiles[fanID], decision: appModel.snapshot.lastDecision)
    }

    private var subtitle: String {
        guard connected else { return "\(model.fan.kind == .builtIn ? "Built-in" : "External") · Disconnected" }
        var parts = [model.fan.kind == .builtIn ? "Built-in" : "External"]
        if let capabilities = model.fan.capabilities {
            parts.append("\(capabilities.minimum.formatted())–\(capabilities.maximum.formatted()) \(unit)")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var footnote: some View {
        if !model.controlsEnabled, let message = model.fan.statusMessage {
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(AccessibilityID.fanConnectionMessage(fanID))
        }
    }

    // MARK: Controls
    //
    // Both modes use exactly two rows of the same heights (a short row, then a slider row), so the card keeps
    // its height and the slider stays in place when switching between Auto and Manual.

    private static let labelWidth: CGFloat = 128
    private static let shortRowHeight: CGFloat = 26
    private static let sliderRowHeight: CGFloat = 36

    private var autoControls: some View {
        VStack(spacing: 6) {
            controlRow("Temperature source", height: Self.shortRowHeight) { sensorPicker }
            controlRow("Start boosting at", height: Self.sliderRowHeight) {
                sliderRow(
                    slider: ValueSlider(
                        value: thresholdBinding, range: 45...85, step: 1,
                        gradient: [.teal, .green, .yellow, .orange],
                        accessibilityValueText: "\(Int(model.threshold)) degrees Celsius",
                        onEditingChanged: commitWhenDone
                    )
                    .accessibilityIdentifier(AccessibilityID.thresholdSlider(fanID))
                    .accessibilityLabel("Threshold"),
                    field: TextField("Threshold", value: thresholdBinding, format: .number.precision(.fractionLength(0)))
                        .accessibilityLabel("Threshold")
                        .accessibilityIdentifier(AccessibilityID.thresholdField(fanID)),
                    fieldWidth: 30, unit: "°C",
                    scale: ("45 °C", "full speed by 95 °C", "85 °C")
                )
            }
            .onChange(of: model.threshold) { _ in scheduleCommit() }
        }
    }

    private var manualControls: some View {
        VStack(spacing: 6) {
            controlRow("Quick set", height: Self.shortRowHeight) {
                ViewThatFits(in: .horizontal) {
                    presetButtons(speedPresets)
                    presetButtons(speedPresets.filter { $0.label == "Min" || $0.label == "Max" })
                }
            }
            controlRow("Target speed", height: Self.sliderRowHeight) {
                sliderRow(
                    slider: ValueSlider(
                        value: manualTargetBinding,
                        range: model.minimumSpeed...max(model.minimumSpeed + 1, model.maximumSpeed),
                        step: model.speedStep,
                        gradient: [tint.opacity(0.55), tint],
                        accessibilityValueText: DisplayFormat.speed(Int(model.manualTarget), unit: unit),
                        onEditingChanged: commitWhenDone
                    )
                    .accessibilityIdentifier(AccessibilityID.speedSlider(fanID))
                    .accessibilityLabel("Target speed"),
                    field: TextField("Speed", value: manualTargetBinding, format: .number.precision(.fractionLength(0)))
                        .accessibilityLabel("Target speed")
                        .accessibilityIdentifier(AccessibilityID.speedField(fanID)),
                    fieldWidth: 46, unit: unit,
                    scale: (Int(model.minimumSpeed).formatted(), "", Int(model.maximumSpeed).formatted())
                )
            }
            .onChange(of: model.manualTarget) { _ in scheduleCommit() }
        }
    }

    /// Label on the left, control on the right, fixed row height.
    private func controlRow<Content: View>(_ title: String, height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.callout)
                .lineLimit(1)
                .frame(width: Self.labelWidth, height: Self.shortRowHeight, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: height, alignment: .top)
    }

    /// Slider with its editable value beside it and a small scale underneath.
    private func sliderRow(
        slider: some View, field: some View, fieldWidth: CGFloat, unit: String,
        scale: (String, String, String)
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 0) {
                slider
                    .frame(height: Self.shortRowHeight)
                HStack {
                    Text(scale.0)
                    Spacer(minLength: 4)
                    Text(scale.1).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(scale.2)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                field
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: fieldWidth)
                    .onSubmit(commitNow)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            .frame(height: Self.shortRowHeight)
            .fixedSize()
        }
    }

    private var sensorPicker: some View {
        Picker("Temperature source", selection: sensorBinding) {
            ForEach(CalculatedSensorKind.allCases, id: \.self) { kind in
                Text(kind.displayName).tag(SensorSelection.calculated(kind))
            }
            Divider()
            ForEach(appModel.snapshot.sensors.readings) { reading in
                Text("\(reading.identity.name) (\(reading.identity.rawKey))")
                    .tag(SensorSelection.physical(reading.id))
            }
            if case let .physical(id) = model.selectedSensor,
               !appModel.snapshot.sensors.readings.contains(where: { $0.id == id }) {
                Text("\(id) (unavailable)").tag(model.selectedSensor)
            }
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityIdentifier(AccessibilityID.autoSensor(fanID))
        .onChange(of: model.selectedSensor) { _ in commitNow() }
    }

    private func presetButtons(_ presets: [(label: String, value: Double)]) -> some View {
        PresetButtons(presets: presets, current: model.manualTarget) { value in
            model.setManualTarget(value)
            commitNow()
        }
    }

    /// Quiet / balanced / full presets across the fan's safe range, snapped to its step.
    private var speedPresets: [(label: String, value: Double)] {
        let low = model.minimumSpeed, high = model.maximumSpeed, step = max(model.speedStep, 1)
        func snap(_ fraction: Double) -> Double { low + ((high - low) * fraction / step).rounded() * step }
        return [("Min", low), ("Quiet", snap(0.25)), ("Balanced", snap(0.5)), ("Max", high)]
    }

    private var thresholdBinding: Binding<Double> {
        Binding(get: { model.threshold }, set: { model.setThreshold($0) })
    }

    private var manualTargetBinding: Binding<Double> {
        Binding(get: { model.manualTarget }, set: { model.setManualTarget($0) })
    }

    /// Continuous inputs (slider drags, typing, keyboard/VoiceOver increments) are debounced so a single
    /// adjustment produces one save and one hardware write instead of one per intermediate value.
    private func scheduleCommit() {
        guard hasUncommittedChanges else { return }
        pendingCommit?.cancel()
        pendingCommit = Task { @MainActor in
            guard (try? await Task.sleep(for: Self.commitDelay)) != nil else { return }
            commitNow()
        }
    }

    private func commitWhenDone(_ isEditing: Bool) {
        editing = isEditing
        if !isEditing { commitNow() }
    }

    /// A draft equal to the stored profile (e.g. one just adopted from the popover) is never re-sent.
    private var hasUncommittedChanges: Bool {
        model.profile() != appModel.snapshot.profiles[fanID]
    }

    private func commitNow() {
        guard hasUncommittedChanges else {
            pendingCommit?.cancel()
            pendingCommit = nil
            return
        }
        pendingCommit?.cancel()
        pendingCommit = nil
        appModel.updateProfile(fanID: model.fan.id, profile: model.profile())
    }
}
