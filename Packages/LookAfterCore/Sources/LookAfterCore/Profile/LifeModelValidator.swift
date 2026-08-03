import Foundation

/// Deterministic validation and fallback parsing for life profile markdown.
public enum LifeModelValidator {

    public static func validateAndMerge(_ model: LifeModel, markdown: String) -> LifeModel {
        var result = model
        result.rawMarkdown = markdown
        result.compiledAt = Date()

        result.timeBlocks = result.timeBlocks.map(sanitizeBlock)
        result.commitments = dedupeCommitments(result.commitments)

        if result.timeBlocks.isEmpty {
            result.timeBlocks = extractBlocks(from: markdown)
        }
        if result.commitments.isEmpty {
            result.commitments = extractCommitments(from: markdown, blocks: result.timeBlocks)
        }
        if result.identity.name.isEmpty {
            result.identity.name = extractName(from: markdown) ?? ""
        }
        if result.identity.mission.isEmpty {
            result.identity.mission = extractMission(from: markdown) ?? ""
        }
        if result.identity.roleFraming.isEmpty {
            result.identity.roleFraming = extractRoleFraming(from: markdown) ?? ""
        }
        if result.priorities.isEmpty {
            result.priorities = extractPriorities(from: markdown)
        }
        if result.adhdRules.isEmpty {
            result.adhdRules = extractSection(named: "ADHD Coaching Rules", from: markdown)
                ?? extractSection(named: "ADHD", from: markdown)
                ?? ""
        }
        if result.coachingRules.isEmpty {
            result.coachingRules = extractSection(named: "Accountability Rules", from: markdown) ?? ""
        }
        if result.decisionFramework.isEmpty {
            result.decisionFramework = extractNumberedList(from: extractSection(named: "Decision Framework", from: markdown) ?? "")
        }

        return result
    }

    /// Builds a life model entirely from markdown without AI.
    public static func compileLocally(from markdown: String) -> LifeModel {
        let blocks = extractBlocks(from: markdown)
        let commitments = extractCommitments(from: markdown, blocks: blocks)
        return LifeModel(
            rawMarkdown: markdown,
            compiledAt: Date(),
            identity: LifeIdentity(
                name: extractName(from: markdown) ?? "",
                roleFraming: extractRoleFraming(from: markdown) ?? "",
                mission: extractMission(from: markdown) ?? "",
                longTermVision: extractSection(named: "My Long-Term Vision", from: markdown) ?? ""
            ),
            priorities: extractPriorities(from: markdown),
            timeBlocks: blocks,
            commitments: commitments,
            adhdRules: extractSection(named: "ADHD Coaching Rules", from: markdown) ?? "",
            decisionFramework: extractNumberedList(from: extractSection(named: "Decision Framework", from: markdown) ?? ""),
            coachingRules: extractSection(named: "Accountability Rules", from: markdown) ?? ""
        )
    }

    // MARK: - Block extraction

    public static func extractBlocks(from markdown: String) -> [ProtectedTimeBlock] {
        var blocks: [ProtectedTimeBlock] = []
        let lines = markdown.components(separatedBy: .newlines)

        var currentLabel: String?
        var priorityOrder: [String] = []
        var collectingPriorities = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("### ") {
                currentLabel = trimmed.replacingOccurrences(of: "### ", with: "").trimmingCharacters(in: .whitespaces)
                collectingPriorities = false
                priorityOrder = []
            }

            if trimmed.hasPrefix("**"), trimmed.contains("–") || trimmed.contains("-") {
                if let label = currentLabel ?? inferLabel(from: trimmed),
                   let range = parseTimeRange(from: trimmed) {
                    let protection: BlockProtection
                    let lower = (currentLabel ?? label).lowercased()
                    if lower.contains("gym") || lower.contains("office") {
                        protection = lower.contains("gym") ? .neverSchedule : .contextOnly
                    } else if lower.contains("creative") || lower.contains("deep work") {
                        protection = .priorityOnly
                        collectingPriorities = true
                    } else if lower.contains("transition") || lower.contains("dinner") {
                        protection = .flexible
                    } else {
                        protection = .flexible
                    }

                    blocks.append(
                        ProtectedTimeBlock(
                            label: label,
                            days: lower.contains("weekend") ? .weekends : .weekdays,
                            startHour: range.startHour,
                            startMinute: range.startMinute,
                            endHour: range.endHour,
                            endMinute: range.endMinute,
                            protection: protection,
                            priorityOrder: nil
                        )
                    )
                }
            }

            if collectingPriorities, let item = numberedListItem(from: trimmed) {
                priorityOrder.append(item)
            } else if collectingPriorities, trimmed.hasPrefix("#") {
                if !priorityOrder.isEmpty, let idx = blocks.lastIndex(where: { $0.isCreativeWindow || $0.label.lowercased().contains("creative") }) {
                    blocks[idx].priorityOrder = priorityOrder
                }
                collectingPriorities = false
            }
        }

        if !priorityOrder.isEmpty, let idx = blocks.lastIndex(where: { $0.label.lowercased().contains("creative") }) {
            blocks[idx].priorityOrder = priorityOrder
        }

        return dedupeBlocks(blocks)
    }

    public static func extractCommitments(from markdown: String, blocks: [ProtectedTimeBlock]) -> [LifeCommitment] {
        var commitments: [LifeCommitment] = []
        let creativeBlock = blocks.first { $0.isCreativeWindow || $0.label.lowercased().contains("creative") }
        let gymBlock = blocks.first { $0.label.lowercased().contains("gym") }

        if let gymBlock {
            commitments.append(
                LifeCommitment(
                    title: "Gym",
                    lifeArea: .health,
                    frequency: .weekdays,
                    preferredBlockLabel: gymBlock.label,
                    defaultMinutes: max(gymBlock.endMinutesFromMidnight - gymBlock.startMinutesFromMidnight, 60),
                    priority: 1,
                    isNonNegotiable: true
                )
            )
        }

        if let dinnerBlock = blocks.first(where: { $0.label.lowercased().contains("dinner") }) {
            commitments.append(
                LifeCommitment(
                    title: "Dinner",
                    lifeArea: .health,
                    frequency: .weekdays,
                    preferredBlockLabel: dinnerBlock.label,
                    defaultMinutes: max(dinnerBlock.endMinutesFromMidnight - dinnerBlock.startMinutesFromMidnight, 30),
                    priority: 2,
                    isNonNegotiable: false
                )
            )
        }

        if let creative = creativeBlock, let order = creative.priorityOrder, !order.isEmpty {
            for (index, activity) in order.enumerated() {
                commitments.append(
                    LifeCommitment(
                        title: activity,
                        lifeArea: .creativity,
                        frequency: .weekdays,
                        preferredBlockLabel: creative.label,
                        defaultMinutes: 45,
                        priority: index + 1,
                        isNonNegotiable: false
                    )
                )
            }
        } else if creativeBlock != nil {
            commitments.append(
                LifeCommitment(
                    title: "Creative block",
                    lifeArea: .creativity,
                    frequency: .weekdays,
                    preferredBlockLabel: creativeBlock?.label,
                    defaultMinutes: 45,
                    priority: 1,
                    isNonNegotiable: false
                )
            )
        }

        let lower = markdown.lowercased()
        if lower.contains("music") && !commitments.contains(where: { $0.title.lowercased().contains("music") }) {
            commitments.append(
                LifeCommitment(
                    title: "Music practice",
                    lifeArea: .creativity,
                    frequency: .weekdays,
                    preferredBlockLabel: creativeBlock?.label,
                    defaultMinutes: 30,
                    priority: 2,
                    isNonNegotiable: false
                )
            )
        }

        return dedupeCommitments(commitments)
    }

    // MARK: - Helpers

    private struct ParsedRange {
        var startHour: Int
        var startMinute: Int
        var endHour: Int
        var endMinute: Int
    }

    private static func parseTimeRange(from line: String) -> ParsedRange? {
        let cleaned = line.replacingOccurrences(of: "*", with: "")
        let pattern = #"(?i)(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*[–-]\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) else {
            return nil
        }

        guard let startH = intGroup(match, 1, in: cleaned),
              let endH = intGroup(match, 4, in: cleaned) else { return nil }

        let startM = intGroup(match, 2, in: cleaned) ?? 0
        let endM = intGroup(match, 5, in: cleaned) ?? 0
        let startMer = stringGroup(match, 3, in: cleaned)
        let endMer = stringGroup(match, 6, in: cleaned)

        guard let sh = normalizeHour(startH, minute: startM, meridiem: startMer),
              let eh = normalizeHour(endH, minute: endM, meridiem: endMer) else { return nil }

        return ParsedRange(startHour: sh.hour, startMinute: sh.minute, endHour: eh.hour, endMinute: eh.minute)
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

    private static func inferLabel(from line: String) -> String? {
        let lower = line.lowercased()
        if lower.contains("office") { return "Office" }
        if lower.contains("gym") { return "Gym" }
        if lower.contains("creative") || lower.contains("deep work") { return "Creative Deep Work" }
        if lower.contains("dinner") { return "Dinner & Recovery" }
        if lower.contains("transition") || lower.contains("commute") { return "Transition" }
        return nil
    }

    private static func extractName(from markdown: String) -> String? {
        if let name = firstCaptureGroup(
            pattern: #"(?i)My name is \*\*([^*]+)\*\*"#,
            in: markdown
        ) {
            return name.trimmingCharacters(in: .whitespaces)
        }
        return LifeProfileNameExtractor.extract(from: markdown)
    }

    private static func extractMission(from markdown: String) -> String? {
        extractSection(named: "My Mission", from: markdown)
    }

    private static func extractRoleFraming(from markdown: String) -> String? {
        let lines = markdown.components(separatedBy: .newlines)
        var parts: [String] = []
        var inIdentity = false
        for line in lines {
            if line.hasPrefix("# My Core Identity") { inIdentity = true; continue }
            if line.hasPrefix("# ") && !line.hasPrefix("# My Core Identity") { break }
            if inIdentity, !line.isEmpty, !line.hasPrefix("My name"), !line.hasPrefix("---") {
                parts.append(line.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces))
            }
        }
        let joined = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private static func extractPriorities(from markdown: String) -> [String] {
        guard let section = extractSection(named: "My Priorities", from: markdown) else { return [] }
        return extractNumberedList(from: section)
    }

    private static func extractSection(named header: String, from markdown: String) -> String? {
        let pattern = "#+\\s*\(NSRegularExpression.escapedPattern(for: header))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = markdown as NSString
        guard let match = regex.firstMatch(in: markdown, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let start = match.range.location + match.range.length
        let remainder = ns.substring(from: start)
        guard let next = remainder.range(of: "\n# ") ?? remainder.range(of: "\n---") else {
            return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(remainder[..<next.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractNumberedList(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .compactMap { line -> String? in
                numberedListItem(from: line.trimmingCharacters(in: .whitespaces))
            }
    }

    private static func numberedListItem(from line: String) -> String? {
        guard let item = firstCaptureGroup(pattern: #"^\d+\.\s+(.+)$"#, in: line) else { return nil }
        return item.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces)
    }

    private static func firstCaptureGroup(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func sanitizeBlock(_ block: ProtectedTimeBlock) -> ProtectedTimeBlock {
        var b = block
        b.startHour = min(max(b.startHour, 0), 23)
        b.endHour = min(max(b.endHour, 0), 23)
        b.startMinute = min(max(b.startMinute, 0), 59)
        b.endMinute = min(max(b.endMinute, 0), 59)
        return b
    }

    private static func dedupeBlocks(_ blocks: [ProtectedTimeBlock]) -> [ProtectedTimeBlock] {
        var seen = Set<String>()
        return blocks.filter { seen.insert($0.label.lowercased()).inserted }
    }

    private static func dedupeCommitments(_ commitments: [LifeCommitment]) -> [LifeCommitment] {
        var seen = Set<String>()
        return commitments.filter { seen.insert($0.title.lowercased()).inserted }
    }

    private static func intGroup(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> Int? {
        guard match.numberOfRanges > index,
              let range = Range(match.range(at: index), in: text) else { return nil }
        return Int(text[range])
    }

    private static func stringGroup(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard match.numberOfRanges > index,
              let range = Range(match.range(at: index), in: text) else { return nil }
        let raw = String(text[range]).trimmingCharacters(in: .whitespaces)
        return raw.isEmpty ? nil : raw
    }
}
