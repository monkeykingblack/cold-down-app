import Foundation
import ThermalCore

actor MockExternalCoolingBackend: ExternalCoolerController {
    private var fan: FanDeviceState
    init(disconnected: Bool = false, capabilityLimited: Bool = false) {
        let availability: WriteAvailability = disconnected ? .disconnected : (capabilityLimited ? .capabilityLimited : .ready)
        fan = FanDeviceState(
            id: "flydigi:37d7:1004", name: "Flydigi BS3 Pro",
            connection: disconnected ? .disconnected : .connected,
            currentSpeed: disconnected ? nil : 1_700, reportedMode: .auto,
            capabilities: SpeedCapabilities(
                minimum: 1_300, maximum: 4_000, step: 100,
                provenance: capabilityLimited ? .unverified : .deterministicMock
            ),
            writeAvailability: availability,
            statusMessage: disconnected ? "BS3 Pro is not connected" : (capabilityLimited ? "Speed range is not yet verified" : nil)
        )
    }
    func connect() {}
    func state() -> FanDeviceState { fan }
    func setTarget(_ speed: Int) throws -> AcknowledgedTarget {
        guard fan.writeAvailability == .ready, let capabilities = fan.capabilities else { throw ThermalControlError.invalidCapabilities }
        let target = capabilities.clamped(speed)
        fan.currentSpeed = target; fan.targetSpeed = target; fan.reportedMode = .manual
        return AcknowledgedTarget(target: target, acknowledgedAt: Date())
    }
}

