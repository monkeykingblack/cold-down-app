import Foundation
import ThermalCore

enum Fixtures {
    static let now = Date(timeIntervalSince1970: 10_000)

    static func reading(
        _ key: String,
        _ value: Double?,
        group: SensorGroup = .cpu,
        state: ReadingState = .fresh,
        at date: Date = now
    ) -> SensorReading {
        SensorReading(
            identity: SensorIdentity(rawKey: key, name: key, group: group),
            valueCelsius: value, timestamp: date, state: state
        )
    }

    static func summary(_ readings: [SensorReading]) -> SensorSummary {
        var aggregator = SensorAggregator()
        return aggregator.ingest(
            SensorBatch(generation: 1, sampledAt: now, readings: readings),
            now: now, refreshInterval: 2
        )
    }

    static func builtIn(
        id: String = "builtin:0",
        current: Int = 2_000,
        availability: WriteAvailability = .ready
    ) -> FanDeviceState {
        FanDeviceState(
            id: id, name: "Mac fan", kind: .builtIn, connection: .connected,
            currentSpeed: current, capabilities: SpeedCapabilities(
                minimum: 1_200, maximum: 5_000, step: 10, provenance: .deviceVerified
            ), writeAvailability: availability
        )
    }

    static func external(
        availability: WriteAvailability = .ready,
        provenance: CapabilityProvenance = .deterministicMock,
        stop: Bool = false
    ) -> FanDeviceState {
        FanDeviceState(
            id: "flydigi:37d7:1004", name: "Flydigi BS3 Pro", kind: .external,
            connection: availability == .disconnected ? .disconnected : .connected,
            currentSpeed: 1_700, capabilities: SpeedCapabilities(
                minimum: 1_300, maximum: 4_000, step: 100,
                provenance: provenance, supportsVerifiedStop: stop
            ), writeAvailability: availability
        )
    }
}

