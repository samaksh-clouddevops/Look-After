import Foundation
import Synchronization

/// A single fixed-time entry in the user's declared daily routine (e.g. "Wake up", "Gym", "Wind down").
/// Distinct from `ProtectedTimeBlock` (which protects a range from scheduling) — a `RoutineBlock`
/// is a user-declared fixed-time commitment that becomes a `DayStructure.Anchor`.
public struct RoutineBlock: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var days: WeekdaySet
    public var startHour: Int
    public var startMinute: Int
    public var durationMinutes: Int
    public var isNonNegotiable: Bool

    public init(
        id: String? = nil,
        title: String,
        days: WeekdaySet = .everyDay,
        startHour: Int,
        startMinute: Int = 0,
        durationMinutes: Int = 30,
        isNonNegotiable: Bool = true
    ) {
        self.id = id ?? UUID().uuidString
        self.title = title
        self.days = days
        self.startHour = min(max(startHour, 0), 23)
        self.startMinute = min(max(startMinute, 0), 59)
        self.durationMinutes = max(durationMinutes, TaskDurationPolicy.minimumMinutes)
        self.isNonNegotiable = isNonNegotiable
    }

    public static let taskTagPrefix = "routine-block:"

    public var taskTag: String { "\(Self.taskTagPrefix)\(id)" }
    public var anchorID: String { "routine-block.\(id)" }

    public var startMinutesFromMidnight: Int { startHour * 60 + startMinute }
    public var endMinutesFromMidnight: Int { startMinutesFromMidnight + durationMinutes }

    public var endHour: Int { (startHour + (startMinute + durationMinutes) / 60) % 24 }
    public var endMinute: Int { (startMinute + durationMinutes) % 60 }

    /// Writes this block's clock onto a recurrence template or a single day's occurrence.
    /// Leaves identity, status, and parent linkage alone except when `asTemplate` clears the parent.
    public func applySchedule(
        to task: inout LifeTask,
        on day: Date,
        calendar: Calendar,
        asTemplate: Bool
    ) {
        task.title = title
        task.estimatedMinutes = max(durationMinutes, TaskDurationPolicy.minimumMinutes)
        let dayStart = calendar.startOfDay(for: day)
        let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: dayStart)
        task.scheduledTime = start
        if let start {
            task.scheduledEndTime = start.addingTimeInterval(TimeInterval(task.estimatedMinutes * 60))
        }
        task.scheduleAnchorID = anchorID
        if asTemplate {
            task.scheduledDate = nil
            task.isRecurrenceTemplate = true
            task.parentTaskId = nil
            task.recurrence = .custom
            task.recurrenceInterval = 1
            task.recurrenceWeekdays = days.recurrenceWeekdayNumbers
        } else {
            task.scheduledDate = dayStart
            task.isRecurrenceTemplate = false
            task.recurrence = nil
            task.recurrenceWeekdays = nil
        }
        var tags = task.tags.filter { !$0.hasPrefix(Self.taskTagPrefix) }
        tags.append(taskTag)
        if !tags.contains("routine") { tags.append("routine") }
        if !tags.contains("daily-routine") { tags.append("daily-routine") }
        task.tags = tags
        if isNonNegotiable {
            task.applyTimeConstraint(.anchored)
        } else {
            let preservedStart = task.scheduledTime
            let preservedEnd = task.scheduledEndTime
            task.applyTimeConstraint(.flexible)
            task.scheduledTime = preservedStart
            task.scheduledEndTime = preservedEnd
        }
        task.updatedAt = Date()
    }

    public func matchesStartClock(_ date: Date?, calendar: Calendar) -> Bool {
        guard let date else { return false }
        return calendar.component(.hour, from: date) == startHour
            && calendar.component(.minute, from: date) == startMinute
    }

    public func timeRangeLabel() -> String {
        "\(UserLifeProfile.formatTime(hour: startHour, minute: startMinute)) – \(UserLifeProfile.formatTime(hour: endHour, minute: endMinute))"
    }

    /// True if this block overlaps `other` on at least one shared day.
    /// Overnight blocks (e.g. sleep 23:00×8h) are split across midnight so morning
    /// collisions are detected.
    public func overlaps(_ other: RoutineBlock) -> Bool {
        guard sharesADay(with: other) else { return false }
        return Self.intervalsOverlap(
            startA: startMinutesFromMidnight,
            durationA: durationMinutes,
            startB: other.startMinutesFromMidnight,
            durationB: other.durationMinutes
        )
    }

    private func sharesADay(with other: RoutineBlock) -> Bool {
        (days.monday && other.days.monday) ||
        (days.tuesday && other.days.tuesday) ||
        (days.wednesday && other.days.wednesday) ||
        (days.thursday && other.days.thursday) ||
        (days.friday && other.days.friday) ||
        (days.saturday && other.days.saturday) ||
        (days.sunday && other.days.sunday)
    }

    private static let minutesPerDay = 24 * 60

    /// Half-open interval overlap on a 24h clock, wrapping overnight durations.
    static func intervalsOverlap(
        startA: Int,
        durationA: Int,
        startB: Int,
        durationB: Int
    ) -> Bool {
        if durationA >= minutesPerDay || durationB >= minutesPerDay { return true }
        for (a0, a1) in daySegments(start: startA, duration: durationA) {
            for (b0, b1) in daySegments(start: startB, duration: durationB) {
                if a0 < b1 && b0 < a1 { return true }
            }
        }
        return false
    }

    private static func daySegments(start: Int, duration: Int) -> [(Int, Int)] {
        let clampedStart = ((start % minutesPerDay) + minutesPerDay) % minutesPerDay
        let end = clampedStart + max(duration, 0)
        if end <= minutesPerDay {
            return [(clampedStart, end)]
        }
        return [(clampedStart, minutesPerDay), (0, end % minutesPerDay)]
    }
}

/// Persists the user's declared fixed daily routine — the ordered list of `RoutineBlock`s
/// that make up "my typical day" (wake, meals, work, gym, wind-down, sleep, etc.).
public enum RoutineBlockStore {
    public static let storageKey = "lifeos.routineBlocks"
    private static let cache = Mutex<[RoutineBlock]?>(nil)

    public static func load() -> [RoutineBlock] {
        if let cached = cache.withLock({ $0 }) { return cached }
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let blocks = try? SharedFormatters.jsonDecoderSeconds.decode([RoutineBlock].self, from: data) else {
            cache.withLock { $0 = [] }
            return []
        }
        cache.withLock { $0 = blocks }
        return blocks
    }

    public static func save(_ blocks: [RoutineBlock]) {
        if let data = try? SharedFormatters.jsonEncoderSeconds.encode(blocks) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        cache.withLock { $0 = blocks }
    }

    public static func reset() {
        cache.withLock { $0 = nil }
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// Drops the in-memory cache so the next `load()` re-reads UserDefaults.
    /// Call after bulk UserDefaults wipes (factory reset) that bypass `reset()`.
    public static func invalidateCache() {
        cache.withLock { $0 = nil }
    }

    /// Blocks that overlap `candidate` on a shared day, excluding `candidate` itself (by id).
    public static func conflicts(with candidate: RoutineBlock, in blocks: [RoutineBlock]? = nil) -> [RoutineBlock] {
        (blocks ?? load()).filter { $0.id != candidate.id && $0.overlaps(candidate) }
    }
}

// MARK: - Migration from free-form fixedScheduleNotes

extension RoutineBlockStore {
    /// Best-effort parse of `UserLifeProfile.fixedScheduleNotes` (comma/semicolon/newline-separated
    /// free text like "Gym 6am-7am, Lunch 1pm") into structured `RoutineBlock`s. Non-destructive:
    /// the source text field is left untouched; anything unparsable is simply skipped.
    public static func importFromFixedScheduleNotes(
        _ notesText: String,
        calendar: Calendar = .current
    ) -> [RoutineBlock] {
        guard !notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let day = calendar.startOfDay(for: Date())
        let entries = notesText
            .replacingOccurrences(of: "\n", with: ",")
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var imported: [RoutineBlock] = []
        for note in entries {
            guard let parsed = OnboardingTaskSeeder.fixedTimeAnchor(
                matchingTitle: note,
                fixedNotes: note,
                on: day,
                calendar: calendar
            ) else { continue }
            imported.append(RoutineBlock(
                title: titleFromFixedNote(note),
                days: .everyDay,
                startHour: calendar.component(.hour, from: parsed.start),
                startMinute: calendar.component(.minute, from: parsed.start),
                durationMinutes: parsed.durationMinutes,
                isNonNegotiable: true
            ))
        }
        return imported
    }

    /// Strips time tokens from free-text notes without destroying title words that contain digits.
    static func titleFromFixedNote(_ note: String) -> String {
        var title = note
        let patterns = [
            #"\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\s*[-–—to]+\s*\d{1,2}(?::\d{2})?\s*(?:am|pm)\b"#,
            #"\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b"#,
            #"\b\d{1,2}:\d{2}\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(title.startIndex..<title.endIndex, in: title)
            title = regex.stringByReplacingMatches(in: title, options: [], range: range, withTemplate: "")
        }
        title = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-–—,"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = title.isEmpty ? note : title
        return String(cleaned.prefix(60))
    }

    /// Runs `importFromFixedScheduleNotes` and merges the result into the current store,
    /// skipping any imported block that overlaps an existing one. Returns the blocks actually added.
    /// Intended to be offered once, e.g. on first visit to the routine builder screen.
    @discardableResult
    public static func migrateFixedScheduleNotesIfNeeded(_ notesText: String, calendar: Calendar = .current) -> [RoutineBlock] {
        var current = load()
        let candidates = importFromFixedScheduleNotes(notesText, calendar: calendar)
        var added: [RoutineBlock] = []
        for candidate in candidates where conflicts(with: candidate, in: current).isEmpty {
            current.append(candidate)
            added.append(candidate)
        }
        if !added.isEmpty {
            save(current)
        }
        return added
    }
}
