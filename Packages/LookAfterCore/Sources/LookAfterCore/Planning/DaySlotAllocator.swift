import Foundation

/// Places flexible tasks into open slots while respecting fixed blocks, priority, and work hours.
public enum DaySlotAllocator {
    public struct Request: Sendable {
        public let id: String
        public let estimatedMinutes: Int
        public let priority: Priority
        public let preferredStart: Date?
        public let hourBounds: PlanningSchedulePolicy.WorkHours?
        public let senseTask: LifeTask?

        public init(
            id: String,
            estimatedMinutes: Int,
            priority: Priority = .medium,
            preferredStart: Date? = nil,
            hourBounds: PlanningSchedulePolicy.WorkHours? = nil,
            senseTask: LifeTask? = nil
        ) {
            self.id = id
            self.estimatedMinutes = estimatedMinutes
            self.priority = priority
            self.preferredStart = preferredStart
            self.hourBounds = hourBounds
            self.senseTask = senseTask
        }

        /// Preferred start, semantic hour fence, and sense payload for one task.
        public static func makingSense(
            of task: LifeTask,
            on day: Date,
            preferredStart: Date? = nil,
            calendar: Calendar = .current
        ) -> Request {
            let preferred = preferredStart
                ?? SemanticPlacementSense.nearestPreferredStart(on: day, for: task, calendar: calendar)
            return Request(
                id: task.id,
                estimatedMinutes: max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes),
                priority: task.priority,
                preferredStart: preferred,
                hourBounds: SemanticPlacementSense.hourBounds(for: task, calendar: calendar),
                senseTask: task
            )
        }
    }

    public struct Allocation: Sendable {
        public let id: String
        public let scheduledTime: Date
    }

    private typealias Interval = TaskScheduleInterval

    public static func allocate(
        requests: [Request],
        existingTasks: [LifeTask],
        workHours: PlanningSchedulePolicy.WorkHours,
        referenceDay: Date? = nil,
        now: Date = Date(),
        calendar: Calendar = .current,
        bufferMinutes: Int = 5,
        extraBlocked: [TaskScheduleInterval] = []
    ) -> [Allocation] {
        guard !requests.isEmpty else { return [] }

        let day = calendar.startOfDay(for: referenceDay ?? now)
        let today = calendar.startOfDay(for: now)
        let floor: Date
        if calendar.isDate(day, inSameDayAs: today) {
            floor = now
        } else {
            // Past and future days are laid out from that morning, not from wall-clock now.
            floor = day
        }
        var blocked = occupiedIntervals(from: existingTasks, on: day, calendar: calendar)
        blocked.append(contentsOf: extraBlocked)
        blocked.sort { $0.start < $1.start }
        var neighbors = existingTasks
        var cursor = PlanningSchedulePolicy.schedulingCursor(now: floor, calendar: calendar, workHours: workHours)
        cursor = advancePastBlocks(cursor, blocked: blocked, bufferMinutes: bufferMinutes, calendar: calendar)

        let sorted = requests.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            switch ($0.preferredStart, $1.preferredStart) {
            case let (left?, right?): return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return $0.id < $1.id
            }
        }

        var results: [Allocation] = []
        for request in sorted {
            let duration = max(request.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
            let hours = request.hourBounds ?? workHours
            let dayEnd = hours.endDate(on: day, calendar: calendar)
            let start = resolveStart(
                ResolveStartInput(
                    preferred: request.preferredStart,
                    cursor: cursor,
                    durationMinutes: duration,
                    bufferMinutes: bufferMinutes,
                    blocked: blocked,
                    workHours: hours,
                    now: floor,
                    calendar: calendar,
                    senseTask: request.senseTask,
                    neighborTasks: neighbors,
                    dayEnd: dayEnd
                )
            )
            guard let start else { continue }

            let end = start.addingTimeInterval(TimeInterval(duration * 60))
            blocked.append(Interval(taskID: request.id, start: start, end: end))
            blocked.sort { $0.start < $1.start }
            results.append(Allocation(id: request.id, scheduledTime: start))
            if var placed = request.senseTask {
                placed.scheduledDate = day
                placed.scheduledTime = start
                placed.scheduledEndTime = end
                neighbors.append(placed)
            }
            cursor = advancePastBlocks(
                calendar.date(byAdding: .minute, value: duration + bufferMinutes, to: start) ?? end,
                blocked: blocked,
                bufferMinutes: bufferMinutes,
                calendar: calendar
            )
        }
        return results
    }

    /// Places flexible tasks across office and creative windows on a specific day.
    public static func allocateAcrossWindows(
        requests: [Request],
        existingTasks: [LifeTask],
        windows: SchedulingWindows,
        on day: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        bufferMinutes: Int = 5,
        calendarEvents: [BriefingCalendarEvent] = []
    ) -> [Allocation] {
        guard !requests.isEmpty else { return [] }

        var remaining = requests
        var occupied = existingTasks.filter { task in
            guard let scheduledDate = task.scheduledDate else { return false }
            return calendar.isDate(scheduledDate, inSameDayAs: day)
        }
        var results: [Allocation] = []
        let extraBlocked =
            OccupiedDay.calendarIntervals(from: calendarEvents, on: day, calendar: calendar)
            + windows.protectedIntervals(on: day, calendar: calendar)

        let boxed = remaining.filter { $0.hourBounds != nil }

        if !boxed.isEmpty {
            let allocated = allocate(
                requests: boxed,
                existingTasks: occupied,
                workHours: windows.officeHours,
                referenceDay: day,
                now: now,
                calendar: calendar,
                bufferMinutes: bufferMinutes,
                extraBlocked: extraBlocked
            )
            for allocation in allocated {
                results.append(allocation)
                if let request = requests.first(where: { $0.id == allocation.id }) {
                    occupied.append(placedTask(from: request, start: allocation.scheduledTime, on: day))
                }
            }
        }

        remaining = requests.filter { request in
            request.hourBounds == nil && !results.contains(where: { $0.id == request.id })
        }

        for window in windows.allSchedulingWindows {
            guard !remaining.isEmpty else { break }
            let allocated = allocate(
                requests: remaining,
                existingTasks: occupied,
                workHours: window,
                referenceDay: day,
                now: now,
                calendar: calendar,
                bufferMinutes: bufferMinutes,
                extraBlocked: extraBlocked
            )
            guard !allocated.isEmpty else { continue }

            for allocation in allocated {
                results.append(allocation)
                remaining.removeAll { $0.id == allocation.id }
                if let request = requests.first(where: { $0.id == allocation.id }) {
                    occupied.append(placedTask(from: request, start: allocation.scheduledTime, on: day))
                }
            }
        }

        return results
    }

    // MARK: - Intervals

    private static func placedTask(from request: Request, start: Date, on day: Date) -> LifeTask {
        var task = request.senseTask ?? LifeTask(
            title: request.id,
            estimatedMinutes: request.estimatedMinutes,
            scheduledDate: day,
            scheduledTime: start
        )
        task.scheduledDate = day
        task.scheduledTime = start
        let duration = max(request.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
        task.scheduledEndTime = start.addingTimeInterval(TimeInterval(duration * 60))
        return task
    }

    private static func occupiedIntervals(
        from tasks: [LifeTask],
        on day: Date,
        calendar: Calendar
    ) -> [Interval] {
        TaskScheduleInterval.intervals(from: tasks, on: day, calendar: calendar)
    }

    // MARK: - Slot search

    private struct ResolveStartInput: Sendable {
        var preferred: Date?
        var cursor: Date
        var durationMinutes: Int
        var bufferMinutes: Int
        var blocked: [Interval]
        var workHours: PlanningSchedulePolicy.WorkHours
        var now: Date
        var calendar: Calendar
        var senseTask: LifeTask?
        var neighborTasks: [LifeTask]
        var dayEnd: Date?
    }

    private static func resolveStart(_ input: ResolveStartInput) -> Date? {
        let preferred = sanitizedPreferred(input.preferred, calendar: input.calendar)

        // Upcoming preferred: try preferred, then later within the window.
        // Never fall back to `now`/cursor *before* that preferred — that parked meals/gym at wall clock.
        if let preferred, preferred >= input.now {
            if fits(
                preferred,
                durationMinutes: input.durationMinutes,
                blocked: input.blocked,
                workHours: input.workHours,
                calendar: input.calendar,
                senseTask: input.senseTask,
                neighborTasks: input.neighborTasks,
                dayEnd: input.dayEnd
            ) {
                return preferred
            }
            if let later = nextOpenSlot(
                startingAt: preferred,
                durationMinutes: input.durationMinutes,
                bufferMinutes: input.bufferMinutes,
                blocked: input.blocked,
                workHours: input.workHours,
                now: input.now,
                calendar: input.calendar,
                senseTask: input.senseTask,
                neighborTasks: input.neighborTasks,
                dayEnd: input.dayEnd
            ) {
                return later
            }
            // Preferred window exhausted — leave unscheduled rather than inventing a premature slot.
            return nil
        }

        return nextOpenSlot(
            startingAt: input.cursor,
            durationMinutes: input.durationMinutes,
            bufferMinutes: input.bufferMinutes,
            blocked: input.blocked,
            workHours: input.workHours,
            now: input.now,
            calendar: input.calendar,
            senseTask: input.senseTask,
            neighborTasks: input.neighborTasks,
            dayEnd: input.dayEnd
        )
    }

    private static func sanitizedPreferred(_ preferred: Date?, calendar: Calendar) -> Date? {
        guard let preferred else { return nil }
        if TaskScheduleInterval.isMidnightTimeOfDay(preferred, calendar: calendar) {
            return nil
        }
        return preferred
    }

    private static func nextOpenSlot(
        startingAt cursor: Date,
        durationMinutes: Int,
        bufferMinutes: Int,
        blocked: [Interval],
        workHours: PlanningSchedulePolicy.WorkHours,
        now: Date,
        calendar: Calendar,
        senseTask: LifeTask?,
        neighborTasks: [LifeTask],
        dayEnd: Date?
    ) -> Date? {
        var candidate = max(cursor, now)
        for _ in 0..<96 {
            if fits(
                candidate,
                durationMinutes: durationMinutes,
                blocked: blocked,
                workHours: workHours,
                calendar: calendar,
                senseTask: senseTask,
                neighborTasks: neighborTasks,
                dayEnd: dayEnd
            ) {
                return candidate
            }
            let probe = Interval(
                taskID: "",
                start: candidate,
                end: candidate.addingTimeInterval(TimeInterval(durationMinutes * 60))
            )
            if let conflict = blocked.first(where: { probe.overlaps($0) }) {
                candidate = conflict.end.addingTimeInterval(TimeInterval(bufferMinutes * 60))
            } else {
                candidate = calendar.date(byAdding: .minute, value: 15, to: candidate) ?? candidate
            }
            if minutesFromMidnight(candidate, calendar: calendar) > workHours.endMinutesFromMidnight {
                return nil
            }
        }
        return nil
    }

    private static func fits(
        _ start: Date,
        durationMinutes: Int,
        blocked: [Interval],
        workHours: PlanningSchedulePolicy.WorkHours,
        calendar: Calendar,
        senseTask: LifeTask?,
        neighborTasks: [LifeTask],
        dayEnd: Date?
    ) -> Bool {
        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        let interval = Interval(taskID: "", start: start, end: end)
        let startMinutes = minutesFromMidnight(start, calendar: calendar)
        let endMinutes = minutesFromMidnight(end, calendar: calendar)
        guard startMinutes >= workHours.startMinutesFromMidnight else { return false }
        guard endMinutes <= workHours.endMinutesFromMidnight else { return false }
        guard !blocked.contains(where: { interval.overlaps($0) }) else { return false }
        guard let task = senseTask else { return true }
        let verdict = SemanticPlacementSense.judge(
            SemanticPlacementSense.Input(
                task: task,
                proposedStart: start,
                durationMinutes: durationMinutes,
                occupied: blocked,
                neighborTasks: neighborTasks,
                calendar: calendar,
                dayEnd: dayEnd
            )
        )
        return SemanticPlacementSense.isSearchableSlot(verdict)
    }

    private static func advancePastBlocks(
        _ cursor: Date,
        blocked: [Interval],
        bufferMinutes: Int,
        calendar: Calendar
    ) -> Date {
        var candidate = cursor
        for _ in 0..<blocked.count {
            guard let conflict = blocked.first(where: { $0.start <= candidate && candidate < $0.end }) else {
                return candidate
            }
            candidate = conflict.end.addingTimeInterval(TimeInterval(bufferMinutes * 60))
        }
        return candidate
    }

    private static func minutesFromMidnight(_ date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}
