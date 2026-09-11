import Foundation
import LookAfterCore

/// LLM-powered semantic understanding — classify on create/edit, and judge
/// placement when the deterministic layer returns `.needsAI`.
/// Scheduling search itself stays deterministic in LookAfterCore.
public final class TaskSemanticAnalyzer: @unchecked Sendable {

    private let glm: GLMService

    public init(glmService: GLMService = .shared) {
        self.glm = glmService
    }

    /// Infer structured task meaning from title + optional context fields.
    public func analyze(task: LifeTask) async throws -> TaskSemanticProfile {
        let prompt = LookAfterPrompts.taskSemanticPrompt(task: task)
        let response = try await glm.complete(
            prompt: prompt,
            systemPrompt: LookAfterPrompts.structuredOutputSystem,
            tier: .economy
        )

        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TaskSemanticAnalyzerError.parseError
        }

        return parseProfile(json: json, task: task)
    }

    /// Second-pass judge when the semantic layer returns `.needsAI`.
    public func judgePlacement(
        task: LifeTask,
        proposedStart: Date,
        durationMinutes: Int,
        neighborTasks: [LifeTask],
        calendar: Calendar = .current
    ) async throws -> PlacementJudgment {
        let prompt = LookAfterPrompts.placementSensePrompt(
            task: task,
            proposedStart: proposedStart,
            durationMinutes: durationMinutes,
            neighborTasks: neighborTasks,
            calendar: calendar
        )
        let response = try await glm.complete(
            prompt: prompt,
            systemPrompt: LookAfterPrompts.structuredOutputSystem,
            tier: .economy
        )
        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TaskSemanticAnalyzerError.parseError
        }
        return PlacementJudgment(
            allowed: json["allowed"] as? Bool ?? false,
            reason: json["reason"] as? String ?? "",
            suggestedStartHour: json["suggestedStartHour"] as? Int,
            suggestedStartMinute: json["suggestedStartMinute"] as? Int
        )
    }

    private func parseProfile(json: [String: Any], task: LifeTask) -> TaskSemanticProfile {
        let typeStr = (json["semanticType"] as? String ?? "generic").lowercased()
        let semanticType = TaskSemanticType.allCases.first { $0.rawValue.lowercased() == typeStr } ?? .generic

        let constraints = parseEnumArray(json["schedulingConstraints"], type: SchedulingConstraintKind.self)
        let preferred = parseEnumArray(json["preferredTimeWindows"], type: TimeWindowPreference.self)
        let forbidden = parseEnumArray(json["forbiddenTimeWindows"], type: TimeWindowPreference.self)

        let flexStr = (json["flexibility"] as? String ?? "moderate").lowercased()
        let flexibility = TaskFlexibility.allCases.first { $0.rawValue.lowercased() == flexStr } ?? .moderate

        let energyStr = (json["energyRequirement"] as? String ?? "moderate").lowercased()
        let energy = SemanticEnergyRequirement.allCases.first { $0.rawValue.lowercased() == energyStr } ?? .moderate

        let cogStr = (json["cognitiveRequirement"] as? String ?? "moderate").lowercased()
        let cognitive = CognitiveRequirement.allCases.first { $0.rawValue.lowercased() == cogStr } ?? .moderate

        return TaskSemanticProfile(
            semanticType: semanticType,
            subtype: json["subtype"] as? String ?? "",
            schedulingConstraints: constraints,
            requiredConditions: json["requiredConditions"] as? [String] ?? [],
            preferredTimeWindows: preferred.isEmpty ? [.anytime] : preferred,
            forbiddenTimeWindows: forbidden,
            estimatedDuration: json["estimatedDuration"] as? Int ?? task.estimatedMinutes,
            flexibility: flexibility,
            splittable: json["splittable"] as? Bool ?? true,
            interruptionTolerance: json["interruptionTolerance"] as? Double ?? 0.5,
            energyRequirement: energy,
            cognitiveRequirement: cognitive,
            locationRequirement: json["locationRequirement"] as? String,
            recurringRules: json["recurringRules"] as? String,
            dependencies: json["dependencies"] as? [String] ?? [],
            consequenceOfDelay: parseConsequence(json["consequenceOfDelay"]),
            confidence: json["confidence"] as? Double ?? 0.75,
            source: .llm
        )
    }

    private func parseConsequence(_ value: Any?) -> ConsequenceOfDelay {
        guard let raw = value as? String else { return .low }
        let normalized = raw.lowercased().replacingOccurrences(of: "_", with: "")
        if normalized.contains("medical") { return .medicalRisk }
        return ConsequenceOfDelay.allCases.first { $0.rawValue.lowercased() == normalized } ?? .low
    }

    private func parseEnumArray<T: RawRepresentable & CaseIterable>(
        _ value: Any?,
        type: T.Type
    ) -> [T] where T.RawValue == String {
        guard let strings = value as? [String] else { return [] }
        return strings.compactMap { raw in
            type.allCases.first {
                $0.rawValue.lowercased() == raw.lowercased().replacingOccurrences(of: " ", with: "")
            }
        }
    }
}

public struct PlacementJudgment: Sendable, Equatable {
    public var allowed: Bool
    public var reason: String
    public var suggestedStartHour: Int?
    public var suggestedStartMinute: Int?

    public init(
        allowed: Bool,
        reason: String,
        suggestedStartHour: Int? = nil,
        suggestedStartMinute: Int? = nil
    ) {
        self.allowed = allowed
        self.reason = reason
        self.suggestedStartHour = suggestedStartHour
        self.suggestedStartMinute = suggestedStartMinute
    }
}

public enum TaskSemanticAnalyzerError: Error, LocalizedError {
    case parseError

    public var errorDescription: String? {
        switch self {
        case .parseError: return "Could not parse semantic profile from LLM response"
        }
    }
}
