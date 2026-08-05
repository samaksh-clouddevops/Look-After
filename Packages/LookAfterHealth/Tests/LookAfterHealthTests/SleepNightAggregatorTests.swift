import XCTest
@testable import LookAfterHealth

final class SleepNightAggregatorTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func sample(
        from start: Date,
        to end: Date,
        value: Int,
        bundle: String,
        name: String = ""
    ) -> SleepSampleInput {
        SleepSampleInput(
            start: start,
            end: end,
            categoryValue: value,
            sourceBundleId: bundle,
            sourceName: name
        )
    }

    func testOverlappingAppleWatchAndIPhoneSleepDoesNotDoubleCount() {
        let now = date(2026, 8, 5, 8, 0)
        let bed = date(2026, 8, 4, 23, 0)
        let wake = date(2026, 8, 5, 6, 0)

        let watch = stagedNight(from: bed, to: wake, bundle: "com.apple.health", name: "Apple Watch")
        let iphoneSleep = [
            sample(from: bed, to: wake, value: SleepCategoryValue.inBed, bundle: "com.apple.health", name: "iPhone")
        ]

        let result = SleepNightAggregator.aggregate(samples: watch + iphoneSleep, now: now, calendar: calendar)

        XCTAssertEqual(result.totalAsleepMinutes, 420, accuracy: 1)
        XCTAssertEqual(result.sessionCount, 1)
        XCTAssertEqual(result.primarySourceBundleId, "com.apple.health")
    }

    func testOverlappingWatchStagesAndThirdPartySleepTrackerDoesNotDoubleCount() {
        let now = date(2026, 8, 5, 8, 0)
        let bed = date(2026, 8, 4, 23, 0)
        let wake = date(2026, 8, 5, 6, 0)

        let watch = stagedNight(from: bed, to: wake, bundle: "com.apple.health")
        let sleepTracker = [
            sample(
                from: bed,
                to: wake,
                value: SleepCategoryValue.asleepUnspecified,
                bundle: "com.autosleep.app",
                name: "AutoSleep"
            )
        ]

        let result = SleepNightAggregator.aggregate(samples: watch + sleepTracker, now: now, calendar: calendar)

        XCTAssertEqual(result.totalAsleepMinutes, 420, accuracy: 1)
    }

    func testMotraWorkoutSourceIsIgnoredOnSleepSamples() {
        let now = date(2026, 8, 5, 8, 0)
        let bed = date(2026, 8, 4, 23, 0)
        let wake = date(2026, 8, 5, 6, 0)

        let watch = stagedNight(from: bed, to: wake, bundle: "com.apple.health")
        let motraSleepNoise = [
            sample(
                from: bed,
                to: wake,
                value: SleepCategoryValue.asleepUnspecified,
                bundle: "com.trainfitness.ios",
                name: "Motra"
            )
        ]

        let result = SleepNightAggregator.aggregate(samples: watch + motraSleepNoise, now: now, calendar: calendar)

        XCTAssertEqual(result.totalAsleepMinutes, 420, accuracy: 1)
        XCTAssertFalse(HealthSourceCatalog.isWorkoutOnlySource("com.apple.health"))
        XCTAssertTrue(HealthSourceCatalog.isWorkoutOnlySource("com.trainfitness.ios"))
    }

    func testOldSummingLogicWouldInflateToFourteenHours() {
        let now = date(2026, 8, 5, 8, 0)
        let bed = date(2026, 8, 4, 23, 0)
        let wake = date(2026, 8, 5, 6, 0)

        let watch = stagedNight(from: bed, to: wake, bundle: "com.apple.health")
        let duplicateTracker = [
            sample(from: bed, to: wake, value: SleepCategoryValue.asleepUnspecified, bundle: "com.autosleep.app")
        ]

        let naiveSum = (watch + duplicateTracker).reduce(0.0) { $0 + $1.durationMinutes }
        XCTAssertGreaterThan(naiveSum, 800)

        let result = SleepNightAggregator.aggregate(samples: watch + duplicateTracker, now: now, calendar: calendar)
        XCTAssertEqual(result.totalAsleepMinutes, 420, accuracy: 1)
    }

    func testOverlappingStageSegmentsFromSameSourceDoNotInflateTotal() {
        let now = date(2026, 8, 5, 8, 0)
        let bed = date(2026, 8, 4, 23, 0)
        let wake = date(2026, 8, 5, 6, 0)

        // Two overlapping core segments — old sum logic would count ~9h.
        let overlapping = [
            sample(from: bed, to: date(2026, 8, 5, 4, 0), value: SleepCategoryValue.asleepCore, bundle: "com.apple.health"),
            sample(from: date(2026, 8, 5, 2, 0), to: wake, value: SleepCategoryValue.asleepCore, bundle: "com.apple.health"),
        ]

        let result = SleepNightAggregator.aggregate(samples: overlapping, now: now, calendar: calendar)
        XCTAssertEqual(result.totalAsleepMinutes, 420, accuracy: 1)
    }

    func testPicksLongestSessionWhenNapAndMainSleepBothEndToday() {
        let now = date(2026, 8, 5, 15, 0)
        let main = stagedNight(
            from: date(2026, 8, 4, 23, 0),
            to: date(2026, 8, 5, 6, 0),
            bundle: "com.apple.health"
        )
        let nap = [
            sample(
                from: date(2026, 8, 5, 14, 0),
                to: date(2026, 8, 5, 14, 45),
                value: SleepCategoryValue.asleepUnspecified,
                bundle: "com.apple.health"
            )
        ]

        let result = SleepNightAggregator.aggregate(samples: main + nap, now: now, calendar: calendar)

        XCTAssertEqual(result.totalAsleepMinutes, 420, accuracy: 1)
        XCTAssertEqual(result.sessionCount, 2)
        XCTAssertEqual(result.wakeTime, date(2026, 8, 5, 6, 0))
    }

    func testInBedFallbackWhenNoAsleepSamples() {
        let now = date(2026, 8, 5, 8, 0)
        let samples = [
            sample(
                from: date(2026, 8, 4, 23, 0),
                to: date(2026, 8, 5, 7, 0),
                value: SleepCategoryValue.inBed,
                bundle: "com.apple.health"
            )
        ]

        let result = SleepNightAggregator.aggregate(samples: samples, now: now, calendar: calendar)

        XCTAssertEqual(result.totalAsleepMinutes, 480, accuracy: 1)
        XCTAssertEqual(result.coreMinutes, 480, accuracy: 1)
    }

    func testMergeIntervalsUnionsOverlap() {
        let merged = SleepNightAggregator.mergeIntervals([
            (date(2026, 8, 4, 23, 0), date(2026, 8, 5, 3, 0)),
            (date(2026, 8, 5, 2, 0), date(2026, 8, 5, 6, 0)),
        ])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(SleepNightAggregator.minutes(in: merged), 420, accuracy: 1)
    }

    // MARK: - Fixtures

    /// 7h staged night: 1h core, 2h deep, 4h REM.
    private func stagedNight(from bed: Date, to wake: Date, bundle: String, name: String = "Apple Watch") -> [SleepSampleInput] {
        let deepStart = calendar.date(byAdding: .hour, value: 1, to: bed)!
        let remStart = calendar.date(byAdding: .hour, value: 3, to: bed)!
        return [
            sample(from: bed, to: deepStart, value: SleepCategoryValue.asleepCore, bundle: bundle, name: name),
            sample(from: deepStart, to: remStart, value: SleepCategoryValue.asleepDeep, bundle: bundle, name: name),
            sample(from: remStart, to: wake, value: SleepCategoryValue.asleepREM, bundle: bundle, name: name),
        ]
    }
}
