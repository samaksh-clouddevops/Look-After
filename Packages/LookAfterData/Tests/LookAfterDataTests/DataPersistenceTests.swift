import XCTest
@testable import LookAfterData
import LookAfterCore

@MainActor
final class DataPersistenceTests: XCTestCase {
    
    var persistence: LocalPersistenceManager!
    
    override func setUp() {
        super.setUp()
        persistence = LocalPersistenceManager.shared
    }
    
    func testTaskPersistence() {
        let originalTasks = [
            LifeTask(title: "Task 1", priority: .high),
            LifeTask(title: "Task 2", priority: .low)
        ]
        
        persistence.save(originalTasks, filename: "test_tasks")
        let loadedTasks = persistence.load([LifeTask].self, filename: "test_tasks")
        
        XCTAssertEqual(loadedTasks.count, 2)
        XCTAssertTrue(loadedTasks.contains(where: { $0.title == "Task 1" }))
        XCTAssertTrue(loadedTasks.contains(where: { $0.title == "Task 2" }))
    }
    
    func testInboxPersistence() {
        let originalItems = [
            InboxItem(content: "Buy coffee beans", type: .text),
            InboxItem(content: "Call tax consultant", type: .note)
        ]
        
        persistence.save(originalItems, filename: "test_inbox")
        let loadedItems = persistence.load([InboxItem].self, filename: "test_inbox")
        
        XCTAssertEqual(loadedItems.count, 2)
        XCTAssertTrue(loadedItems.contains(where: { $0.content == "Buy coffee beans" }))
    }
    
    func testShoppingItemsPersistence() {
        let items = [ShoppingItem(name: "Organic Milk", quantity: 2, isPurchased: false)]
        persistence.save(items, filename: "test_shopping")
        
        let loaded = persistence.load([ShoppingItem].self, filename: "test_shopping")
        XCTAssertEqual(loaded.count, 1)
        XCTAssertTrue(loaded.contains(where: { $0.name == "Organic Milk" }))
    }
    
    func testJournalEntriesPersistence() {
        let entry = JournalEntry(title: "Evening Reflection", content: "Great focus day working on FlowOS", mood: "Great")
        persistence.save([entry], filename: "test_journal")
        
        let loaded = persistence.load([JournalEntry].self, filename: "test_journal")
        XCTAssertEqual(loaded.count, 1)
        XCTAssertTrue(loaded.contains(where: { $0.title == "Evening Reflection" }))
    }
}
