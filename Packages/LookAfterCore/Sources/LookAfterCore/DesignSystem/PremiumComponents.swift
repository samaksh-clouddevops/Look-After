import SwiftUI

// MARK: - Premium Background

/// Cinematic dark background — delegates to continuous cinematic field.
public struct PremiumBackground: View {
    public init() {}

    public var body: some View {
        CinematicBackground()
    }
}

// MARK: - Screen Scaffold

/// Standard screen wrapper — premium background + optional scroll. Use on every screen.
public struct PremiumScreen<Content: View>: View {
    var scroll: Bool
    @ViewBuilder let content: Content

    public init(scroll: Bool = true, @ViewBuilder content: () -> Content) {
        self.scroll = scroll
        self.content = content()
    }

    public var body: some View {
        ZStack {
            PremiumBackground()

            if scroll {
                ScrollView(.vertical, showsIndicators: false) {
                    content
                }
            } else {
                content
            }
        }
    }
}

public extension View {
    /// Wraps content in the premium screen scaffold.
    func premiumScreen(scroll: Bool = true) -> some View {
        PremiumScreen(scroll: scroll) { self }
    }
}

// MARK: - Hero Zone

/// Occupies roughly the top third — one dominant visual experience.
public struct HeroZone<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: DesignSystem.heroGap) {
            content
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: DesignSystem.heroMinHeight, alignment: .center)
        .multilineTextAlignment(.center)
    }
}

// MARK: - Press style

public struct PremiumPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(PremiumMotion.spring(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

// MARK: - Screen Chrome

public struct ScreenChrome: View {
    let onSettings: () -> Void
    var onTrailing: (() -> Void)?
    var trailingIcon: String?

    public init(onSettings: @escaping () -> Void, trailingIcon: String? = "mic.fill", onTrailing: (() -> Void)? = nil) {
        self.onSettings = onSettings
        self.trailingIcon = trailingIcon
        self.onTrailing = onTrailing
    }

    public var body: some View {
        HStack {
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(DesignSystem.textMuted)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            if let trailingIcon, let onTrailing {
                Button(action: onTrailing) {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(DesignSystem.textMuted)
                        .frame(width: 44, height: 44)
                }
            }
        }
    }
}

// MARK: - Motion

public struct AppearAnimation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    var delay: Double

    public init(delay: Double = 0) {
        self.delay = delay
    }

    public func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: (visible || reduceMotion) ? 0 : 12)
            .onAppear {
                withAnimation(PremiumMotion.appear(delay: delay, reduceMotion: reduceMotion)) {
                    visible = true
                }
            }
    }
}

public extension View {
    func appearAnimation(delay: Double = 0) -> some View {
        modifier(AppearAnimation(delay: delay))
    }
}

// MARK: - Legacy Background Alias

/// Deprecated — use `PremiumBackground` directly.
public struct AnimatedGradientBackground: View {
    public init() {}

    public var body: some View {
        PremiumBackground()
    }
}

// MARK: - List Row

public struct PremiumListRow: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var showsChevron: Bool
    var isActive: Bool
    let action: () -> Void

    public init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        showsChevron: Bool = true,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.showsChevron = showsChevron
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.spacingMD) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(isActive ? DesignSystem.accentPrimary : DesignSystem.textMuted)
                        .frame(width: 28, alignment: .center)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.dsBody(weight: .medium))
                        .foregroundColor(DesignSystem.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(.dsCaption())
                            .foregroundColor(DesignSystem.textMuted)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 8)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.textMuted)
                }
            }
            .padding(.vertical, DesignSystem.spacingSM)
            .contentShape(Rectangle())
        }
        .buttonStyle(PremiumPressStyle())
    }
}

// MARK: - Navigation Bar

public struct PremiumNavigationBar: View {
    let title: String
    var leadingIcon: String?
    var trailingIcon: String?
    var onLeading: (() -> Void)?
    var onTrailing: (() -> Void)?

    public init(
        title: String,
        leadingIcon: String? = nil,
        trailingIcon: String? = nil,
        onLeading: (() -> Void)? = nil,
        onTrailing: (() -> Void)? = nil
    ) {
        self.title = title
        self.leadingIcon = leadingIcon
        self.trailingIcon = trailingIcon
        self.onLeading = onLeading
        self.onTrailing = onTrailing
    }

    public var body: some View {
        HStack(spacing: DesignSystem.spacingMD) {
            if let leadingIcon, let onLeading {
                navButton(icon: leadingIcon, action: onLeading)
            } else {
                Color.clear.frame(width: DesignSystem.iconButtonSize, height: DesignSystem.iconButtonSize)
            }

            Spacer(minLength: 0)

            Text(title)
                .font(.dsHeadline())
                .foregroundColor(DesignSystem.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let trailingIcon, let onTrailing {
                navButton(icon: trailingIcon, action: onTrailing)
            } else {
                Color.clear.frame(width: DesignSystem.iconButtonSize, height: DesignSystem.iconButtonSize)
            }
        }
        .padding(.horizontal, DesignSystem.spacingMD)
        .frame(minHeight: DesignSystem.minTouchTarget)
    }

    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(DesignSystem.textMuted)
                .frame(width: DesignSystem.iconButtonSize, height: DesignSystem.iconButtonSize)
        }
        .buttonStyle(PremiumPressStyle())
    }
}

// MARK: - Input

public struct PremiumInput: View {
    let title: String
    @Binding var text: String
    var placeholder: String
    var icon: String?
    var axis: Axis

    public init(
        _ title: String,
        text: Binding<String>,
        placeholder: String = "",
        icon: String? = nil,
        axis: Axis = .horizontal
    ) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
        self.icon = icon
        self.axis = axis
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            Text(title)
                .font(.dsCaption(weight: .medium))
                .foregroundColor(DesignSystem.textSecondary)

            HStack(spacing: DesignSystem.spacingSM) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(DesignSystem.textMuted)
                }

                TextField(placeholder, text: $text, axis: axis)
                    .font(.dsBody())
                    .foregroundColor(DesignSystem.textPrimary)
                    .tint(DesignSystem.accentPrimary)
            }
            .padding(.horizontal, DesignSystem.spacingMD)
            .padding(.vertical, DesignSystem.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                    .fill(DesignSystem.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                    .stroke(DesignSystem.divider, lineWidth: 1)
            )
        }
    }
}

// MARK: - Sheet

public struct ImmersiveSheet<Content: View>: View {
    let title: String
    var onDismiss: (() -> Void)?
    @ViewBuilder let content: Content

    public init(
        title: String,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.onDismiss = onDismiss
        self.content = content()
    }

    public var body: some View {
        ZStack {
            PremiumBackground()

            VStack(spacing: 0) {
                PremiumNavigationBar(
                    title: title,
                    leadingIcon: onDismiss != nil ? "xmark" : nil,
                    onLeading: onDismiss
                )
                .padding(.top, DesignSystem.spacingSM)

                ScrollView(showsIndicators: false) {
                    content
                        .screenPadding()
                        .padding(.vertical, DesignSystem.spacingLG)
                }
            }
        }
    }
}

// MARK: - Modal

public struct PremiumModal<Content: View>: View {
    @Binding var isPresented: Bool
    let title: String
    @ViewBuilder let content: Content

    public init(
        isPresented: Binding<Bool>,
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self._isPresented = isPresented
        self.title = title
        self.content = content()
    }

    public var body: some View {
        ZStack {
            if isPresented {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { isPresented = false }
                    .transition(.opacity)

                VStack(spacing: DesignSystem.spacingLG) {
                    HStack {
                        Text(title)
                            .font(.dsTitle())
                            .foregroundColor(DesignSystem.textPrimary)
                        Spacer()
                        Button(action: { isPresented = false }, label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(DesignSystem.textMuted)
                                .frame(width: 32, height: 32)
                        })
                        .buttonStyle(PremiumPressStyle())
                    }

                    content
                }
                .padding(DesignSystem.spacingXL)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusHero, style: .continuous)
                        .fill(DesignSystem.backgroundElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusHero, style: .continuous)
                        .stroke(Color.white.opacity(0.04), lineWidth: 1)
                )
                .screenPadding()
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(PremiumMotion.pressSpring, value: isPresented)
    }
}

// MARK: - Alert

public struct PremiumAlert: View {
    let title: String
    let message: String
    var primaryTitle: String
    var secondaryTitle: String?
    let onPrimary: () -> Void
    var onSecondary: (() -> Void)?

    public init(
        title: String,
        message: String,
        primaryTitle: String = "OK",
        secondaryTitle: String? = nil,
        onPrimary: @escaping () -> Void,
        onSecondary: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.primaryTitle = primaryTitle
        self.secondaryTitle = secondaryTitle
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
    }

    public var body: some View {
        VStack(spacing: DesignSystem.spacingLG) {
            VStack(spacing: DesignSystem.spacingSM) {
                Text(title)
                    .font(.dsHeadline())
                    .foregroundColor(DesignSystem.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.dsBody())
                    .foregroundColor(DesignSystem.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: DesignSystem.spacingSM) {
                PremiumPrimaryButton(primaryTitle, action: onPrimary)
                if let secondaryTitle, let onSecondary {
                    PremiumGhostButton(secondaryTitle, action: onSecondary)
                }
            }
        }
        .padding(DesignSystem.spacingXL)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusHero, style: .continuous)
                .fill(DesignSystem.backgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.radiusHero, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }
}

#if canImport(UIKit)
import UIKit
#endif