import Foundation

/// Places flexible tasks into open slots while respecting fixed blocks, priority, and work hours.
public enum DaySlotAllocator {
    public struct Request: Sendable {
        public let id: String
        public let estimatedMinutes: Int
        public let priority: Priority
        public let preferredStart: Date?

        public init(
            id: String,
            estimatedMinutes: Int,
            priority: Priority = .medium,
            preferredStart: Date? = nil
        ) {
            self.id = id
            self.estimatedMinutes = estimatedMinutes
            self.priority = priority
            self.preferredStart = preferredStart
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
        bufferMinutes: Int = 5
    ) -> [Allocation] {
        guard !requests.isEmpty else { return [] }

        let day = calendar.startOfDay(for: referenceDay ?? now)
        let isFutureDay = day > calendar.startOfDay(for: now)
        let floor = isFutureDay ? day : now
        var blocked = occupiedIntervals(from: existingTasks, on: day, calendar: calendar)
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
            let start = resolveStart(
                ResolveStartInput(
                    preferred: request.preferredStart,
                    cursor: cursor,
                    durationMinutes: duration,
                    bufferMinutes: bufferMinutes,
                    blocked: blocked,
                    workHours: workHours,
                    now: floor,
                    calendar: calendar
                )
            )
            guard let start else { continue }

            let end = start.addingTimeInterval(TimeInterval(duration * 60))
            blocked.append(Interval(taskID: request.id, start: start, end: end))
            blocked.sort { $0.start < $1.start }
            results.append(Allocation(id: request.id, scheduledTime: start))
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
        bufferMinutes: Int = 5
    ) -> [Allocation] {
        guard !requests.isEmpty else { return [] }

        var remaining = requests
        var occupied = existingTasks.filter { task in
            guard let scheduledDate = task.scheduledDate else { return false }
            return calendar.isDate(scheduledDate, inSameDayAs: day)
        }
        var results: [Allocation] = []

        for window in windows.allSchedulingWindows {
            guard !remaining.isEmpty else { break }
            let allocated = allocate(
                requests: remaining,
                existingTasks: occupied,
                workHours: window,
                referenceDay: day,
                now: now,
                calendar: calendar,
                bufferMinutes: bufferMinutes
            )
            guard !allocated.isEmpty else { continue }

            for allocation in allocated {
                results.append(allocation)
                remaining.removeAll { $0.id == allocation.id }
                if let request = requests.first(where: { $0.id == allocation.id }) {
                    let placeholder = LifeTask(
                        title: request.id,
                        estimatedMinutes: request.estimatedMinutes,
                        scheduledDate: day,
                        scheduledTime: allocation.scheduledTime
                    )
                    occupied.append(placeholder)
                }
            }
        }

        return results
    }

    // MARK: - Intervals

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
    }

    private static func resolveStart(_ input: ResolveStartInput) -> Date? {
        if let preferred = input.preferred,
           preferred >= input.now,
           fits(
            preferred,
            durationMinutes: input.durationMinutes,
            blocked: input.blocked,
            workHours: input.workHours,
            calendar: input.calendar
           ) {
            return preferred
        }
        return nextOpenSlot(
            startingAt: input.cursor,
            durationMinutes: input.durationMinutes,
            bufferMinutes: input.bufferMinutes,
            blocked: input.blocked,
            workHours: input.workHours,
            now: input.now,
            calendar: input.calendar
        )
    }

    private static func nextOpenSlot(
        startingAt cursor: Date,
        durationMinutes: Int,
        bufferMinutes: Int,
        blocked: [Interval],
        workHours: PlanningSchedulePolicy.WorkHours,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        var candidate = max(cursor, now)
        for _ in 0..<96 {
            if fits(candidate, durationMinutes: durationMinutes, blocked: blocked, workHours: workHours, calendar: calendar) {
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
        calendar: Calendar
    ) -> Bool {
        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        let interval = Interval(taskID: "", start: start, end: end)
        let startMinutes = minutesFromMidnight(start, calendar: calendar)
        let endMinutes = minutesFromMidnight(end, calendar: calendar)
        guard startMinutes >= workHours.startMinutesFromMidnight else { return false }
        guard endMinutes <= workHours.endMinutesFromMidnight else { return false }
        return !blocked.contains { interval.overlaps($0) }
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
