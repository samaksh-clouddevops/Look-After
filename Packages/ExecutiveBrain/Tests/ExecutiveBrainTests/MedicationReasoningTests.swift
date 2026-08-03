import XCTest
@testable import ExecutiveBrain
import LifeOSCore

final class MedicationReasoningTests: XCTestCase {

    func testNeverSuggestsEveningForMorningThyroid() {
        var components = DateComponents()
        components.hour = 7
        components.minute = 30
        let scheduled = Calendar.current.date(from: components)!

        let med = Medication(
            name: "Levothyroxine",
            dosage: "50mcg",
            scheduledTime: scheduled,
            isTaken: false
        )

        // Afternoon — missed morning window
        var nowComponents = DateComponents()
        nowComponents.year = 2026
        nowComponents.month = 8
        nowComponents.day = 1
        nowComponents.hour = 15
        nowComponents.minute = 0
        let now = Calendar.current.date(from: nowComponents)!

        let status = MedicationReasoningEngine.buildWorldStatus(medications: [med], now: now)
        guard case .missedToday(let items) = status else {
            XCTFail("Expected missedToday, got \(status)")
            return
        }
        XCTAssertEqual(items.first?.name, "Levothyroxine")

        let unsafe = "Take your thyroid medicine this evening."
        XCTAssertFalse(MedicationReasoningEngine.isSafeRecommendation(unsafe, status: status))

        let reminder = MedicationReasoningEngine.reminderMessage(for: status)!
        XCTAssertTrue(reminder.contains("7:30") || reminder.contains("7:30 AM") || reminder.lowercased().contains("scheduled"))
        XCTAssertFalse(reminder.lowercased().contains("evening"))
    }

    func testDueNowWithinScheduledWindow() {
        var components = DateComponents()
        components.hour = 8
        components.minute = 0
        let scheduled = Calendar.current.date(from: components)!

        let med = Medication(name: "Levothyroxine", dosage: "50mcg", scheduledTime: scheduled)

        var nowComponents = DateComponents()
        nowComponents.year = 2026
        nowComponents.month = 8
        nowComponents.day = 1
        nowComponents.hour = 8
        nowComponents.minute = 15
        let now = Calendar.current.date(from: nowComponents)!

        let status = MedicationReasoningEngine.buildWorldStatus(medications: [med], now: now)
        guard case .dueNow = status else {
            XCTFail("Expected dueNow")
            return
        }
    }

    func testNoMedicationConfigured() {
        let status = MedicationReasoningEngine.buildWorldStatus(medications: [], now: Date())
        XCTAssertEqual(status, .noneConfigured)
    }
}
