import Foundation
import LookAfterAI
import LookAfterCore

public enum CaptureIntentClassifier {
    private static let lowConfidenceThreshold = 0.55

    public static func classify(
        request: CaptureRequest,
        glm: GLMService = .shared
    ) async -> CaptureRoutingDecision {
        if let hint = request.hintedIntent, hint != .auto {
            return heuristicDecision(for: request, forcedIntent: hint)
        }

        if let aiDecision = await classifyWithAI(request: request, glm: glm),
           aiDecision.confidence >= lowConfidenceThreshold {
            return aiDecision
        }

        return heuristicDecision(for: request, forcedIntent: nil)
    }

    private static func classifyWithAI(
        request: CaptureRequest,
        glm: GLMService
    ) async -> CaptureRoutingDecision? {
        let prompt = LookAfterPrompts.captureRoutingPrompt(
            text: request.text,
            hintedIntent: request.hintedIntent?.rawValue,
            contextScreen: request.contextHints.screen
        )
        do {
            let response = try await glm.complete(
                prompt: prompt,
                systemPrompt: LookAfterPrompts.captureRoutingSystem,
                tier: .standard
            )
            return parseDecision(from: response, fallbackText: request.text)
        } catch {
            return nil
        }
    }

    static func parseDecision(from response: String, fallbackText: String) -> CaptureRoutingDecision? {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let intentRaw = (json["intent"] as? String)?.lowercased() ?? "task"
        let intent: CaptureIntent
        switch intentRaw {
        case "note": intent = .note
        case "event", "reminder", "calendar": intent = .event
        case "mood", "health": intent = .mood
        case "insight": intent = .insight
        case "archive", "none": intent = .auto
        default: intent = .task
        }

        if intentRaw == "archive" {
            return CaptureRoutingDecision(intent: .auto, confidence: 0.9, summary: fallbackText)
        }

        let confidence = json["confidence"] as? Double ?? 0.7
        var scheduledAt: Date?
        if let iso = json["scheduledAtISO"] as? String {
            scheduledAt = ISO8601DateFormatter().date(from: iso)
        }

        var lifeArea: LifeArea?
        if let areaStr = json["lifeArea"] as? String {
            lifeArea = LifeArea.allCases.first { $0.rawValue == areaStr }
        }
        var priority: Priority?
        if let priorityStr = json["priority"] as? String {
            priority = Priority.allCases.first { $0.label == priorityStr }
        }
        var difficulty: TaskDifficulty?
        if let diffStr = json["taskDifficulty"] as? String {
            difficulty = TaskDifficulty.allCases.first { $0.rawValue == diffStr }
        }

        return CaptureRoutingDecision(
            intent: intent,
            confidence: confidence,
            title: json["title"] as? String,
            summary: json["summary"] as? String,
            scheduledAt: scheduledAt,
            durationMinutes: json["durationMinutes"] as? Int,
            moodLabel: json["moodLabel"] as? String,
            lifeArea: lifeArea,
            priority: priority,
            difficulty: difficulty,
            estimatedMinutes: json["estimatedMinutes"] as? Int
        )
    }

    static func heuristicDecision(for request: CaptureRequest, forcedIntent: CaptureIntent?) -> CaptureRoutingDecision {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()

        if let forcedIntent {
            return CaptureRoutingDecision(
                intent: forcedIntent,
                confidence: 0.85,
                title: extractTitle(from: text, intent: forcedIntent),
                summary: text,
                scheduledAt: request.contextHints.preselectedDate,
                moodLabel: moodLabel(from: request.contextHints.moodLevel)
            )
        }

        if lower.hasPrefix("[health]") || lower.contains("mood:") {
            return CaptureRoutingDecision(intent: .mood, confidence: 0.8, title: nil, summary: text, moodLabel: "Okay")
        }
        if lower.hasPrefix("[reminder]") || lower.contains(" @ ") || containsScheduleLanguage(lower) {
            return CaptureRoutingDecision(
                intent: .event,
                confidence: 0.75,
                title: extractTitle(from: text, intent: .event),
                summary: text,
                scheduledAt: request.contextHints.preselectedDate ?? inferDate(from: text)
            )
        }
        if lower.hasPrefix("[idea]") || lower.hasPrefix("[insight]") {
            return CaptureRoutingDecision(
                intent: .insight,
                confidence: 0.75,
                title: extractTitle(from: text, intent: .insight),
                summary: text
            )
        }
        if lower.hasPrefix("[task]") {
            return CaptureRoutingDecision(
                intent: .task,
                confidence: 0.8,
                title: extractTitle(from: text, intent: .task),
                summary: text,
                estimatedMinutes: 15
            )
        }

        if containsMoodLanguage(lower) {
            return CaptureRoutingDecision(intent: .mood, confidence: 0.7, summary: text, moodLabel: "Okay")
        }
        if containsScheduleLanguage(lower) {
            return CaptureRoutingDecision(
                intent: .event,
                confidence: 0.65,
                title: extractTitle(from: text, intent: .event),
                summary: text,
                scheduledAt: inferDate(from: text)
            )
        }
        if lower.contains("remember that") || lower.contains("note to self") {
            return CaptureRoutingDecision(
                intent: .note,
                confidence: 0.65,
                title: extractTitle(from: text, intent: .note),
                summary: text
            )
        }

        return CaptureRoutingDecision(
            intent: .task,
            confidence: 0.6,
            title: extractTitle(from: text, intent: .task),
            summary: text,
            estimatedMinutes: 15
        )
    }

    private static func extractTitle(from text: String, intent: CaptureIntent) -> String {
        var cleaned = text
        for prefix in ["[Task]", "[Idea]", "[Reminder]", "[Health]", "[Insight]"] {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        if intent == .event, let atRange = cleaned.range(of: " @ ") {
            cleaned = String(cleaned[..<atRange.lowerBound])
        }
        if intent == .mood, cleaned.lowercased().hasPrefix("mood:") {
            cleaned = String(cleaned.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }
        let line = cleaned.split(separator: "\n").first.map(String.init) ?? cleaned
        return String(line.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsScheduleLanguage(_ lower: String) -> Bool {
        ["tomorrow", "today at", "monday", "tuesday", "wednesday", "thursday", "friday", "appointment", "meeting at", "at 3", "at 9"]
            .contains { lower.contains($0) }
    }

    private static func containsMoodLanguage(_ lower: String) -> Bool {
        ["feeling", "mood", "anxious", "tired", "exhausted", "energized", "stressed"]
            .contains { lower.contains($0) }
    }

    private static func inferDate(from text: String) -> Date? {
        if text.lowercased().contains("tomorrow") {
            return Calendar.current.date(byAdding: .day, value: 1, to: Date())
        }
        return nil
    }

    private static func moodLabel(from level: Double?) -> String? {
        guard let level else { return nil }
        switch level {
        case ..<0.33: return "Low"
        case ..<0.66: return "Okay"
        default: return "Good"
        }
    }
}
