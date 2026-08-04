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
    
    func testEmailSignInFlow() async throws {
        let testEmail = "test.user@flowos.app"
        let testPass = "FlowOSSecret123!"
        
        try await firebase.signIn(email: testEmail, password: testPass)
        
        XCTAssertTrue(firebase.isAuthenticated, "FirebaseManager must set isAuthenticated to true upon sign in.")
        XCTAssertNotNil(firebase.currentUserId, "FirebaseManager must set currentUserId upon sign in.")
        XCTAssertEqual(firebase.userEmail, testEmail, "UserEmail must match sign-in email.")
    }
    
    func testAccountCreationFlow() async throws {
        let newEmail = "user.create@flowos.app"
        let newPass = "NewAccountPass456!"
        
        try await firebase.createAccount(email: newEmail, password: newPass)
        
        XCTAssertTrue(firebase.isAuthenticated, "FirebaseManager must set isAuthenticated to true upon account creation.")
        XCTAssertNotNil(firebase.currentUserId, "FirebaseManager must set currentUserId upon account creation.")
        XCTAssertEqual(firebase.userEmail, newEmail, "UserEmail must match creation email.")
    }
    
    func testGuestAnonymousFlow() async throws {
        try await firebase.signInAnonymously()
        
        XCTAssertTrue(firebase.isAuthenticated, "FirebaseManager must set isAuthenticated to true for guest mode.")
        XCTAssertNotNil(firebase.currentUserId, "CurrentUserId must be generated for guest mode.")
        XCTAssertTrue(firebase.currentUserId?.hasPrefix("guest_") ?? false || !(firebase.currentUserId?.isEmpty ?? true))
    }
    
    func testSignOutFlow() async throws {
        try await firebase.signIn(email: "signout.test@flowos.app", password: "Password123!")
        XCTAssertTrue(firebase.isAuthenticated)
        
        try firebase.signOut()
        
        XCTAssertFalse(firebase.isAuthenticated, "SignOut must reset isAuthenticated to false.")
        XCTAssertNil(firebase.currentUserId, "SignOut must clear currentUserId.")
        XCTAssertNil(firebase.userEmail, "SignOut must clear userEmail.")
    }
}
