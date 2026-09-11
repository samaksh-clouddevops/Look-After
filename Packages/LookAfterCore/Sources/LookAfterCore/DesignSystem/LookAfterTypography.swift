import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Typography v2.2 (ADHD cognitive ease + Dynamic Type)

/// Design tokens for type. Point sizes are the **default** Dynamic Type size;
/// `Font.ds*` APIs scale with the user's Larger Text setting.
public enum LookAfterTypography {
    public static let screenTitleSize: CGFloat = 25
    public static let userNameSize: CGFloat = 25
    public static let briefingSalutationSize: CGFloat = 17
    public static let briefingUserNameSize: CGFloat = 30
    public static let cardTitleSize: CGFloat = 16
    public static let bodySize: CGFloat = 14
    public static let sectionLabelSize: CGFloat = 12.5
    public static let captionSize: CGFloat = 11
    /// S04-03: slightly above caption2 default so five tab labels stay readable next to icons.
    public static let tabLabelSize: CGFloat = 11
    public static let iconLargeSize: CGFloat = 44

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

    /// Maps Look After roles → system text styles for Dynamic Type scaling.
    public enum TextRole {
        case screenTitle
        case userName
        case briefingSalutation
        case briefingUserName
        case cardTitle
        case body
        case sectionLabel
        case caption
        case tabLabel
        case icon
        case iconLarge

        public var textStyle: Font.TextStyle {
            switch self {
            case .screenTitle, .userName: return .title
            case .briefingUserName: return .title2
            case .briefingSalutation, .body: return .body
            case .cardTitle, .icon: return .headline
            case .sectionLabel: return .caption
            case .caption, .tabLabel: return .caption2
            case .iconLarge: return .largeTitle
            }
        }

        public var pointSize: CGFloat {
            switch self {
            case .screenTitle: return LookAfterTypography.screenTitleSize
            case .userName: return LookAfterTypography.userNameSize
            case .briefingSalutation: return LookAfterTypography.briefingSalutationSize
            case .briefingUserName: return LookAfterTypography.briefingUserNameSize
            case .cardTitle, .icon: return LookAfterTypography.cardTitleSize
            case .body: return LookAfterTypography.bodySize
            case .sectionLabel: return LookAfterTypography.sectionLabelSize
            case .caption: return LookAfterTypography.captionSize
            case .tabLabel: return LookAfterTypography.tabLabelSize
            case .iconLarge: return LookAfterTypography.iconLargeSize
            }
        }

        #if canImport(UIKit)
        var uiTextStyle: UIFont.TextStyle {
            switch self {
            case .screenTitle, .userName: return .title1
            case .briefingUserName: return .title2
            case .briefingSalutation, .body: return .body
            case .cardTitle, .icon: return .headline
            case .sectionLabel: return .caption1
            case .caption, .tabLabel: return .caption2
            case .iconLarge: return .largeTitle
            }
        }
        #endif
    }
}

public extension Font {
    /// Scaled system font anchored to a Look After typography role.
    static func ds(
        _ role: LookAfterTypography.TextRole,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        #if canImport(UIKit)
        // UIFontMetrics → AXCoreUtilities. When called from a Swift Task / concurrent
        // context, iOS 26 logs unsafeForcedSync faults. Prefer semantic styles there.
        let inSwiftTask = withUnsafeCurrentTask { $0 != nil }
        if inSwiftTask {
            return .system(role.textStyle, design: design).weight(weight)
        }
        let base = UIFont.preferredLookAfterFont(
            size: role.pointSize,
            weight: weight,
            design: design
        )
        let scaled = UIFontMetrics(forTextStyle: role.uiTextStyle).scaledFont(for: base)
        return Font(scaled)
        #else
        // macOS SPM / AppKit: semantic styles still track system text size.
        return .system(role.textStyle, design: design).weight(weight)
        #endif
    }

    static func dsScreenTitle() -> Font {
        ds(.screenTitle, weight: .bold)
    }

    static func dsUserName() -> Font {
        ds(.userName, weight: .semibold, design: .serif)
    }

    static func dsBriefingSalutation() -> Font {
        ds(.briefingSalutation, weight: .regular)
    }

    static func dsBriefingUserName() -> Font {
        ds(.briefingUserName, weight: .semibold, design: .serif)
    }

    static func dsCardTitle() -> Font {
        ds(.cardTitle, weight: .semibold)
    }

    static func dsBody(weight: Font.Weight = .regular) -> Font {
        ds(.body, weight: weight)
    }

    static func dsSectionLabel() -> Font {
        ds(.sectionLabel, weight: .semibold)
    }

    static func dsCaption(weight: Font.Weight = .medium) -> Font {
        ds(.caption, weight: weight)
    }

    static func dsTabLabel(weight: Font.Weight = .medium) -> Font {
        ds(.tabLabel, weight: weight)
    }

    static func dsIcon(weight: Font.Weight = .semibold) -> Font {
        ds(.icon, weight: weight)
    }

    static func dsIconLarge(weight: Font.Weight = .regular) -> Font {
        ds(.iconLarge, weight: weight)
    }

    static func dsDisplay() -> Font { dsScreenTitle() }
    static func dsLargeTitle() -> Font { dsScreenTitle() }
    static func dsTitle() -> Font { dsCardTitle() }
    static func dsHeadline(weight: Font.Weight = .semibold) -> Font {
        ds(.cardTitle, weight: weight)
    }
    static func dsSecondary(weight: Font.Weight = .regular) -> Font { dsBody(weight: weight) }
    static func dsMetadata(weight: Font.Weight = .regular) -> Font { dsCaption(weight: weight) }
    static func dsChip(weight: Font.Weight = .medium) -> Font { dsCaption(weight: weight) }
}

#if canImport(UIKit)
private extension UIFont {
    static func preferredLookAfterFont(
        size: CGFloat,
        weight: Font.Weight,
        design: Font.Design
    ) -> UIFont {
        let uiWeight = uiFontWeight(weight)
        var descriptor = UIFont.systemFont(ofSize: size, weight: uiWeight).fontDescriptor
        switch design {
        case .serif:
            if let serif = descriptor.withDesign(.serif) { descriptor = serif }
        case .rounded:
            if let rounded = descriptor.withDesign(.rounded) { descriptor = rounded }
        case .monospaced:
            if let mono = descriptor.withDesign(.monospaced) { descriptor = mono }
        default:
            break
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func uiFontWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}
#endif

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
