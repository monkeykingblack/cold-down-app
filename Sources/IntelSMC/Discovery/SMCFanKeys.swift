import Foundation

/// Fan key naming and mode semantics, following Stats (SMC/smc.swift `fanModeKey`, `FanMode`).
public enum SMCFanKeys {
    /// Intel Macs with a global forced-mode bitmask (bit n = fan n forced).
    public static let legacyModeMask = "FS! "
    /// Apple Silicon (M1–M4) test-mode unlock that makes thermalmonitord yield fan control.
    public static let unlock = "Ftst"

    public static func key(_ index: Int, _ suffix: String) -> String {
        "F\(String(index, radix: 16).uppercased())\(suffix)"
    }

    /// Newer Apple Silicon names the per-fan mode key in lowercase (`F0md`); others use `F0Md`.
    public static func modeKey(_ index: Int, lowercase: Bool) -> String {
        key(index, lowercase ? "md" : "Md")
    }

    /// Mode byte values: 0 = automatic, 1 = forced (manual), 3 = system-controlled (Apple Silicon; treated as auto).
    public static func isForced(modeByte: UInt8) -> Bool { modeByte == 1 }
}
