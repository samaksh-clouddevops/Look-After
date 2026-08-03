import XCTest
@testable import LifeOSCore

final class LifeOSCoreTests: XCTestCase {
    func testLifeTaskProgress() {
        var task = LifeTask(title: "Test Task", estimatedMinutes: 30)
        task.steps = [
            TaskStep(title: "Step 1", isCompleted: true),
            TaskStep(title: "Step 2", isCompleted: false)
        ]
        XCTAssertEqual(task.progress, 0.5)
    }
    
    func testEnergyLevelComparison() {
        XCTAssertTrue(EnergyLevel.peak > EnergyLevel.low)
        XCTAssertTrue(EnergyLevel.recovery < EnergyLevel.moderate)
    }
}
