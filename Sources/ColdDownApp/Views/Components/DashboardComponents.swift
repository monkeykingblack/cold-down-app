import SwiftUI
import ThermalCore

// MARK: - Theme

enum Dashboard {
    static let cornerRadius: CGFloat = 10
    static let spacing: CGFloat = 10
    /// Key behind **Settings › General › Smooth value animations**, read straight from defaults so every
    /// animated site honours it without threading a preference through the view tree.
    static let smoothAnimationsKey = "ColdDown.smoothAnimations"

    /// Off by default, and that default is the point. Every reading changes on each refresh, so each change
    /// starts a spring; across a page of rows that is the whole window animating almost continuously. Measured
    /// over 15 s windows on an Intel Mac: Overview 24.5% of a core with them on against 5.5% off, and the
    /// Sensors tab 36.1% against 3.9%. Anyone who wants the motion back can pay for it deliberately.
    static var valueAnimation: Animation? {
        UserDefaults.standard.bool(forKey: smoothAnimationsKey)
            ? .spring(response: 0.5, dampingFraction: 0.85) : nil
    }

    /// Cool teal → green → amber → red, keyed to the thresholds the policy cares about.
    static func temperatureColor(_ celsius: Double?) -> Color {
        guard let celsius else { return .secondary }
        switch celsius {
        case ..<55: return .teal
        case ..<75: return .green
        case ..<85: return .yellow
        case ..<95: return .orange
        default: return .red
        }
    }

    /// Short labels for tight spaces (the popover header); the main window uses the full `rawValue`.
    static func shortModeName(_ mode: OverallControlMode) -> String {
        switch mode {
        case .readOnly: "Read only"
        case .automatic: "Auto"
        case .manual: "Manual"
        case .safetyFallback: "Fallback"
        }
    }

    static func modeTint(_ mode: OverallControlMode) -> Color {
        switch mode {
        case .safetyFallback: .orange
        case .manual: .blue
        case .automatic: .green
        case .readOnly: .secondary
        }
    }

    enum FanActivity: Equatable {
        /// Waiting for the hardware to follow a mode change (Apple Silicon takeover can take a few seconds).
        case transitioning(String)
        /// Auto profile, but Cold Down's curve is deliberately driving the fan above the threshold.
        case boosting(String)
    }

    static func activity(fan: FanDeviceState, profile: FanProfile?, decision: CoolingDecision?) -> FanActivity? {
        guard fan.kind == .builtIn, fan.connection == .connected, fan.writeAvailability == .ready,
              let profile, let reported = fan.reportedMode else { return nil }
        let curveIsDriving: Bool = {
            if case .target = decision?.builtInActions[fan.id] { return true }
            return false
        }()
        if profile.mode == .auto, curveIsDriving {
            return .boosting("Boosting — above your \(profile.thresholdCelsius) °C threshold")
        }
        guard reported != profile.mode else { return nil }
        return .transitioning(profile.mode == .manual ? "Taking control…" : "Returning to Auto…")
    }

    /// Position of a fan's current speed within its safe range, when known.
    static func speedFraction(_ fan: FanDeviceState) -> Double? {
        guard let speed = fan.currentSpeed, let capabilities = fan.capabilities,
              capabilities.maximum > capabilities.minimum else { return nil }
        if speed <= 0 { return 0 }
        let fraction = Double(speed - capabilities.minimum) / Double(capabilities.maximum - capabilities.minimum)
        return min(max(fraction, 0), 1)
    }
}

// MARK: - Card

struct DashboardCard<Content: View>: View {
    var padding: CGFloat = 12
    /// Stretch to the height offered (used inside `BalancedGrid` rows so neighbouring cards line up).
    var fillHeight = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
            // The shadow hangs off the background shape, not off the card as a whole. Shadowing the card made
            // SwiftUI rasterize its contents offscreen on every value change, which a profile showed as
            // CoreAnimation `make_cgimage` work; the drawn result is the same, because the opaque background
            // is what defines the silhouette.
            .background {
                RoundedRectangle(cornerRadius: Dashboard.cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Dashboard.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }
}

struct CardTitle: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

// MARK: - Temperature gauge

/// A 270° arc gauge from 20 °C to 105 °C with the value in the middle.
struct TemperatureGauge: View {
    let celsius: Double?
    var lineWidth: CGFloat = 8
    var valueFont: Font = .system(size: 20, weight: .semibold, design: .rounded)
    var valueIdentifier: String?

    private static let range = 20.0...105.0
    private static let sweep = 0.75

    private var fraction: Double {
        guard let celsius else { return 0 }
        return min(max((celsius - Self.range.lowerBound) / (Self.range.upperBound - Self.range.lowerBound), 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: Self.sweep)
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
            // A flat tint rather than an AngularGradient: conic shading has no GPU fast path, so CoreGraphics
            // re-rasterized the arc on the CPU for every frame the value animation ran (it showed up in a
            // profile as `RGBAf16_shade_conic_RGB`). The arc now matches the colour of the reading below it.
            Circle()
                .trim(from: 0, to: Self.sweep * fraction)
                .stroke(
                    Dashboard.temperatureColor(celsius),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .animation(Dashboard.valueAnimation, value: fraction)
            valueText
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var valueText: some View {
        let text = Text(DisplayFormat.temperature(celsius, placeholder: "—"))
            .font(valueFont)
            .monospacedDigit()
            .foregroundStyle(Dashboard.temperatureColor(celsius))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, lineWidth)
            .numericTransition(value: celsius)
        if let valueIdentifier {
            text.accessibilityIdentifier(valueIdentifier)
        } else {
            text
        }
    }
}

// MARK: - Speed ring

struct SpeedRing: View {
    let fraction: Double?
    var tint: Color = .accentColor
    var lineWidth: CGFloat = 4

    /// Unlike the single headline gauge, a speed ring is drawn once per fan and is only 32 pt across, where a
    /// spring is barely perceptible but still animates every refresh. It snaps instead.
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction ?? 0)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Dashboard.valueAnimation, value: fraction ?? 0)
        }
        .opacity(fraction == nil ? 0.4 : 1)
        .accessibilityHidden(true)
    }
}

// MARK: - Sparkline

/// A smoothed line with a soft gradient fill. Draws nothing until there are two samples.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = .accentColor
    /// Optional fixed range so small wiggles are not exaggerated.
    var minimumSpan: Double = 1

    var body: some View {
        GeometryReader { geometry in
            if values.count >= 2 {
                let points = normalizedPoints(in: geometry.size)
                ZStack {
                    areaPath(points, size: geometry.size)
                        .fill(LinearGradient(colors: [tint.opacity(0.25), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                    linePath(points)
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let low = values.min() ?? 0
        let high = max(values.max() ?? 0, low + minimumSpan)
        let span = high - low
        let step = size.width / CGFloat(max(values.count - 1, 1))
        return values.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step, y: size.height * (1 - CGFloat((value - low) / span)) * 0.9 + size.height * 0.05)
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for (previous, point) in zip(points, points.dropFirst()) {
                let mid = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
                path.addQuadCurve(to: mid, control: previous)
            }
            if let last = points.last { path.addLine(to: last) }
        }
    }

    private func areaPath(_ points: [CGPoint], size: CGSize) -> Path {
        var path = linePath(points)
        path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: size.height))
        path.addLine(to: CGPoint(x: points.first?.x ?? 0, y: size.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Small pieces

struct StatChip: View {
    let title: String
    let celsius: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(DisplayFormat.temperature(celsius, placeholder: "—"))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(celsius == nil ? .secondary : .primary)
                .lineLimit(1)
                .fixedSize()
                .numericTransition(value: celsius)
        }
        .accessibilityElement(children: .combine)
    }
}

struct Pill: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}

/// A thin bar showing where a temperature sits between 20 °C and 105 °C.
struct TemperatureBar: View {
    let celsius: Double?

    var body: some View {
        GeometryReader { geometry in
            let fraction = celsius.map { min(max(($0 - 20) / 85, 0), 1) } ?? 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Dashboard.temperatureColor(celsius))
                    .frame(width: geometry.size.width * fraction)
                    .animation(Dashboard.valueAnimation, value: fraction)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Rolls digits smoothly when a numeric value changes, if `Dashboard.valueAnimation` is on.
    @ViewBuilder
    func numericTransition(value: Double?) -> some View {
        if Dashboard.valueAnimation != nil {
            self.contentTransition(.numericText(value: value ?? 0))
                .animation(Dashboard.valueAnimation, value: value)
        } else {
            self
        }
    }
}

/// Small status line under a fan: a spinner while switching modes, a bolt while the Auto curve boosts.
struct FanActivityLine: View {
    let activity: Dashboard.FanActivity
    /// Icon only (text in the tooltip), for tight rows such as the popover.
    var compact = false

    private var text: String {
        switch activity {
        case let .transitioning(text), let .boosting(text): text
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            switch activity {
            case .transitioning: ProgressView().controlSize(.mini)
            case .boosting: Image(systemName: "bolt.fill").foregroundStyle(.orange)
            }
            if !compact { Text(text) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .help(text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
