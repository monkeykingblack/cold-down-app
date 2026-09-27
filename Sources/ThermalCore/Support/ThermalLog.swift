import Foundation
import OSLog

public enum ThermalLog {
    /// Taken from whichever bundle is running, so the app's and the helper's messages file under the
    /// identifiers they actually ship with. It used to be a literal `com.example.ColdDown`, which meant a
    /// build with its own identifiers still logged under the placeholder one and `log show` had to be told
    /// to look for a subsystem the app no longer had.
    private static let subsystem = Bundle.main.bundleIdentifier ?? "ColdDown"
    public static let smc = Logger(subsystem: subsystem, category: "SMC")
    public static let hid = Logger(subsystem: subsystem, category: "HID")
    public static let policy = Logger(subsystem: subsystem, category: "Policy")
    public static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    public static let xpc = Logger(subsystem: subsystem, category: "XPC")
    public static let safety = Logger(subsystem: subsystem, category: "Safety")
}
