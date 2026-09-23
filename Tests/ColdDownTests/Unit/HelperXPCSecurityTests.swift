import XCTest
import ColdDownShared

final class HelperXPCSecurityTests: XCTestCase {
    func testNarrowXPCInterfaceCanBeConstructed() {
        XCTAssertNotNil(HelperXPCInterface.make())
    }

    func testClientRequirementPinsTeam() {
        let requirement = HelperClientRequirement.make(
            identifier: "com.acme.ColdDown", teamIdentifier: "ABCDE12345", allowUnpinnedTeam: false
        )
        XCTAssertEqual(
            requirement,
            #"anchor apple generic and identifier "com.acme.ColdDown" and certificate leaf[subject.OU] = "ABCDE12345""#
        )
    }

    func testReleaseWithoutTeamRefusesAllClients() {
        XCTAssertNil(HelperClientRequirement.make(identifier: "com.acme.ColdDown", teamIdentifier: nil, allowUnpinnedTeam: false))
        XCTAssertNil(HelperClientRequirement.make(identifier: "com.acme.ColdDown", teamIdentifier: "", allowUnpinnedTeam: false))
        XCTAssertNil(HelperClientRequirement.make(identifier: "com.acme.ColdDown", teamIdentifier: "$(DEVELOPMENT_TEAM)", allowUnpinnedTeam: false))
    }

    func testDebugWithoutTeamStillChecksIdentifier() {
        XCTAssertEqual(
            HelperClientRequirement.make(identifier: "com.acme.ColdDown", teamIdentifier: nil, allowUnpinnedTeam: true),
            #"identifier "com.acme.ColdDown""#
        )
    }

    func testRequirementRejectsInjectionInIdentifier() {
        XCTAssertNil(HelperClientRequirement.make(
            identifier: #"x" or anchor apple generic or identifier "y"#, teamIdentifier: "ABCDE12345", allowUnpinnedTeam: true
        ))
    }
}
