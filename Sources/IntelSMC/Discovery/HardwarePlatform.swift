import Darwin

public enum HardwarePlatform {
    /// True on Apple Silicon, including an Intel slice running under Rosetta.
    public static let isAppleSilicon: Bool = sysctlFlag("sysctl.proc_translated") || sysctlFlag("hw.optional.arm64")

    /// `machdep.cpu.brand_string`, e.g. "Apple M4 Pro" or "Intel(R) Core(TM) i9-9980HK CPU @ 2.40GHz".
    public static let brandString: String = sysctlString("machdep.cpu.brand_string") ?? ""

    private static func sysctlFlag(_ name: String) -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 && value == 1
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
}

/// The SoC family, used to pick SMC sensor keys that change with every Apple Silicon generation.
/// Mirrors Stats' `Platform` (Kit/plugins/SystemKit.swift), but unknown future chips degrade to
/// `.unknownAppleSilicon` (generic keys + HID sensors) instead of being unsupported.
public enum ChipPlatform: Hashable, Sendable {
    public enum Tier: String, Hashable, Sendable, CaseIterable { case base, pro, max, ultra }

    case intel
    /// M-series with a known sensor-key table (generations 1–5).
    case appleSilicon(generation: Int, tier: Tier)
    /// Apple Silicon whose keys are not catalogued (newer M-series, A-series Macs, Rosetta's "VirtualApple").
    case unknownAppleSilicon

    public static let knownGenerations = 1...5

    public static let current: ChipPlatform = resolve(
        brandString: HardwarePlatform.brandString,
        isAppleSilicon: HardwarePlatform.isAppleSilicon
    )

    /// Rosetta reports a generic brand string, so the runtime architecture check wins over the name.
    public static func resolve(brandString: String, isAppleSilicon: Bool) -> ChipPlatform {
        let parsed = parse(brandString: brandString)
        switch (parsed, isAppleSilicon) {
        case (.intel, true): return .unknownAppleSilicon
        case (.unknownAppleSilicon, false) where brandString.isEmpty: return .intel
        default: return parsed
        }
    }

    public static func parse(brandString: String) -> ChipPlatform {
        let name = brandString.lowercased()
        if name.contains("intel") { return .intel }
        // Whole-token match ("m1" must not match "m10"), unlike Stats' substring test.
        guard let match = name.range(of: #"\bm([0-9]+)\b"#, options: .regularExpression),
              let generation = Int(name[match].dropFirst()) else {
            return .unknownAppleSilicon
        }
        guard knownGenerations.contains(generation) else { return .unknownAppleSilicon }
        let tier: Tier
        if name.contains("ultra") { tier = .ultra }
        else if name.contains("max") { tier = .max }
        else if name.contains("pro") { tier = .pro }
        else { tier = .base }
        return .appleSilicon(generation: generation, tier: tier)
    }

    public var isAppleSilicon: Bool { self != .intel }
}
