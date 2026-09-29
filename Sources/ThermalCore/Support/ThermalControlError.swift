import Foundation

public enum ThermalControlError: Error, LocalizedError, Equatable, Sendable {
    case unavailable(String)
    case invalidData(String)
    case invalidCapabilities
    case forbiddenCommand
    case timeout
    case disconnected
    case acknowledgementRejected

    public var errorDescription: String? {
        switch self {
        case let .unavailable(message), let .invalidData(message): message
        case .invalidCapabilities: "Device capabilities are not safe for control."
        case .forbiddenCommand: "The requested hardware command is forbidden."
        case .timeout: "The hardware request timed out."
        case .disconnected: "The device is disconnected."
        case .acknowledgementRejected: "The device rejected the request."
        }
    }
}

