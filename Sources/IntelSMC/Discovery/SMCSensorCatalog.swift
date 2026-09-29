import Foundation
import ThermalCore

public enum SMCSensorCatalog {
    private static let known: [String: (String, SensorGroup)] = [
        "TC0P": ("CPU proximity", .cpu), "TC0D": ("CPU diode", .cpu),
        "TC0E": ("CPU diode virtual", .cpu), "TC0F": ("CPU diode filtered", .cpu),
        "TG0P": ("GPU proximity", .gpu), "TG0D": ("GPU die", .gpu),
        "Th0H": ("Main heatsink", .heatsink), "Tm0P": ("Memory proximity", .memory),
        "TPCD": ("PCH die", .pch), "TB0T": ("Battery", .battery),
        "TA0P": ("Ambient", .ambient), "TCGC": ("GPU Intel Graphics", .gpu)
    ]

    public static func identity(for key: String) -> SensorIdentity {
        if let core = cpuCoreNumber(key) {
            return SensorIdentity(rawKey: key, name: "CPU core \(core)", group: .cpu)
        }
        // Only per-core keys feed the CPU average (Stats' `TC%C`); other `TC…` keys are proximity/package/uncore.
        if let entry = known[key] {
            return SensorIdentity(rawKey: key, name: entry.0, group: entry.1, countsTowardAverage: entry.1 != .cpu)
        }
        let upper = key.uppercased()
        if upper.hasPrefix("TC") {
            return SensorIdentity(rawKey: key, name: "CPU temperature", group: .cpu, countsTowardAverage: false)
        }
        let group: SensorGroup
        let name: String
        if upper.hasPrefix("TG") { group = .gpu; name = "GPU temperature" }
        else if upper.hasPrefix("TH") { group = .heatsink; name = "Heatsink temperature" }
        else if upper.hasPrefix("TM") { group = .memory; name = "Memory temperature" }
        else if upper.hasPrefix("TP") { group = .pch; name = "PCH temperature" }
        else if upper.hasPrefix("TB") { group = .battery; name = "Battery temperature" }
        else if upper.hasPrefix("TA") { group = .ambient; name = "Ambient temperature" }
        else { group = .other; name = "Temperature sensor \(key)" }
        return SensorIdentity(rawKey: key, name: name, group: group)
    }

    /// The core number of an Intel per-core key (`TC1C`, `TC2c`, …), or nil for any other key.
    static func cpuCoreNumber(_ key: String) -> Int? {
        let characters = Array(key)
        guard characters.count == 4, characters[0] == "T", characters[1] == "C",
              characters[3] == "C" || characters[3] == "c" else { return nil }
        return characters[2].wholeNumberValue
    }

    public static func looksLikeTemperature(key: String, type: String) -> Bool {
        guard key.count == 4, key.first == "T" else { return false }
        // Types are four characters, so the float type arrives as "flt " (with a trailing space).
        let normalized = type.trimmingCharacters(in: .controlCharacters.union(.whitespaces).union(CharacterSet(charactersIn: "\0")))
        return normalized == "sp78" || normalized == "fpe2" || normalized == "flt"
    }
}

