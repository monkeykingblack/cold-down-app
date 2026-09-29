import Foundation
import ThermalCore

actor MockSensorBackend: SensorProvider {
    private var generation: UInt64 = 0
    private var tick = 0
    private let noSensors: Bool

    init(noSensors: Bool = false) {
        self.noSensors = noSensors
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
}
