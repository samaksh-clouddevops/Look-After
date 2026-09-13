import XCTest
@testable import LookAfterData
import LookAfterCore

@MainActor
final class IdentityServiceTests: XCTestCase {

    func testMapSignedOut() {
        let state = IdentityService.map(
            isAuthenticated: false,
            currentUserId: nil,
            resolvedUserId: "",
            email: nil,
            cloudSyncAvailable: false
        )
        XCTAssertEqual(state, .signedOut)
        XCTAssertFalse(state.isStableForBootstrap)
    }

    func testMapGuestOffline() {
        let state = IdentityService.map(
            isAuthenticated: true,
            currentUserId: "guest_abc",
            resolvedUserId: "guest_abc",
            email: nil,
            cloudSyncAvailable: false
        )
        XCTAssertEqual(state, .offlineGuest(userId: "guest_abc"))
        XCTAssertTrue(state.isStableForBootstrap)
    }

    func testMapSyntheticUsrWithoutCloud() {
        let state = IdentityService.map(
            isAuthenticated: true,
            currentUserId: "usr_deadbeef",
            resolvedUserId: "usr_deadbeef",
            email: "a@b.com",
            cloudSyncAvailable: false
        )
        if case .offlineGuest(let id) = state {
            XCTAssertEqual(id, "usr_deadbeef")
        } else {
            XCTFail("expected offlineGuest, got \(state)")
        }
    }

    func testMapFirebaseUserWhenCloudAvailable() {
        let state = IdentityService.map(
            isAuthenticated: true,
            currentUserId: "firebase-uid-1",
            resolvedUserId: "firebase-uid-1",
            email: "user@lookafter.app",
            cloudSyncAvailable: true
        )
        XCTAssertEqual(
            state,
            .firebaseUser(userId: "firebase-uid-1", email: "user@lookafter.app")
        )
    }

    func testSessionContainerNilWhenFlagOff() {
        ArchitectureFeatureFlags.resetAllToDefaults()
        XCTAssertFalse(ArchitectureFeatureFlags.useSessionContainer)
        let identity = IdentityService.shared
        let session = SessionContainer.makeIfReady(identity: identity, requireFlag: true)
        XCTAssertNil(session)
    }

    func testSessionContainerBuildsWhenFlagOnAndStable() {
        ArchitectureFeatureFlags.resetAllToDefaults()
        ArchitectureFeatureFlags.useSessionContainer = true
        defer { ArchitectureFeatureFlags.resetAllToDefaults() }

        let identity = IdentityService.shared
        identity.applyForTesting(.offlineGuest(userId: "guest_test_session"))
        let session = SessionContainer.makeIfReady(identity: identity, requireFlag: true)
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.userId, "guest_test_session")
        XCTAssertFalse(session?.isIdentityStale ?? true)

        session?.tearDown()
        XCTAssertEqual(session?.isTornDown, true)
    }

    func testGenerationBumpsOnTransition() {
        let identity = IdentityService.shared
        let g0 = identity.generation
        identity.applyForTesting(.signedOut)
        identity.applyForTesting(.offlineGuest(userId: "guest_gen"))
        XCTAssertGreaterThan(identity.generation, g0)
        identity.applyForTesting(.signedOut)
    }
}
