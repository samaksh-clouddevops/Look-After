import XCTest
@testable import LookAfterCore

final class CompanionEngineTests: XCTestCase {

    func testDurationEstimateRangeWhenLowConfidence() {
        var environment = EnvironmentContext.baseline
        environment.sleepQuality = .poor
        let snapshot = LifeContextSnapshot(
            currentEnergy: 0.3,
            availableTimeMinutes: 45,
            sleepQuality: .poor
        )
        let task = LifeTask(
            title: "OAuth review",
            steps: [
                TaskStep(title: "Step 1", isCompleted: true),
                TaskStep(title: "Step 2", isCompleted: false)
            ],
            estimatedMinutes: 40
        )
        let estimate = DurationEstimator().estimate(
            DurationEstimator.Input(task: task, snapshot: snapshot, priorElapsedMinutes: 5)
        )
        XCTAssertTrue(estimate.displayLabel.contains("About"))
        XCTAssertGreaterThan(estimate.pointMinutes, 0)
    }

    func testContinueExpiresOnNewDayMorning() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let resume = ResumeSnapshot(
            lastTaskTitle: "Search API",
            workingContext: WorkingContext(kind: .task, title: "Search API", taskID: "t1"),
            savedAt: yesterday
        )
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 1
        components.hour = 9
        let morning = Calendar.current.date(from: components)!
        let snapshot = LifeContextSnapshot(currentMission: LifeTask(title: "Design review", estimatedMinutes: 20))
        let decision = ContinueRelevanceEngine().evaluate(
            ContinueRelevanceEngine.Input(
                resume: resume,
                snapshot: snapshot,
                heroTask: snapshot.currentMission,
                now: morning
            )
        )
        if case .freshStart = decision {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected fresh start on new day morning")
        }
    }

    func testContinueWhenRecentlyInterrupted() {
        let resume = ResumeSnapshot(
            lastTaskTitle: "HealthKit Integration",
            workingContext: WorkingContext(kind: .task, title: "HealthKit Integration", taskID: "hk"),
            savedAt: Date().addingTimeInterval(-3600)
        )
        let task = LifeTask(id: "hk", title: "HealthKit Integration", estimatedMinutes: 30)
        let snapshot = LifeContextSnapshot(currentMission: task, lastWorkingContext: WorkingContext(kind: .task, title: "HealthKit Integration", taskID: "hk"))
        let decision = ContinueRelevanceEngine().evaluate(
            ContinueRelevanceEngine.Input(resume: resume, snapshot: snapshot, heroTask: task)
        )
        if case .continueWork(let ctx, _) = decision {
            XCTAssertEqual(ctx.title, "HealthKit Integration")
        } else {
            XCTFail("Expected continue work")
        }
    }

    func testTodaysStoryGenerated() {
        let tasks = [
            LifeTask(title: "OAuth review", estimatedMinutes: 30),
            LifeTask(title: "HealthKit testing", estimatedMinutes: 45)
        ]
        let snapshot = LifeContextSnapshot(sleepQuality: .good)
        let story = TodaysStoryGenerator().generate(
            TodaysStoryGenerator.Input(snapshot: snapshot, tasks: tasks, timelineItems: [], now: Date())
        )
        XCTAssertTrue(story.isReady)
        XCTAssertFalse(story.narrativeParagraphs.isEmpty)
        XCTAssertFalse(story.segments.isEmpty)
    }

    func testSleepInsightIncludesMetrics() {
        let snapshot = LifeContextSnapshot(sleepQuality: .poor)
        var health = HealthSummary()
        health.totalSleepMinutes = 368
        health.deepSleepMinutes = 52
        let insight = InsightBuilder.sleepInsight(snapshot: snapshot, health: health)
        XCTAssertNotNil(insight)
        XCTAssertEqual(insight?.destination, .healthSleep)
        XCTAssertFalse(insight?.metrics.isEmpty ?? true)
    }

    func testPositiveSleepInsightForGoodNight() {
        let snapshot = LifeContextSnapshot(sleepQuality: .good)
        var health = HealthSummary()
        health.totalSleepMinutes = 582
        health.deepSleepMinutes = 95
        let insight = InsightBuilder.sleepInsight(snapshot: snapshot, health: health)
        XCTAssertNotNil(insight)
        XCTAssertTrue(insight?.headline.contains("Well rested") ?? false)
        XCTAssertEqual(insight?.destination, .healthSleep)
    }

    func testBriefingUsesDynamicDurationNotFixedPomodoro() {
        let task = LifeTask(title: "HealthKit Integration", estimatedMinutes: 47)
        let snapshot = LifeContextSnapshot(currentMission: task)
        let briefing = ContextBriefingGenerator().generate(from: snapshot, resume: nil)
        // Duration lives on durationEstimate (supporting line is why-now copy).
        let durationText = [
            briefing.hero.durationEstimate?.displayLabel,
            briefing.hero.durationEstimate?.shortLabel,
            briefing.hero.supportingLine,
            briefing.hero.actionLine
        ].compactMap { $0 }.joined(separator: " ")
        XCTAssertTrue(durationText.contains("47"), "Expected dynamic 47m estimate, got: \(durationText)")
        XCTAssertFalse(durationText.contains("25 min") || durationText.contains("25-minute"))
        XCTAssertEqual(briefing.hero.action.kind, .beginWork)
    }

    func testLowConfidencePromptWhenUncertain() {
        let resume = ResumeSnapshot(
            lastTaskTitle: "Old project",
            workingContext: WorkingContext(kind: .task, title: "Old project"),
            savedAt: Date().addingTimeInterval(-20 * 3600)
        )
        let briefing = ContextBriefingGenerator().generate(
            from: LifeContextSnapshot(),
            resume: resume,
            context: ContextBriefingGenerator.GenerationContext(flowConfidenceScore: 0.4)
        )
        XCTAssertTrue(
            briefing.hero.confidenceLevel == .low ||
            briefing.hero.lowConfidencePrompt != nil ||
            briefing.hero.action.kind == .viewPlan
        )
    }

    func testOutcomeHeadlinePreservesStartWork() {
        XCTAssertEqual(HumanLanguage.outcomeHeadline(title: "Start Work"), "Start Work")
        XCTAssertFalse(HumanLanguage.outcomeHeadline(title: "Start Work").lowercased().contains("finish start"))
    }

    func testOutcomeHeadlineContinueWorkingWhenInProgress() {
        XCTAssertEqual(HumanLanguage.outcomeHeadline(title: "Start Work", progress: 0.4), "Continue Working")
    }

    func testContinueSessionBuildOrFallbackNeverNil() {
        let snapshot = LifeContextSnapshot(currentMission: LifeTask(title: "Start Work", estimatedMinutes: 20))
        let context = ContinueSessionContext.buildOrFallback(
            from: nil,
            task: snapshot.currentMission,
            snapshot: snapshot,
            healthSummary: nil,
            insights: [],
            confidenceScore: 0.8,
            fallbackTitle: "Start Work"
        )
        XCTAssertEqual(context.workingContext.title, "Start Work")
        XCTAssertFalse(context.restorationSteps.isEmpty)
    }
}
