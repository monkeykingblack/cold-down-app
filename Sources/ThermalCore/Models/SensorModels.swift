import Foundation

public enum SensorGroup: String, Codable, CaseIterable, Sendable {
    case cpu = "CPU"
    case gpu = "GPU"
    case heatsink = "Heatsink"
    case memory = "Memory"
    case pch = "PCH"
    case battery = "Battery"
    case ambient = "Ambient"
    case other = "Other"
}

public enum ReadingState: String, Codable, Sendable {
    case fresh
    case stale
    case unavailable
    case invalid
}

public struct SensorIdentity: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let rawKey: String
    public let name: String
    public let group: SensorGroup
    /// Whether the sensor feeds its group's average. Like Stats, Intel CPU averages only the per-core sensors;
    /// proximity, package and uncore keys sit well below the cores and would drag the average down.
    public let countsTowardAverage: Bool

    public init(rawKey: String, name: String, group: SensorGroup, idPrefix: String = "smc", countsTowardAverage: Bool = true) {
        self.id = "\(idPrefix):\(rawKey)"
        self.rawKey = rawKey
        self.name = name
        self.group = group
        self.countsTowardAverage = countsTowardAverage
    }
}

public struct SensorReading: Identifiable, Codable, Hashable, Sendable {
    public let identity: SensorIdentity
    public let valueCelsius: Double?
    public let timestamp: Date
    public let state: ReadingState

    public var id: String { identity.id }

    public init(identity: SensorIdentity, valueCelsius: Double?, timestamp: Date, state: ReadingState) {
        self.identity = identity
        self.valueCelsius = valueCelsius
        self.timestamp = timestamp
        self.state = state
    }

    public var isValid: Bool {
        guard state == .fresh, let valueCelsius else { return false }
        return valueCelsius.isFinite && (-20...125).contains(valueCelsius)
    }
}

public struct SensorBatch: Codable, Sendable {
    public let generation: UInt64
    public let sampledAt: Date
    public let readings: [SensorReading]

    public init(generation: UInt64, sampledAt: Date, readings: [SensorReading]) {
        self.generation = generation
        self.sampledAt = sampledAt
        self.readings = readings
    }
}

public enum CalculatedSensorKind: String, Codable, CaseIterable, Sendable {
    case cpuAverage
    case gpuAverage
    case allAverage
    case hottest

    public var displayName: String {
        switch self {
        case .cpuAverage: "CPU average"
        case .gpuAverage: "GPU average"
        case .allAverage: "All-sensor average"
        case .hottest: "Hottest sensor"
        }
    }
}

public struct SensorSummary: Codable, Sendable {
    public let readings: [SensorReading]
    public let calculated: [CalculatedSensorKind: Double]
    public let hottestByGroup: [SensorGroup: SensorReading]
    public let generatedAt: Date

    public init(
        readings: [SensorReading],
        calculated: [CalculatedSensorKind: Double],
        hottestByGroup: [SensorGroup: SensorReading],
        generatedAt: Date
    ) {
        self.readings = readings
        self.calculated = calculated
        self.hottestByGroup = hottestByGroup
        self.generatedAt = generatedAt
    }

    public static func empty(at date: Date = Date()) -> SensorSummary {
        SensorSummary(readings: [], calculated: [:], hottestByGroup: [:], generatedAt: date)
    }

    public var hottestReading: SensorReading? {
        readings.filter(\.isValid).max { ($0.valueCelsius ?? -.infinity) < ($1.valueCelsius ?? -.infinity) }
    }
}
