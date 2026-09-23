import Foundation
import ThermalCore

/// Control semantics ported from THRM (internal/device/device.go):
/// - enter realtime mode (0x23) once and cache it; re-enter only after the device reports it left realtime
///   (0xEF push with mode bit 0 clear, or 0x21 answering "not realtime"), since re-sending it on every tick
///   interrupts the control session;
/// - skip writes that change the target by less than 50 RPM;
/// - read measured RPM from the device's 0xEF pushes rather than assuming the target was reached;
/// - on release, leave realtime mode (0x24) so the cooler returns to its own gear. THRM just closes the handle,
///   which leaves the last realtime target running.
public actor BS3ProController: ExternalCoolerController {
    /// Range THRM uses for realtime control is 0...5000; 1000 is the practical floor and 4000 the top factory gear.
    public static let auditedCapabilities = SpeedCapabilities(
        minimum: 1_000, maximum: 4_000, step: 50, provenance: .auditedModel
    )
    static let minimumChange = 50

    private let transport: any FlydigiReportTransport
    private let executor: FlydigiTransactionExecutor
    private let capabilities: SpeedCapabilities?
    private let allowDeterministicMock: Bool
    private var measuredSpeed: Int?
    private var operatingMode: FanControlMode?
    private var realtimeActive = false
    private var lastTarget: Int?

    public init(
        transport: any FlydigiReportTransport,
        capabilities: SpeedCapabilities? = nil,
        allowDeterministicMock: Bool = false
    ) {
        self.transport = transport
        self.executor = FlydigiTransactionExecutor(transport: transport)
        self.capabilities = capabilities
        self.allowDeterministicMock = allowDeterministicMock
    }

    public func connect() async {
        realtimeActive = false
        lastTarget = nil
        guard await transport.isConnected() else { return }
        if let rpmFrame = try? await executor.execute(command: .queryRPM), rpmFrame.payload.count >= 2 {
            measuredSpeed = Int(rpmFrame.payload[0]) | Int(rpmFrame.payload[1]) << 8
        }
        // Work mode 1-4 = one of the device's own gears, 5 = host realtime control.
        if let modeFrame = try? await executor.execute(command: .queryWorkMode), let mode = modeFrame.payload.first {
            realtimeActive = mode == 5
            operatingMode = realtimeActive ? .manual : .auto
        }
    }

    public func state() async -> FanDeviceState {
        let connected = await transport.isConnected()
        if connected, let status = await transport.latestStatus() {
            measuredSpeed = status.currentRPM
            operatingMode = status.realtimeActive ? .manual : .auto
            if !status.realtimeActive, realtimeActive {
                // A physical gear change or reconnect ended the realtime session.
                realtimeActive = false
                lastTarget = nil
            }
        }
        let productID = await transport.connectedProductID() ?? 0x1004
        let ready = connected && capabilities.map(canWrite) == true
        return FanDeviceState(
            id: "flydigi:37d7:1004", name: Self.name(for: productID), kind: .external,
            connection: connected ? .connected : .disconnected,
            currentSpeed: connected ? measuredSpeed : nil, targetSpeed: lastTarget,
            reportedMode: operatingMode, capabilities: capabilities,
            writeAvailability: !connected ? .disconnected : (ready ? .ready : .capabilityLimited),
            statusMessage: !connected ? "Cooler is not connected" : (ready ? nil : "Speed range is not yet verified")
        )
    }

    public func setTarget(_ speed: Int) async throws -> AcknowledgedTarget {
        guard await transport.isConnected() else { throw ThermalControlError.disconnected }
        guard let capabilities, canWrite(capabilities) else { throw ThermalControlError.invalidCapabilities }
        let target = capabilities.clamped(speed)
        if realtimeActive, let lastTarget, abs(lastTarget - target) < Self.minimumChange {
            return AcknowledgedTarget(target: lastTarget, acknowledgedAt: Date())
        }
        do {
            try await writeRealtime(target)
        } catch ThermalControlError.acknowledgementRejected {
            // 0x21 answers 2 when realtime mode was lost; re-enter once and retry.
            realtimeActive = false
            try await writeRealtime(target)
        } catch {
            realtimeActive = false
            lastTarget = nil
            throw error
        }
        lastTarget = target
        operatingMode = .manual
        return AcknowledgedTarget(target: target, acknowledgedAt: Date())
    }

    /// Hands control back to the cooler's own gear setting.
    public func releaseControl() async {
        guard realtimeActive, await transport.isConnected() else { return }
        _ = try? await executor.execute(command: .exitRealtimeRPM)
        realtimeActive = false
        lastTarget = nil
        operatingMode = .auto
    }

    private func writeRealtime(_ target: Int) async throws {
        if !realtimeActive {
            _ = try await executor.execute(command: .enterRealtimeRPM)
            realtimeActive = true
        }
        let value = UInt16(target)
        _ = try await executor.execute(command: .setRealtimeRPM, payload: Data([UInt8(value & 0xFF), UInt8(value >> 8)]))
    }

    private func canWrite(_ value: SpeedCapabilities) -> Bool {
        value.permitsRealHardwareWrites()
            || (allowDeterministicMock && value.isStructurallyValid && value.provenance == .deterministicMock)
    }

    static func name(for productID: Int) -> String {
        switch productID {
        case 0x1001: "Flydigi BS2"
        case 0x1002: "Flydigi BS2 Pro"
        case 0x1003: "Flydigi BS3"
        default: "Flydigi BS3 Pro"
        }
    }
}
