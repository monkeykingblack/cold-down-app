import Foundation

public struct SensorAggregator: Sendable {
    private var latestGeneration: UInt64?
    private var readingsByID: [String: SensorReading] = [:]

    public init() {}

    public mutating func ingest(
        _ batch: SensorBatch,
        now: Date,
        refreshInterval: TimeInterval
    ) -> SensorSummary {
        if let latestGeneration, batch.generation < latestGeneration {
            return summarize(now: now, refreshInterval: refreshInterval)
        }

        let acceptingNewGeneration = latestGeneration == nil || batch.generation > latestGeneration!
        if acceptingNewGeneration { latestGeneration = batch.generation }
        var seen = Set<String>()

        for candidate in batch.readings {
            seen.insert(candidate.id)
            if let existing = readingsByID[candidate.id] {
                if candidate.timestamp < existing.timestamp { continue }
                if candidate.timestamp == existing.timestamp {
                    if candidate == existing { continue }
                    continue
                }
            }
            readingsByID[candidate.id] = Self.validated(candidate)
        }

        if acceptingNewGeneration {
            for (id, existing) in readingsByID where !seen.contains(id) {
                readingsByID[id] = SensorReading(
                    identity: existing.identity,
                    valueCelsius: nil,
                    timestamp: batch.sampledAt,
                    state: .unavailable
                )
            }
        }
        return summarize(now: now, refreshInterval: refreshInterval)
    }

    public mutating func current(now: Date, refreshInterval: TimeInterval) -> SensorSummary {
        summarize(now: now, refreshInterval: refreshInterval)
    }

    public static func validated(_ reading: SensorReading) -> SensorReading {
        guard let value = reading.valueCelsius, value.isFinite, (-20...125).contains(value) else {
            return SensorReading(
                identity: reading.identity,
                valueCelsius: nil,
                timestamp: reading.timestamp,
                state: reading.state == .unavailable ? .unavailable : .invalid
            )
        }
        return reading
    }

    private mutating func summarize(now: Date, refreshInterval: TimeInterval) -> SensorSummary {
        let staleAfter = max(refreshInterval * 3, 6)
        for (id, reading) in readingsByID where reading.state == .fresh {
            if now.timeIntervalSince(reading.timestamp) > staleAfter {
                readingsByID[id] = SensorReading(
                    identity: reading.identity,
                    valueCelsius: reading.valueCelsius,
                    timestamp: reading.timestamp,
                    state: .stale
                )
            }
        }

        // Fully deterministic order: several Apple Silicon HID sensors share a name, and ties must not fall back
        // to dictionary order, which changes between refreshes and makes lists jump around.
        let readings = readingsByID.values.sorted {
            if $0.identity.group != $1.identity.group { return $0.identity.group.rawValue < $1.identity.group.rawValue }
            if $0.identity.name != $1.identity.name { return $0.identity.name < $1.identity.name }
            return $0.id < $1.id
        }
        let valid = readings.filter(\.isValid)
        var calculated: [CalculatedSensorKind: Double] = [:]
        let cpu = Self.averageInputs(valid, group: .cpu)
        let gpu = Self.averageInputs(valid, group: .gpu)
        let all = valid.compactMap(\.valueCelsius)
        if !cpu.isEmpty { calculated[.cpuAverage] = cpu.reduce(0, +) / Double(cpu.count) }
        if !gpu.isEmpty { calculated[.gpuAverage] = gpu.reduce(0, +) / Double(gpu.count) }
        if !all.isEmpty {
            calculated[.allAverage] = all.reduce(0, +) / Double(all.count)
            calculated[.hottest] = all.max()
        }
        var byGroup: [SensorGroup: SensorReading] = [:]
        for reading in valid {
            if let current = byGroup[reading.identity.group],
               (current.valueCelsius ?? -.infinity) >= (reading.valueCelsius ?? -.infinity) { continue }
            byGroup[reading.identity.group] = reading
        }
        return SensorSummary(readings: readings, calculated: calculated, hottestByGroup: byGroup, generatedAt: now)
    }

    /// The group's averaged sensors, or every sensor in the group when the machine exposes none of them.
    private static func averageInputs(_ readings: [SensorReading], group: SensorGroup) -> [Double] {
        let inGroup = readings.filter { $0.identity.group == group }
        let averaged = inGroup.filter(\.identity.countsTowardAverage)
        return (averaged.isEmpty ? inGroup : averaged).compactMap(\.valueCelsius)
    }
}

public extension SensorSummary {
    func temperature(for selection: SensorSelection) -> Double? {
        switch selection {
        case let .physical(id):
            return readings.first { $0.id == id && $0.isValid }?.valueCelsius
        case let .calculated(kind):
            return calculated[kind]
        }
    }

    var hasFreshTemperature: Bool { readings.contains(where: \.isValid) }
}

