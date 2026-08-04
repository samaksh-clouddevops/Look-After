import SwiftUI

/// Calm hero — one title, optional support, one metadata line, one primary action.
/// Everything else lives behind progressive disclosure.
public struct CalmHeroSurface: View {
    let content: CalmHeroContent
    let primaryAction: () -> Void
    var secondaryActions: [CalmHeroSecondaryAction]

    @State private var isExpanded = false

    public init(
        content: CalmHeroContent,
        primaryAction: @escaping () -> Void,
        secondaryActions: [CalmHeroSecondaryAction] = []
    ) {
        self.content = content
        self.primaryAction = primaryAction
        self.secondaryActions = secondaryActions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
            VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                Text(content.title)
                    .font(.dsTitle())
                    .foregroundColor(DesignSystem.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let supporting = content.supportingLine, !supporting.isEmpty {
                    Text(supporting)
                        .font(.dsBody())
                        .foregroundColor(DesignSystem.textSecondary)
                        .lineLimit(1)
                }

                if let metadata = content.metadataLine, !metadata.isEmpty {
                    Text(metadata)
                        .font(.dsMetadata())
                        .foregroundColor(DesignSystem.textMuted)
                        .lineLimit(1)
                }
            }

            PremiumPrimaryButton(content.primaryActionTitle, icon: "arrow.right", action: primaryAction)

            if content.disclosure?.hasContent == true || !secondaryActions.isEmpty {
                disclosureAffordance
            }

            if isExpanded {
                disclosureBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var disclosureAffordance: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                isExpanded.toggle()
            }
        } label: {
            Text(isExpanded ? "Hide details" : "Why this?")
                .font(.dsMetadata())
                .foregroundColor(DesignSystem.textMuted)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var disclosureBody: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
            if let disclosure = content.disclosure {
                if let narrative = disclosure.narrative, !narrative.isEmpty {
                    Text(narrative)
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(disclosure.whyLines, id: \.self) { line in
                    Text(line)
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let prompt = disclosure.alternativePrompt, !prompt.isEmpty {
                    Text(prompt)
                        .font(.dsMetadata())
                        .foregroundColor(DesignSystem.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !secondaryActions.isEmpty {
                VStack(spacing: DesignSystem.spacingSM) {
                    ForEach(secondaryActions) { action in
                        PremiumGhostButton(action.title, icon: action.icon, fillsWidth: true) {
                            action.action()
                        }
                    }
                }
            }
        }
        .padding(.top, DesignSystem.spacingXS)
    }
}

/// Collapsed one-line health signal — details on demand.
public struct CalmHealthSnapshotLine: View {
    let label: String
    let detail: String
    var expandedBody: AnyView?

    @State private var isExpanded = false

    public init(label: String, detail: String) {
        self.label = label
        self.detail = detail
        self.expandedBody = nil
    }

    public init(label: String, detail: String, @ViewBuilder expanded: () -> some View) {
        self.label = label
        self.detail = detail
        self.expandedBody = AnyView(expanded())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            Button {
                guard expandedBody != nil else { return }
                withAnimation(.easeInOut(duration: 0.22)) { isExpanded.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                    HStack(alignment: .firstTextBaseline, spacing: DesignSystem.spacingSM) {
                        Text(label)
                            .font(.dsBody(weight: .semibold))
                            .foregroundColor(DesignSystem.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                        Spacer(minLength: 8)
                        if expandedBody != nil {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(DesignSystem.textMuted)
                        }
                    }
                    Text(detail)
                        .font(.dsMetadata())
                        .foregroundColor(DesignSystem.textMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(.plain)

            if isExpanded, let expandedBody {
                expandedBody
                    .transition(.opacity)
            }
        }
    }
}

/// Section header for progressive disclosure of non-hero briefing content.
public struct CalmDisclosureSection<Content: View>: View {
    let title: String
    let collapsedHint: String
    @ViewBuilder let content: () -> Content

    @State private var isExpanded = false

    public init(title: String, collapsedHint: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.collapsedHint = collapsedHint
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { isExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.dsMetadata(weight: .semibold))
                            .foregroundColor(DesignSystem.textMuted)
                        if !isExpanded {
                            Text(collapsedHint)
                                .font(.dsCaption())
                                .foregroundColor(DesignSystem.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.textMuted)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
