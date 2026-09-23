import XCTest
import FlydigiHID
import ThermalCore

final class FlydigiCapabilityTests: XCTestCase {
    func testOnlyEvidenceBackedRangesAuthorizeRealWrites() {
        XCTAssertFalse(SpeedCapabilities(minimum: 1_300, maximum: 4_000, provenance: .unverified).permitsRealHardwareWrites())
        XCTAssertFalse(SpeedCapabilities(minimum: 1_300, maximum: 4_000, provenance: .deterministicMock).permitsRealHardwareWrites())
        XCTAssertTrue(SpeedCapabilities(minimum: 1_300, maximum: 4_000, provenance: .deviceVerified).permitsRealHardwareWrites())
        XCTAssertTrue(SpeedCapabilities(minimum: 1_300, maximum: 4_000, provenance: .auditedModel).permitsRealHardwareWrites())
    }

    func testUnverifiedConnectedControllerIsCapabilityLimitedAndDoesNotWrite() async {
        let transport = ScriptedReportTransport([])
        let controller = BS3ProController(
            transport: transport,
            capabilities: SpeedCapabilities(minimum: 1_300, maximum: 4_000, provenance: .unverified)
        )
        let state = await controller.state()
        XCTAssertEqual(state.writeAvailability, .capabilityLimited)
        do { _ = try await controller.setTarget(2_000); XCTFail("Expected capability failure") } catch { }
        let reports = await transport.sentReports()
        XCTAssertTrue(reports.isEmpty)
    }
}
