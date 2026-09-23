import Foundation
import ThermalCore

/// A temperature key the SMC exposes on specific Apple Silicon generations.
public struct SMCSensorDefinition: Hashable, Sendable {
    public let key: String
    public let name: String
    public let group: SensorGroup
    /// nil = every Apple Silicon generation.
    public let generations: Set<Int>?
    /// nil = every tier of the matching generations.
    public let tiers: Set<ChipPlatform.Tier>?

    public init(_ key: String, _ name: String, _ group: SensorGroup, generations: Set<Int>? = nil, tiers: Set<ChipPlatform.Tier>? = nil) {
        self.key = key; self.name = name; self.group = group
        self.generations = generations; self.tiers = tiers
    }

    func applies(generation: Int, tier: ChipPlatform.Tier) -> Bool {
        (generations?.contains(generation) ?? true) && (tiers?.contains(tier) ?? true)
    }

    public func identity() -> SensorIdentity { SensorIdentity(rawKey: key, name: name, group: group) }
}

/// Apple Silicon SMC temperature keys per generation, ported from Stats' `SensorsList`
/// (Modules/Sensors/values.swift). Apple renames these keys with every SoC, so the table is
/// intersected with the keys the SMC actually reports before reading.
public enum AppleSiliconSMCSensorKeys {
    private static func cores(_ keys: [String], _ kind: String, generations: Set<Int>) -> [SMCSensorDefinition] {
        keys.enumerated().map { SMCSensorDefinition($1, "CPU \(kind) core \($0 + 1)", .cpu, generations: generations) }
    }

    private static func gpus(_ keys: [String], generations: Set<Int>, tiers: Set<ChipPlatform.Tier>? = nil, firstIndex: Int = 1) -> [SMCSensorDefinition] {
        keys.enumerated().map { SMCSensorDefinition($1, "GPU \($0 + firstIndex)", .gpu, generations: generations, tiers: tiers) }
    }

    public static let all: [SMCSensorDefinition] = {
        var list: [SMCSensorDefinition] = []
        // M1 (values.swift: "Apple Silicon" block)
        list += cores(["Tp09", "Tp0T"], "efficiency", generations: [1])
        list += cores(["Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"], "performance", generations: [1])
        list += gpus(["Tg05", "Tg0D", "Tg0L", "Tg0T"], generations: [1])
        list += ["Tm02", "Tm06", "Tm08", "Tm09"].enumerated().map { SMCSensorDefinition($1, "Memory \($0 + 1)", .memory, generations: [1]) }
        // M2
        list += cores(["Tp1h", "Tp1t", "Tp1p", "Tp1l"], "efficiency", generations: [2])
        list += cores(["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"], "performance", generations: [2])
        list += gpus(["Tg0f", "Tg0j"], generations: [2])
        // M3
        list += cores(["Te05", "Te0L", "Te0P", "Te0S"], "efficiency", generations: [3])
        list += cores(["Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"], "performance", generations: [3])
        list += gpus(["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"], generations: [3])
        // M4 — the first two GPU keys differ between the base chip and Pro/Max/Ultra.
        list += cores(["Te05", "Te0S", "Te09", "Te0H"], "efficiency", generations: [4])
        list += cores(["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"], "performance", generations: [4])
        list += gpus(["Tg0G", "Tg0H"], generations: [4], tiers: [.base])
        list += gpus(["Tg1U", "Tg1k"], generations: [4], tiers: [.pro, .max, .ultra])
        list += gpus(["Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"], generations: [4], firstIndex: 3)
        list += ["Tm0p", "Tm1p", "Tm2p"].enumerated().map { SMCSensorDefinition($1, "Memory proximity \($0 + 1)", .memory, generations: [4]) }
        // M5
        list += cores(["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K"], "super", generations: [5])
        list += cores(["Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"], "performance", generations: [5])
        list += gpus(["Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g"], generations: [5])
        list += common
        return list
    }()

    /// Keys shared by every Apple Silicon Mac; also the only table used for uncatalogued chips.
    public static let common: [SMCSensorDefinition] = [
        SMCSensorDefinition("TaLP", "Airflow left", .ambient),
        SMCSensorDefinition("TaRF", "Airflow right", .ambient),
        SMCSensorDefinition("TH0x", "NAND", .other),
        SMCSensorDefinition("TB1T", "Battery 1", .battery),
        SMCSensorDefinition("TB2T", "Battery 2", .battery),
        SMCSensorDefinition("TW0P", "Airport", .other)
    ]

    /// The definitions to probe on `chip`. Intel returns an empty list: its keys are discovered generically.
    public static func definitions(for chip: ChipPlatform) -> [SMCSensorDefinition] {
        switch chip {
        case .intel: return []
        case .unknownAppleSilicon: return common
        case let .appleSilicon(generation, tier): return all.filter { $0.applies(generation: generation, tier: tier) }
        }
    }
}
