import SwiftUI

/// A slim custom slider: gradient-filled capsule track, round thumb, click-to-jump and drag.
/// Unlike `Slider(step:)` on macOS it never draws tick marks, so wide fine-grained ranges stay clean.
/// Accessibility and UI tests see a regular slider through `accessibilityRepresentation`.
struct ValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var gradient: [Color] = [.accentColor.opacity(0.7), .accentColor]
    var accessibilityValueText: String = ""
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var dragging = false
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    private let trackHeight: CGFloat = 6
    private let thumbSize: CGFloat = 16

    private var fraction: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        GeometryReader { geometry in
            let usable = max(geometry.size.width - thumbSize, 1)
            let thumbX = CGFloat(min(max(fraction, 0), 1)) * usable
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbSize / 2)
                Capsule()
                    .fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                    .frame(width: thumbX + thumbSize / 2, height: trackHeight)
                    .padding(.leading, thumbSize / 2)
                    .opacity(isEnabled ? 1 : 0.35)
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.12)))
                    .shadow(color: .black.opacity(0.22), radius: dragging ? 3 : 1.5, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .scaleEffect(dragging ? 1.12 : (hovering && isEnabled ? 1.05 : 1))
                    .offset(x: thumbX)
                    .animation(.easeOut(duration: 0.12), value: dragging)
                    .animation(.easeOut(duration: 0.12), value: hovering)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !dragging { dragging = true; onEditingChanged(true) }
                        update(to: gesture.location.x - thumbSize / 2, usable: usable)
                    }
                    .onEnded { _ in
                        dragging = false
                        onEditingChanged(false)
                    }
            )
            .onHover { hovering = $0 }
        }
        .frame(height: thumbSize + 4)
        .accessibilityRepresentation {
            Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
                .accessibilityValue(accessibilityValueText)
        }
    }

    private func update(to x: CGFloat, usable: CGFloat) {
        let raw = range.lowerBound + Double(min(max(x / usable, 0), 1)) * (range.upperBound - range.lowerBound)
        let snapped = step > 0 ? (((raw - range.lowerBound) / step).rounded() * step + range.lowerBound) : raw
        value = min(max(snapped, range.lowerBound), range.upperBound)
    }
}

/// Small capsule chips for jumping to common values. The whole capsule is clickable, with hover/press feedback.
struct PresetButtons: View {
    let presets: [(label: String, value: Double)]
    let current: Double
    let select: (Double) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(presets, id: \.label) { preset in
                Button(preset.label) { select(preset.value) }
                    .buttonStyle(PresetChipStyle(selected: abs(preset.value - current) < 0.5))
                    .accessibilityAddTraits(abs(preset.value - current) < 0.5 ? .isSelected : [])
            }
        }
        .fixedSize()
    }
}

private struct PresetChipStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Chip(configuration: configuration, selected: selected)
    }

    private struct Chip: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(selected ? Color.accentColor.opacity(0.35) : .clear))
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .opacity(isEnabled ? 1 : 0.5)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }

        private var fill: Color {
            if selected { return Color.accentColor.opacity(0.16) }
            return Color.primary.opacity(hovering && isEnabled ? 0.12 : 0.06)
        }
    }
}
