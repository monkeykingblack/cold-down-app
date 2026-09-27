import SwiftUI
import ThermalCore

enum SegmentSize { case regular, small }

/// The app's one segmented control (tabs, fan mode in the window, fan mode in the popover).
/// A soft capsule track with an accent pill for the selection and per-segment hover. Each segment is a real
/// accessible button (selected trait, own identifier `<identifier>.<title>`), so VoiceOver and UI tests get
/// correct frames; an `accessibilityRepresentation` stand-in reported zero-size, unclickable segments.
struct PillSegmentedControl<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        var symbol: String?
    }

    let label: String
    let options: [Option]
    @Binding var selection: Value
    var size: SegmentSize = .regular
    /// Stretch segments to fill the available width (popover rows) instead of hugging their titles.
    var fillsWidth = false
    var identifier: String?

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                Button { selection = option.value } label: {
                    HStack(spacing: 5) {
                        if let symbol = option.symbol { Image(systemName: symbol) }
                        Text(option.title).lineLimit(1)
                    }
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
                }
                .buttonStyle(SegmentStyle(selected: selection == option.value, size: size))
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
                .accessibilityIdentifier(identifier.map { "\($0).\(option.title.lowercased())" } ?? "")
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .opacity(isEnabled ? 1 : 0.5)
        .fixedSize(horizontal: !fillsWidth, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier ?? "")
    }
}

private struct SegmentStyle: ButtonStyle {
    let selected: Bool
    let size: SegmentSize

    func makeBody(configuration: Configuration) -> some View {
        SegmentBody(configuration: configuration, selected: selected, small: size == .small)
    }

    private struct SegmentBody: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        let small: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font((small ? Font.caption : Font.callout).weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(hovering && isEnabled ? 0.9 : 0.65))
                .padding(.horizontal, small ? 9 : 12)
                .padding(.vertical, small ? 3 : 5)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: hovering)
                // The selection itself is not animated. Crossfading it took 150 ms during which the old
                // segment had faded and the new one had not arrived, so both read as grey: the click looked
                // like it had been swallowed even though the page behind had already changed. Hover keeps its
                // fade, since nothing is waiting on it.
                .onHover { hovering = $0 }
        }

        private var fill: Color {
            if selected { return Color.accentColor.opacity(0.16) }
            return Color.primary.opacity(hovering && isEnabled ? 0.08 : 0)
        }
    }
}

extension PillSegmentedControl where Value == FanControlMode {
    static func fanMode(
        _ selection: Binding<FanControlMode>, fanName: String, identifier: String,
        size: SegmentSize = .regular, fillsWidth: Bool = false
    ) -> Self {
        PillSegmentedControl(
            label: "\(fanName) mode",
            options: [.init(value: .auto, title: "Auto"), .init(value: .manual, title: "Manual")],
            selection: selection, size: size, fillsWidth: fillsWidth, identifier: identifier
        )
    }
}
