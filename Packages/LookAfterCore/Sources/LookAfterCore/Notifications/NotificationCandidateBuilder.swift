import Foundation

/// Builds notification candidates from deterministic app state (no LLM).
public enum NotificationCandidateBuilder {

    public static func build(
        from input: NotificationRefreshInput,
        calendar: Calendar = .current
    ) -> [NotificationCandidate] {
        var candidates: [NotificationCandidate] = []
        let dayKey = ProactiveDailyBudget.dayKey(for: input.now, calendar: calendar)
        let now = input.now

        candidates += medicationCandidates(medications: input.medications, now: now, dayKey: dayKey, calendar: calendar)
        candidates += meetingPrepCandidate(event: input.nextCalendarEvent, now: now, calendar: calendar)
        candidates += taskCandidates(tasks: input.tasks, now: now, calendar: calendar)
        candidates += morningBriefingCandidate(
            postWake: input.postWake,
            userDisplayName: input.userDisplayName,
            now: now,
            dayKey: dayKey,
            calendar: calendar
        )
        candidates += brainHeroCandidate(
            heroTitle: input.heroTaskTitle,
            heroTaskId: input.heroTaskId,
            now: now,
            dayKey: dayKey,
            calendar: calendar
        )
        candidates += focusBreakCandidate(
            focusSessionActive: input.focusSessionActive,
            breakFireDate: input.focusBreakFireDate,
            sessionToken: input.focusSessionToken,
            now: now
        )

        return candidates
    }

    // MARK: - Medication

    private static func medicationCandidates(
        medications: [Medication],
        now: Date,
        dayKey: String,
        calendar: Calendar
    ) -> [NotificationCandidate] {
        medications.compactMap { med in
            guard !med.isTaken else { return nil }
            let scheduledToday = scheduledTimeToday(med.scheduledTime, now: now, calendar: calendar)
            let fireDate: Date
            let body: String

            if isInDueWindow(scheduled: scheduledToday, now: now) {
                fireDate = now.addingTimeInterval(60)
                body = "Take \(med.name) — scheduled for \(timeLabel(scheduledToday))"
            } else if scheduledToday > now {
                fireDate = scheduledToday
                body = "Take \(med.name) — scheduled for \(timeLabel(scheduledToday))"
            } else if isPastDueWindow(scheduled: scheduledToday, now: now) {
                fireDate = now.addingTimeInterval(60)
                body = "Log \(med.name) when you're ready."
            } else {
                return nil
            }

            return NotificationCandidate(
                id: NotificationIdentifier.proactive(.medication, suffix: "\(med.id).\(dayKey)"),
                kind: .medication,
                title: "Medication",
                body: body,
                fireDate: fireDate,
                route: .medication,
                routePayload: med.id
            )
        }
    }

    // MARK: - Meeting prep

    private static func meetingPrepCandidate(
        event: CalendarEventReference?,
        now: Date,
        calendar: Calendar
    ) -> [NotificationCandidate] {
        guard let event else { return [] }
        let minutesUntil = max(0, Int(event.startDate.timeIntervalSince(now) / 60))
        guard minutesUntil >= NotificationPolicy.meetingPrepWindowMin else { return [] }

        let fireDate: Date
        if minutesUntil <= NotificationPolicy.meetingPrepWindowMax {
            fireDate = now.addingTimeInterval(60)
        } else {
            fireDate = event.startDate.addingTimeInterval(-TimeInterval(NotificationPolicy.meetingPrepLeadMinutes * 60))
            guard fireDate > now else { return [] }
        }

        let title = event.title.isEmpty ? "Upcoming meeting" : event.title
        let body = "Meeting in \(max(minutesUntil, NotificationPolicy.meetingPrepLeadMinutes)) min — \(title)"

        return [
            NotificationCandidate(
                id: NotificationIdentifier.proactive(.meetingPrep, suffix: event.id),
                kind: .meetingPrep,
                title: "Meeting prep",
                body: body,
                fireDate: fireDate,
                route: .today,
                routePayload: event.id
            )
        ]
    }

    // MARK: - Tasks

    private static func taskCandidates(
        tasks: [LifeTask],
        now: Date,
        calendar: Calendar
    ) -> [NotificationCandidate] {
        tasks.compactMap { task in
            guard task.status.isActive else { return nil }

            let fireDate: Date?
            if task.isOverdue {
                fireDate = now.addingTimeInterval(60)
            } else if let scheduled = task.scheduledTime, scheduled > now, calendar.isDateInToday(scheduled) {
                fireDate = scheduled
            } else if let deadline = task.deadline, deadline > now, calendar.isDateInToday(deadline) {
                fireDate = deadline.addingTimeInterval(-15 * 60)
            } else {
                return nil
            }

            guard let resolvedFireDate = fireDate, resolvedFireDate > now else { return nil }
            let headline = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !headline.isEmpty else { return nil }

            return NotificationCandidate(
                id: NotificationIdentifier.proactive(.taskDue, suffix: task.id),
                kind: .taskDue,
                title: "Task due",
                body: "Start \(headline)",
                fireDate: resolvedFireDate,
                route: .task,
                routePayload: task.id
            )
        }
    }

    // MARK: - Morning briefing

    private static func morningBriefingCandidate(
        postWake: PostWakeDetector.Result,
        userDisplayName: String,
        now: Date,
        dayKey: String,
        calendar: Calendar
    ) -> [NotificationCandidate] {
        guard postWake.isPostWake else { return [] }
        let greetingName = userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = greetingName.isEmpty ? "Good morning" : "Good morning, \(greetingName)"
        let fireDate = now.addingTimeInterval(2 * 60)

        return [
            NotificationCandidate(
                id: NotificationIdentifier.proactive(.morningBriefing, suffix: dayKey),
                kind: .morningBriefing,
                title: title,
                body: "Your briefing is ready — tap to see today's plan.",
                fireDate: fireDate,
                route: .briefing
            )
        ]
    }

    // MARK: - Brain hero

    private static func brainHeroCandidate(
        heroTitle: String?,
        heroTaskId: String?,
        now: Date,
        dayKey: String,
        calendar: Calendar
    ) -> [NotificationCandidate] {
        guard let heroTitle, !heroTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 10
        components.minute = 0
        let defaultMorning = calendar.date(from: components) ?? now.addingTimeInterval(3600)
        let fireDate = max(defaultMorning, now.addingTimeInterval(30 * 60))

        return [
            NotificationCandidate(
                id: NotificationIdentifier.proactive(.brainHero, suffix: dayKey),
                kind: .brainHero,
                title: "Ready when you are",
                body: "Start \(heroTitle)",
                fireDate: fireDate,
                route: .brain,
                routePayload: heroTaskId
            )
        ]
    }

    // MARK: - Focus break

    private static func focusBreakCandidate(
        focusSessionActive: Bool,
        breakFireDate: Date?,
        sessionToken: String?,
        now: Date
    ) -> [NotificationCandidate] {
        guard focusSessionActive, let breakFireDate, breakFireDate > now else { return [] }
        let token = sessionToken ?? "active"

        return [
            NotificationCandidate(
                id: NotificationIdentifier.focusBreak(sessionToken: token),
                kind: .focusBreak,
                title: "Break time",
                body: "Step away for a few minutes — your focus block is complete.",
                fireDate: breakFireDate,
                route: .focusSession
            )
        ]
    }

    // MARK: - Schedule helpers

    private static func scheduledTimeToday(_ scheduled: Date, now: Date, calendar: Calendar) -> Date {
        let time = calendar.dateComponents([.hour, .minute], from: scheduled)
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = time.hour
        components.minute = time.minute
        return calendar.date(from: components) ?? scheduled
    }

    private static func isInDueWindow(scheduled: Date, now: Date) -> Bool {
        let start = scheduled.addingTimeInterval(-30 * 60)
        let end = scheduled.addingTimeInterval(60 * 60)
        return now >= start && now <= end
    }

    private static func isPastDueWindow(scheduled: Date, now: Date) -> Bool {
        let end = scheduled.addingTimeInterval(60 * 60)
        return now > end
    }

    private static func timeLabel(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
