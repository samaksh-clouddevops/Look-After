import XCTest
@testable import LifeOSCore

final class CoreDomainTests: XCTestCase {
    
    // MARK: - Task Model Tests
    
    func testLifeTaskInitializationAndDefaults() {
        let task = LifeTask(
            title: "Write documentation",
            description: "Complete developer guide",
            priority: .high,
            requiredEnergy: .high
        )
        
        XCTAssertEqual(task.title, "Write documentation")
        XCTAssertEqual(task.description, "Complete developer guide")
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.requiredEnergy, .high)
        XCTAssertEqual(task.status, .pending)
        XCTAssertTrue(task.steps.isEmpty)
        XCTAssertNotNil(task.id)
    }
    
    func testTaskStatusTransitions() {
        var task = LifeTask(title: "Deep work session")
        XCTAssertEqual(task.status, .pending)
        
        task.status = .inProgress
        XCTAssertEqual(task.status, .inProgress)
        
        task.status = .completed
        XCTAssertEqual(task.status, .completed)
    }
    
    func testTaskStepManagement() {
        var task = LifeTask(title: "Plan project")
        let step1 = TaskStep(title: "Research requirements", isCompleted: false, estimatedMinutes: 5)
        let step2 = TaskStep(title: "Draft architecture diagram", isCompleted: true, estimatedMinutes: 10)
        
        task.steps = [step1, step2]
        XCTAssertEqual(task.steps.count, 2)
        XCTAssertFalse(task.steps[0].isCompleted)
        XCTAssertTrue(task.steps[1].isCompleted)
    }
    
    // MARK: - Energy Level Enum Tests
    
    func testEnergyLevelMetrics() {
        let peak = EnergyLevel.peak
        let high = EnergyLevel.high
        let moderate = EnergyLevel.moderate
        let low = EnergyLevel.low
        let recovery = EnergyLevel.recovery
        
        XCTAssertEqual(peak.numericValue, 1.0)
        XCTAssertEqual(high.numericValue, 0.75)
        XCTAssertEqual(moderate.numericValue, 0.5)
        XCTAssertEqual(low.numericValue, 0.25)
        XCTAssertEqual(recovery.numericValue, 0.1)
    }
    
    // MARK: - Inbox Item Tests
    
    func testInboxItemCategorization() {
        let item = InboxItem(
            content: "Remember to call client tomorrow at 10 AM",
            type: .text,
            status: .unprocessed
        )
        
        XCTAssertEqual(item.content, "Remember to call client tomorrow at 10 AM")
        XCTAssertEqual(item.type, .text)
        XCTAssertEqual(item.status, .unprocessed)
    }
}
