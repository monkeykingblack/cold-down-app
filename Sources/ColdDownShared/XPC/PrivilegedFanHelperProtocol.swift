import Foundation
import ThermalCore

public let thermalHelperMachService = Bundle.main.object(
    forInfoDictionaryKey: "ThermalHelperMachService"
) as? String ?? "com.example.ColdDown.Helper"

public let thermalExpectedClientIdentifier = Bundle.main.object(
    forInfoDictionaryKey: "ThermalExpectedClientIdentifier"
) as? String ?? "com.example.ColdDown"

/// The Apple Developer team that must have signed the client app. Empty when the build is unsigned.
public let thermalExpectedClientTeamIdentifier = Bundle.main.object(
    forInfoDictionaryKey: "ThermalExpectedClientTeamIdentifier"
) as? String

public enum HelperClientRequirement {
    /// Builds the code-signing requirement the helper imposes on XPC clients.
    ///
    /// A valid team identifier is always pinned via the leaf certificate's OU; without it, any
    /// Developer ID app could claim the client's bundle identifier. When no team is configured,
    /// Debug builds fall back to an identifier-only requirement and Release builds get `nil`,
    /// meaning the helper must refuse every connection.
    public static func make(identifier: String, teamIdentifier: String?, allowUnpinnedTeam: Bool) -> String? {
        guard identifier.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil else { return nil }
        if let teamIdentifier, teamIdentifier.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil {
            return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        }
        return allowUnpinnedTeam ? "identifier \"\(identifier)\"" : nil
    }
}

public final class HelperFanRecord: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }
    public let fanID: String
    public let name: String
    public let currentRPM: Int
    public let minimumRPM: Int
    public let maximumRPM: Int
    public let targetRPM: Int?
    public let isAutomatic: Bool?

    public init(
        fanID: String, name: String, currentRPM: Int, minimumRPM: Int,
        maximumRPM: Int, targetRPM: Int?, isAutomatic: Bool?
    ) {
        self.fanID = fanID; self.name = name; self.currentRPM = currentRPM
        self.minimumRPM = minimumRPM; self.maximumRPM = maximumRPM
        self.targetRPM = targetRPM; self.isAutomatic = isAutomatic
    }

    public required init?(coder: NSCoder) {
        guard let fanID = coder.decodeObject(of: NSString.self, forKey: "fanID") as String?,
              let name = coder.decodeObject(of: NSString.self, forKey: "name") as String? else { return nil }
        self.fanID = fanID; self.name = name
        currentRPM = coder.decodeInteger(forKey: "currentRPM")
        minimumRPM = coder.decodeInteger(forKey: "minimumRPM")
        maximumRPM = coder.decodeInteger(forKey: "maximumRPM")
        targetRPM = coder.containsValue(forKey: "targetRPM") ? coder.decodeInteger(forKey: "targetRPM") : nil
        isAutomatic = coder.containsValue(forKey: "automatic") ? coder.decodeBool(forKey: "automatic") : nil
    }

    public func encode(with coder: NSCoder) {
        coder.encode(fanID, forKey: "fanID"); coder.encode(name, forKey: "name")
        coder.encode(currentRPM, forKey: "currentRPM"); coder.encode(minimumRPM, forKey: "minimumRPM")
        coder.encode(maximumRPM, forKey: "maximumRPM")
        if let targetRPM { coder.encode(targetRPM, forKey: "targetRPM") }
        if let isAutomatic { coder.encode(isAutomatic, forKey: "automatic") }
    }

    public func deviceState(writeAvailability: WriteAvailability = .ready) -> FanDeviceState {
        FanDeviceState(
            id: fanID, name: name, kind: .builtIn, connection: .connected,
            currentSpeed: currentRPM, targetSpeed: targetRPM,
            reportedMode: isAutomatic.map { $0 ? .auto : .manual },
            capabilities: SpeedCapabilities(
                minimum: minimumRPM, maximum: maximumRPM, provenance: .deviceVerified
            ),
            writeAvailability: writeAvailability
        )
    }
}

@objc public protocol PrivilegedFanHelperXPCProtocol {
    func listFans(reply: @escaping ([HelperFanRecord]?, NSError?) -> Void)
    func setFanAuto(fanID: String, reply: @escaping (NSError?) -> Void)
    func setFanTargetRPM(fanID: String, rpm: Int, reply: @escaping (Int, NSError?) -> Void)
    func restoreAllFansToAuto(reply: @escaping (Bool, NSError?) -> Void)
    func renewLease(reply: @escaping (Date?, NSError?) -> Void)
}

public enum HelperXPCInterface {
    public static func make() -> NSXPCInterface {
        let interface = NSXPCInterface(with: PrivilegedFanHelperXPCProtocol.self)
        let classes = NSSet(array: [NSArray.self, HelperFanRecord.self, NSError.self, NSString.self, NSDate.self])
            as! Set<AnyHashable>
        interface.setClasses(
            classes,
            for: #selector(PrivilegedFanHelperXPCProtocol.listFans(reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        return interface
    }
}
