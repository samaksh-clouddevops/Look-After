import Foundation

/// Minimal visible hero — at most title, one supporting line, one metadata line, one action.
public struct CalmHeroContent: Sendable, Equatable {
    public var title: String
    public var supportingLine: String?
    public var metadataLine: String?
    public var primaryActionTitle: String
    public var disclosure: CalmHeroDisclosure?

    public init(
        title: String,
        supportingLine: String? = nil,
        metadataLine: String? = nil,
        primaryActionTitle: String,
        disclosure: CalmHeroDisclosure? = nil
    ) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.supportingLine = supportingLine.map { CalmHeroContentBuilder.singleLine($0) }
        self.metadataLine = metadataLine.map { CalmHeroContentBuilder.singleLine($0) }
        self.primaryActionTitle = primaryActionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.disclosure = disclosure
    }
}

/// Full Brain reasoning — only shown after progressive disclosure.
public struct CalmHeroDisclosure: Sendable, Equatable {
    public var narrative: String?
    public var whyLines: [String]
    public var skipConsequence: String?
    public var alternativePrompt: String?

    public init(
        narrative: String? = nil,
        whyLines: [String] = [],
        skipConsequence: String? = nil,
        alternativePrompt: String? = nil
    ) {
        self.narrative = narrative
        self.whyLines = whyLines
        self.skipConsequence = skipConsequence
        self.alternativePrompt = alternativePrompt
    }

    public var hasContent: Bool {
        !(narrative?.isEmpty ?? true)
            || !whyLines.isEmpty
            || !(skipConsequence?.isEmpty ?? true)
            || !(alternativePrompt?.isEmpty ?? true)
    }
}

public struct CalmHeroSecondaryAction: Identifiable, Sendable, Equatable {
    public let id: String
    public var title: String
    public var icon: String?
    public var action: () -> Void

    public init(id: String, title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.icon = icon
        self.action = action
    }

    public static func == (lhs: CalmHeroSecondaryAction, rhs: CalmHeroSecondaryAction) -> Bool {
        lhs.id == rhs.title && lhs.title == rhs.title && lhs.icon == rhs.icon
    }
}

/// Picks the single best visible lines from rich Brain output.
public enum CalmHeroContentBuilder {

    public static func from(
        title: String,
        buttonLabel: String,
        greeting: String? = nil,
        contextLine: String? = nil,
        outcomeLine: String? = nil,
        whyLine: String? = nil,
        durationLabel: String? = nil,
        windowLabel: String? = nil,
        narrative: String? = nil,
        skipConsequence: String? = nil,
        alternativePrompt: String? = nil,
        whyNowReasons: [String] = []
    ) -> CalmHeroContent {
        let supporting = preferredSupporting(
            why: whyLine ?? contextLine,
            narrative: outcomeLine ?? narrative,
            alternative: alternativePrompt
        )
        let dedupedSupporting = supporting.flatMap { line in
            isNearDuplicate(line, title) ? nil : line
        }
        let actionTitle = distinctActionLabel(buttonLabel, title: title)

        let metadata = metadataLine(
            greeting: greeting,
            duration: durationLabel,
            window: windowLabel
        )

        var extraWhy = whyNowReasons
        if let skipConsequence, !skipConsequence.isEmpty {
            extraWhy.append("If you skip this: \(skipConsequence)")
        }

        let fullNarrative = [contextLine, outcomeLine, narrative]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let disclosure = CalmHeroDisclosure(
            narrative: fullNarrative != (supporting ?? "") ? fullNarrative : nil,
            whyLines: uniqueLines(extraWhy + [whyLine]),
            alternativePrompt: alternativePrompt
        )

        return CalmHeroContent(
            title: title,
            supportingLine: dedupedSupporting,
            metadataLine: metadata,
            primaryActionTitle: actionTitle,
            disclosure: disclosure.hasContent ? disclosure : nil
        )
    }

    private static func isNearDuplicate(_ text: String, _ title: String) -> Bool {
        let a = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let b = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty || b.isEmpty { return false }
        return a == b || a.contains(b) || b.contains(a)
    }

    private static func distinctActionLabel(_ button: String, title: String) -> String {
        let trimmedButton = button.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isNearDuplicate(trimmedButton, title) { return trimmedButton }
        return "Start now"
    }

    public static func metadataLine(greeting: String? = nil, duration: String? = nil, window: String? = nil) -> String? {
        let parts = [greeting, duration, window]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { singleLine($0) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    public static func preferredSupporting(why: String?, narrative: String?, alternative: String?) -> String? {
        if let why, !why.isEmpty { return firstSentence(why) }
        if let narrative, !narrative.isEmpty { return firstSentence(narrative) }
        if let alternative, !alternative.isEmpty { return firstSentence(alternative) }
        return nil
    }

    public static func singleLine(_ text: String) -> String {
        firstSentence(text.replacingOccurrences(of: "\n", with: " "))
    }

    public static func firstSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let terminators: [Character] = [".", "!", "?"]
        if let index = trimmed.firstIndex(where: { terminators.contains($0) }) {
            let end = trimmed.index(after: index)
            let sentence = String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count >= 12 { return sentence }
        }

        if trimmed.count > 90 {
            let prefix = trimmed.prefix(87)
            if let lastSpace = prefix.lastIndex(of: " ") {
                return String(prefix[..<lastSpace]) + "…"
            }
            return String(prefix) + "…"
        }

        return trimmed
    }

    private static func uniqueLines(_ lines: [String?]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for line in lines.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            let key = line.lowercased()
            if seen.insert(key).inserted {
                result.append(line)
            }
        }
        return result
    }
}

// Briefing bridge — keeps LookAfterFeatures types out of LookAfterCore views.
public extension CalmHeroContentBuilder {
    static func fromBriefingHero(
        greeting: String,
        actionLine: String,
        narrative: String,
        whyLine: String?,
        buttonLabel: String,
        durationLabel: String?,
        ignoreConsequence: String?,
        alternativeLabel: String?
    ) -> CalmHeroContent {
        from(
            title: actionLine,
            buttonLabel: buttonLabel,
            greeting: greeting,
            contextLine: nil,
            outcomeLine: nil,
            whyLine: whyLine,
            durationLabel: durationLabel,
            narrative: narrative,
            skipConsequence: ignoreConsequence,
            alternativePrompt: alternativeLabel
        )
    }

    /// Immersive briefing — greeting shown separately; metadata is duration only.
    static func immersiveBriefingContent(
        actionLine: String,
        narrative: String,
        whyLine: String?,
        buttonLabel: String,
        durationLabel: String?,
        ignoreConsequence: String?,
        alternativeLabel: String?
    ) -> CalmHeroContent {
        from(
            title: actionLine,
            buttonLabel: buttonLabel,
            whyLine: whyLine,
            durationLabel: durationLabel,
            narrative: narrative,
            skipConsequence: ignoreConsequence,
            alternativePrompt: alternativeLabel
        )
    }
}
