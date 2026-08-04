import SwiftUI

// MARK: - Typography v2.1 (ADHD cognitive ease)

public enum LookAfterTypography {
    public static let screenTitleSize: CGFloat = 25
    public static let userNameSize: CGFloat = 25
    public static let briefingSalutationSize: CGFloat = 17
    public static let briefingUserNameSize: CGFloat = 30
    public static let cardTitleSize: CGFloat = 16
    public static let bodySize: CGFloat = 14
    public static let sectionLabelSize: CGFloat = 12.5
    public static let captionSize: CGFloat = 11
    public static let tabLabelSize: CGFloat = 10

    public static let screenTitleLineSpacing: CGFloat = 7
    public static let userNameLineSpacing: CGFloat = 7
    public static let briefingSalutationLineSpacing: CGFloat = 8
    public static let briefingUserNameLineSpacing: CGFloat = 8
    public static let cardTitleLineSpacing: CGFloat = 8
    public static let bodyLineSpacing: CGFloat = 9
    public static let sectionLabelLineSpacing: CGFloat = 3.5
    public static let captionLineSpacing: CGFloat = 3
    public static let tabLabelLineSpacing: CGFloat = 2

    public static let screenTitleTracking: CGFloat = -0.5
    public static let sectionLabelTracking: CGFloat = 0.5
    public static let captionTracking: CGFloat = 0.2

    public static let radiusCard: CGFloat = 24
}

public extension Font {
    static func dsScreenTitle() -> Font {
        .system(size: LookAfterTypography.screenTitleSize, weight: .bold, design: .default)
    }

    static func dsUserName() -> Font {
        .system(size: LookAfterTypography.userNameSize, weight: .semibold, design: .serif)
    }

    static func dsBriefingSalutation() -> Font {
        .system(size: LookAfterTypography.briefingSalutationSize, weight: .regular, design: .default)
    }

    static func dsBriefingUserName() -> Font {
        .system(size: LookAfterTypography.briefingUserNameSize, weight: .semibold, design: .serif)
    }

    static func dsCardTitle() -> Font {
        .system(size: LookAfterTypography.cardTitleSize, weight: .semibold, design: .default)
    }

    static func dsBody(weight: Font.Weight = .regular) -> Font {
        .system(size: LookAfterTypography.bodySize, weight: weight, design: .default)
    }

    static func dsSectionLabel() -> Font {
        .system(size: LookAfterTypography.sectionLabelSize, weight: .semibold, design: .default)
    }

    static func dsCaption(weight: Font.Weight = .medium) -> Font {
        .system(size: LookAfterTypography.captionSize, weight: weight, design: .default)
    }

    static func dsTabLabel(weight: Font.Weight = .medium) -> Font {
        .system(size: LookAfterTypography.tabLabelSize, weight: weight, design: .default)
    }

    /// SF Symbol sizing aligned to v2.1 tokens (use instead of raw `.system(size:)`).
    static func dsIcon(weight: Font.Weight = .semibold) -> Font {
        .system(size: LookAfterTypography.cardTitleSize, weight: weight, design: .default)
    }

    static func dsIconLarge(weight: Font.Weight = .regular) -> Font {
        .system(size: 44, weight: weight, design: .default)
    }

    static func dsDisplay() -> Font { dsScreenTitle() }
    static func dsLargeTitle() -> Font { dsScreenTitle() }
    static func dsTitle() -> Font { dsCardTitle() }
    static func dsHeadline(weight: Font.Weight = .semibold) -> Font {
        .system(size: LookAfterTypography.cardTitleSize, weight: weight, design: .default)
    }
    static func dsSecondary(weight: Font.Weight = .regular) -> Font { dsBody(weight: weight) }
    static func dsMetadata(weight: Font.Weight = .regular) -> Font { dsCaption(weight: weight) }
    static func dsChip(weight: Font.Weight = .medium) -> Font { dsCaption(weight: weight) }
}

public struct LookAfterTextStyle: ViewModifier {
    let font: Font
    let lineSpacing: CGFloat
    let tracking: CGFloat
    let color: Color

    public func body(content: Content) -> some View {
        content
            .font(font)
            .lineSpacing(lineSpacing)
            .kerning(tracking)
            .foregroundColor(color)
    }
}

public extension View {
    func textStyleScreenTitle(color: Color = DesignSystem.textPrimary) -> some View {
        modifier(LookAfterTextStyle(
            font: .dsScreenTitle(),
            lineSpacing: LookAfterTypography.screenTitleLineSpacing,
            tracking: LookAfterTypography.screenTitleTracking,
            color: color
        ))
    }

    func textStyleUserName(color: Color = DesignSystem.textPrimary) -> some View {
        modifier(LookAfterTextStyle(
            font: .dsUserName(),
            lineSpacing: LookAfterTypography.userNameLineSpacing,
            tracking: 0,
            color: color
        ))
    }

    func textStyleBriefingSalutation(color: Color = DesignSystem.textSecondary) -> some View {
        modifier(LookAfterTextStyle(
            font: .dsBriefingSalutation(),
            lineSpacing: LookAfterTypography.briefingSalutationLineSpacing,
            tracking: 0,
            color: color
        ))
    }

    func textStyleBriefingUserName(color: Color = DesignSystem.textPrimary) -> some View {
        modifier(LookAfterTextStyle(
            font: .dsBriefingUserName(),
            lineSpacing: LookAfterTypography.briefingUserNameLineSpacing,
            tracking: 0,
            color: color
        ))
    }

    func textStyleCardTitle(color: Color = DesignSystem.textPrimary) -> some View {
        modifier(LookAfterTextStyle(
            font: .dsCardTitle(),
            lineSpacing: LookAfterTypography.cardTitleLineSpacing,
            tracking: 0,
            color: color
        ))
    }

    func textStyleBody(color: Color = DesignSystem.textPrimary) -> some View {
        modifier(LookAfterTextStyle(
            font: .dsBody(),
            lineSpacing: LookAfterTypography.bodyLineSpacing,
            tracking: 0,
            color: color
        ))
    }

    func textStyleSectionLabel(color: Color = DesignSystem.textPrimary) -> some View {
        modifier(LookAfterTextStyle(
            font: .dsSectionLabel(),
            lineSpacing: LookAfterTypography.sectionLabelLineSpacing,
            tracking: LookAfterTypography.sectionLabelTracking,
            color: color
        ))
    }

    func textStyleCaption(color: Color = DesignSystem.textSecondary) -> some View {
        modifier(LookAfterTextStyle(
            font: .dsCaption(),
            lineSpacing: LookAfterTypography.captionLineSpacing,
            tracking: LookAfterTypography.captionTracking,
            color: color
        ))
    }

    func textStyleTabLabel(color: Color = DesignSystem.textSecondary, active: Bool = false) -> some View {
        modifier(LookAfterTextStyle(
            font: .dsTabLabel(weight: active ? .bold : .medium),
            lineSpacing: LookAfterTypography.tabLabelLineSpacing,
            tracking: 0,
            color: color
        ))
    }
}
