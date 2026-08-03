import Foundation

/// Guided life-profile sections for onboarding and Settings.
public struct StructuredLifeProfileSections: Codable, Sendable, Equatable {
    public var personality: String
    public var adhdFocusPatterns: String
    public var dailySchedule: String
    public var planningPreferences: String

    public init(
        personality: String = "",
        adhdFocusPatterns: String = "",
        dailySchedule: String = "",
        planningPreferences: String = ""
    ) {
        self.personality = personality
        self.adhdFocusPatterns = adhdFocusPatterns
        self.dailySchedule = dailySchedule
        self.planningPreferences = planningPreferences
    }

    public var isEmpty: Bool {
        [personality, adhdFocusPatterns, dailySchedule, planningPreferences]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public var hasContent: Bool { !isEmpty }
}

public enum LifeProfileSection: String, CaseIterable, Sendable, Identifiable {
    case personality
    case adhdFocusPatterns
    case dailySchedule
    case planningPreferences

    public var id: String { rawValue }

    /// Sections shown in onboarding/settings — personality is learned from day-end reflection instead.
    public static var brainContextSections: [LifeProfileSection] {
        [.adhdFocusPatterns, .dailySchedule, .planningPreferences]
    }

    public var title: String {
        switch self {
        case .personality: return "Personality & work style"
        case .adhdFocusPatterns: return "ADHD & focus patterns"
        case .dailySchedule: return "Daily schedule & office hours"
        case .planningPreferences: return "How the AI should plan"
        }
    }

    public var promptHeader: String {
        switch self {
        case .personality: return "PERSONALITY & WORK STYLE"
        case .adhdFocusPatterns: return "ADHD & FOCUS PATTERNS"
        case .dailySchedule: return "DAILY SCHEDULE & OFFICE HOURS"
        case .planningPreferences: return "HOW THE AI SHOULD PLAN"
        }
    }

    public var placeholder: String {
        switch self {
        case .personality:
            return "Who you are at work and home. Strengths, communication style, what motivates you, what drains you…"
        case .adhdFocusPatterns:
            return "Task initiation, time blindness, hyperfocus, overwhelm triggers, what helps you start and finish…"
        case .dailySchedule:
            return "Typical wake time, commute, office hours, meetings rhythm, lunch, evening routine, weekend pattern…"
        case .planningPreferences:
            return "Hard rules for the planner: batch similar work, no meetings after 4 PM, mornings for deep work, flexible tasks only…"
        }
    }
}

/// Builds and parses the persisted `UserLifeProfile.profileText` blob.
public enum LifeProfileComposer {
    public static func compile(_ sections: StructuredLifeProfileSections) -> String {
        var blocks: [String] = []
        appendBlock(header: LifeProfileSection.personality.promptHeader, body: sections.personality, to: &blocks)
        appendBlock(header: LifeProfileSection.adhdFocusPatterns.promptHeader, body: sections.adhdFocusPatterns, to: &blocks)
        appendBlock(header: LifeProfileSection.dailySchedule.promptHeader, body: sections.dailySchedule, to: &blocks)
        appendBlock(header: LifeProfileSection.planningPreferences.promptHeader, body: sections.planningPreferences, to: &blocks)
        return blocks.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func parse(_ profileText: String) -> StructuredLifeProfileSections {
        let trimmed = profileText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return StructuredLifeProfileSections() }

        var sections = StructuredLifeProfileSections()
        let headers = LifeProfileSection.allCases.map(\.promptHeader)
        var foundStructured = false

        for (index, section) in LifeProfileSection.allCases.enumerated() {
            guard let body = extractSection(named: section.promptHeader, from: trimmed, nextHeaders: Array(headers.dropFirst(index + 1))) else {
                continue
            }
            foundStructured = true
            switch section {
            case .personality: sections.personality = body
            case .adhdFocusPatterns: sections.adhdFocusPatterns = body
            case .dailySchedule: sections.dailySchedule = body
            case .planningPreferences: sections.planningPreferences = body
            }
        }

        if !foundStructured {
            sections.personality = trimmed
        }
        return sections
    }

    public static func value(in sections: StructuredLifeProfileSections, for section: LifeProfileSection) -> String {
        switch section {
        case .personality: return sections.personality
        case .adhdFocusPatterns: return sections.adhdFocusPatterns
        case .dailySchedule: return sections.dailySchedule
        case .planningPreferences: return sections.planningPreferences
        }
    }

    public static func updating(
        _ sections: StructuredLifeProfileSections,
        section: LifeProfileSection,
        value: String
    ) -> StructuredLifeProfileSections {
        var copy = sections
        switch section {
        case .personality: copy.personality = value
        case .adhdFocusPatterns: copy.adhdFocusPatterns = value
        case .dailySchedule: copy.dailySchedule = value
        case .planningPreferences: copy.planningPreferences = value
        }
        return copy
    }

    public static func organizeStructuredPrompt(
        _ sections: StructuredLifeProfileSections,
        profile: UserLifeProfile = UserLifeProfileStore.load()
    ) -> String {
        """
        You are organizing a user's life profile for an ADHD day-planning assistant.
        Rewrite the content into the EXACT section headers below.
        Rules:
        - Preserve ALL facts and preferences — do NOT summarize away detail.
        - You may fix grammar, reorder bullets, and clarify wording.
        - Do NOT invent new facts.
        - Keep each section — use "(none yet)" only if the user left it blank.
        - Plain text only. No markdown fences.
        - Do NOT contradict these structured hours (they are stored separately in the app):
          Work hours: \(profile.workStartHour):00 – \(profile.workEndHour):00
          Peak energy: \(profile.peakStartHour):00 – \(profile.peakEndHour):00
          Fixed schedule notes: \(profile.fixedScheduleNotes.isEmpty ? "(none)" : profile.fixedScheduleNotes)

        Required format:
        PERSONALITY & WORK STYLE
        ...

        ADHD & FOCUS PATTERNS
        ...

        DAILY SCHEDULE & OFFICE HOURS
        ...

        HOW THE AI SHOULD PLAN
        ...

        USER INPUT:
        \(compile(sections))
        """
    }

    /// Offline section formatting — no API key required.
    public static func organizeLocally(_ sections: StructuredLifeProfileSections) -> StructuredLifeProfileSections {
        var copy = sections
        copy.personality = sections.personality.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.adhdFocusPatterns = sections.adhdFocusPatterns.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.dailySchedule = sections.dailySchedule.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.planningPreferences = sections.planningPreferences.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    /// Offline organization for free-form conversation input.
    public static func organizeLocally(freeform: String) -> StructuredLifeProfileSections {
        let trimmed = freeform.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return StructuredLifeProfileSections() }
        var sections = parse(trimmed)
        if !sections.hasContent {
            sections = splitFreeformIntoSections(trimmed)
        }
        return organizeLocally(sections)
    }

    private static func splitFreeformIntoSections(_ text: String) -> StructuredLifeProfileSections {
        var sections = StructuredLifeProfileSections()
        var scheduleLines: [String] = []
        var planningLines: [String] = []
        var adhdLines: [String] = []
        var personalityLines: [String] = []

        for line in text.components(separatedBy: .newlines) {
            let l = line.lowercased()
            if l.contains("standup") || l.contains("office") || l.contains("work hour")
                || l.contains("commute") || l.contains("pickup") || l.contains("gym at")
                || l.contains("wake") || l.contains("lunch") {
                scheduleLines.append(line)
            } else if l.contains("adhd") || l.contains("focus") || l.contains("hyperfocus")
                || l.contains("overwhelm") || l.contains("task initiation") || l.contains("time blind") {
                adhdLines.append(line)
            } else if l.contains("never schedule") || l.contains("deep work") || l.contains("batch")
                || l.contains("planner") || l.contains("don't move") || l.contains("hard rule") {
                planningLines.append(line)
            } else {
                personalityLines.append(line)
            }
        }

        sections.personality = personalityLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        sections.adhdFocusPatterns = adhdLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        sections.dailySchedule = scheduleLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        sections.planningPreferences = planningLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        if !sections.hasContent {
            sections.personality = text
        }
        return sections
    }

    public static func organizeConversationPrompt(_ freeform: String) -> String {
        """
        You are organizing a user's life description for an ADHD day-planning assistant.
        Rewrite into the EXACT section headers below.
        Rules:
        - Preserve ALL facts — do NOT cut detail to hit a word limit.
        - You may fix grammar and group related points.
        - Do NOT invent new facts.
        - Plain text only. No markdown fences.

        Required format:
        PERSONALITY & WORK STYLE
        ...

        ADHD & FOCUS PATTERNS
        ...

        DAILY SCHEDULE & OFFICE HOURS
        ...

        HOW THE AI SHOULD PLAN
        ...

        USER INPUT:
        \(freeform)
        """
    }

    private static func appendBlock(header: String, body: String, to blocks: inout [String]) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        blocks.append("\(header)\n\(trimmed)")
    }

    private static func extractSection(named header: String, from text: String, nextHeaders: [String]) -> String? {
        guard let range = text.range(of: header, options: [.caseInsensitive]) else { return nil }
        let afterHeader = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !afterHeader.isEmpty else { return "" }

        var endIndex = afterHeader.endIndex
        for next in nextHeaders {
            if let nextRange = afterHeader.range(of: next, options: [.caseInsensitive]) {
                if nextRange.lowerBound < endIndex {
                    endIndex = nextRange.lowerBound
                }
            }
        }

        let body = String(afterHeader[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return body
    }
}
