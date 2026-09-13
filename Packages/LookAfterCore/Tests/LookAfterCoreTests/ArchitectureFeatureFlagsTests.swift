import XCTest
@testable import LookAfterCore

final class ArchitectureFeatureFlagsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ArchitectureFeatureFlags.resetAllToDefaults()
    }

    override func tearDown() {
        ArchitectureFeatureFlags.resetAllToDefaults()
        super.tearDown()
    }

    func testSessionContainerDefaultsOff() {
        XCTAssertFalse(ArchitectureFeatureFlags.useSessionContainer)
    }

    func testSyncOutboxDefaultsOff() {
        XCTAssertFalse(ArchitectureFeatureFlags.useSyncOutbox)
    }

    func testBrainFacadeAndEventBusDefaultOff() {
        XCTAssertFalse(ArchitectureFeatureFlags.useBrainFacade)
        XCTAssertFalse(ArchitectureFeatureFlags.useTypedEventBus)
    }

    func testFlagsRoundTrip() {
        ArchitectureFeatureFlags.useSessionContainer = true
        ArchitectureFeatureFlags.useSyncOutbox = true
        ArchitectureFeatureFlags.useBrainFacade = true
        ArchitectureFeatureFlags.useTypedEventBus = true
        ArchitectureFeatureFlags.proxyOnlyAI = false

        XCTAssertTrue(ArchitectureFeatureFlags.useSessionContainer)
        XCTAssertTrue(ArchitectureFeatureFlags.useSyncOutbox)
        XCTAssertTrue(ArchitectureFeatureFlags.useBrainFacade)
        XCTAssertTrue(ArchitectureFeatureFlags.useTypedEventBus)
        XCTAssertFalse(ArchitectureFeatureFlags.proxyOnlyAI)

        let snap = ArchitectureFeatureFlags.debugSnapshot
        XCTAssertEqual(snap["useSessionContainer"], true)
        XCTAssertEqual(snap["useSyncOutbox"], true)
    }

    func testResetClearsOverrides() {
        ArchitectureFeatureFlags.useSessionContainer = true
        ArchitectureFeatureFlags.resetAllToDefaults()
        XCTAssertFalse(ArchitectureFeatureFlags.useSessionContainer)
    }
}
