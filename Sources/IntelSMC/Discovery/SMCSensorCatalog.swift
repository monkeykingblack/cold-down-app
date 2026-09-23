import Foundation
import ThermalCore

public enum SMCSensorCatalog {
    private static let known: [String: (String, SensorGroup)] = [
        "TC0P": ("CPU proximity", .cpu), "TC0D": ("CPU die", .cpu),
        "TC0E": ("CPU core", .cpu), "TC0F": ("CPU core", .cpu),
        "TG0P": ("GPU proximity", .gpu), "TG0D": ("GPU die", .gpu),
        "Th0H": ("Main heatsink", .heatsink), "Tm0P": ("Memory proximity", .memory),
        "TPCD": ("PCH die", .pch), "TB0T": ("Battery", .battery),
        "TA0P": ("Ambient", .ambient)
    ]

    public static func identity(for key: String) -> SensorIdentity {
        if let entry = known[key] { return SensorIdentity(rawKey: key, name: entry.0, group: entry.1) }
        let upper = key.uppercased()
        let group: SensorGroup
        let name: String
        if upper.hasPrefix("TC") { group = .cpu; name = "CPU temperature" }
        else if upper.hasPrefix("TG") { group = .gpu; name = "GPU temperature" }
        else if upper.hasPrefix("TH") { group = .heatsink; name = "Heatsink temperature" }
        else if upper.hasPrefix("TM") { group = .memory; name = "Memory temperature" }
        else if upper.hasPrefix("TP") { group = .pch; name = "PCH temperature" }
        else if upper.hasPrefix("TB") { group = .battery; name = "Battery temperature" }
        else if upper.hasPrefix("TA") { group = .ambient; name = "Ambient temperature" }
        else { group = .other; name = "Temperature sensor \(key)" }
        return SensorIdentity(rawKey: key, name: name, group: group)
    }

    public static func looksLikeTemperature(key: String, type: String) -> Bool {
        guard key.count == 4, key.first == "T" else { return false }
        // Types are four characters, so the float type arrives as "flt " (with a trailing space).
        let normalized = type.trimmingCharacters(in: .controlCharacters.union(.whitespaces).union(CharacterSet(charactersIn: "\0")))
        return normalized == "sp78" || normalized == "fpe2" || normalized == "flt"
    }
}

