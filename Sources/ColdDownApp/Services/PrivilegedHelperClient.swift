import Foundation
import ServiceManagement
import ThermalCore
import ColdDownShared

/// Resumes a continuation exactly once, whichever of reply, XPC error, or timeout arrives first.
private final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var timer: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }

    func setTimer(_ task: Task<Void, Never>) {
        lock.lock(); defer { lock.unlock() }
        if continuation == nil { task.cancel() } else { timer = task }
    }

    /// Returns true only for the call that actually resumed the continuation.
    @discardableResult
    func resume(_ result: Result<Value, Error>) -> Bool {
        lock.lock()
        let pending = continuation
        let pendingTimer = timer
        continuation = nil
        timer = nil
        lock.unlock()
        pendingTimer?.cancel()
        guard let pending else { return false }
        pending.resume(with: result)
        return true
    }
}

actor XPCPrivilegedHelperClient: PrivilegedFanHelperClient {
    private static let callTimeout: Duration = .seconds(5)
    /// Taking over an Apple Silicon fan waits ~3 s for thermalmonitord plus bounded retries (up to ~30 s).
    private static let fanTargetTimeout: Duration = .seconds(45)
    private var connection: NSXPCConnection?
    private var currentStatus: HelperStatus = .unavailable
    private let disabled: Bool
    private let service = SMAppService.daemon(plistName: "ColdDownHelper.plist")
    private var cachedServiceStatus: (value: SMAppService.Status, readAt: ContinuousClock.Instant)?

    /// Longer than a refresh interval, so an app that refreshes every couple of seconds does not pay for the
    /// round trip on every pass. Installing or approving the helper is noticed within this window.
    private static let serviceStatusLifetime: Duration = .seconds(5)

    init(disabled: Bool = false) { self.disabled = disabled }

    /// `SMAppService.status` is a synchronous round trip to the background-task daemon, and a single refresh
    /// asks for it five or more times (status, listFans, renewLease, and one setAuto per fan); a profile put
    /// 86% of the refresh cost inside it. It only changes when the user installs, removes or approves the
    /// helper, so a brief cache collapses those into one call. Every transport failure clears it, so a helper
    /// that disappears is still noticed on the very next call.
    private var serviceStatus: SMAppService.Status {
        let now = ContinuousClock.now
        if let cached = cachedServiceStatus, now - cached.readAt < Self.serviceStatusLifetime {
            return cached.value
        }
        let value = service.status
        cachedServiceStatus = (value, now)
        return value
    }

    func status() async -> HelperStatus {
        guard !disabled else { return .unavailable }
        guard serviceStatus == .enabled else {
            currentStatus = mappedServiceStatus
            return currentStatus
        }
        _ = try? await renewLease()
        return currentStatus
    }

    func listFans() async throws -> [FanDeviceState] {
        let records: [HelperFanRecord] = try await perform { proxy, complete in
            proxy.listFans { records, error in
                complete(error.map { .failure($0) } ?? .success(records ?? []))
            }
        }
        return records.map { $0.deviceState() }
    }

    func setAuto(fanID: String) async throws {
        let _: Bool = try await perform { proxy, complete in
            proxy.setFanAuto(fanID: fanID) { error in complete(error.map { .failure($0) } ?? .success(true)) }
        }
    }

    func setTargetRPM(fanID: String, rpm: Int) async throws -> Int {
        try await perform(timeout: Self.fanTargetTimeout) { proxy, complete in
            proxy.setFanTargetRPM(fanID: fanID, rpm: rpm) { applied, error in
                complete(error.map { .failure($0) } ?? .success(applied))
            }
        }
    }

    func restoreAllToAuto() async {
        guard !disabled, serviceStatus == .enabled else { return }
        let _: Bool? = try? await perform { proxy, complete in
            proxy.restoreAllFansToAuto { restored, _ in complete(.success(restored)) }
        }
    }

    func renewLease() async throws -> Date {
        try await perform { proxy, complete in
            proxy.renewLease { date, error in
                if let error { complete(.failure(error)) }
                else if let date { complete(.success(date)) }
                else { complete(.failure(ThermalControlError.unavailable("Helper returned no lease"))) }
            }
        }
    }

    /// Runs one XPC call. Transport failures (invalidation, interruption, timeout) drop the connection so the next
    /// call reconnects; errors *returned by the helper* keep the connection and only mark the helper interrupted.
    private func perform<Value: Sendable>(
        timeout: Duration = callTimeout,
        _ body: @escaping (PrivilegedFanHelperXPCProtocol, @escaping @Sendable (Result<Value, Error>) -> Void) -> Void
    ) async throws -> Value {
        let connection = try activeConnection()
        let connectionID = ObjectIdentifier(connection)
        let outcome: Result<Value, Error>
        do {
            outcome = .success(try await withCheckedThrowingContinuation { continuation in
                let once = ResumeOnce(continuation)
                let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
                    once.resume(.failure(error))
                    // Any transport error means the connection is unusable, even if a reply already arrived.
                    guard let self else { return }
                    Task { await self.connectionFailed(connectionID) }
                } as? PrivilegedFanHelperXPCProtocol
                guard let proxy else {
                    once.resume(.failure(ThermalControlError.unavailable("Privileged helper proxy is unavailable")))
                    return
                }
                once.setTimer(Task { [weak self] in
                    guard (try? await Task.sleep(for: timeout)) != nil else { return }
                    if once.resume(.failure(ThermalControlError.timeout)) {
                        await self?.connectionFailed(connectionID)
                    }
                })
                body(proxy) { once.resume($0) }
            })
        } catch {
            outcome = .failure(error)
        }
        switch outcome {
        case let .success(value):
            if self.connection.map(ObjectIdentifier.init) == connectionID { currentStatus = .healthy }
            return value
        case let .failure(error):
            if self.connection.map(ObjectIdentifier.init) == connectionID { currentStatus = .interrupted }
            throw error
        }
    }

    private func activeConnection() throws -> NSXPCConnection {
        guard !disabled else {
            currentStatus = .unavailable
            throw ThermalControlError.unavailable("Privileged helper is not enabled")
        }
        // A live connection is its own proof that the helper is enabled, and asking the background-task
        // daemon costs a synchronous round trip on every single call. Interruption and invalidation already
        // drop the connection, so the registration state only has to be consulted when there is none to reuse.
        if let connection { return connection }
        guard serviceStatus == .enabled else {
            currentStatus = mappedServiceStatus
            throw ThermalControlError.unavailable("Privileged helper is not enabled")
        }
        let connection = NSXPCConnection(machServiceName: thermalHelperMachService, options: .privileged)
        let connectionID = ObjectIdentifier(connection)
        connection.remoteObjectInterface = HelperXPCInterface.make()
        connection.interruptionHandler = { [weak self] in
            guard let self else { return }
            Task { await self.connectionFailed(connectionID) }
        }
        connection.invalidationHandler = { [weak self] in
            guard let self else { return }
            Task { await self.connectionFailed(connectionID) }
        }
        connection.resume()
        self.connection = connection
        currentStatus = .interrupted
        return connection
    }

    /// Drops (and invalidates) the connection only if it is still the current one, so a late callback
    /// from an old connection can never tear down its replacement.
    private func connectionFailed(_ connectionID: ObjectIdentifier) {
        guard let connection, ObjectIdentifier(connection) == connectionID else { return }
        self.connection = nil
        currentStatus = .unavailable
        // The cached registration state is deliberately kept: a dropped connection says nothing about whether
        // the daemon is still registered, and a helper that rejects or drops every call would otherwise make
        // each retry re-ask the background-task daemon, which is the expensive part.
        connection.invalidate()
    }

    private var mappedServiceStatus: HelperStatus {
        switch serviceStatus {
        case .enabled: .healthy
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        default: .notRegistered
        }
    }
}
