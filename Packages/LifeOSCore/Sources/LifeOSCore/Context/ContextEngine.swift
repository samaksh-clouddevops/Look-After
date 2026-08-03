import Foundation

/// Input bundle for a single context calculation pass.
public struct ContextEngineInput: Sendable {
    public var cognitiveSnapshot: CognitiveSnapshot?
    public var healthSummary: HealthSummary?
    public var environment: EnvironmentContext
    public var flowSurface: FlowSurface?
    public var activeFlowSession: FlowSessionState?
    public var heroTask: LifeTask?
    public var topTasks: [LifeTask]
    public var unpurchasedShoppingCount: Int
    public var resumeSnapshot: ResumeSnapshot?
    public var now: Date
    public var peakStartHour: Int

    public init(
        cognitiveSnapshot: CognitiveSnapshot? = nil,
        healthSummary: HealthSummary? = nil,
        environment: EnvironmentContext = .baseline,
        flowSurface: FlowSurface? = nil,
        activeFlowSession: FlowSessionState? = nil,
        heroTask: LifeTask? = nil,
        topTasks: [LifeTask] = [],
        unpurchasedShoppingCount: Int = 0,
        resumeSnapshot: ResumeSnapshot? = nil,
        now: Date = Date(),
        peakStartHour: Int = 9
    ) {
        self.cognitiveSnapshot = cognitiveSnapshot
        self.healthSummary = healthSummary
        self.environment = environment
        self.flowSurface = flowSurface
        self.activeFlowSession = activeFlowSession
        self.heroTask = heroTask
        self.topTasks = topTasks
        self.unpurchasedShoppingCount = unpurchasedShoppingCount
        self.resumeSnapshot = resumeSnapshot
        self.now = now
        self.peakStartHour = peakStartHour
    }
}

/// Continuously fuses signals into a single situational snapshot.
public struct ContextEngine: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func calculate(_ input: ContextEngineInput) -> LifeContextSnapshot {
        let energy = resolveEnergy(input)
        let availableTime = resolveAvailableTime(input)
        let location = resolveLocation(input)
        let devices = resolveDevices(input)
        let calendarSummary = resolveCalendar(input)
        let sleep = resolveSleepQuality(input)
        let readiness = resolveHealthReadiness(input, energy: energy, sleep: sleep)
        let mission = resolveMission(input)
        let lastContext = resolveLastWorkingContext(input)
        let completion = resolveCompletionProbability(input, energy: energy, availableTime: availableTime, readiness: readiness)

        return LifeContextSnapshot(
            currentEnergy: energy,
            availableTimeMinutes: availableTime,
            location: location,
            activeDevices: devices,
            calendarAvailability: calendarSummary,
            sleepQuality: sleep,
            healthReadiness: readiness,
            currentMission: mission,
            lastWorkingContext: lastContext,
            completionProbability: completion,
            unpurchasedShoppingCount: input.unpurchasedShoppingCount,
            calculatedAt: input.now
        )
    }

    // MARK: - Resolvers

    private func resolveEnergy(_ input: ContextEngineInput) -> Double {
        if input.activeFlowSession?.isActive == true { return max(input.environment.energyScore, 0.72) }
        if let surface = input.flowSurface { return surface.energyScore }
        if let snap = input.cognitiveSnapshot { return snap.energyScore }
        return input.environment.energyScore
    }

    private func resolveAvailableTime(_ input: ContextEngineInput) -> Int {
        if let event = input.environment.nextEvent, event.minutesUntilStart > 0 {
            return min(input.environment.freeBlockMinutes, event.minutesUntilStart)
        }
        if let snap = input.cognitiveSnapshot, snap.availableMinutes > 0 {
            return min(snap.availableMinutes, input.environment.freeBlockMinutes)
        }
        return input.environment.freeBlockMinutes
    }

    private func resolveLocation(_ input: ContextEngineInput) -> LocationContext {
        if let loc = input.environment.locationContext { return loc }
        return .unknown
    }

    private func resolveDevices(_ input: ContextEngineInput) -> ActiveDeviceSummary {
        var parts: [String] = []
        if input.environment.focusModeEnabled { parts.append("Focus on") }
        let battery = Int(input.environment.batteryLevel * 100)
        parts.append("\(battery)% battery")
        if input.environment.isLowPowerMode { parts.append("Low Power") }
        let label = parts.isEmpty ? "Device ready" : parts.joined(separator: " · ")
        return ActiveDeviceSummary(
            focusModeEnabled: input.environment.focusModeEnabled,
            batteryLevel: input.environment.batteryLevel,
            isLowPowerMode: input.environment.isLowPowerMode,
            label: label
        )
    }

    private func resolveCalendar(_ input: ContextEngineInput) -> CalendarAvailabilitySummary {
        let event = input.environment.nextEvent ?? input.flowSurface?.nextCalendarEvent
        return CalendarAvailabilitySummary(
            freeBlockMinutes: input.environment.freeBlockMinutes,
            nextEventTitle: event?.title,
            minutesUntilNextEvent: event?.minutesUntilStart,
            hasOpenFlowWindow: input.environment.flowWindow != nil || input.environment.freeBlockMinutes >= 25
        )
    }

    private func resolveSleepQuality(_ input: ContextEngineInput) -> SleepQuality {
        if input.environment.sleepQuality != .unknown { return input.environment.sleepQuality }
        if let score = input.healthSummary?.sleepQualityScore {
            if score >= 0.8 { return .excellent }
            if score >= 0.65 { return .good }
            if score >= 0.45 { return .fair }
            return .poor
        }
        return .unknown
    }

    private func resolveHealthReadiness(_ input: ContextEngineInput, energy: Double, sleep: SleepQuality) -> Double {
        var score = energy
        if let snap = input.cognitiveSnapshot {
            score = (score + snap.recoveryScore + snap.focusCapacity) / 3.0
        }
        if let surface = input.flowSurface {
            score = (score + surface.focusReadiness) / 2.0
        }
        switch sleep {
        case .excellent: score += 0.08
        case .good: break
        case .fair: score -= 0.08
        case .poor: score -= 0.18
        case .unknown: break
        }
        return min(max(score, 0), 1)
    }

    private func resolveMission(_ input: ContextEngineInput) -> LifeTask? {
        if input.activeFlowSession?.isActive == true,
           let id = input.activeFlowSession?.taskID,
           let task = input.topTasks.first(where: { $0.id == id }) ?? input.heroTask, task.id == id {
            return task
        }

        let candidates = uniqueMissionCandidates(from: input)
        return candidates.first { task in
            TaskHeroEligibility.isEligible(
                for: task,
                now: input.now,
                calendar: calendar,
                allTasks: input.topTasks
            )
        }
    }

    private func uniqueMissionCandidates(from input: ContextEngineInput) -> [LifeTask] {
        var seen = Set<String>()
        var ordered: [LifeTask] = []
        for task in [input.heroTask, input.flowSurface?.heroTask].compactMap({ $0 }) + input.topTasks {
            guard seen.insert(task.id).inserted else { continue }
            ordered.append(task)
        }
        return ordered
    }

    private func resolveLastWorkingContext(_ input: ContextEngineInput) -> WorkingContext? {
        if let session = input.activeFlowSession, session.isActive,
           let task = input.heroTask ?? input.topTasks.first(where: { $0.id == session.taskID }) {
            let mins = session.elapsedSeconds / 60
            return WorkingContext(
                kind: .focusSession,
                title: task.title,
                subtitle: "\(mins)m in flow",
                taskID: task.id
            )
        }
        if let resume = input.resumeSnapshot?.workingContext,
           input.resumeSnapshot?.isStale != true,
           !resume.isStale(at: input.now) {
            return resume
        }
        if let title = input.resumeSnapshot?.lastTaskTitle {
            return WorkingContext(kind: .task, title: title, taskID: input.resumeSnapshot?.lastTaskID)
        }
        return nil
    }

    private func resolveCompletionProbability(
        _ input: ContextEngineInput,
        energy: Double,
        availableTime: Int,
        readiness: Double
    ) -> Double {
        guard let mission = resolveMission(input) else { return readiness * energy }

        if let taskProb = mission.completionProbability {
            return min(max(taskProb, 0), 1)
        }
        if let prediction = input.flowSurface?.prediction, prediction.taskID == mission.id, prediction.confidence > 0 {
            return prediction.confidence
        }

        let duration = mission.estimatedMinutes
        let timeFit: Double = availableTime >= duration ? 1.0 : (availableTime >= 15 ? 0.65 : 0.35)
        let flowBoost = input.activeFlowSession?.isActive == true ? 0.12 : 0
        let raw = (energy * 0.35) + (readiness * 0.35) + (timeFit * 0.3) + flowBoost
        return min(max(raw, 0.05), 0.98)
    }
}

private extension WorkingContext {
    func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(capturedAt) > 86_400
    }
}
