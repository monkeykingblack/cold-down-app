import Foundation

public struct CoolingPolicy: Sendable {
    public init() {}

    public func evaluate(
        summary: SensorSummary,
        fanStates: [FanDeviceState],
        profiles: [String: FanProfile],
        helperStatus: HelperStatus,
        externalState: FanDeviceState?,
        now: Date
    ) -> CoolingDecision {
        let builtIns = fanStates.filter { $0.kind == .builtIn }
        let externalReady = externalState?.connection == .connected
            && externalState?.writeAvailability == .ready
            && externalState?.capabilities?.isStructurallyValid == true
        let anyCritical = summary.readings.contains { $0.isValid && ($0.valueCelsius ?? -.infinity) >= 95 }
            || summary.calculated.values.contains { $0.isFinite && $0 >= 95 }

        if anyCritical {
            return CoolingDecision(
                band: .critical,
                externalAction: externalReady ? .target(externalState!.capabilities!.maximum, requiresAcknowledgement: false) : .none,
                builtInActions: Dictionary(uniqueKeysWithValues: builtIns.map { ($0.id, .automatic) }),
                reason: "A fresh temperature reached the 95°C critical boundary.",
                evaluatedAt: now
            )
        }

        var demands: [ProfileDemand] = []
        var selectedSourceUnavailable = false
        for fan in fanStates {
            guard let profile = profiles[fan.id], profile.mode == .auto else { continue }
            guard let temperature = summary.temperature(for: profile.selectedSensor) else {
                selectedSourceUnavailable = true
                continue
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
            demands.append(ProfileDemand(
                fanID: fan.id, temperatureCelsius: temperature, thresholdCelsius: threshold,
                band: band, normalizedProgress: progress
            ))
        }

        let builtInManualNeedsVisibility = builtIns.contains {
            profiles[$0.id]?.mode == .manual
        } && !summary.hasFreshTemperature
        if selectedSourceUnavailable || builtInManualNeedsVisibility {
            return CoolingDecision(
                band: .safetyFallback,
                demands: demands,
                externalAction: externalReady ? .target(externalState!.capabilities!.maximum, requiresAcknowledgement: false) : .none,
                builtInActions: Dictionary(uniqueKeysWithValues: builtIns.map { ($0.id, .automatic) }),
                reason: "A controlling temperature source is unavailable.",
                evaluatedAt: now
            )
        }

        let winner = demands.max { lhs, rhs in
            if lhs.band != rhs.band { return lhs.band < rhs.band }
            if lhs.normalizedProgress != rhs.normalizedProgress { return lhs.normalizedProgress < rhs.normalizedProgress }
            return lhs.fanID < rhs.fanID
        }
        let overallBand = winner?.band ?? .cool
        let externalAction = externalAction(for: winner, state: externalState, ready: externalReady)
        var builtInActions: [String: BuiltInCoolingAction] = [:]

        for fan in builtIns {
            guard helperStatus == .healthy,
                  fan.writeAvailability == .ready,
                  let capabilities = fan.capabilities,
                  capabilities.isStructurallyValid,
                  let profile = profiles[fan.id] else {
                builtInActions[fan.id] = .automatic
                continue
            }
            if profile.mode == .manual {
                builtInActions[fan.id] = .target(capabilities.clamped(profile.manualTarget), requiresExternalAcknowledgement: false)
                continue
            }
            guard let demand = demands.first(where: { $0.fanID == fan.id }), demand.band == .hot else {
                builtInActions[fan.id] = .automatic
                continue
            }
            let interpolated = Double(capabilities.minimum)
                + demand.normalizedProgress * Double(capabilities.maximum - capabilities.minimum)
            // Never take over below what macOS Auto is currently running, but once the fan is under our control
            // its current speed just echoes our last target, so it must not act as a floor (that would ratchet).
            let systemFloor = fan.reportedMode == .manual ? capabilities.minimum : (fan.currentSpeed ?? capabilities.minimum)
            let target = capabilities.clamped(max(systemFloor, Int(interpolated.rounded())))
            builtInActions[fan.id] = .target(target, requiresExternalAcknowledgement: externalReady)
        }

        return CoolingDecision(
            band: overallBand,
            demands: demands,
            winningDemand: winner,
            externalAction: externalAction,
            builtInActions: builtInActions,
            evaluatedAt: now
        )
    }

    private func externalAction(
        for demand: ProfileDemand?,
        state: FanDeviceState?,
        ready: Bool
    ) -> ExternalCoolingAction {
        guard ready, let state, let capabilities = state.capabilities else { return .none }
        guard let demand else {
            return capabilities.supportsVerifiedStop ? .stop : .target(capabilities.minimum, requiresAcknowledgement: false)
        }
        switch demand.band {
        case .cool:
            return capabilities.supportsVerifiedStop ? .stop : .target(capabilities.minimum, requiresAcknowledgement: false)
        case .warm:
            let value = Double(capabilities.minimum)
                + demand.normalizedProgress * Double(capabilities.maximum - capabilities.minimum)
            return .target(capabilities.clamped(Int(value.rounded())), requiresAcknowledgement: false)
        case .hot:
            return .target(capabilities.maximum, requiresAcknowledgement: true)
        case .critical, .safetyFallback:
            return .target(capabilities.maximum, requiresAcknowledgement: false)
        }
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}

