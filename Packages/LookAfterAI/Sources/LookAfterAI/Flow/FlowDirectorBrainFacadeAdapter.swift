import Foundation
import LookAfterCore

/// Adapts FlowDirector surface into BrainFacade output (Phase 3).
@MainActor
public struct FlowDirectorBrainFacadeAdapter: BrainFacadeProtocol {
    private let director: FlowDirector

    public init(director: FlowDirector) {
        self.director = director
    }

    public func recommend(_ input: BrainFacadeInput) async -> BrainFacadeOutput? {
        if let sleep = input.sleepHours, sleep < 6 {
            return BrainFacadeOutput(
                headline: "Protect capacity before deep work",
                supportingLine: "Sleep was short — skip heavy focus for now.",
                taskID: director.surface.heroTask?.id,
                backendID: "flowDirector.recovery",
                confidence: 0.75
            )
        }

        let surface = director.surface
        let heroTitle = surface.heroTask?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let briefing = surface.briefingLines.first ?? surface.greeting
        let headline: String
        if !heroTitle.isEmpty {
            headline = heroTitle
        } else if !briefing.isEmpty {
            headline = briefing
        } else {
            return nil
        }

        let support: String = {
            if !heroTitle.isEmpty, briefing != heroTitle { return briefing }
            if surface.briefingLines.count > 1 { return surface.briefingLines[1] }
            return ""
        }()

        return BrainFacadeOutput(
            headline: headline,
            supportingLine: support,
            taskID: surface.heroTask?.id,
            backendID: "flowDirector.surface",
            confidence: surface.confidence > 0 ? surface.confidence : 0.6
        )
    }
}

/// Prefers FlowDirector surface; falls back to deterministic backend.
@MainActor
public struct FlowAwareBrainFacade: BrainFacadeProtocol {
    private let flow: FlowDirectorBrainFacadeAdapter?
    private let fallback: any BrainFacadeProtocol

    public init(
        director: FlowDirector?,
        fallback: any BrainFacadeProtocol = DeterministicBrainFacadeBackend()
    ) {
        self.flow = director.map { FlowDirectorBrainFacadeAdapter(director: $0) }
        self.fallback = fallback
    }

    public func recommend(_ input: BrainFacadeInput) async -> BrainFacadeOutput? {
        if let flow, let out = await flow.recommend(input) {
            return out
        }
        return await fallback.recommend(input)
    }
}
