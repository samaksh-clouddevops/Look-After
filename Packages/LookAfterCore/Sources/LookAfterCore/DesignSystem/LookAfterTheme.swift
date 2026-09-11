import SwiftUI

// MARK: - Semantic palette (V4)

/// Resolved semantic colors for the active color scheme.
public struct LookAfterSemanticColors: Equatable, Sendable {
    public var canvas: Color
    public var surfacePrimary: Color
    public var surfaceSecondary: Color
    public var surfaceElevated: Color
    public var textPrimary: Color
    public var textSecondary: Color
    public var textMuted: Color
    public var border: Color
    public var divider: Color
    public var shadow: Color
    public var actionPrimary: Color
    public var actionOnPrimary: Color
    public var focus: Color
    public var health: Color
    public var reflection: Color
    public var learning: Color
    public var finance: Color
    public var relationships: Color
    public var travel: Color
    public var success: Color
    public var warning: Color
    public var error: Color

    public static let light = LookAfterSemanticColors(
        canvas: Color(hex: "F8F8F6"),
        surfacePrimary: Color(hex: "FFFFFF"),
        surfaceSecondary: Color(hex: "F3F4F6"),
        surfaceElevated: Color(hex: "ECEEF1"),
        textPrimary: Color(hex: "1C1C1E"),
        textSecondary: Color(hex: "6B7280"),
        textMuted: Color(hex: "9CA3AF"),
        border: Color(hex: "E5E7EB"),
        divider: Color(hex: "ECECEC"),
        shadow: Color.black.opacity(0.05),
        actionPrimary: Color(hex: "C8FF4D"),
        actionOnPrimary: Color(hex: "1C1C1E"),
        focus: Color(hex: "7DD3FC"),
        health: Color(hex: "74C69D"),
        reflection: Color(hex: "B8A1FF"),
        learning: Color(hex: "F4C95D"),
        finance: Color(hex: "E9C46A"),
        relationships: Color(hex: "F497B6"),
        travel: Color(hex: "4DD0E1"),
        success: Color(hex: "7FD37F"),
        warning: Color(hex: "F6C453"),
        error: Color(hex: "F87171")
    )

    public static let dark = LookAfterSemanticColors(
        canvas: Color(hex: "111315"),
        surfacePrimary: Color(hex: "191C1F"),
        surfaceSecondary: Color(hex: "23272C"),
        surfaceElevated: Color(hex: "2B3036"),
        textPrimary: Color(hex: "F4F4F4"),
        textSecondary: Color(hex: "C5CAD1"),
        textMuted: Color(hex: "A8AEB8"),
        border: Color(hex: "31353A"),
        divider: Color(hex: "2A2E33"),
        shadow: Color.black.opacity(0.35),
        actionPrimary: Color(hex: "C8FF4D"),
        actionOnPrimary: Color(hex: "1C1C1E"),
        focus: Color(hex: "7DD3FC"),
        health: Color(hex: "74C69D"),
        reflection: Color(hex: "B8A1FF"),
        learning: Color(hex: "F4C95D"),
        finance: Color(hex: "E9C46A"),
        relationships: Color(hex: "F497B6"),
        travel: Color(hex: "4DD0E1"),
        success: Color(hex: "7FD37F"),
        warning: Color(hex: "F6C453"),
        error: Color(hex: "F87171")
    )

    public static func resolved(for scheme: ColorScheme) -> LookAfterSemanticColors {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - In-app appearance override

public enum AppAppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public static let storageKey = "lookafter.appearanceMode"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    public static func load(from defaults: UserDefaults = .standard) -> AppAppearanceMode {
        guard let raw = defaults.string(forKey: storageKey),
              let mode = AppAppearanceMode(rawValue: raw) else { return .system }
        return mode
    }

    public var isDark: Bool { self == .dark }

    public var usesSystemSetting: Bool { self == .system }
}

// MARK: - Environment (semantic palette)

private struct LookAfterThemeKey: EnvironmentKey {
    static let defaultValue = LookAfterSemanticColors.light
}

public extension EnvironmentValues {
    var lookAfterTheme: LookAfterSemanticColors {
        get { self[LookAfterThemeKey.self] }
        set { self[LookAfterThemeKey.self] = newValue }
    }
}

public extension View {
    /// Injects semantic colors from the system color scheme.
    func lookAfterThemed() -> some View {
        modifier(LookAfterThemeModifier())
    }
}

private struct LookAfterThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.lookAfterTheme, LookAfterSemanticColors.resolved(for: colorScheme))
    }
}

// MARK: - Adaptive Color helper

public extension Color {
    static func adaptive(light: String, dark: String) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
        #else
        return Color(hex: light)
        #endif
    }
}

#if canImport(AppKit)
import AppKit
#endif
