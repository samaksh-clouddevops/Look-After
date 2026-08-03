import Foundation
import LookAfterCore
import ExecutiveBrain

public struct DecisionFixture: Codable, Sendable {
    public var id: String
    public var sourceDocument: String
    public var input: FixtureInput
    public var expectedDecision: ExpectedDecision
    public var minMatchScore: Double
}

public struct FixtureInput: Codable, Sendable {
    public var sleepHours: Double?
    public var freeBlockMinutes: Int?
    public var nextEventMinutes: Int?
    public var nextEventTitle: String?
    public var taskTitle: String?
    public var taskMinutes: Int?
    public var energyScore: Double?
    public var medicationName: String?
    public var medicationHour: Int?
    public var medicationMinute: Int?
    public var deadlineTitle: String?
    public var deadlineDueDays: Int?
    public var scheduledGym: Bool?
    public var now: String?
}

public struct ExpectedDecision: Codable, Sendable {
    public var intentContains: [String]?
    public var mustNotRecommend: [String]?
    public var conclusionsContainAny: [String]?
    public var planContainsMedication: String?
}

public struct BrainFixtureBuilder: Sendable {
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public init() {}

    public func buildInput(from fixture: FixtureInput) -> BrainTickInput {
        var environment = EnvironmentContext.baseline
        if let free = fixture.freeBlockMinutes {
            environment.freeBlockMinutes = free
        }
        if let nextMin = fixture.nextEventMinutes, let title = fixture.nextEventTitle {
            let now = parseDate(fixture.now) ?? Date()
            environment.nextEvent = CalendarEventReference(
                id: "evt-1",
                title: title,
                startDate: now.addingTimeInterval(TimeInterval(nextMin * 60)),
                endDate: now.addingTimeInterval(TimeInterval((nextMin + 30) * 60)),
                minutesUntilStart: nextMin
            )
        }

        var tasks: [LifeTask] = []
        if let title = fixture.taskTitle {
            tasks.append(LifeTask(title: title, estimatedMinutes: fixture.taskMinutes ?? 30))
        }
        if fixture.scheduledGym == true {
            tasks.append(LifeTask(title: "Gym", estimatedMinutes: 60))
        }

        let energy = fixture.energyScore ?? 0.6
        let available = fixture.freeBlockMinutes ?? 60
        let hero = tasks.first
        let snapshot = ContextEngine().calculate(ContextEngineInput(
            cognitiveSnapshot: CognitiveSnapshot(energyScore: energy, availableMinutes: available),
            environment: environment,
            heroTask: hero,
            topTasks: tasks
        ))

        var medications: [Medication] = []
        if let medName = fixture.medicationName,
           let hour = fixture.medicationHour,
           let minute = fixture.medicationMinute {
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            let scheduled = Calendar.current.date(from: components) ?? Date()
            medications.append(Medication(name: medName, dosage: "dose", scheduledTime: scheduled))
        }

        var health: HealthSummary?
        if let sleep = fixture.sleepHours {
            var h = HealthSummary()
            h.totalSleepMinutes = sleep * 60
            health = h
        }

        return BrainTickInput(
            snapshot: snapshot,
            healthSummary: health,
            medications: medications,
            tasks: tasks,
            now: parseDate(fixture.now) ?? Date()
        )
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        if let d = isoFormatter.date(from: string) { return d }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return fallback.date(from: string)
    }
}

public struct DecisionRegressionRunner: Sendable {
    private let engine = ExecutiveBrainEngine()
    private let builder = BrainFixtureBuilder()

    public init() {}

    public func run(fixturesDir: String = EVPPaths.fixture("decisions")) throws -> [TestResult] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: fixturesDir) else {
            throw EVPError.io("Cannot read fixtures: \(fixturesDir)")
        }

        var results: [TestResult] = []
        for file in files.sorted() where file.hasSuffix(".json") {
            let path = (fixturesDir as NSString).appendingPathComponent(file)
            let start = Date()
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let fixture = try JSONDecoder().decode(DecisionFixture.self, from: data)
            let result = evaluate(fixture: fixture, fixturePath: path, startedAt: start)
            results.append(result)
        }
        return results
    }

    public func run(requirementId: String, fixturesDir: String = EVPPaths.fixture("decisions")) throws -> TestResult {
        let all = try run(fixturesDir: fixturesDir)
        guard let match = all.first(where: { $0.requirementId == requirementId }) else {
            throw EVPError.runner("No fixture for \(requirementId)")
        }
        return match
    }

    private func evaluate(fixture: DecisionFixture, fixturePath: String, startedAt: Date) -> TestResult {
        let input = builder.buildInput(from: fixture.input)
        let state = engine.tick(input)
        let score = matchScore(state: state, expected: fixture.expectedDecision)
        let passed = score >= fixture.minMatchScore
        let duration = Int(Date().timeIntervalSince(startedAt) * 1000)

        let intentText = describeIntent(state)
        let conclusions = state.decision.reasoning.conclusions.joined(separator: " ")

        return TestResult(
            requirementId: fixture.id,
            sourceDocument: fixture.sourceDocument,
            validationLayer: .decision,
            status: passed ? .pass : .fail,
            durationMs: duration,
            evidence: [
                "fixture: \(fixturePath)",
                "matchScore: \(String(format: "%.3f", score))",
                "intent: \(intentText)",
                "conclusions: \(conclusions.prefix(200))"
            ],
            message: passed ? nil : "Score \(String(format: "%.3f", score)) below min \(fixture.minMatchScore)"
        )
    }

    private func matchScore(state: BrainState, expected: ExpectedDecision) -> Double {
        var points = 0.0
        var total = 0.0

        let intentText = describeIntent(state).lowercased()
        let conclusions = state.decision.reasoning.conclusions.joined(separator: " ").lowercased()
        let headline = state.decision.headline.lowercased()
        let combined = intentText + " " + conclusions + " " + headline

        if let contains = expected.intentContains, !contains.isEmpty {
            total += 1
            if contains.allSatisfy({ combined.contains($0.lowercased()) }) {
                points += 1
            }
        }

        if let any = expected.conclusionsContainAny, !any.isEmpty {
            total += 1
            if any.contains(where: { combined.contains($0.lowercased()) }) {
                points += 1
            }
        }

        if let banned = expected.mustNotRecommend {
            total += 1
            let hasBanned = banned.contains { combined.contains($0.lowercased()) }
            if !hasBanned { points += 1 }
        }

        if let med = expected.planContainsMedication {
            total += 1
            let hasMed = state.plan.blocks.contains { $0.kind == .medication && $0.title == med }
            if hasMed { points += 1 }
        }

        if total == 0 {
            return state.decision.confidence > 0 ? 1.0 : 0.0
        }
        return points / total
    }

    private func describeIntent(_ state: BrainState) -> String {
        var parts: [String] = [state.decision.headline, state.decision.primaryAction.label]
        parts.append(state.decision.reasoning.conclusions.joined(separator: "; "))
        parts.append(state.hero.actionLine)
        return parts.joined(separator: " | ")
    }
}
