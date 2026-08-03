import SwiftUI

/// LifeOS Design System — premium monochrome with restrained lime accent.
public struct DesignSystem {

    // MARK: - Backgrounds

    public static let backgroundPrimary = Color(hex: "0C0D0F")
    public static let backgroundSecondary = Color(hex: "17181C")
    public static let backgroundElevated = Color(hex: "1F2126")

    /// Legacy aliases
    public static let surfaceGlass = backgroundElevated.opacity(0.92)
    public static let borderGlass = divider

    // MARK: - Text

    public static let textPrimary = Color(hex: "F4F5F6")
    public static let textSecondary = Color(hex: "A5ABB5")
    public static let textMuted = Color(hex: "A5ABB5").opacity(0.65)

    // MARK: - Accent (use sparingly — ~10% of UI)

    public static let accentPrimary = Color(hex: "B8FF5A")
    public static let accentHover = Color(hex: "C6FF73")
    public static let accentPressed = Color(hex: "9BE83C")
    public static let accentGlow = Color(hex: "B8FF5A").opacity(0.18)

    /// Legacy — map to neutral; do not use for decorative icons
    public static let accentSecondary = textSecondary
    public static let accentTertiary = textMuted

    // MARK: - Semantic (monochrome-first)

    public static let success = accentPrimary
    public static let warning = textSecondary
    public static let error = Color(hex: "FF6B6B")
    public static let divider = Color.white.opacity(0.06)

    // MARK: - Gradients

    /// Primary CTA — solid lime reads cleaner than gradient on dark
    public static let accentGradient = LinearGradient(
        colors: [accentPrimary, accentPrimary],
        startPoint: .top,
        endPoint: .bottom
    )

    public static let energyGradient = LinearGradient(
        colors: [accentPrimary.opacity(0.8), accentPrimary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let warmGradient = accentGradient
    public static let healthGradient = accentGradient

    public static let backgroundGradient = LinearGradient(
        colors: [backgroundPrimary, backgroundPrimary],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Spacing

    public static let spacingXS: CGFloat = 6
    public static let spacingSM: CGFloat = 10
    public static let spacingMD: CGFloat = 16
    public static let spacingLG: CGFloat = 24
    public static let spacingXL: CGFloat = 28
    public static let spacingXXL: CGFloat = 40
    public static let spacingXXXL: CGFloat = 48

    public static let screenHorizontal: CGFloat = 28
    public static let sectionGap: CGFloat = 48
    public static let heroGap: CGFloat = 20

    // MARK: - Radius

    public static let radiusSM: CGFloat = 14
    public static let radiusMD: CGFloat = 20
    public static let radiusLG: CGFloat = 24
    public static let radiusXL: CGFloat = 28
    public static let radiusHero: CGFloat = 32
    public static let radiusSurface: CGFloat = 24
    public static let radiusButton: CGFloat = 20
    public static let radiusFull: CGFloat = 100

    // MARK: - Layout

    public static let minTouchTarget: CGFloat = 44
    public static let iconButtonSize: CGFloat = 44
    public static let readableMaxWidth: CGFloat = 680
    public static let heroMinHeight: CGFloat = 300
    public static let heroViewportRatio: CGFloat = 0.50

    /// Briefing first-viewport proportions (header + hero + preview + footer ≈ 100%).
    public enum BriefingViewport {
        public static let header: CGFloat = 0.10
        public static let hero: CGFloat = 0.50
        public static let preview: CGFloat = 0.20
        public static let footer: CGFloat = 0.20
        /// Compact spacing between scroll chapters — content-sized, not viewport-sized.
        public static let chapterSpacing: CGFloat = 28
    }

    // MARK: - Shadows

    public static let shadowElevated = Color.black.opacity(0.25)
    public static let shadowRadius: CGFloat = 16
    public static let shadowYOffset: CGFloat = 8
}

// MARK: - Motion

public enum PremiumMotion {
    public static let springResponse: Double = 0.35
    public static let springDamping: Double = 0.82
    public static let fadeDuration: Double = 0.5
    public static let blurDuration: Double = 0.4
    public static let appearOffset: CGFloat = 12

    public static var pressSpring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }

    public static var fade: Animation {
        .easeOut(duration: fadeDuration)
    }

    public static func appear(delay: Double = 0) -> Animation {
        .easeOut(duration: fadeDuration).delay(delay)
    }
}

// MARK: - Typography

public extension Font {
    static func dsDisplay() -> Font {
        .system(size: 34, weight: .semibold, design: .default)
    }

    static func dsTitle() -> Font {
        .system(size: 28, weight: .semibold, design: .default)
    }

    static func dsHeadline(weight: Font.Weight = .medium) -> Font {
        .system(size: 20, weight: weight, design: .default)
    }

    static func dsBody(weight: Font.Weight = .regular) -> Font {
        .system(size: 17, weight: weight, design: .default)
    }

    static func dsCaption(weight: Font.Weight = .regular) -> Font {
        .system(size: 14, weight: weight, design: .default)
    }

    static func dsMetadata(weight: Font.Weight = .medium) -> Font {
        .system(size: 12, weight: weight, design: .default)
    }

    static func dsLargeTitle(weight: Font.Weight = .semibold) -> Font {
        dsDisplay()
    }

    static func dsChip(weight: Font.Weight = .medium) -> Font {
        dsMetadata(weight: weight)
    }
}

// MARK: - View layout helpers

public extension View {
    func minTouchTarget(_ size: CGFloat = DesignSystem.minTouchTarget) -> some View {
        frame(minWidth: size, minHeight: size)
    }

    func dsPrimaryText(lineLimit: Int = 3) -> some View {
        self
            .lineLimit(lineLimit)
            .truncationMode(.tail)
            .multilineTextAlignment(.center)
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
    @State private var phase: CGFloat = 0

    public init() {}

    public func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.06), .clear],
                    startPoint: .init(x: phase - 0.5, y: 0.5),
                    endPoint: .init(x: phase + 0.5, y: 0.5)
                )
                .blendMode(.overlay)
            )
            .onAppear {
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
