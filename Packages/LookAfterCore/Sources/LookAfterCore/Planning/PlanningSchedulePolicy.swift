import Foundation

/// Validates and normalizes schedule slots for day planning.
public enum PlanningSchedulePolicy {
    public struct WorkHours: Sendable, Equatable {
        public var startHour: Int
        public var startMinute: Int
        public var endHour: Int
        public var endMinute: Int

        public init(startHour: Int = 9, startMinute: Int = 0, endHour: Int = 18, endMinute: Int = 0) {
            self.startHour = min(max(startHour, 0), 23)
            self.startMinute = min(max(startMinute, 0), 59)
            self.endHour = min(max(endHour, 0), 23)
            self.endMinute = min(max(endMinute, 0), 59)
        }

        public var startMinutesFromMidnight: Int { startHour * 60 + startMinute }
        public var endMinutesFromMidnight: Int { endHour * 60 + endMinute }

        public static func from(profile: UserLifeProfile) -> WorkHours {
            WorkHours(
                startHour: profile.workStartHour,
                startMinute: profile.workStartMinute,
                endHour: profile.workEndHour,
                endMinute: profile.workEndMinute
            )
        }
    }

    /// Returns a valid future schedule time, rolling forward if needed.
    public static func validatedSchedule(
        hour: Int,
        minute: Int,
        now: Date = Date(),
        calendar: Calendar = .current,
        workHours: WorkHours
    ) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        var candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now

        if candidate <= now {
            candidate = calendar.date(byAdding: .minute, value: 15, to: now) ?? candidate
        }

        let candidateMinutes = calendar.component(.hour, from: candidate) * 60 + calendar.component(.minute, from: candidate)
        if candidateMinutes < workHours.startMinutesFromMidnight {
            candidate = calendar.date(
                bySettingHour: workHours.startHour,
                minute: workHours.startMinute,
                second: 0,
                of: candidate
            ) ?? candidate
            if candidate <= now {
                candidate = calendar.date(byAdding: .minute, value: 15, to: now) ?? candidate
            }
        }

        let adjustedMinutes = calendar.component(.hour, from: candidate) * 60 + calendar.component(.minute, from: candidate)
        if adjustedMinutes > workHours.endMinutesFromMidnight {
            return nil
        }

        return candidate
    }

    /// Next reasonable slot at least 15 minutes from now, within work hours.
    public static func nextAvailableSlot(
        now: Date = Date(),
        calendar: Calendar = .current,
        workHours: WorkHours
    ) -> (hour: Int, minute: Int)? {
        let start = calendar.date(byAdding: .minute, value: 15, to: now) ?? now
        let startMinutes = calendar.component(.hour, from: start) * 60 + calendar.component(.minute, from: start)
        if startMinutes < workHours.startMinutesFromMidnight {
            return (workHours.startHour, workHours.startMinute)
        }
        if startMinutes > workHours.endMinutesFromMidnight {
            return nil
        }
        return (
            calendar.component(.hour, from: start),
            calendar.component(.minute, from: start)
        )
    }

    /// Initial cursor for local schedulers — next valid moment within work hours.
    public static func schedulingCursor(
        now: Date = Date(),
        calendar: Calendar = .current,
        workHours: WorkHours
    ) -> Date {
        if let slot = nextAvailableSlot(now: now, calendar: calendar, workHours: workHours),
           let date = validatedSchedule(hour: slot.hour, minute: slot.minute, now: now, calendar: calendar, workHours: workHours) {
            return date
        }
        return calendar.date(bySettingHour: workHours.startHour, minute: workHours.startMinute, second: 0, of: now) ?? now
    }

    // MARK: - Multi-window scheduling (Life Model)

    /// Returns a valid schedule time within any allowed window (office + creative).
    public static func validatedScheduleInWindows(
        hour: Int,
        minute: Int,
        now: Date = Date(),
        calendar: Calendar = .current,
        windows: SchedulingWindows
    ) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        let candidateMinutes = hour * 60 + minute
        if windows.isProtected(minutesFromMidnight: candidateMinutes) {
            return nil
        }

        for window in windows.allSchedulingWindows {
            if candidateMinutes >= window.startMinutesFromMidnight,
               candidateMinutes <= window.endMinutesFromMidnight,
               let date = validatedSchedule(hour: hour, minute: minute, now: now, calendar: calendar, workHours: window) {
                return date
            }
        }
        return nil
    }

    /// Next slot in any scheduling window (office first, then creative).
    public static func nextAvailableSlotInWindows(
        now: Date = Date(),
        calendar: Calendar = .current,
        windows: SchedulingWindows
    ) -> (hour: Int, minute: Int)? {
        for window in windows.allSchedulingWindows {
            if let slot = nextAvailableSlot(now: now, calendar: calendar, workHours: window) {
                let minutes = slot.hour * 60 + slot.minute
                if !windows.isProtected(minutesFromMidnight: minutes) {
                    return slot
                }
            }
        }
        return nil
    }

    public static func schedulingCursorInWindows(
        now: Date = Date(),
        calendar: Calendar = .current,
        windows: SchedulingWindows
    ) -> Date {
        if let slot = nextAvailableSlotInWindows(now: now, calendar: calendar, windows: windows),
           let date = validatedScheduleInWindows(hour: slot.hour, minute: slot.minute, now: now, calendar: calendar, windows: windows) {
            return date
        }
        return schedulingCursor(now: now, calendar: calendar, workHours: windows.officeHours)
    }

    public static func advanceCursor(
        _ cursor: Date,
        byMinutes minutes: Int,
        bufferMinutes: Int = 5,
        workHours: WorkHours,
        calendar: Calendar = .current
    ) -> Date {
        let next = calendar.date(byAdding: .minute, value: minutes + bufferMinutes, to: cursor) ?? cursor
        let nextMinutes = calendar.component(.hour, from: next) * 60 + calendar.component(.minute, from: next)
        if nextMinutes > workHours.endMinutesFromMidnight {
            return next
        }
        return next
    }

    public static func components(from date: Date, calendar: Calendar = .current) -> (hour: Int, minute: Int) {
        (
            calendar.component(.hour, from: date),
            calendar.component(.minute, from: date)
        )
    }
}
