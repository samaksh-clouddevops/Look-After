import Foundation

/// Validates and repairs same-day task schedules so no two tasks overlap.
public enum DayScheduleReconciler {

    public struct Result: Sendable {
        public var tasks: [LifeTask]
        public var changedTaskIDs: Set<String>
        public var conflictTaskIDs: Set<String>

        public init(
            tasks: [LifeTask] = [],
            changedTaskIDs: Set<String> = [],
            conflictTaskIDs: Set<String> = []
        ) {
            self.tasks = tasks
            self.changedTaskIDs = changedTaskIDs
            self.conflictTaskIDs = conflictTaskIDs
        }
    }

    /// Reconciles scheduled tasks on a single day via deterministic cascade.
    /// No unresolved conflicts / no manual prompts — every clash is auto-triaged.
    public static func reconcile(
        tasks: [LifeTask],
        on day: Date,
        model: LifeModel? = nil,
        now: Date = Date(),
        calendar: Calendar = .current,
        bufferMinutes: Int = 5,
        calendarEvents: [BriefingCalendarEvent] = []
    ) -> Result {
        let dayStart = calendar.startOfDay(for: day)

        // 1) Snap life commitments to model block times first.
        var changedIDs = Set<String>()
        let synced: [LifeTask] = tasks.map { task in
            guard task.status.isActive, let scheduledDate = task.scheduledDate,
                  calendar.isDate(scheduledDate, inSameDayAs: dayStart) else {
                return task
            }
            let updated = syncCommitmentTimes(task, model: model, day: dayStart, calendar: calendar)
            if updated.scheduledTime != task.scheduledTime
                || updated.scheduledEndTime != task.scheduledEndTime
                || updated.estimatedMinutes != task.estimatedMinutes {
                changedIDs.insert(task.id)
            }
            return updated
        }

        // 2) Deterministic conflict cascade (anchored > flexible > fluid); calendar occupies.
        let cascade = ConflictResolutionCascade.resolve(
            tasks: synced,
            on: dayStart,
            model: model,
            now: now,
            calendar: calendar,
            bufferMinutes: bufferMinutes,
            parkedQueue: ParkedTaskQueueStore.shared,
            remainingTasks: synced,
            calendarEvents: calendarEvents
        )
        changedIDs.formUnion(cascade.changedTaskIDs)

        // Forest-not-trees: distill macro actions for Morning Briefing (never raw decision spam).
        CascadeActionLog.shared.record(
            result: cascade,
            resurrectedCount: ResurrectedTaskRegistry.shared.activeIDs(now: now).count,
            now: now,
            calendar: calendar
        )

        // Cascade guarantees a clean day — never surface manual conflict IDs.
        return Result(
            tasks: cascade.tasks,
            changedTaskIDs: changedIDs,
            conflictTaskIDs: []
        )
    }

    /// Midnight / day-boundary Reaper sweep.
    /// endOfDay → skipped; strict window miss → expired; collision → superseded; else park.
    public static func sweepDayBoundary(
        tasks: [LifeTask],
        from previousDay: Date,
        to nextDay: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        parkedQueue: ParkedTaskQueueStore? = nil
    ) -> Result {
        let prevStart = calendar.startOfDay(for: previousDay)
        let nextStart = calendar.startOfDay(for: nextDay)

        let tomorrowActives = tasks.filter { task in
            guard task.status.isActive, let d = task.scheduledDate else { return false }
            return calendar.isDate(d, inSameDayAs: nextStart)
        }

        var changed: Set<String> = []
        var decisions: [ConflictCascadeDecision] = []
        var byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        let yesterdayIncomplete = tasks.filter { task in
            guard task.status.isActive, let d = task.scheduledDate else { return false }
            return calendar.isDate(d, inSameDayAs: prevStart)
        }

        for var task in yesterdayIncomplete {
            let policy = TaskEphemeralityDefaults.expiration(for: task)

            if policy == .endOfDay {
                task.status = .skipped
                task.scheduledTime = nil
                task.scheduledEndTime = nil
                task.updatedAt = now
                byID[task.id] = task
                changed.insert(task.id)
                decisions.append(.init(taskID: task.id, action: .expired, reason: "midnight_end_of_day_skip"))
                continue
            }

            if case .strictWindow(let minutes) = policy, let start = task.scheduledTime {
                let combined = calendar.combine(date: calendar.startOfDay(for: task.scheduledDate ?? start), timeFrom: start) ?? start
                if now > combined.addingTimeInterval(TimeInterval(minutes * 60)) {
                    task.status = .expired
                    task.scheduledTime = nil
                    task.scheduledEndTime = nil
                    task.updatedAt = now
                    byID[task.id] = task
                    changed.insert(task.id)
                    decisions.append(.init(taskID: task.id, action: .expired, reason: "midnight_strict_window"))
                    continue
                }
            }

            switch TaskReaper.verdict(
                for: task,
                now: now,
                destinationDayTasks: tomorrowActives,
                calendar: calendar
            ) {
            case .supersede:
                task.status = .superseded
                task.scheduledTime = nil
                task.scheduledEndTime = nil
                task.updatedAt = now
                byID[task.id] = task
                changed.insert(task.id)
                decisions.append(.init(taskID: task.id, action: .superseded, reason: "midnight_semantic_collision"))
                continue
            case .expire:
                task.status = .expired
                task.scheduledTime = nil
                task.scheduledEndTime = nil
                task.updatedAt = now
                byID[task.id] = task
                changed.insert(task.id)
                decisions.append(.init(taskID: task.id, action: .expired, reason: "midnight_reaper_expire"))
                continue
            case .alive:
                break
            }

            // Recurrence occurrences are re-materialized on sync — never park stale series rows.
            if task.parentTaskId != nil {
                task.status = .superseded
                task.scheduledTime = nil
                task.scheduledEndTime = nil
                task.updatedAt = now
                byID[task.id] = task
                changed.insert(task.id)
                decisions.append(.init(taskID: task.id, action: .superseded, reason: "midnight_series_refresh"))
                continue
            }

            task.scheduledTime = nil
            task.scheduledEndTime = nil
            task.scheduledDate = nil
            task.applyTimeConstraint(.fluid)
            task.updatedAt = now
            parkedQueue?.enqueue(from: task, reason: "midnight_rollover_park", now: now)
            byID[task.id] = task
            changed.insert(task.id)
            decisions.append(.init(taskID: task.id, action: .park, reason: "midnight_park_for_rollover"))
        }

        let merged = tasks.map { byID[$0.id] ?? $0 }
        CascadeActionLog.shared.record(
            result: ConflictCascadeResult(tasks: merged, decisions: decisions, changedTaskIDs: changed),
            now: now,
            calendar: calendar
        )
        return Result(tasks: merged, changedTaskIDs: changed, conflictTaskIDs: [])
    }

    /// Returns true when two tasks overlap, or a task overlaps calendar/protected occupancy.
    public static func hasOverlap(
        _ tasks: [LifeTask],
        on day: Date,
        calendar: Calendar = .current,
        calendarEvents: [BriefingCalendarEvent] = [],
        model: LifeModel? = nil
    ) -> Bool {
        OccupiedDay.build(
            tasks: tasks,
            calendarEvents: calendarEvents,
            model: model,
            on: day,
            calendar: calendar
        ).hasOverlap
    }

    // MARK: - Commitment sync

    /// Snaps life-commitment tasks to their LifeModel block start/end when drifted.
    public static func syncCommitmentTimes(
        _ task: LifeTask,
        model: LifeModel?,
        day: Date,
        calendar: Calendar = .current
    ) -> LifeTask {
        guard task.isLifeCommitmentTask, let model else { return task }
        guard let commitment = model.commitments.first(where: {
            task.tags.contains(model.commitmentID(for: $0.title))
                || task.title.caseInsensitiveCompare($0.title) == .orderedSame
        }) else { return task }

        guard let blockLabel = commitment.preferredBlockLabel,
              let block = model.block(matching: blockLabel) else { return task }

        guard block.days.includes(day, calendar: calendar) else { return task }

        var updated = task
        guard let start = calendar.date(
            bySettingHour: block.startHour,
            minute: block.startMinute,
            second: 0,
            of: day
        ) else { return task }

        let endMinutes = block.startMinutesFromMidnight + commitment.defaultMinutes
        let endHour = endMinutes / 60
        let endMinute = endMinutes % 60
        let end = calendar.date(
            bySettingHour: min(endHour, 23),
            minute: endMinute,
            second: 0,
            of: day
        )

        updated.scheduledDate = day
        updated.scheduledTime = start
        updated.scheduledEndTime = end
        updated.estimatedMinutes = commitment.defaultMinutes
        if commitment.isNonNegotiable || block.protection == .neverSchedule || block.protection == .priorityOnly {
            updated.applyTimeConstraint(.anchored)
        } else if updated.schedulingModeValue == .fixedTime {
            updated.applyTimeConstraint(.flexible)
        }
        return updated
    }
}
