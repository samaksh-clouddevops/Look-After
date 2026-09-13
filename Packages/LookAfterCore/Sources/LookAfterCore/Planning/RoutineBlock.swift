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

    public var startMinutesFromMidnight: Int { startHour * 60 + startMinute }
    public var endMinutesFromMidnight: Int { startMinutesFromMidnight + durationMinutes }

    public func timeRangeLabel() -> String {
        let endHour = (startHour + (startMinute + durationMinutes) / 60) % 24
        let endMinute = (startMinute + durationMinutes) % 60
        return "\(UserLifeProfile.formatTime(hour: startHour, minute: startMinute)) – \(UserLifeProfile.formatTime(hour: endHour, minute: endMinute))"
    }

    /// True if this block overlaps `other` on at least one shared day.
    public func overlaps(_ other: RoutineBlock) -> Bool {
        guard sharesADay(with: other) else { return false }
        return startMinutesFromMidnight < other.endMinutesFromMidnight
            && other.startMinutesFromMidnight < endMinutesFromMidnight
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
        cache.withLock { $0 = [] }
        UserDefaults.standard.removeObject(forKey: storageKey)
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
            let strippedTitle = note.components(separatedBy: CharacterSet.decimalDigits).joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let title = strippedTitle.isEmpty ? note : strippedTitle
            imported.append(RoutineBlock(
                title: String(title.prefix(60)),
                days: .everyDay,
                startHour: calendar.component(.hour, from: parsed.start),
                startMinute: calendar.component(.minute, from: parsed.start),
                durationMinutes: parsed.durationMinutes,
                isNonNegotiable: true
            ))
        }
        return imported
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
