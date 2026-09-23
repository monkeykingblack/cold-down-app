import XCTest
import ThermalCore

final class PrivilegedHelperSafetyTests: XCTestCase {
    func testLeaseExpiresAndRejectsWrongOwner() async throws {
        let lease = SafetyLease(duration: 8)
        let owner = UUID(); let other = UUID()
        _ = await lease.acquire(owner: owner, now: Fixtures.now)
        let valid = await lease.isValid(owner: owner, now: Fixtures.now.addingTimeInterval(7.9))
        let expired = await lease.hasExpired(now: Fixtures.now.addingTimeInterval(8))
        XCTAssertTrue(valid)
        XCTAssertTrue(expired)
        do {
            _ = try await lease.renew(owner: other, now: Fixtures.now)
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(error as? ThermalControlError, .unauthorized)
        }
    }

    func testExpireKeepsOwnershipSoRestorationIsRetried() async {
        let lease = SafetyLease(duration: 8)
        let owner = UUID()
        _ = await lease.acquire(owner: owner, now: Fixtures.now)
        await lease.expire(owner: owner, now: Fixtures.now)
        let expired = await lease.hasExpired(now: Fixtures.now)
        let valid = await lease.isValid(owner: owner, now: Fixtures.now)
        XCTAssertTrue(expired)
        XCTAssertFalse(valid)
    }

    func testClampingNeverAllowsBuiltInStop() {
        let capabilities = Fixtures.builtIn().capabilities!
        XCTAssertEqual(capabilities.clamped(0), capabilities.minimum)
    }
}
