import Foundation
import ThermalCore
import FlydigiHID

actor EventRecorder {
    private(set) var events: [String] = []
    func append(_ value: String) { events.append(value) }
    func values() -> [String] { events }
}

actor MockSensorProvider: SensorProvider {
    var batches: [SensorBatch]
    init(_ batches: [SensorBatch]) { self.batches = batches }
    func readSensors() throws -> SensorBatch {
        guard !batches.isEmpty else { throw ThermalControlError.unavailable("No batch") }
        return batches.count == 1 ? batches[0] : batches.removeFirst()
    }
}

actor MockFanReader: BuiltInFanReader {
    var fans: [FanDeviceState]
    init(_ fans: [FanDeviceState]) { self.fans = fans }
    func listFans() -> [FanDeviceState] { fans }
}

actor MockBuiltInController: BuiltInFanController {
    enum Action: Equatable { case auto(String), target(String, Int), restore }
    var fans: [FanDeviceState]
    private(set) var actions: [Action] = []
    let recorder: EventRecorder?
    init(_ fans: [FanDeviceState], recorder: EventRecorder? = nil) { self.fans = fans; self.recorder = recorder }
    func listFans() -> [FanDeviceState] { fans }
    func setAuto(fanID: String) async { actions.append(.auto(fanID)); await recorder?.append("auto") }
    func setTargetRPM(fanID: String, rpm: Int) async -> Int {
        let fan = fans.first { $0.id == fanID }
        let target = fan?.capabilities?.clamped(rpm) ?? rpm
        actions.append(.target(fanID, target)); await recorder?.append("internal")
        return target
    }
    func restoreAllToAuto() async { actions.append(.restore); await recorder?.append("restore") }
    func recorded() -> [Action] { actions }
}

actor MockExternalController: ExternalCoolerController {
    var fanState: FanDeviceState
    var shouldFail = false
    private(set) var targets: [Int] = []
    let recorder: EventRecorder?
    init(_ state: FanDeviceState, recorder: EventRecorder? = nil) { fanState = state; self.recorder = recorder }
    func state() -> FanDeviceState { fanState }
    func connect() {}
    func setTarget(_ speed: Int) async throws -> AcknowledgedTarget {
        targets.append(speed); await recorder?.append("external")
        if shouldFail { throw ThermalControlError.timeout }
        return AcknowledgedTarget(target: speed, acknowledgedAt: Fixtures.now)
    }
    func setFailure(_ value: Bool) { shouldFail = value }
    func recordedTargets() -> [Int] { targets }
}

actor MockHelperClient: PrivilegedFanHelperClient {
    let controller: MockBuiltInController
    var helperStatus: HelperStatus
    init(controller: MockBuiltInController, status: HelperStatus = .healthy) {
        self.controller = controller; helperStatus = status
    }
    func status() -> HelperStatus { helperStatus }
    func listFans() async throws -> [FanDeviceState] { await controller.listFans() }
    func setAuto(fanID: String) async throws { await controller.setAuto(fanID: fanID) }
    func setTargetRPM(fanID: String, rpm: Int) async throws -> Int { await controller.setTargetRPM(fanID: fanID, rpm: rpm) }
    func restoreAllToAuto() async { await controller.restoreAllToAuto() }
    func renewLease() -> Date { Fixtures.now.addingTimeInterval(8) }
}

actor ScriptedReportTransport: FlydigiReportTransport {
    enum Response: Sendable { case data(Data), failure(ThermalControlError) }
    var connected = true
    var responses: [Response]
    /// Reports already sitting in the input buffer before a request is sent.
    var staleReports: [Data]
    private(set) var writes: [Data] = []
    private(set) var discards = 0
    init(_ responses: [Response], staleReports: [Data] = []) { self.responses = responses; self.staleReports = staleReports }
    func discardPendingReports() { staleReports.removeAll(); discards += 1 }
    func send(_ report: Data) { writes.append(report) }
    func nextReport() throws -> Data {
        if !staleReports.isEmpty { return staleReports.removeFirst() }
        guard !responses.isEmpty else { throw ThermalControlError.timeout }
        switch responses.removeFirst() {
        case let .data(data): return data
        case let .failure(error): throw error
        }
    }
    func isConnected() -> Bool { connected }
    func sentReports() -> [Data] { writes }
}

