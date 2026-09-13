import Foundation

/// Offers a micro-chunk coach moment when a task has been deferred repeatedly.
/// For high deferral counts on recurring / weekday-bound work, also records a learning hint
/// so the scheduler can deprioritize the current day (Brain #L-003).
public struct DeferralRule: FlowSchedulingRuleProtocol {
    public let deferralThreshold: Int
    /// Above this count, treat as chronic pattern — nudge day shift, not just micro-chunk.
    public let chronicDeferralThreshold: Int

    public let identifier = "DeferralRule"

    public init(deferralThreshold: Int = 3, chronicDeferralThreshold: Int = 5) {
        self.deferralThreshold = deferralThreshold
        self.chronicDeferralThreshold = chronicDeferralThreshold
    }

    public func apply(to state: inout MutableSchedulingState, context: FlowSchedulingContext) {
        guard let hero = state.heroTask else { return }
        let count = context.deferralCount(for: hero.id)
        guard count >= deferralThreshold else { return }

        if count >= chronicDeferralThreshold,
           hero.recurrenceRule != .none || hero.isLifeCommitmentTask {
            // Prefer not to push the same failing weekly plan as a full hero block.
            state.actionType = .tryMicro
            state.suggestedDurationMinutes = min(state.suggestedDurationMinutes, 10)
            if let shifted = ChronicDeferralLearning.shiftedScheduleDate(
                for: hero,
                deferralCount: count,
                from: context.currentTime
            ) {
                let dayLabel = shifted.shortDateString
                let notice = RescheduleNotice(
                    taskID: hero.id,
                    taskTitle: hero.title,
                    explanation: "Often deferred — try moving toward \(dayLabel)."
                )
                if !state.rescheduledTasks.contains(where: { $0.taskID == hero.id }) {
                    state.rescheduledTasks.append(notice)
                }
            }
            state.coachMoment = CoachMoment(
                message: ChronicDeferralLearning.coachMessage(for: hero, deferralCount: count),
                primaryAction: "Try 10 min",
                secondaryAction: "Move this day",
                momentType: .microChunkOffer
            )
            state.reasoningLines.append(
                "Chronic deferral (\(count)×) — micro start + weekday shift suggested (learning)."
            )
            state.appliedRuleIDs.append(identifier)
            return
        }

        state.actionType = .tryMicro
        state.suggestedDurationMinutes = min(state.suggestedDurationMinutes, 5)
        state.coachMoment = CoachMoment(
            message: UserFacingCopy.microActionMessage(deferralCount: count),
            primaryAction: UserFacingCopy.microActionLabel(task: hero),
            secondaryAction: "Not now",
            momentType: .microChunkOffer
        )
        state.reasoningLines.append("Repeated deferrals detected — micro-chunk offered.")
        state.appliedRuleIDs.append(identifier)
    }
}

/// Pure helpers for chronic deferral → preferred weekday shift (Brain #L-003).
public enum ChronicDeferralLearning {
    /// Suggest shifting a weekly commitment one day later when deferred enough times.
    public static func suggestedWeekdayOffset(deferralCount: Int, threshold: Int = 3) -> Int? {
        guard deferralCount >= threshold else { return nil }
        // +1 day after 3 deferrals, +2 after 6, capped at +3.
        let steps = min(3, 1 + (deferralCount - threshold) / 3)
        return steps
    }

    public static func coachMessage(for task: LifeTask, deferralCount: Int) -> String {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let short = title.isEmpty ? "this" : "\"\(title.truncated(to: 28))\""
        return "You've deferred \(short) \(deferralCount) times. Try a shorter start — or move it to a better day."
    }

    /// Returns a new scheduled date one+ days later if the task looks chronically deferred.
    public static func shiftedScheduleDate(
        for task: LifeTask,
        deferralCount: Int,
        from day: Date = Date(),
        calendar: Calendar = .current,
        threshold: Int = 3
    ) -> Date? {
        guard let offset = suggestedWeekdayOffset(deferralCount: deferralCount, threshold: threshold) else {
            return nil
        }
        let start = calendar.startOfDay(for: task.scheduledDate ?? day)
        return calendar.date(byAdding: .day, value: offset, to: start)
    }
}
