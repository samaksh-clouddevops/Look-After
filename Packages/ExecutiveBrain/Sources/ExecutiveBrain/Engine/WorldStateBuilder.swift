import Foundation
import LookAfterCore

/// Fuses fragmented signals into one canonical WorldState.
public struct WorldStateBuilder: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func build(from input: BrainTickInput) -> WorldState {
        let snapshot = input.snapshot
        let sleepHours = input.healthSummary.flatMap { summary -> Double? in
            guard let minutes = summary.totalSleepMinutes, minutes > 0 else { return nil }
            return minutes / 60.0
        }

        let cognitiveLoad = resolveCognitiveLoad(
            energy: snapshot.currentEnergy,
            sleepQuality: snapshot.sleepQuality,
            minutesUntilMeeting: snapshot.calendarAvailability.minutesUntilNextEvent
        )

        let deadlines = input.tasks
            .filter { $0.status.isActive }
            .compactMap { task -> TaskDeadlineRef? in
                guard let deadline = task.deadline else { return nil }
                let days = calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: input.now),
                    to: calendar.startOfDay(for: deadline)
                ).day ?? 0
                return TaskDeadlineRef(id: task.id, taskTitle: task.title, deadline: deadline, daysRemaining: days)
            }
            .sorted { $0.deadline < $1.deadline }

        let meetingCount = input.timelineItems.filter {
            $0.kind == .meeting
                && calendar.isDate($0.date, inSameDayAs: input.now)
                && !$0.isCompleted
        }.count

        return WorldState(
            generatedAt: input.now,
            currentEnergy: snapshot.currentEnergy,
            cognitiveLoad: cognitiveLoad,
            sleepHoursLastNight: sleepHours,
            sleepQuality: snapshot.sleepQuality,
            healthReadiness: snapshot.healthReadiness,
            availableMinutes: snapshot.availableTimeMinutes,
            minutesUntilNextEvent: snapshot.calendarAvailability.minutesUntilNextEvent,
            nextEventTitle: snapshot.calendarAvailability.nextEventTitle,
            isMeetingHeavyDay: meetingCount >= 3,
            currentMission: snapshot.currentMission,
            topTasks: Array(input.tasks.filter { $0.status.isActive }.prefix(8)),
            upcomingDeadlines: deadlines,
            lastWorkingContext: snapshot.lastWorkingContext,
            location: snapshot.location,
            medicationStatus: MedicationReasoningEngine.buildWorldStatus(
                medications: input.medications,
                now: input.now,
                calendar: calendar
            ),
            unpurchasedShoppingCount: snapshot.unpurchasedShoppingCount,
            unpaidBillsCount: input.upcomingBills.filter { !$0.isPaid }.count,
            isInFlowSession: input.snapshot.lastWorkingContext?.kind == .focusSession,
            resumeSnapshot: input.resume
        )
    }

    private func resolveCognitiveLoad(
        energy: Double,
        sleepQuality: SleepQuality,
        minutesUntilMeeting: Int?
    ) -> CognitiveLoadLevel {
        if sleepQuality == .poor || energy < 0.35 { return .overloaded }
        if let mins = minutesUntilMeeting, mins <= 30 { return .high }
        if energy < 0.55 { return .moderate }
        return .low
    }
}
