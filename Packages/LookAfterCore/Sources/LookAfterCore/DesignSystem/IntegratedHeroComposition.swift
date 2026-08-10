import SwiftUI

/// Hero — frames the user's actual context; calm surface by default.
public struct IntegratedHeroComposition: View {
    let content: CalmHeroContent
    let frame: LifeContextFrame
    let onContinue: () -> Void

    public init(
        greeting: String,
        concreteLine: String,
        outcomeTitle: String,
        durationLabel: String,
        contextMeta: String? = nil,
        frame: LifeContextFrame,
        whyNowReasons: [String] = [],
        contextLine: String? = nil,
        lowConfidencePrompt: String? = nil,
        onContinue: @escaping () -> Void
    ) {
        self.frame = frame
        self.onContinue = onContinue

        var disclosure = CalmHeroDisclosure(
            narrative: concreteLine.isEmpty ? nil : concreteLine,
            whyLines: whyNowReasons,
            alternativePrompt: lowConfidencePrompt
        )
        let supporting = CalmHeroContentBuilder.preferredSupporting(
            why: contextLine,
            narrative: concreteLine.isEmpty ? nil : concreteLine,
            alternative: lowConfidencePrompt
        )
        if disclosure.narrative == supporting {
            disclosure.narrative = nil
        }

        self.content = CalmHeroContent(
            title: outcomeTitle,
            supportingLine: supporting,
            metadataLine: CalmHeroContentBuilder.metadataLine(
                greeting: greeting,
                duration: durationLabel.isEmpty ? nil : durationLabel,
                window: contextMeta
            ),
            // Action language > vague "Continue" (UX excellence).
            primaryActionTitle: durationLabel.isEmpty ? "Start now" : "Start · \(durationLabel)",
            disclosure: disclosure.hasContent ? disclosure : nil
        )
    }

    public var body: some View {
        ZStack {
            ResumeContextBackdrop(frame: frame)

            VStack(spacing: 0) {
                Spacer(minLength: 52)

                CalmHeroSurface(content: content, primaryAction: {
                    HapticManager.impact(.medium)
                    onContinue()
                })
                .padding(.horizontal, 28)

                Spacer(minLength: 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}
