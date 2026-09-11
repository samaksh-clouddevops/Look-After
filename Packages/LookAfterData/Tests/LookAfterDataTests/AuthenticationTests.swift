import XCTest
import FirebaseCore
@testable import LookAfterData
import LookAfterCore

@MainActor
final class AuthenticationTests: XCTestCase {
    
    var firebase: FirebaseManager!
    
    override func setUp() async throws {
        try await super.setUp()
        if FirebaseApp.app() == nil {
            FirebaseApp.configure(options: LookAfterFirebaseConfiguration.mockOptions(projectID: "flowos-test-app"))
        }
        firebase = FirebaseManager.shared
        try? firebase.signOut()
    }
    
    override func tearDown() async throws {
        try? firebase.signOut()
        firebase = nil
        try await super.tearDown()
    }
    
    func testInitialUnauthenticatedState() {
        XCTAssertFalse(firebase.isAuthenticated, "FirebaseManager should start unauthenticated after signOut.")
        XCTAssertNil(firebase.currentUserId, "CurrentUserId should be nil after signOut.")
        XCTAssertNil(firebase.userEmail, "UserEmail should be nil after signOut.")
    }
    
    func testEmailSignInDoesNotMarkAuthenticatedOnAuthFailure() async {
        let before = firebase.isAuthenticated
        do {
            try await firebase.signIn(email: "no.such.user@lookafter.test", password: "DefinitelyWrongPass999!")
            XCTFail("Expected Auth failure; must not invent fallback UIDs")
        } catch {
            XCTAssertFalse(firebase.isAuthenticated || before && firebase.currentUserId?.hasPrefix("usr_") == true)
            XCTAssertFalse(firebase.currentUserId?.hasPrefix("usr_") ?? false, "Must not use hashValue fallback UIDs")
        }
    }
    
    func testAccountCreationDoesNotMarkAuthenticatedOnAuthFailure() async {
        do {
            try await firebase.createAccount(email: "likely.invalid", password: "x")
            XCTFail("Expected Auth failure for invalid email")
        } catch {
            XCTAssertFalse(firebase.currentUserId?.hasPrefix("usr_") ?? false)
        }
    }
    
    func testGuestAnonymousFlowUsesFirebaseOrThrows() async {
        // With Firebase configured, anonymous must await Auth — success or throw.
        // Must never leave a hashValue-based usr_* id.
        do {
            try await firebase.signInAnonymously()
            XCTAssertTrue(firebase.isAuthenticated)
            XCTAssertNotNil(firebase.currentUserId)
            XCTAssertFalse(firebase.currentUserId?.hasPrefix("usr_") ?? false)
        } catch {
            XCTAssertFalse(firebase.isAuthenticated, "Failed Auth must not leave authenticated=true")
        }
    }
    
    func testGuestLocalIdentityIsStableAcrossCalls() throws {
        try GuestLocalIdentity.deleteForTests()
        let first = try GuestLocalIdentity.resolvedOrCreate()
        let second = try GuestLocalIdentity.resolvedOrCreate()
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("guest_"))
        XCTAssertFalse(first.contains("usr_"))
    }
    
    func testSignOutFlowClearsSessionFlags() async throws {
        // Establish a local guest session via Keychain path is not reachable while FirebaseApp
        // is configured; verify signOut clears whatever session flags exist.
        try? await firebase.signInAnonymously()
        try firebase.signOut()
        
        XCTAssertFalse(firebase.isAuthenticated, "SignOut must reset isAuthenticated to false.")
        XCTAssertNil(firebase.currentUserId, "SignOut must clear currentUserId.")
        XCTAssertNil(firebase.userEmail, "SignOut must clear userEmail.")
    }
}
