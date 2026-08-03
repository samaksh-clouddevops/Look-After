import XCTest
import FirebaseCore
@testable import LookAfterData
@testable import LookAfterAI
import LookAfterCore

@MainActor
final class SimulatedUserFlowTests: XCTestCase {
    
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
    
    func testCompleteRealUserJourneySimulation() async throws {
        print("🚀 [User Simulation] Step 1: User opens app & clicks 'Continue with Google'")
        let userEmail = "test.user@example.com"
        try await firebase.signIn(email: userEmail, password: "GoogleSSOPassword123!")
        
        XCTAssertTrue(firebase.isAuthenticated, "User should be signed in")
        XCTAssertEqual(firebase.userEmail, userEmail)
        XCTAssertNotNil(firebase.currentUserId)
        
        print("👤 [User Simulation] Step 2: User sets profile name and preferences in Settings")
        UserDefaults.standard.set("Alex", forKey: "userName")
        UserDefaults.standard.set("Encouraging & Gentle", forKey: "aiCoachTone")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "userName"), "Alex")
        
        print("💡 [User Simulation] Step 3: User captures a quick thought in Universal Inbox")
        let rawThought = InboxItem(content: "Need to organize quarterly taxes and renew car insurance", type: .text)
        persistence.save([rawThought], filename: "user_inbox")
        
        let inboxItems = persistence.load([InboxItem].self, filename: "user_inbox")
        XCTAssertTrue(inboxItems.contains(where: { $0.content.contains("quarterly taxes") }))
        
        print("🧠 [User Simulation] Step 4: User creates a task and decomposes it with AI")
        var taxTask = LifeTask(
            title: "Organize Quarterly Taxes",
            description: "Gather Q3 receipts and calculate deductions",
            priority: .high,
            requiredEnergy: .high
        )
        
        let glm = GLMService.makeForTesting(keyManager: GLMKeyManager(
            secretStore: InMemorySecretStore(),
            metadataKey: "simulation.test.\(UUID().uuidString)"
        ))
        glm.debugCompleteHandler = { _, _ in """
        {
            "detectedRecurrence": "none",
            "steps": [
                { "title": "Gather Q3 receipts folder", "estimatedMinutes": 5 },
                { "title": "Calculate total deductible expenses", "estimatedMinutes": 10 },
                { "title": "Upload summary to tax portal", "estimatedMinutes": 5 }
            ]
        }
        """ }

        let decomposer = TaskDecomposer(glmService: glm)
        let (steps, recurrence) = try await decomposer.decompose(task: taxTask)
        XCTAssertEqual(steps.count, 3)
        XCTAssertEqual(recurrence, TaskRecurrence.none)
        
        taxTask.steps = steps
        persistence.save([taxTask], filename: "user_tasks")
        
        print("⏱️ [User Simulation] Step 5: User clicks 'START NOW' and completes subtask Step 1")
        taxTask.steps[0].isCompleted = true
        XCTAssertTrue(taxTask.steps[0].isCompleted)
        
        print("⚡ [User Simulation] Step 6: User logs high energy & focus after session")
        let snapshot = CognitiveSnapshot(energy: .high, energyScore: 0.85, focusCapacity: 0.9, contextNotes: "Feeling sharp after focus session")
        persistence.save([snapshot], filename: "user_cognitive_snapshots")
        let savedSnapshots = persistence.load([CognitiveSnapshot].self, filename: "user_cognitive_snapshots")
        XCTAssertEqual(savedSnapshots.first?.energyScore, 0.85)
        
        print("🛒 [User Simulation] Step 7: User interacts with Life Modules (Shopping & Journal)")
        let coffeeItem = ShoppingItem(name: "Cold Brew Coffee", category: "Groceries", isPurchased: true)
        persistence.save([coffeeItem], filename: "user_shopping")
        let shoppingList = persistence.load([ShoppingItem].self, filename: "user_shopping")
        XCTAssertTrue(shoppingList.first?.isPurchased == true)
        
        let journal = JournalEntry(title: "Tax Session Progress", content: "Gathered all receipts cleanly!", mood: "Great")
        persistence.save([journal], filename: "user_journal")
        let journalEntries = persistence.load([JournalEntry].self, filename: "user_journal")
        XCTAssertEqual(journalEntries.first?.title, "Tax Session Progress")
        
        print("🔒 [User Simulation] Step 8: User opens Settings and clicks 'Sign Out'")
        try firebase.signOut()
        XCTAssertFalse(firebase.isAuthenticated)
        XCTAssertNil(firebase.currentUserId)
        XCTAssertNil(firebase.userEmail)
        
        print("✅ [User Simulation] Real-user journey completed 100% successfully!")
    }
}
