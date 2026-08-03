import XCTest
import FirebaseCore
@testable import LookAfterData
@testable import LookAfterAI
import LookAfterCore

@MainActor
final class FullAppIntegrationTests: XCTestCase {
    
    var firebase: FirebaseManager!
    var persistence: LocalPersistenceManager!
    
    override func setUp() async throws {
        try await super.setUp()
        if FirebaseApp.app() == nil {
            let options = FirebaseOptions(googleAppID: "1:123456789:ios:abcdef", gcmSenderID: "123456789")
            options.apiKey = "AIzaSyMockTestKey123456789"
            options.projectID = "flowos-test-app"
            FirebaseApp.configure(options: options)
        }
        firebase = FirebaseManager.shared
        persistence = LocalPersistenceManager.shared
        try? firebase.signOut()
    }
    
    func testEndToEndUserTaskLifecycle() async throws {
        // Step 1: User Signs In with Google SSO email
        let testEmail = "test.user@example.com"
        try await firebase.signIn(email: testEmail, password: "TestPassword123!")
        
        XCTAssertTrue(firebase.isAuthenticated, "User should be authenticated after sign in.")
        XCTAssertEqual(firebase.userEmail, testEmail)
        XCTAssertNotNil(firebase.currentUserId)
        
        // Step 2: Create a complex task
        var mainTask = LifeTask(
            title: "Build ADHD FlowOS iOS App",
            description: "Complete design system, AI cognitive engine, and persistence layers",
            priority: .high,
            requiredEnergy: .high
        )
        
        // Step 3: Decompose task using AI Cognitive Engine
        let glm = GLMService.makeForTesting(keyManager: GLMKeyManager(
            secretStore: InMemorySecretStore(),
            metadataKey: "integration.test.\(UUID().uuidString)"
        ))
        glm.debugCompleteHandler = { _ in """
        {
            "detectedRecurrence": "none",
            "steps": [
                { "title": "Design dark mode palette", "estimatedMinutes": 5 },
                { "title": "Implement SwiftData & Firebase fallback", "estimatedMinutes": 10 },
                { "title": "Build AI cognitive engine", "estimatedMinutes": 15 }
            ]
        }
        """ }

        let decomposer = TaskDecomposer(glmService: glm)
        let (steps, _) = try await decomposer.decompose(task: mainTask)
        
        XCTAssertEqual(steps.count, 3)
        
        mainTask.steps = steps
        
        // Step 4: Persist Task to Local Data Layer
        persistence.save([mainTask], filename: "test_integration_tasks")
        let savedTasks = persistence.load([LifeTask].self, filename: "test_integration_tasks")
        
        XCTAssertTrue(savedTasks.contains(where: { $0.title == "Build ADHD FlowOS iOS App" }))
        
        // Step 5: Complete Task Step
        mainTask.status = .completed
        persistence.save([mainTask], filename: "test_integration_tasks")
        
        // Step 6: User Signs Out safely
        try firebase.signOut()
        XCTAssertFalse(firebase.isAuthenticated)
        XCTAssertNil(firebase.currentUserId)
        XCTAssertNil(firebase.userEmail)
    }
}
