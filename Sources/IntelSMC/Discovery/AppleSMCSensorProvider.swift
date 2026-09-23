import Foundation
import ThermalCore

public actor AppleSMCSensorProvider: SensorProvider {
    /// Stats drops SMC temperatures of exactly 0 (unpopulated keys) or above 110 °C (garbage); so do we.
    public static let plausibleRange: ClosedRange<Double> = 0.001...110

    private let connection: AppleSMCConnection?
    private let chip: ChipPlatform
    private var generation: UInt64 = 0
    private var cachedKeys: [String] = []

    public init(connection: AppleSMCConnection? = try? AppleSMCConnection(), chip: ChipPlatform = .current) {
        self.connection = connection
        self.chip = chip
    }

    public func readSensors() async throws -> SensorBatch {
        generation &+= 1
        let sampledAt = Date()
        guard let connection else { return SensorBatch(generation: generation, sampledAt: sampledAt, readings: []) }
        if cachedKeys.isEmpty || generation.isMultiple(of: 30) {
            cachedKeys = (try? connection.allKeys()) ?? []
        }
        let candidates = Self.sensorCandidates(chip: chip, availableKeys: cachedKeys)
        var readings: [SensorReading] = []
        for identity in candidates {
            guard let value = try? connection.read(identity.rawKey),
                  SMCSensorCatalog.looksLikeTemperature(key: identity.rawKey, type: value.dataType),
                  let temperature = try? SMCValueCodec.decodeTemperature(data: value.bytes, type: value.dataType),
                  Self.plausibleRange.contains(temperature) else { continue }
            readings.append(SensorReading(identity: identity, valueCelsius: temperature, timestamp: sampledAt, state: .fresh))
        }
        return SensorBatch(generation: generation, sampledAt: sampledAt, readings: readings)
    }

    /// Which keys to read on `chip`: on Intel every `T…` key the SMC reports (named generically);
    /// on Apple Silicon only the catalogued keys for that generation that the SMC actually has, because the
    /// generic Intel prefixes (e.g. `TP…` = PCH) mean something else there.
    public static func sensorCandidates(chip: ChipPlatform, availableKeys: [String]) -> [SensorIdentity] {
        guard chip.isAppleSilicon else {
            return availableKeys.filter { $0.first == "T" }.map(SMCSensorCatalog.identity(for:))
        }
        let available = Set(availableKeys)
        var seen = Set<String>()
        return AppleSiliconSMCSensorKeys.definitions(for: chip)
            .filter { available.contains($0.key) && seen.insert($0.key).inserted }
            .map { $0.identity() }
    }
}
