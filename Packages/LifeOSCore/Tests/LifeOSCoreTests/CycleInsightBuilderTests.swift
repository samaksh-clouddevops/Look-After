import XCTest
@testable import LifeOSCore

final class CycleInsightBuilderTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testNoInsightsWhenDisabled() {
        let insights = CycleInsightBuilder.build(snapshot: .disabled, logs: [])
        XCTAssertTrue(insights.isEmpty)
    }

    func testLowConfidenceLearningInsight() {
        let snapshot = CycleSnapshot(
            cycleDay: 10,
            phase: .follicular,
            daysUntilPeriod: 18,
            predictedPeriodStart: nil,
            confidence: .low,
            averageCycleLengthDays: 28,
            averagePeriodLengthDays: 5,
            isEnabled: true
        )

        let insights = CycleInsightBuilder.build(snapshot: snapshot, logs: [])
        XCTAssertTrue(insights.contains { $0.headline.contains("learning") })
    }

    func testPeriodApproachingInsight() {
        let snapshot = CycleSnapshot(
            cycleDay: 26,
            phase: .luteal,
            daysUntilPeriod: 2,
            predictedPeriodStart: nil,
            confidence: .medium,
            averageCycleLengthDays: 28,
            averagePeriodLengthDays: 5,
            isEnabled: true
        )

        let insights = CycleInsightBuilder.build(snapshot: snapshot, logs: [])
        XCTAssertTrue(insights.contains { $0.headline == "Period approaching" })
    }

    func testMenstrualRecoveryInsight() {
        let snapshot = CycleSnapshot(
            cycleDay: 1,
            phase: .menstrual,
            daysUntilPeriod: 27,
            predictedPeriodStart: nil,
            confidence: .medium,
            averageCycleLengthDays: 28,
            averagePeriodLengthDays: 5,
            isEnabled: true
        )

        let insights = CycleInsightBuilder.build(snapshot: snapshot, logs: [], sleepHours: 5.5)
        XCTAssertTrue(insights.contains { $0.actionKind == .recoveryMode })
    }

    func testLutealLowEnergyPatternInsight() {
        let periodStart = makeDate(year: 2026, month: 7, day: 1)
        let lutealDay1 = makeDate(year: 2026, month: 7, day: 24)
        let lutealDay2 = makeDate(year: 2026, month: 7, day: 25)
        let prefs = CycleTrackingPreferences(
            isEnabled: true,
            averageCycleLengthDays: 28,
            averagePeriodLengthDays: 5,
            lastPeriodStart: periodStart
        )
        CyclePreferencesStore.save(prefs)
        defer { CyclePreferencesStore.save(.default) }

        let logs = [
            CycleDayLog(day: lutealDay1, energy: 2, source: .manual),
            CycleDayLog(day: lutealDay2, energy: 1, source: .manual),
        ]
        let snapshot = CycleEngine.snapshot(
            CycleEngine.Input(
                preferences: prefs,
                logs: logs,
                now: lutealDay2,
                calendar: calendar
            )
        )

        let insights = CycleInsightBuilder.build(snapshot: snapshot, logs: logs, calendar: calendar)
        XCTAssertTrue(insights.contains { $0.headline == "Luteal phase pattern" })
    }

    func testCapacityModifierMenstrual() {
        let snapshot = CycleSnapshot(
            cycleDay: 1,
            phase: .menstrual,
            daysUntilPeriod: 27,
            predictedPeriodStart: nil,
            confidence: .medium,
            averageCycleLengthDays: 28,
            averagePeriodLengthDays: 5,
            isEnabled: true
        )

        let modifier = CycleInsightBuilder.capacityModifier(snapshot: snapshot, logs: [])
        XCTAssertEqual(modifier, -12)
    }

    func testCapacityModifierDisabled() {
        XCTAssertEqual(CycleInsightBuilder.capacityModifier(snapshot: .disabled, logs: []), 0)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
