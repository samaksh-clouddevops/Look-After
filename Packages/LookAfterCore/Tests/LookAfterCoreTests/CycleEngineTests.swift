import XCTest
@testable import LookAfterCore

final class CycleEngineTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testDisabledWhenTrackingOff() {
        let prefs = CycleTrackingPreferences(isEnabled: false)
        let snapshot = CycleEngine.snapshot(
            CycleEngine.Input(preferences: prefs, calendar: calendar)
        )
        XCTAssertFalse(snapshot.isEnabled)
        XCTAssertEqual(snapshot.phase, .unknown)
    }

    func testMenstrualPhaseDayOne() {
        let periodStart = makeDate(year: 2026, month: 7, day: 28)
        let today = makeDate(year: 2026, month: 7, day: 28)
        let prefs = CycleTrackingPreferences(
            isEnabled: true,
            averageCycleLengthDays: 28,
            averagePeriodLengthDays: 5,
            lastPeriodStart: periodStart
        )

        let snapshot = CycleEngine.snapshot(
            CycleEngine.Input(preferences: prefs, now: today, calendar: calendar)
        )

        XCTAssertEqual(snapshot.cycleDay, 1)
        XCTAssertEqual(snapshot.phase, .menstrual)
        XCTAssertEqual(snapshot.daysUntilPeriod, 27)
    }

    func testLutealPhaseLateCycle() {
        let periodStart = makeDate(year: 2026, month: 7, day: 1)
        let today = makeDate(year: 2026, month: 7, day: 25)
        let prefs = CycleTrackingPreferences(
            isEnabled: true,
            averageCycleLengthDays: 28,
            averagePeriodLengthDays: 5,
            lastPeriodStart: periodStart
        )

        let snapshot = CycleEngine.snapshot(
            CycleEngine.Input(preferences: prefs, now: today, calendar: calendar)
        )

        XCTAssertEqual(snapshot.cycleDay, 25)
        XCTAssertEqual(snapshot.phase, .luteal)
        XCTAssertEqual(snapshot.daysUntilPeriod, 3)
    }

    func testPeriodOneWeekAway() {
        let periodStart = makeDate(year: 2026, month: 7, day: 1)
        let today = makeDate(year: 2026, month: 7, day: 22)
        let prefs = CycleTrackingPreferences(
            isEnabled: true,
            averageCycleLengthDays: 28,
            averagePeriodLengthDays: 5,
            lastPeriodStart: periodStart
        )

        let snapshot = CycleEngine.snapshot(
            CycleEngine.Input(preferences: prefs, now: today, calendar: calendar)
        )

        XCTAssertEqual(snapshot.cycleDay, 22)
        XCTAssertEqual(snapshot.daysUntilPeriod, 6)
        XCTAssertEqual(snapshot.phase, .luteal)
    }

    func testStaleLastPeriodStartRollsForward() {
        let periodStart = makeDate(year: 2026, month: 5, day: 1)
        let today = makeDate(year: 2026, month: 7, day: 22)
        let prefs = CycleTrackingPreferences(
            isEnabled: true,
            averageCycleLengthDays: 28,
            averagePeriodLengthDays: 5,
            lastPeriodStart: periodStart
        )

        let snapshot = CycleEngine.snapshot(
            CycleEngine.Input(preferences: prefs, now: today, calendar: calendar)
        )

        // May 1 → Jun 26 current anchor (28-day cycles); Jul 22 = day 27, period in 1 day
        XCTAssertEqual(snapshot.cycleDay, 27)
        XCTAssertEqual(snapshot.daysUntilPeriod, 1)
    }

    func testRecentSpuriousFlowDoesNotOverrideManualStart() {
        let periodStart = makeDate(year: 2026, month: 7, day: 1)
        let today = makeDate(year: 2026, month: 7, day: 22)
        let spuriousFlow = makeDate(year: 2026, month: 7, day: 21)
        let prefs = CycleTrackingPreferences(
            isEnabled: true,
            averageCycleLengthDays: 28,
            averagePeriodLengthDays: 5,
            lastPeriodStart: periodStart
        )
        let logs = [CycleDayLog(day: spuriousFlow, flow: .light, source: .manual)]

        let snapshot = CycleEngine.snapshot(
            CycleEngine.Input(preferences: prefs, logs: logs, now: today, calendar: calendar)
        )

        XCTAssertEqual(snapshot.cycleDay, 22)
        XCTAssertEqual(snapshot.daysUntilPeriod, 6)
    }

    func testShouldTreatFlowAsNewPeriodStart() {
        let lastStart = makeDate(year: 2026, month: 7, day: 1)
        let prefs = CycleTrackingPreferences(isEnabled: true, lastPeriodStart: lastStart)
        let newPeriod = CycleDayLog(day: makeDate(year: 2026, month: 7, day: 29), flow: .medium, source: .manual)
        let midCycle = CycleDayLog(day: makeDate(year: 2026, month: 7, day: 3), flow: .light, source: .manual)

        XCTAssertTrue(
            CycleEngine.shouldTreatFlowAsNewPeriodStart(log: newPeriod, logs: [], preferences: prefs, calendar: calendar)
        )
        XCTAssertFalse(
            CycleEngine.shouldTreatFlowAsNewPeriodStart(log: midCycle, logs: [], preferences: prefs, calendar: calendar)
        )
    }

    func testLearnedCycleLengthFromLogs() {
        let start1 = makeDate(year: 2026, month: 5, day: 1)
        let start2 = makeDate(year: 2026, month: 5, day: 30)
        let today = makeDate(year: 2026, month: 6, day: 10)
        let logs = [
            CycleDayLog(day: start1, flow: .medium, source: .manual),
            CycleDayLog(day: start2, flow: .heavy, source: .manual),
        ]
        let prefs = CycleTrackingPreferences(
            isEnabled: true,
            lastPeriodStart: start2
        )

        let snapshot = CycleEngine.snapshot(
            CycleEngine.Input(preferences: prefs, logs: logs, now: today, calendar: calendar)
        )

        XCTAssertEqual(snapshot.averageCycleLengthDays, 29)
    }

    func testPeriodDaysHighlightRange() {
        let periodStart = makeDate(year: 2026, month: 7, day: 1)
        let prefs = CycleTrackingPreferences(
            isEnabled: true,
            averageCycleLengthDays: 28,
            averagePeriodLengthDays: 5,
            lastPeriodStart: periodStart
        )
        let rangeStart = calendar.startOfDay(for: periodStart)
        let rangeEnd = calendar.startOfDay(for: makeDate(year: 2026, month: 7, day: 10))
        let days = CycleEngine.periodDays(
            in: rangeStart...rangeEnd,
            input: CycleEngine.Input(preferences: prefs, calendar: calendar)
        )

        XCTAssertEqual(days.count, 5)
        XCTAssertTrue(days.contains(rangeStart))
    }

    func testSymptomFrequencyByPhase() {
        let periodStart = makeDate(year: 2026, month: 7, day: 1)
        let lutealDay = makeDate(year: 2026, month: 7, day: 24)
        let prefs = CycleTrackingPreferences(
            isEnabled: true,
            averageCycleLengthDays: 28,
            averagePeriodLengthDays: 5,
            lastPeriodStart: periodStart
        )
        let logs = [
            CycleDayLog(day: lutealDay, symptoms: ["Headache"], energy: 2, source: .manual),
            CycleDayLog(day: calendar.date(byAdding: .day, value: 1, to: lutealDay)!, symptoms: ["Headache"], energy: 1, source: .manual),
        ]

        let frequencies = CycleEngine.symptomFrequencyByPhase(
            input: CycleEngine.Input(preferences: prefs, logs: logs, calendar: calendar)
        )

        XCTAssertGreaterThanOrEqual(frequencies[.luteal]?["Headache"] ?? 0, 1)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
