import Foundation
import LookAfterAI
import LookAfterCore

public enum NaturalLanguageTaskCaptureError: Error, LocalizedError, Sendable {
    case emptyInput
    case parseError

    public var errorDescription: String? {
        switch self {
        case .emptyInput: return "Enter a task description first."
        case .parseError: return "Couldn't understand that task. Try rephrasing."
        }
    }
}

/// Extracts a review-ready `NaturalLanguageTaskDraft` from free-text input (R3).
/// Never commits directly — the caller routes the result through the existing
/// inbox-draft review UI, matching the trust model of `createFromInbox`.
public enum NaturalLanguageTaskCaptureService {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func extractDraft(
        from text: String,
        glm: GLMService,
        now: Date = Date()
    ) async throws -> NaturalLanguageTaskDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NaturalLanguageTaskCaptureError.emptyInput }

        let response = try await glm.complete(
            prompt: LookAfterPrompts.naturalLanguageTaskCapturePrompt(text: trimmed, now: now),
            systemPrompt: LookAfterPrompts.naturalLanguageTaskCaptureSystem,
            tier: .standard
        )

        guard let json = parseJSON(response) else {
            throw NaturalLanguageTaskCaptureError.parseError
        }

        let draft = buildDraft(from: json, fallbackTitle: trimmed)
        return NaturalLanguageTaskDraftValidator.validated(draft, now: now)
    }

    // MARK: - Parsing

    static func parseJSON(_ raw: String) -> [String: Any]? {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func buildDraft(from json: [String: Any], fallbackTitle: String) -> NaturalLanguageTaskDraft {
        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var draft = NaturalLanguageTaskDraft(title: (title?.isEmpty == false ? title! : fallbackTitle))

        draft.lifeArea = extractField(json, key: "lifeArea") { raw in
            (raw as? String).flatMap { str in LifeArea.allCases.first { $0.rawValue == str } }
        }
        draft.priority = extractField(json, key: "priority", allowModelInference: false) { raw in
            (raw as? String).flatMap(Priority.fromLLM)
        }
        draft.difficulty = extractField(json, key: "difficulty") { raw in
            (raw as? String).flatMap { str in TaskDifficulty.allCases.first { $0.rawValue == str } }
        }
        draft.timeConstraint = extractField(json, key: "timeConstraint") { raw in
            (raw as? String).flatMap { str in TimeConstraint.allCases.first { $0.rawValue == str } }
        }
        draft.estimatedMinutes = extractField(json, key: "estimatedMinutes", allowModelInference: false) { raw in
            raw as? Int
        }
        draft.deadline = extractField(json, key: "deadline") { raw in
            (raw as? String).flatMap(parseDate)
        }
        draft.scheduledAt = extractField(json, key: "scheduledAt") { raw in
            (raw as? String).flatMap(parseDate)
        }

        return draft
    }

    /// Generic per-field decode: enforces the status/source contract and the "no fabricated
    /// value" rule (malformed enum strings, or a missing value for known/inferred, → unknown).
    private static func extractField<T>(
        _ json: [String: Any],
        key: String,
        allowModelInference: Bool = true,
        parse: (Any) -> T?
    ) -> ExtractedField<T> {
        guard let obj = json[key] as? [String: Any] else { return .unknown }
        let status = (obj["status"] as? String).flatMap(ExtractedFieldStatus.init(rawValue:)) ?? .unknown
        var source = (obj["source"] as? String).flatMap(ExtractedFieldSource.init(rawValue:))

        guard status == .known || status == .inferred else {
            return ExtractedField(value: nil, status: status, source: nil)
        }

        if !allowModelInference, source == .modelInference {
            return .unknown
        }

        guard let raw = obj["value"], !(raw is NSNull), let value = parse(raw) else {
            return .unknown
        }

        if source == nil { source = .modelInference }
        return ExtractedField(value: value, status: status, source: source)
    }

    private static func parseDate(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoFormatterNoFraction.date(from: string)
    }
}
