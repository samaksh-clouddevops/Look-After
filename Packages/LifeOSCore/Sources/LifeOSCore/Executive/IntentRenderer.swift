import Foundation

public struct HeroIntentViewModel: Sendable, Equatable {
    public var title: String
    public var subtitle: String
    public var durationLabel: String
    public var primaryButton: String
    public var whyNowLine: String

    public init(
        title: String,
        subtitle: String,
        durationLabel: String,
        primaryButton: String,
        whyNowLine: String
    ) {
        self.title = title
        self.subtitle = subtitle
        self.durationLabel = durationLabel
        self.primaryButton = primaryButton
        self.whyNowLine = whyNowLine
    }
}

public enum IntentRenderer {
    public static func hero(
        from intent: ExecutiveIntent,
        snapshot: LifeContextSnapshot? = nil,
        whyNow: [String] = []
    ) -> HeroIntentViewModel {
        let rendered = HumanLanguage.render(intent.semantics, snapshot: snapshot, whyNow: whyNow)
        let subtitle = intent.expectedOutcome.isEmpty ? rendered.benefitLine : intent.expectedOutcome
        let why = whyNow.first ?? intent.intention

        return HeroIntentViewModel(
            title: rendered.headline,
            subtitle: subtitle,
            durationLabel: rendered.durationLine,
            primaryButton: rendered.buttonLabel,
            whyNowLine: why
        )
    }
}
