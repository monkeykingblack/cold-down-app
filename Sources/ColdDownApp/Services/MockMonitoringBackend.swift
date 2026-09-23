import Foundation
import ThermalCore

actor MockMonitoringBackend: SensorProvider, BuiltInFanReader {
    private var generation: UInt64 = 0
    private var tick = 0
    private let noSensors: Bool
    private let helperAvailable: Bool
    private let twoFans: Bool

    init(noSensors: Bool = false, helperAvailable: Bool = true, twoFans: Bool = false) {
        self.noSensors = noSensors
        self.helperAvailable = helperAvailable
        self.twoFans = twoFans
    }

    func readSensors() -> SensorBatch {
        generation &+= 1; tick += 1
        let now = Date()
        guard !noSensors else { return SensorBatch(generation: generation, sampledAt: now, readings: []) }
        let wave = sin(Double(tick) / 8)
        let values: [(String, String, SensorGroup, Double)] = [
            ("TC0P", "CPU proximity", .cpu, 67 + wave * 6),
            ("TC0D", "CPU die", .cpu, 71 + wave * 7),
            ("TG0P", "GPU proximity", .gpu, 58 + wave * 4),
            ("Th0H", "Main heatsink", .heatsink, 55 + wave * 3),
            ("Tm0P", "Memory proximity", .memory, 47 + wave * 2),
            ("TPCD", "PCH die", .pch, 51 + wave * 2),
            ("TB0T", "Battery", .battery, 32 + wave),
            ("TA0P", "Ambient", .ambient, 27 + wave)
        ]
        return SensorBatch(generation: generation, sampledAt: now, readings: values.map {
            SensorReading(
                identity: SensorIdentity(rawKey: $0.0, name: $0.1, group: $0.2),
                valueCelsius: $0.3, timestamp: now, state: .fresh
            )
        })
    }

    func listFans() -> [FanDeviceState] {
        let names = twoFans ? ["Left fan", "Right fan"] : ["Mac fan"]
        return names.enumerated().map { index, name in
            FanDeviceState(
                id: "builtin:\(index)", name: name, kind: .builtIn, connection: .connected,
                currentSpeed: 2_100 + index * 180 + tick * 7 % 300, targetSpeed: nil, reportedMode: .auto,
                capabilities: SpeedCapabilities(minimum: 1_200, maximum: 5_500 + index * 300, step: 10, provenance: .deviceVerified),
                writeAvailability: helperAvailable ? .ready : .helperMissing,
                statusMessage: helperAvailable ? nil : "Install the helper to enable built-in fan control"
            )
        }
    }
}

