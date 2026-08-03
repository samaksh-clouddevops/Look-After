import SwiftUI

// MARK: - Scroll tracking

public struct ScrollOffsetKey: PreferenceKey {
    public static var defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Backgrounds

/// V4 flat canvas — calm, no decorative glows.
public struct CinematicBackground: View {
    public init(accentIntensity: Double = 0) {}

    public var body: some View {
        DesignSystem.backgroundPrimary
            .ignoresSafeArea()
    }
}

/// Sleep atmosphere — darker, still, minimal light.
public struct SleepAtmosphereBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            Color(hex: "080809").ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.white.opacity(0.025),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 0.35),
                startRadius: 0,
                endRadius: 420
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(hex: "0A0B0D").opacity(0),
                    Color(hex: "080809")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Primary CTA (hero object)

public struct ImmersivePrimaryCTA: View {
    let title: String
    let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(DesignSystem.accentPrimary.opacity(0.15))
                    .blur(radius: 20)
                    .padding(-8)

                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(DesignSystem.backgroundPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(DesignSystem.accentPrimary)
                    )
            }
        }
        .buttonStyle(PremiumPressStyle())
    }
}

// MARK: - Visual memory (Continue — real context only)

public struct VisualMemoryCanvas: View {
    let frame: LifeContextFrame
    var progress: Double

    public init(frame: LifeContextFrame, progress: Double = 1) {
        self.frame = frame
        self.progress = progress
    }

    public init(
        context: WorkingContext,
        resume: ResumeSnapshot? = nil,
        task: LifeTask? = nil,
        progress: Double = 1
    ) {
        var built = LifeContextFrameBuilder.build(resume: resume, task: task)
        if !built.hasContent {
            built = LifeContextFrame(
                sourceLabel: Self.sourceLabel(for: context),
                primaryText: context.title,
                secondaryText: context.subtitle
            )
        }
        self.init(frame: built, progress: progress)
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            ResumeContextBackdrop(frame: frame)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

            LinearGradient(
                colors: [Color.clear, DesignSystem.backgroundPrimary.opacity(0.82)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

            if let title = frame.primaryText, progress > 0.4 {
                VStack(alignment: .leading, spacing: 8) {
                    if let source = frame.sourceLabel {
                        Text(source)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                    Text(title)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(DesignSystem.textPrimary.opacity(0.92))
                        .lineLimit(3)
                    if let secondary = frame.secondaryText {
                        Text(secondary)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
                .padding(28)
                .opacity(Double(progress))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private static func sourceLabel(for context: WorkingContext) -> String {
        switch context.kind {
        case .browser: return "Safari"
        case .note, .brainCapture: return "Notes"
        case .document: return "Document"
        case .file: return "File"
        case .aiCoach: return "Conversation"
        case .focusSession: return "Timer"
        case .task: return "Task"
        case .screen: return "Screen"
        }
    }
}

// MARK: - Narrative typography (Today's Story)

public struct NarrativeBeat: View {
    let period: String
    let activity: String

    public init(period: String, activity: String) {
        self.period = period
        self.activity = activity
    }

    public var body: some View {
        VStack(spacing: 28) {
            Text(period)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(DesignSystem.textMuted.opacity(0.7))
                .frame(maxWidth: .infinity)

            Text(activity)
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(DesignSystem.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 20)
    }
}

public struct ScrollOffsetReporter: View {
    public init() {}

    public var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(
                    key: ScrollOffsetKey.self,
                    value: geo.frame(in: .named("cinematicScroll")).minY
                )
        }
        .frame(height: 0)
    }
}
