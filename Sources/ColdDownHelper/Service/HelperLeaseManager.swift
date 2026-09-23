import Foundation
import ThermalCore

actor HelperLeaseManager {
    private let lease: SafetyLease
    private var owner: UUID?

    init(duration: TimeInterval = 8) { lease = SafetyLease(duration: duration) }

    /// A newly accepted session always takes the lease over from any previous session.
    func begin(owner: UUID, now: Date = Date()) async -> Date {
        self.owner = owner
        return await lease.acquire(owner: owner, now: now)
    }

    /// Renews the caller's lease. After a fail-safe restoration cleared the lease, the (single, active)
    /// session may re-acquire it instead of being forced to reconnect.
    func renew(owner: UUID, now: Date = Date()) async throws -> Date {
        if self.owner == nil { return await begin(owner: owner, now: now) }
        return try await lease.renew(owner: owner, now: now)
    }

    func validate(owner: UUID, now: Date = Date()) async -> Bool {
        await lease.isValid(owner: owner, now: now)
    }

    /// True only for the current owner of an expired lease; other sessions never trigger restoration.
    func needsRestore(owner: UUID, now: Date = Date()) async -> Bool {
        guard self.owner == owner else { return false }
        return await lease.hasExpired(now: now)
    }

    /// Keeps ownership but forces expiry so the watchdog retries a restoration that failed.
    func expire(owner: UUID, now: Date = Date()) async {
        guard self.owner == owner else { return }
        await lease.expire(owner: owner, now: now)
    }

    func clear(owner: UUID) async {
        guard self.owner == owner else { return }
        self.owner = nil
        await lease.clear()
    }

    /// Releases the lease when a session ends. Returns true when the ending session was in control
    /// (or nobody is), meaning fans must be restored; false when another session has already taken over.
    func release(owner: UUID) async -> Bool {
        if self.owner == owner {
            self.owner = nil
            await lease.clear()
            return true
        }
        return self.owner == nil
    }
}
