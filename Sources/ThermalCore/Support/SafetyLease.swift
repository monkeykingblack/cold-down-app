import Foundation

public actor SafetyLease {
    private let duration: TimeInterval
    private var owner: UUID?
    private var expiry: Date?

    public init(duration: TimeInterval = 8) { self.duration = duration }

    @discardableResult
    public func acquire(owner newOwner: UUID, now: Date) -> Date {
        owner = newOwner
        let deadline = now.addingTimeInterval(duration)
        expiry = deadline
        return deadline
    }

    public func renew(owner candidate: UUID, now: Date) throws -> Date {
        guard owner == candidate, let expiry, expiry > now else { throw ThermalControlError.unauthorized }
        let deadline = now.addingTimeInterval(duration)
        self.expiry = deadline
        return deadline
    }

    public func isValid(owner candidate: UUID, now: Date) -> Bool {
        owner == candidate && (expiry ?? .distantPast) > now
    }

    public func hasExpired(now: Date) -> Bool {
        owner != nil && (expiry ?? .distantPast) <= now
    }

    /// Marks the lease as expired without releasing ownership, so a watchdog keeps retrying restoration.
    public func expire(owner candidate: UUID, now: Date) {
        guard owner == candidate else { return }
        expiry = now
    }

    public func clear() { owner = nil; expiry = nil }
}

