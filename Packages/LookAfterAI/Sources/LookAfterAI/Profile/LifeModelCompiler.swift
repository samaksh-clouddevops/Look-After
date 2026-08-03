import Foundation
import LookAfterCore

/// Compiles raw life profile markdown into a structured LifeModel.
public final class LifeModelCompiler {
    private let glm: GLMService

    public init(glmService: GLMService = .shared) {
        self.glm = glmService
    }

    public func compile(markdown: String, preferAI: Bool = true) async -> LifeModel {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return LifeModel()
        }

        if preferAI, glm.hasConfiguredAPIKey {
            do {
                let raw = try await glm.complete(
                    prompt: LookAfterPrompts.lifeModelCompilePrompt(markdown: trimmed),
                    systemPrompt: LookAfterPrompts.lifeModelCompileSystem
                )
                if let decoded = decodeModel(from: raw) {
                    return LifeModelValidator.validateAndMerge(decoded, markdown: trimmed)
                }
            } catch {
                print("[LifeModelCompiler] AI compile failed: \(error.localizedDescription)")
            }
        }

        return LifeModelValidator.validateAndMerge(
            LifeModelValidator.compileLocally(from: trimmed),
            markdown: trimmed
        )
    }

    private func decodeModel(from response: String) -> LifeModel? {
        let clean = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = clean.data(using: .utf8),
              let model = try? JSONDecoder().decode(LifeModel.self, from: data) else {
            return nil
        }
        return model
    }
}
