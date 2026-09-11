import SwiftUI

// MARK: - Chrome control matrix (P0 consistency)

/// Shared sizes for toolbar / tab / FAB — keeps text and controls optically compatible.
public enum LAChromeMetrics {
    public static let iconPointSize: CGFloat = 17
    public static let iconWeight: Font.Weight = .medium
    public static let toolbarGap: CGFloat = DesignSystem.spacingXS
    /// Capture FAB diameter — slightly under 44 so it doesn’t dominate tab icons.
    public static let fabDiameter: CGFloat = 40
    public static let chipMinHeight: CGFloat = DesignSystem.minTouchTarget
}

public enum LAToolbarProminence: Sendable {
    /// Neutral glass icon circle.
    case regular
    /// Lime filled primary action (one per toolbar max).
    case primary
}

/// Standard 44×44 toolbar icon button used on Briefing / Today / Tasks / You.
public struct LAToolbarIconButton: View {
    let systemName: String
    var prominence: LAToolbarProminence
    var accessibilityLabelText: String
    var accessibilityIdentifierValue: String?
    var isDisabled: Bool
    var showsProgress: Bool
    let action: () -> Void

    public init(
        systemName: String,
        prominence: LAToolbarProminence = .regular,
        accessibilityLabel: String,
        accessibilityIdentifier: String? = nil,
        isDisabled: Bool = false,
        showsProgress: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.prominence = prominence
        self.accessibilityLabelText = accessibilityLabel
        self.accessibilityIdentifierValue = accessibilityIdentifier
        self.isDisabled = isDisabled
        self.showsProgress = showsProgress
        self.action = action
    }

    public var body: some View {
        Group {
            switch prominence {
            case .regular:
                Button(action: action) { label }
                    .buttonStyle(.glass)
                    .tint(DesignSystem.textSecondary)
            case .primary:
                Button(action: action) { label }
                    .buttonStyle(.glassProminent)
                    .tint(LookAfterChrome.accentTint)
            }
        }
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabelText)
        .modifier(OptionalAccessibilityIdentifier(accessibilityIdentifierValue))
    }

    @ViewBuilder
    private var label: some View {
        Group {
            if showsProgress {
                ProgressView()
                    .scaleEffect(0.75)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: LAChromeMetrics.iconPointSize, weight: LAChromeMetrics.iconWeight))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(prominence == .primary ? DesignSystem.accentOnPrimary : DesignSystem.textPrimary)
            }
        }
        .frame(width: DesignSystem.iconButtonSize, height: DesignSystem.iconButtonSize)
        .contentShape(Rectangle())
    }
}

private struct OptionalAccessibilityIdentifier: ViewModifier {
    let id: String?
    init(_ id: String?) { self.id = id }
    @ViewBuilder
    func body(content: Content) -> some View {
        if let id, !id.isEmpty {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
    }
}

/// Horizontal capsule action used for schedule / negotiation options.
public struct LAActionChipButton: View {
    let title: String
    var isEmphasized: Bool
    let action: () -> Void

    public init(_ title: String, isEmphasized: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isEmphasized = isEmphasized
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.dsBody(weight: .semibold))
                .foregroundStyle(isEmphasized ? DesignSystem.accentOnPrimary : DesignSystem.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, DesignSystem.spacingMD)
                .frame(minHeight: LAChromeMetrics.chipMinHeight)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            isEmphasized
                                ? DesignSystem.accentPrimary
                                : DesignSystem.accentPrimary.opacity(0.12)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(
                                    DesignSystem.accentPrimary.opacity(isEmphasized ? 0 : 0.35),
                                    lineWidth: 1
                                )
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

/// Wave A2 Capture control: quiet elevated plate + quiet outline + accent plus only.
/// Never `.glassProminent` or filled lime — that equaled the selected-tab language.
public struct LACaptureFAB: View {
    var bounceToken: Int
    var reduceMotion: Bool
    let action: () -> Void

    public init(bounceToken: Int = 0, reduceMotion: Bool = false, action: @escaping () -> Void) {
        self.bounceToken = bounceToken
        self.reduceMotion = reduceMotion
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: LAChromeMetrics.iconPointSize, weight: .semibold))
                .foregroundStyle(DesignSystem.accentPrimary)
                .frame(width: LAChromeMetrics.fabDiameter, height: LAChromeMetrics.fabDiameter)
                .background {
                    Circle()
                        .fill(DesignSystem.contentSurfaceElevated)
                        .overlay(
                            Circle()
                                .stroke(DesignSystem.border, lineWidth: 1)
                        )
                }
                .modifier(CaptureFABBounceModifier(token: bounceToken, reduceMotion: reduceMotion))
                .frame(maxWidth: .infinity)
                .frame(minHeight: DesignSystem.minTouchTarget)
                .contentShape(Rectangle())
        }
        // Plain — not glassProminent; selected tabs keep lime tint separately.
        .buttonStyle(.plain)
    }
}

private struct CaptureFABBounceModifier: ViewModifier {
    let token: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.symbolEffect(.bounce, value: token)
        }
    }
}
