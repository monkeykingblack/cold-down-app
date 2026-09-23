import Foundation
import ThermalCore

public actor PlatformSensorProvider: SensorProvider {
    private let isAppleSiliconHardware: Bool
    private let smcProvider: AppleSMCSensorProvider
    private let hidProvider: AppleSiliconHIDSensorProvider
    private var generation: UInt64 = 0

    public init(chip: ChipPlatform = .current) {
        isAppleSiliconHardware = chip.isAppleSilicon
        smcProvider = AppleSMCSensorProvider(chip: chip)
        hidProvider = AppleSiliconHIDSensorProvider()
    }

    public func readSensors() async throws -> SensorBatch {
        generation &+= 1
        let smc = try await smcProvider.readSensors()
        var readings = smc.readings
        var sampledAt = smc.sampledAt
        if isAppleSiliconHardware {
            // Like Stats with HID enabled: the chip's SMC core keys and the HID die sensors are merged.
            // HID readings use a distinct "hid:" id prefix, so they never collide with SMC keys, and they keep
            // CPU/GPU averages available on chips whose SMC keys are not catalogued yet.
            let hid = try await hidProvider.readSensors()
            readings += hid.readings
            sampledAt = max(sampledAt, hid.sampledAt)
        }
        return SensorBatch(generation: generation, sampledAt: sampledAt, readings: readings)
    }
}
