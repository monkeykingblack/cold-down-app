import XCTest
import ServiceManagement
@testable import ColdDownApp

final class HelperAutoRegistrationTests: XCTestCase {
    func testRegistersANeverRegisteredHelperOnce() {
        XCTAssertTrue(HelperRegistrationService.shouldAutoRegister(serviceStatus: .notRegistered, alreadyAttempted: false, helperBundled: true))
        // Never-registered daemons usually report .notFound.
        XCTAssertTrue(HelperRegistrationService.shouldAutoRegister(serviceStatus: .notFound, alreadyAttempted: false, helperBundled: true))
        XCTAssertFalse(HelperRegistrationService.shouldAutoRegister(serviceStatus: .notRegistered, alreadyAttempted: true, helperBundled: true))
    }

    func testNeverTouchesAnExistingRegistrationOrAMissingHelper() {
        for status: SMAppService.Status in [.enabled, .requiresApproval] {
            XCTAssertFalse(HelperRegistrationService.shouldAutoRegister(serviceStatus: status, alreadyAttempted: false, helperBundled: true))
        }
        XCTAssertFalse(HelperRegistrationService.shouldAutoRegister(serviceStatus: .notFound, alreadyAttempted: false, helperBundled: false))
    }
}
