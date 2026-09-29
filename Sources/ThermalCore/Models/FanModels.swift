import Foundation

public enum ConnectionState: String, Codable, Sendable { case connected, disconnected }
public enum FanControlMode: String, Codable, CaseIterable, Sendable { case auto, manual }
public enum CapabilityProvenance: String, Codable, Sendable {
    case unverified, deviceVerified, auditedModel, deterministicMock
}
public enum WriteAvailability: String, Codable, Sendable {
    case ready, disconnected, capabilityLimited, invalidCapabilities, awaitingAcknowledgement
}

public struct SpeedCapabilities: Codable, Hashable, Sendable {
    public let minimum: Int
    public let maximum: Int
    public let step: Int
    public let unit: String
    public let provenance: CapabilityProvenance
    public let supportsVerifiedStop: Bool

    public init(
        minimum: Int,
        maximum: Int,
        step: Int = 1,
        unit: String = "RPM",
        provenance: CapabilityProvenance,
        supportsVerifiedStop: Bool = false
    ) {
        self.minimum = minimum
        self.maximum = maximum
        self.step = step
        self.unit = unit
        self.provenance = provenance
        self.supportsVerifiedStop = supportsVerifiedStop
    }

    public var isStructurallyValid: Bool {
        step > 0 && maximum >= minimum && (supportsVerifiedStop ? minimum >= 0 : minimum > 0)
    }

    public func clamped(_ value: Int) -> Int {
        guard isStructurallyValid else { return minimum }
        let bounded = min(max(value, minimum), maximum)
        let offset = bounded - minimum
        let rounded = Int((Double(offset) / Double(step)).rounded()) * step + minimum
        return min(max(rounded, minimum), maximum)
    }

    public func permitsRealHardwareWrites() -> Bool {
        isStructurallyValid && (provenance == .deviceVerified || provenance == .auditedModel)
    }
}

public struct FanDeviceState: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public var connection: ConnectionState
    public var currentSpeed: Int?
    public var targetSpeed: Int?
    public var reportedMode: FanControlMode?
    public var capabilities: SpeedCapabilities?
    public var writeAvailability: WriteAvailability
    public var statusMessage: String?

    public init(
        id: String,
        name: String,
        connection: ConnectionState,
        currentSpeed: Int? = nil,
        targetSpeed: Int? = nil,
        reportedMode: FanControlMode? = nil,
        capabilities: SpeedCapabilities? = nil,
        writeAvailability: WriteAvailability,
        statusMessage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.connection = connection
        self.currentSpeed = currentSpeed
        self.targetSpeed = targetSpeed
        self.reportedMode = reportedMode
        self.capabilities = capabilities
        self.writeAvailability = writeAvailability
        self.statusMessage = statusMessage
    }
}

public enum SensorSelection: Codable, Hashable, Sendable {
    case physical(String)
    case calculated(CalculatedSensorKind)

    public var displayName: String {
        switch self {
        case let .physical(id): id
        case let .calculated(kind): kind.displayName
        }
    }
}

public struct FanProfile: Codable, Hashable, Sendable {
    public var mode: FanControlMode
    public var selectedSensor: SensorSelection
    public var thresholdCelsius: Int
    public var manualTarget: Int

    public init(
        mode: FanControlMode = .auto,
        selectedSensor: SensorSelection = .calculated(.cpuAverage),
        // The cooler idles below this and ramps to full speed by +10 °C.
        thresholdCelsius: Int = 65,
        manualTarget: Int = 2_000
    ) {
        self.mode = mode
        self.selectedSensor = selectedSensor
        self.thresholdCelsius = min(max(thresholdCelsius, 45), 85)
        self.manualTarget = manualTarget
    }

    public func validated(for fan: FanDeviceState) -> FanProfile {
        var result = self
        result.thresholdCelsius = min(max(thresholdCelsius, 45), 85)
        if let capabilities = fan.capabilities, capabilities.isStructurallyValid {
            result.manualTarget = capabilities.clamped(manualTarget)
        }
        return result
    }

    /// What a fan follows until the user saves a profile for it: Auto on the CPU average (the hottest reading
    /// on a Mac without CPU sensors), with the fan's current speed as the Manual starting point.
    public static func suggested(for fan: FanDeviceState, summary: SensorSummary) -> FanProfile {
        FanProfile(
            selectedSensor: summary.calculated[.cpuAverage] == nil ? .calculated(.hottest) : .calculated(.cpuAverage),
            manualTarget: fan.currentSpeed ?? fan.capabilities?.minimum ?? 1
        ).validated(for: fan)
    }
}

public enum ThermalBand: Int, Codable, Comparable, Sendable {
    case cool = 0, warm = 1, hot = 2, safetyFallback = 3, critical = 4
    public static func < (lhs: ThermalBand, rhs: ThermalBand) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct ProfileDemand: Codable, Hashable, Sendable {
    public let fanID: String
    public let temperatureCelsius: Double
    public let thresholdCelsius: Int
    public let band: ThermalBand
    public let normalizedProgress: Double
}

public enum ExternalCoolingAction: Codable, Equatable, Sendable {
    case none
    case stop
    case target(Int)
}

public struct CoolingDecision: Codable, Equatable, Sendable {
    public let band: ThermalBand
    public let demand: ProfileDemand?
    public let externalAction: ExternalCoolingAction
    public let reason: String?
    public let evaluatedAt: Date

    public init(
        band: ThermalBand,
        demand: ProfileDemand? = nil,
        externalAction: ExternalCoolingAction = .none,
        reason: String? = nil,
        evaluatedAt: Date
    ) {
        self.band = band
        self.demand = demand
        self.externalAction = externalAction
        self.reason = reason
        self.evaluatedAt = evaluatedAt
    }
}

