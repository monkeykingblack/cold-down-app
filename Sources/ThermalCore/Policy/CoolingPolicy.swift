import Foundation

/// Decides what the cooler should do from the current temperatures and its profile.
public struct CoolingPolicy: Sendable {
    public init() {}

    public func evaluate(
        summary: SensorSummary,
        profiles: [String: FanProfile],
        externalState: FanDeviceState?,
        now: Date
    ) -> CoolingDecision {
        let capabilities: SpeedCapabilities? = {
            guard let externalState, externalState.connection == .connected,
                  externalState.writeAvailability == .ready,
                  let capabilities = externalState.capabilities, capabilities.isStructurallyValid else { return nil }
            return capabilities
        }()
        let anyCritical = summary.readings.contains { $0.isValid && ($0.valueCelsius ?? -.infinity) >= 95 }
            || summary.calculated.values.contains { $0.isFinite && $0 >= 95 }

        if anyCritical {
            return CoolingDecision(
                band: .critical,
                externalAction: capabilities.map { .target($0.maximum) } ?? .none,
                reason: "A fresh temperature reached the 95°C critical boundary.",
                evaluatedAt: now
            )
        }

        // Nothing to drive: the cooler is absent, disconnected, or its range is not trusted.
        guard let externalState, let capabilities else {
            return CoolingDecision(band: .cool, evaluatedAt: now)
        }

        let profile = profiles[externalState.id] ?? FanProfile.suggested(for: externalState, summary: summary)
        // Manual holds its own target instead of following the temperature.
        if profile.mode == .manual {
            return CoolingDecision(
                band: .cool,
                externalAction: .target(capabilities.clamped(profile.manualTarget)),
                evaluatedAt: now
            )
        }

        guard let temperature = summary.temperature(for: profile.selectedSensor) else {
            return CoolingDecision(
                band: .safetyFallback,
                externalAction: .target(capabilities.maximum),
                reason: "A controlling temperature source is unavailable.",
                evaluatedAt: now
            )
        }

        let threshold = min(max(profile.thresholdCelsius, 45), 85)
        let hotStart = threshold + 10
        let band: ThermalBand
        let progress: Double
        if temperature < Double(threshold) {
            band = .cool; progress = 0
        } else if temperature < Double(hotStart) {
            band = .warm; progress = Self.clamp((temperature - Double(threshold)) / 10)
        } else {
            band = .hot
            let width = 95 - hotStart
            progress = width > 0 ? Self.clamp((temperature - Double(hotStart)) / Double(width)) : 0
        }
        let demand = ProfileDemand(
            fanID: externalState.id, temperatureCelsius: temperature, thresholdCelsius: threshold,
            band: band, normalizedProgress: progress
        )

        // Idles below the threshold, ramps across the warm band, and holds its maximum once hot.
        let action: ExternalCoolingAction
        switch band {
        case .cool:
            action = capabilities.supportsVerifiedStop ? .stop : .target(capabilities.minimum)
        case .warm:
            let value = Double(capabilities.minimum) + progress * Double(capabilities.maximum - capabilities.minimum)
            action = .target(capabilities.clamped(Int(value.rounded())))
        case .hot, .critical, .safetyFallback:
            action = .target(capabilities.maximum)
        }

        return CoolingDecision(band: band, demand: demand, externalAction: action, evaluatedAt: now)
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}
