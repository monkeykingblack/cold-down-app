import Foundation
import ThermalCore

enum Fixtures {
    static let now = Date(timeIntervalSince1970: 10_000)

    /// A throwaway defaults suite. Call `cleanUp` (usually in `defer`): removing the domain alone leaves its
    /// plist behind in ~/Library/Preferences, one per test run.
    static func temporaryDefaults(_ prefix: String) -> (defaults: UserDefaults, suite: String, cleanUp: () -> Void) {
        let suite = "\(prefix).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, suite, {
            defaults.removePersistentDomain(forName: suite)
            let file = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(suite).plist")
            try? FileManager.default.removeItem(at: file)
        })
    }

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

    static func external(
        availability: WriteAvailability = .ready,
        provenance: CapabilityProvenance = .deterministicMock,
        stop: Bool = false
    ) -> FanDeviceState {
        FanDeviceState(
            id: "flydigi:37d7:1004", name: "Flydigi BS3 Pro",
            connection: availability == .disconnected ? .disconnected : .connected,
            currentSpeed: 1_700, capabilities: SpeedCapabilities(
                minimum: 1_300, maximum: 4_000, step: 100,
                provenance: provenance, supportsVerifiedStop: stop
            ), writeAvailability: availability
        )
    }
}

