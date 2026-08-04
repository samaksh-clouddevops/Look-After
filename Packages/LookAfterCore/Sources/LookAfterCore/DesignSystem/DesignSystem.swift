import SwiftUI

/// Look After Design System V4 — semantic tokens, calm Apple-quality hierarchy.
public struct DesignSystem {

    // MARK: - Adaptive semantic backgrounds (V4)

    public static let backgroundPrimary = Color.adaptive(light: "F8F8F6", dark: "111315")
    public static let backgroundSecondary = Color.adaptive(light: "FFFFFF", dark: "191C1F")
    public static let backgroundElevated = Color.adaptive(light: "ECEEF1", dark: "2B3036")

    public static let surfaceGlass = backgroundSecondary.opacity(0.92)
    public static let borderGlass = border

    // MARK: - Text

    public static let textPrimary = Color.adaptive(light: "1C1C1E", dark: "F4F4F4")
    public static let textSecondary = Color.adaptive(light: "6B7280", dark: "B7BDC6")
    public static let textMuted = Color.adaptive(light: "9CA3AF", dark: "8D939C")

    // MARK: - Surfaces & borders

    public static let border = Color.adaptive(light: "E5E7EB", dark: "31353A")
    public static let borderPrimary = border
    public static let divider = Color.adaptive(light: "ECECEC", dark: "2A2E33")

    // MARK: - Accent (primary action — ~5% of UI)
    // V4 action green — current action, selection, progress, complete, recording only.
    // Never use as a full-card background. On-accent text is near-black for contrast.

    public static let accentPrimary = Color(hex: "C8FF4D")
    public static let accentHover = Color(hex: "D4FF6E")
    public static let accentPressed = Color(hex: "B4E63A")
    public static let accentGlow = Color(hex: "C8FF4D").opacity(0.18)
    public static let accentOnPrimary = Color(hex: "1C1C1E")

    public static let accentSecondary = textSecondary
    public static let accentTertiary = textMuted

    // MARK: - Semantic accents

    public static let focus = Color(hex: "7DD3FC")
    public static let health = Color(hex: "74C69D")
    public static let reflection = Color(hex: "B8A1FF")
    public static let learning = Color(hex: "F4C95D")
    public static let finance = Color(hex: "E9C46A")
    public static let relationships = Color(hex: "F497B6")
    public static let travel = Color(hex: "4DD0E1")
    public static let success = Color(hex: "7FD37F")
    public static let warning = Color(hex: "F6C453")
    public static let error = Color(hex: "F87171")

    // MARK: - Gradients

    public static let accentGradient = LinearGradient(
        colors: [accentPrimary, accentPrimary],
        startPoint: .top,
        endPoint: .bottom
    )

    public static let energyGradient = LinearGradient(
        colors: [accentPrimary.opacity(0.85), accentPrimary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let warmGradient = accentGradient
    public static let healthGradient = LinearGradient(
        colors: [health.opacity(0.8), health],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let backgroundGradient = LinearGradient(
        colors: [backgroundPrimary, backgroundPrimary],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Spacing (V4 scale)

    public static let spacingXXS: CGFloat = 4
    public static let spacingXS: CGFloat = 8
    public static let spacingSM: CGFloat = 12
    public static let spacingMD: CGFloat = 16
    public static let spacingLG: CGFloat = 24
    public static let spacingXL: CGFloat = 32
    public static let spacingXXL: CGFloat = 40
    public static let spacingXXXL: CGFloat = 48
    public static let spacingHero: CGFloat = 64

    public static let screenHorizontal: CGFloat = 32
    public static let cardPaddingMin: CGFloat = 24
    public static let sectionGap: CGFloat = 48
    public static let heroGap: CGFloat = 24

    // MARK: - Radius (V4)

    public static let radiusSM: CGFloat = 12
    public static let radiusMD: CGFloat = 18
    public static let radiusLG: CGFloat = 28
    public static let radiusXL: CGFloat = 28
    public static let radiusHero: CGFloat = 36
    public static let radiusFloating: CGFloat = 44
    public static let radiusSurface: CGFloat = 28
    public static let radiusButton: CGFloat = 18
    public static let radiusFull: CGFloat = 100

    // MARK: - Layout

    public static let minTouchTarget: CGFloat = 44
    public static let iconButtonSize: CGFloat = 44
    public static let readableMaxWidth: CGFloat = 680
    public static let heroMinHeight: CGFloat = 300
    public static let heroViewportRatio: CGFloat = 0.50

    public enum BriefingViewport {
        public static let header: CGFloat = 0.10
        public static let hero: CGFloat = 0.55
        public static let preview: CGFloat = 0.15
        public static let footer: CGFloat = 0.20
        /// Tighter horizontal inset so section cards read wider on briefing.
        public static let sectionHorizontal: CGFloat = 20
        public static let chapterSpacing: CGFloat = 12
        public static let heroSpacerCap: CGFloat = 32
        public static let scrollHintHeight: CGFloat = 56
    }

    // MARK: - Shadows

    public static let shadowElevated = Color.adaptive(
        light: "000000",
        dark: "000000"
    ).opacity(0.05)

    public static func shadowOpacity(for scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.35 : 0.05
    }

    public static let shadowRadius: CGFloat = 12
    public static let shadowYOffset: CGFloat = 4
}

// MARK: - Motion

public enum PremiumMotion {
    public static let springResponse: Double = 0.42
    public static let springDamping: Double = 0.88
    public static let fadeDuration: Double = 0.35
    public static let blurDuration: Double = 0.3
    public static let appearOffset: CGFloat = 8

    public static var pressSpring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }

    public static var fade: Animation {
        .easeOut(duration: fadeDuration)
    }

    public static func appear(delay: Double = 0, reduceMotion: Bool = false) -> Animation {
        if reduceMotion {
            return .linear(duration: 0.01).delay(delay)
        }
        return .easeOut(duration: fadeDuration).delay(delay)
    }

    public static func spring(reduceMotion: Bool = false) -> Animation {
        if reduceMotion { return .linear(duration: 0.01) }
        return pressSpring
    }
}

// Typography v2.1 → LookAfterTypography.swift

// MARK: - View layout helpers

public extension View {
    func minTouchTarget(_ size: CGFloat = DesignSystem.minTouchTarget) -> some View {
        frame(minWidth: size, minHeight: size)
    }

    func dsPrimaryText(lineLimit: Int = 3) -> some View {
        self
            .lineLimit(lineLimit)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    func dsChipText() -> some View {
        self
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.85)
            .allowsTightening(true)
    }

    func screenPadding() -> some View {
        padding(.horizontal, DesignSystem.screenHorizontal)
    }

    func lookAfterScreenBackground() -> some View {
        background(DesignSystem.backgroundPrimary.ignoresSafeArea())
    }
}

// MARK: - Color Hex Extension

public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Shimmer

public struct ShimmerEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    public init() {}

    public func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    LinearGradient(
                        colors: [.clear, Color.primary.opacity(0.04), .clear],
                        startPoint: .init(x: phase - 0.5, y: 0.5),
                        endPoint: .init(x: phase + 0.5, y: 0.5)
                    )
                    .blendMode(.overlay)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

public extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}
