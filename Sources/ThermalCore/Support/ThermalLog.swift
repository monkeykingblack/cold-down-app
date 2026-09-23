import Foundation
import OSLog

public enum ThermalLog {
    private static let subsystem = "com.example.ColdDown"
    public static let smc = Logger(subsystem: subsystem, category: "SMC")
    public static let hid = Logger(subsystem: subsystem, category: "HID")
    public static let policy = Logger(subsystem: subsystem, category: "Policy")
    public static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    public static let xpc = Logger(subsystem: subsystem, category: "XPC")
    public static let safety = Logger(subsystem: subsystem, category: "Safety")
}
