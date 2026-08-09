import Foundation

/// Creates a small set of starter tasks from explicit schedule notes only.
public enum OnboardingTaskSeeder {

    public struct SeedResult: Sendable, Equatable {
        public var fixedTasks: [LifeTask]
        public var flexibleTasks: [LifeTask]

        public init(fixedTasks: [LifeTask] = [], flexibleTasks: [LifeTask] = []) {
            self.fixedTasks = fixedTasks
            self.flexibleTasks = flexibleTasks
        }

        public var allTasks: [LifeTask] { fixedTasks + flexibleTasks }
        public var isEmpty: Bool { allTasks.isEmpty }
    }

    private static let maxFixedTasks = 6
    private static let maxFlexibleTasks = 4
    private static let dailyRoutineTag = "daily-routine"

    private struct RoutineSlot: Sendable {
        var title: String
        var hour: Int
        var minute: Int
        var durationMinutes: Int
        var lifeArea: LifeArea
    }

    private static let dailyMealAndHygieneSlots: [RoutineSlot] = [
        RoutineSlot(title: "Breakfast", hour: 8, minute: 0, durationMinutes: 20, lifeArea: .health),
        RoutineSlot(title: "Brush teeth — morning", hour: 7, minute: 30, durationMinutes: 5, lifeArea: .personal),
        RoutineSlot(title: "Lunch", hour: 12, minute: 30, durationMinutes: 30, lifeArea: .health),
        RoutineSlot(title: "Snacks", hour: 16, minute: 0, durationMinutes: 10, lifeArea: .health),
        RoutineSlot(title: "Dinner", hour: 19, minute: 0, durationMinutes: 45, lifeArea: .health),
        RoutineSlot(title: "Brush teeth — evening", hour: 21, minute: 30, durationMinutes: 5, lifeArea: .personal),
    ]

    private static let dailyActivityRoutineSlots: [RoutineSlot] = [
        RoutineSlot(title: "Gym", hour: 18, minute: 0, durationMinutes: 60, lifeArea: .health),
        RoutineSlot(title: "Workout", hour: 18, minute: 0, durationMinutes: 60, lifeArea: .health),
    ]

    private static let activityRoutineKeywords = ["gym", "workout", "exercise", "lift", "training"]

    private static let creativeRoutineKeywords = ["vocal", "music", "creative", "art", "studio"]

    private static let dailyFlexibleRoutines: [(title: String, minutes: Int, lifeArea: LifeArea)] = [
        ("Morning review", 10, .work),
    ]

    /// Routine titles removed from the task list — handled elsewhere in the app (e.g. Timeline journal).
    public static let retiredRoutineTitles: Set<String> = ["journal"]

    public static func seedTasks(
        from profile: UserLifeProfile,
        sections: StructuredLifeProfileSections? = nil
    ) -> SeedResult {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var fixed: [LifeTask] = []
        var flexible: [LifeTask] = []
        var seenTitles = Set<String>()

        func appendFixed(from note: String) {
            guard fixed.count < maxFixedTasks else { return }
            guard let task = makeFixedTask(from: note, calendar: calendar, anchorDay: today) else { return }
            let key = normalizedTitle(task.title)
            guard seenTitles.insert(key).inserted else { return }
            fixed.append(task)
        }

        func appendFlexible(title: String, minutes: Int, lifeArea: LifeArea = .personal) {
            guard flexible.count < maxFlexibleTasks else { return }
            guard let sanitized = sanitizeTitle(title), isValidTitle(sanitized) else { return }
            let key = normalizedTitle(sanitized)
            guard seenTitles.insert(key).inserted else { return }
            flexible.append(
                LifeTask(
                    title: sanitized,
                    description: "",
                    lifeArea: lifeArea,
                    priority: .medium,
                    difficulty: .easy,
                    estimatedMinutes: minutes,
                    tags: ["onboarding", "flexible"],
                    schedulingMode: .flexible
                )
            )
        }

        // Explicit notes + extractor hits from profile/sections (always merge — never skip when notes exist).
        for note in explicitFixedNotes(profile: profile, sections: sections) {
            appendFixed(from: note)
        }

        appendFlexible(title: "Take medication", minutes: 5, lifeArea: .medication)

        appendDailyRoutineFixed(calendar: calendar, anchorDay: today, fixed: &fixed, seenTitles: &seenTitles)
        appendDailyRoutineFlexible(flexible: &flexible, seenTitles: &seenTitles)

        if fixed.isEmpty, flexible.isEmpty {
            appendFlexible(title: "Plan my day", minutes: 15, lifeArea: .work)
        }

        return SeedResult(fixedTasks: fixed, flexibleTasks: flexible)
    }

    /// Lowercased, whitespace-normalized title for series dedupe across templates and occurrences.
    public static func normalizedRoutineTitle(_ title: String) -> String {
        normalizedTitle(title)
    }

    /// True when `title` matches a seeded daily meal/hygiene slot or flexible routine.
    public static func isKnownDailyRoutineTitle(_ title: String) -> Bool {
        let key = normalizedTitle(title)
        if dailyMealAndHygieneSlots.contains(where: { normalizedTitle($0.title) == key }) {
            return true
        }
        if dailyActivityRoutineSlots.contains(where: { normalizedTitle($0.title) == key }) {
            return true
        }
        if activityRoutineKeywords.contains(where: { key.contains($0) }) {
            return true
        }
        return dailyFlexibleRoutines.contains { normalizedTitle($0.title) == key }
    }

    /// Activity routines (Gym, Workout) — preferred anchor but shiftable on conflict.
    public static func isActivityRoutineTitle(_ title: String) -> Bool {
        let key = normalizedTitle(title)
        if dailyActivityRoutineSlots.contains(where: { normalizedTitle($0.title) == key }) {
            return true
        }
        return activityRoutineKeywords.contains(where: { key.contains($0) })
    }

    /// Meal routines (Breakfast, Lunch, Dinner, Snacks) — preferred anchor but shiftable on conflict.
    public static func isMealRoutineTitle(_ title: String) -> Bool {
        let key = normalizedTitle(title)
        let mealTitles = ["breakfast", "lunch", "dinner", "snacks", "brunch", "supper"]
        if mealTitles.contains(key) { return true }
        return dailyMealAndHygieneSlots.contains { slot in
            mealTitles.contains(normalizedTitle(slot.title))
                && normalizedTitle(slot.title) == key
        }
    }

    /// Canonical clock anchor for a known daily routine title (meals, hygiene, gym).
    public static func routineAnchorTime(
        forTitle title: String,
        on day: Date,
        calendar: Calendar = .current
    ) -> (start: Date, durationMinutes: Int)? {
        let key = normalizedTitle(title)
        let allSlots = dailyMealAndHygieneSlots + dailyActivityRoutineSlots
        if let slot = allSlots.first(where: { normalizedTitle($0.title) == key }) {
            return routineSlotTime(slot, on: day, calendar: calendar)
        }
        if activityRoutineKeywords.contains(where: { key.contains($0) }),
           !creativeRoutineKeywords.contains(where: { key.contains($0) }),
           let gymSlot = dailyActivityRoutineSlots.first(where: { normalizedTitle($0.title) == "gym" }) {
            return routineSlotTime(gymSlot, on: day, calendar: calendar)
        }
        return nil
    }

    private static func routineSlotTime(
        _ slot: RoutineSlot,
        on day: Date,
        calendar: Calendar
    ) -> (start: Date, durationMinutes: Int)? {
        guard let start = calendar.date(
            bySettingHour: slot.hour,
            minute: slot.minute,
            second: 0,
            of: calendar.startOfDay(for: day)
        ) else { return nil }
        return (start, slot.durationMinutes)
    }

    /// Parses fixed schedule notes and returns a match for the given task title.
    public static func fixedTimeAnchor(
        matchingTitle title: String,
        fixedNotes: String,
        on day: Date,
        calendar: Calendar = .current
    ) -> (start: Date, durationMinutes: Int)? {
        let target = normalizedTitle(title)
        let dayStart = calendar.startOfDay(for: day)
        for note in splitNotes(fixedNotes) {
            guard let parsed = parseTimedCommitment(note) else { continue }
            guard normalizedTitle(parsed.title) == target
                || titlesMatchLoosely(normalizedTitle(parsed.title), target) else { continue }
            guard let start = calendar.date(
                bySettingHour: parsed.hour,
                minute: parsed.minute,
                second: 0,
                of: dayStart
            ) else { continue }
            return (start, parsed.defaultDurationMinutes)
        }
        return nil
    }

    private static func titlesMatchLoosely(_ lhs: String, _ rhs: String) -> Bool {
        lhs.contains(rhs) || rhs.contains(lhs)
    }

    /// Standard daily routines (meals, hygiene, review) — used for onboarding and backfill.
    public static func dailyRoutineTasks(calendar: Calendar = .current, anchorDay: Date = Date()) -> [LifeTask] {
        let today = calendar.startOfDay(for: anchorDay)
        var fixed: [LifeTask] = []
        var flexible: [LifeTask] = []
        var seenTitles = Set<String>()
        appendDailyRoutineFixed(calendar: calendar, anchorDay: today, fixed: &fixed, seenTitles: &seenTitles)
        appendDailyRoutineFlexible(flexible: &flexible, seenTitles: &seenTitles)
        return fixed + flexible
    }

    /// True when a fixed-schedule note can become a timed task.
    public static func canParseFixedNote(_ note: String) -> Bool {
        parseTimedCommitment(note) != nil
    }

    /// Detects junk titles from an earlier, overly aggressive seeder or broken parsing.
    public static func isJunkOnboardingTask(title: String, description: String = "") -> Bool {
        if isMalformedTaskTitle(title) { return true }

        let combined = "\(title) \(description)".lowercased()
        if title.count > 55 { return true }
        if title.split(separator: " ").count > 10 { return true }
        let junkPhrases = [
            "life profile",
            "never moved",
            "planner",
            "personality &",
            "adhd &",
            "how the ai",
            "finish your",
            "review life profile",
        ]
        return junkPhrases.contains { combined.contains($0) }
    }

    private static func appendDailyRoutineFixed(
        calendar: Calendar,
        anchorDay: Date,
        fixed: inout [LifeTask],
        seenTitles: inout Set<String>
    ) {
        for slot in dailyMealAndHygieneSlots {
            guard fixed.count < maxFixedTasks + dailyMealAndHygieneSlots.count else { return }
            let key = normalizedTitle(slot.title)
            guard seenTitles.insert(key).inserted else { continue }
            guard let start = calendar.date(
                bySettingHour: slot.hour,
                minute: slot.minute,
                second: 0,
                of: anchorDay
            ) else { continue }

            let end = start.addingTimeInterval(TimeInterval(slot.durationMinutes * 60))
            var task = LifeTask(
                title: slot.title,
                description: "",
                lifeArea: slot.lifeArea,
                priority: .medium,
                difficulty: .easy,
                estimatedMinutes: slot.durationMinutes,
                scheduledDate: anchorDay,
                scheduledTime: start,
                tags: ["onboarding", "fixed", dailyRoutineTag],
                recurrence: .daily,
                schedulingMode: .fixedTime,
                scheduledEndTime: end
            )
            task = TaskEphemeralityDefaults.enrich(task)
            fixed.append(task)
        }
    }

    private static func appendDailyRoutineFlexible(
        flexible: inout [LifeTask],
        seenTitles: inout Set<String>
    ) {
        for routine in dailyFlexibleRoutines {
            guard flexible.count < maxFlexibleTasks + dailyFlexibleRoutines.count else { return }
            let key = normalizedTitle(routine.title)
            guard seenTitles.insert(key).inserted else { continue }
            flexible.append(
                LifeTask(
                    title: routine.title,
                    description: "",
                    lifeArea: routine.lifeArea,
                    priority: .low,
                    difficulty: .easy,
                    estimatedMinutes: routine.minutes,
                    tags: ["onboarding", "flexible", dailyRoutineTag],
                    schedulingMode: .flexible
                )
            )
        }
    }

    // MARK: - Sources

    private static func explicitFixedNotes(
        profile: UserLifeProfile,
        sections: StructuredLifeProfileSections?
    ) -> [String] {
        var notes = splitNotes(profile.fixedScheduleNotes)

        let parsedSections = sections ?? LifeProfileComposer.parse(profile.profileText)
        let extracted = LifeProfileScheduleExtractor.extract(
            profileText: profile.profileText,
            sections: parsedSections
        )
        if let fixed = extracted.fixedScheduleNotes {
            notes.append(contentsOf: splitNotes(fixed))
        }

        return Array(Set(
            notes
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && canParseFixedNote($0) }
        ))
    }

    private static func profileTextMentionsMedication(
        profile: UserLifeProfile,
        sections: StructuredLifeProfileSections?
    ) -> Bool {
        let corpus = [
            sections?.adhdFocusPatterns,
            sections?.dailySchedule,
            profile.profileText
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return corpus.contains("medication") || corpus.contains("meds")
    }

    private static func splitNotes(_ raw: String) -> [String] {
        raw
            .replacingOccurrences(of: "\n", with: ",")
            .split { $0 == "," || $0 == ";" }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func makeFixedTask(from note: String, calendar: Calendar, anchorDay: Date) -> LifeTask? {
        guard let parsed = parseTimedCommitment(note) else { return nil }
        guard let sanitized = sanitizeTitle(parsed.title), isValidTitle(sanitized) else { return nil }
        guard let start = calendar.date(
            bySettingHour: parsed.hour,
            minute: parsed.minute,
            second: 0,
            of: anchorDay
        ) else { return nil }

        let minutes = parsed.defaultDurationMinutes
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))

        return LifeTask(
            title: sanitized,
            description: "",
            lifeArea: parsed.lifeArea,
            priority: .medium,
            difficulty: .easy,
            estimatedMinutes: minutes,
            scheduledDate: anchorDay,
            scheduledTime: start,
            tags: ["onboarding", "fixed"],
            recurrence: .daily,
            schedulingMode: .fixedTime,
            scheduledEndTime: end
        )
    }

    private struct ParsedCommitment {
        var title: String
        var hour: Int
        var minute: Int
        var defaultDurationMinutes: Int
        var lifeArea: LifeArea
    }

    private static func parseTimedCommitment(_ note: String) -> ParsedCommitment? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return nil }

        let patterns = [
            // "Daily standup 10:00 AM"
            #"(?i)^(.{2,40}?)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*$"#,
            // "Daily standup at 10:00 AM"
            #"(?i)^(.{2,40}?)\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*$"#,
            // "8:30 AM – Daily stand-up"
            #"(?i)^(\d{1,2})(?::(\d{2}))?\s*(am|pm)\s*[–-]\s*(.{2,40})\s*$"#,
            // "8:30 AM Daily stand-up" (no dash)
            #"(?i)^(\d{1,2})(?::(\d{2}))?\s*(am|pm)\s+(.{2,40})\s*$"#,
        ]

        for (patternIndex, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else { continue }

            let title: String
            let hour: Int
            let minute: Int
            let meridiem: String?

            if patternIndex >= 2 {
                guard let hourRange = Range(match.range(at: 1), in: trimmed),
                      let parsedHour = Int(trimmed[hourRange]),
                      let titleRange = Range(match.range(at: 4), in: trimmed) else { continue }
                hour = parsedHour
                minute = intGroup(match, 2, in: trimmed) ?? 0
                meridiem = stringGroup(match, 3, in: trimmed)
                title = String(trimmed[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                guard let titleRange = Range(match.range(at: 1), in: trimmed),
                      let hourRange = Range(match.range(at: 2), in: trimmed),
                      let parsedHour = Int(trimmed[hourRange]) else { continue }
                hour = parsedHour
                minute = intGroup(match, 3, in: trimmed) ?? 0
                meridiem = stringGroup(match, 4, in: trimmed)
                title = String(trimmed[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard let normalized = normalizeHour(hour, minute: minute, meridiem: meridiem) else { continue }
            let cleanedTitle = sanitizeTitle(title)
            guard let cleanedTitle, isValidTitle(cleanedTitle) else { continue }

            return ParsedCommitment(
                title: cleanedTitle,
                hour: normalized.hour,
                minute: normalized.minute,
                defaultDurationMinutes: defaultDuration(for: cleanedTitle),
                lifeArea: lifeArea(for: cleanedTitle)
            )
        }

        return nil
    }

    private static func normalizeHour(_ hour: Int, minute: Int, meridiem: String?) -> (hour: Int, minute: Int)? {
        var h = hour
        let m = min(max(minute, 0), 59)
        if let meridiem {
            let lower = meridiem.lowercased()
            if lower == "pm", h < 12 { h += 12 }
            if lower == "am", h == 12 { h = 0 }
        } else if h >= 1 && h <= 8 {
            h += 12
        }
        guard (0...23).contains(h) else { return nil }
        return (h, m)
    }

    private static func defaultDuration(for title: String) -> Int {
        let lower = title.lowercased()
        if lower.contains("gym") || lower.contains("workout") { return 60 }
        if lower.contains("standup") || lower.contains("meeting") || lower.contains("call") { return 30 }
        if lower.contains("pickup") { return 30 }
        return 30
    }

    private static func lifeArea(for title: String) -> LifeArea {
        let lower = title.lowercased()
        if lower.contains("gym") || lower.contains("pickup") { return .health }
        if lower.contains("standup") || lower.contains("meeting") || lower.contains("work") { return .work }
        return .personal
    }

    private static func sanitizeTitle(_ raw: String) -> String? {
        var title = raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        // Strip leading bullets and dashes (ASCII + en/em dash).
        let leadingPunctuation = CharacterSet(charactersIn: "•·-*–—\t ")
        title = title.trimmingCharacters(in: leadingPunctuation)

        // "stand-up/ work meeting" → "stand-up work meeting"
        title = title.replacingOccurrences(of: "/", with: " ")
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop trailing time ranges and orphan dashes: "(9 AM – 5:30 PM)", "(– 5:30 PM)", "–"
        title = title.replacingOccurrences(
            of: #"\([^)]*[–-][^)]*\)\s*$"#,
            with: "",
            options: .regularExpression
        )
        title = title.replacingOccurrences(
            of: #"[–-]\s*$"#,
            with: "",
            options: .regularExpression
        )
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else { return nil }
        if title.count > 48 {
            title = String(title.prefix(48)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title.isEmpty ? nil : title
    }

    /// Titles that should never become tasks (broken parse or schedule boundaries).
    private static func isMalformedTaskTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let lower = trimmed.lowercased()

        // Time-only labels like "8:30 AM –" or "5:30 PM"
        if trimmed.range(
            of: #"^\d{1,2}(:\d{2})?\s*(am|pm)?\s*[–-]?\s*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }

        // Work-hour boundaries, not actionable tasks.
        if lower.contains("office hours") || lower.contains("protect office") || lower.contains("work hours") {
            return true
        }

        // Broken parse fragments.
        if lower.contains("(–") || lower.contains("(-") { return true }
        if trimmed.hasPrefix("–") || trimmed.hasPrefix("-") || trimmed.hasPrefix("•") { return true }

        let letterCount = trimmed.filter(\.isLetter).count
        if letterCount < 3 { return true }

        return false
    }

    private static func isValidTitle(_ title: String) -> Bool {
        !isJunkOnboardingTask(title: title) && !isMalformedTaskTitle(title)
    }

    private static func intGroup(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> Int? {
        guard match.numberOfRanges > index,
              let range = Range(match.range(at: index), in: text) else { return nil }
        let raw = String(text[range]).trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        return Int(raw)
    }

    private static func stringGroup(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard match.numberOfRanges > index,
              let range = Range(match.range(at: index), in: text) else { return nil }
        let raw = String(text[range]).trimmingCharacters(in: .whitespaces)
        return raw.isEmpty ? nil : raw
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
