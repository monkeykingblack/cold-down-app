import AppleSiliconHIDBridge
import Foundation
import ThermalCore

private final class HIDTemperatureCollector {
    var values: [(String, Double)] = []
}

public enum AppleSiliconHIDSensorCatalog {
    public static func identity(for rawKey: String) -> SensorIdentity {
        let lowercased = rawKey.lowercased()
        let name: String
        let group: SensorGroup

        switch lowercased {
        case let key where key.hasPrefix("pacc mtr temp sensor"):
            name = numberedName("CPU performance core", rawKey: rawKey)
            group = .cpu
        case let key where key.hasPrefix("eacc mtr temp sensor"):
            name = numberedName("CPU efficiency core", rawKey: rawKey)
            group = .cpu
        case let key where key.hasPrefix("gpu mtr temp sensor"):
            name = numberedName("GPU core", rawKey: rawKey)
            group = .gpu
        case let key where key.hasPrefix("soc mtr temp sensor"):
            name = numberedName("SoC core", rawKey: rawKey)
            group = .other
        case let key where key.hasPrefix("ane mtr temp sensor"):
            name = numberedName("Neural engine", rawKey: rawKey)
            group = .other
        case let key where key.hasPrefix("isp mtr temp sensor"):
            name = numberedName("Image signal processor", rawKey: rawKey)
            group = .other
        case let key where key.hasPrefix("pmgr soc die temp sensor"):
            name = numberedName("Power manager die", rawKey: rawKey)
            group = .other
        case let key where key.hasPrefix("pmu tdev"):
            name = numberedName("Power management unit device", rawKey: rawKey)
            group = .other
        case let key where key.hasPrefix("pmu tdie"):
            name = numberedName("Power management unit die", rawKey: rawKey)
            group = .other
        case let key where key == "gas gauge battery":
            name = "Battery"
            group = .battery
        case let key where key.hasPrefix("nand ch"):
            name = numberedName("NAND channel", rawKey: rawKey)
            group = .other
        default:
            name = rawKey
            group = .other
        }

        return SensorIdentity(rawKey: rawKey, name: name, group: group, idPrefix: "hid")
    }

    private static func numberedName(_ base: String, rawKey: String) -> String {
        let digits = rawKey.filter(\.isNumber)
        guard let zeroBasedIndex = Int(digits) else { return base }
        return "\(base) \(zeroBasedIndex + 1)"
    }
}

public actor AppleSiliconHIDSensorProvider: SensorProvider {
    private var generation: UInt64 = 0

    public init() {}

    public func readSensors() async throws -> SensorBatch {
        generation &+= 1
        let sampledAt = Date()

        let collector = HIDTemperatureCollector()
        let context = Unmanaged.passUnretained(collector).toOpaque()
        CDVisitAppleSiliconTemperatures({ name, value, context in
            guard let name, let context else { return }
            let collector = Unmanaged<HIDTemperatureCollector>
                .fromOpaque(context)
                .takeUnretainedValue()
            collector.values.append((String(cString: name), value))
        }, context)

        let readings = collector.values
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
            .map { rawKey, temperature -> SensorReading in
                let identity = AppleSiliconHIDSensorCatalog.identity(for: rawKey)
                guard temperature.isFinite, (0..<110).contains(temperature) else {
                    return SensorReading(
                        identity: identity,
                        valueCelsius: nil,
                        timestamp: sampledAt,
                        state: .invalid
                    )
                }
                return SensorReading(
                    identity: identity,
                    valueCelsius: temperature,
                    timestamp: sampledAt,
                    state: .fresh
                )
            }
        return SensorBatch(generation: generation, sampledAt: sampledAt, readings: readings)
    }
}
