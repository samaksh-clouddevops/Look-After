import SwiftUI
import LookAfterCore
import LookAfterHealth

/// Plain-language health connection status for Today, Settings, and detail sheets.
struct HealthStatusBanner: View {
    let status: HealthConnectionStatus
    var style: Style = .full
    var onPrimaryAction: () -> Void
    var onSeeDetails: (() -> Void)?
    var onLearnMore: (() -> Void)?

    enum Style {
        case full
        case compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(status.headline)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("health-status-headline")

                    if style == .full {
                        Text(status.explanation)
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if style == .full, !status.fixSteps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(status.fixSteps.prefix(3).enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(DesignSystem.textMuted)
                            Text(step)
                                .font(.system(size: 11))
                                .foregroundColor(DesignSystem.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.leading, 32)
            }

            if !status.missingMetrics.isEmpty, style == .full {
                Text("Missing: \(status.missingMetrics.joined(separator: ", "))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DesignSystem.warning)
                    .padding(.leading, 32)
            }

            HStack(spacing: DesignSystem.spacingSM) {
                if status.primaryAction != .none, !status.primaryActionLabel.isEmpty {
                    Button(action: onPrimaryAction) {
                        Text(status.primaryActionLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.accentOnPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(DesignSystem.accentPrimary))
                    }
                    .buttonStyle(.plain)
                }

                if let onSeeDetails {
                    Button(action: onSeeDetails) {
                        Text("See details")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.accentPrimary)
                    }
                    .buttonStyle(.plain)
                }

                if let onLearnMore {
                    Button(action: onLearnMore) {
                        Text("Learn more")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, style == .full ? 32 : 0)
            .padding(.top, 2)
        }
        .padding(DesignSystem.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                        .stroke(iconColor.opacity(0.35), lineWidth: 1)
                )
        )
        .accessibilityIdentifier("health-status-banner")
    }

    private var iconName: String {
        switch status.kind {
        case .allGood: return "checkmark.circle.fill"
        case .partialData, .syncStale: return "exclamationmark.triangle.fill"
        case .waitingForData: return "clock.fill"
        case .accessBlocked, .trackingOff: return "hand.raised.slash.fill"
        case .notSetUp: return "heart.text.square.fill"
        }
    }

    private var iconColor: Color {
        switch status.kind {
        case .allGood: return DesignSystem.success
        case .partialData, .syncStale, .waitingForData: return DesignSystem.warning
        case .accessBlocked, .trackingOff, .notSetUp: return DesignSystem.error
        }
    }
}

enum HealthStatusActionHandler {
    static func perform(
        _ action: HealthStatusAction,
        onConnect: @escaping () -> Void,
        onSync: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        switch action {
        case .connect:
            onConnect()
        case .syncNow:
            onSync()
        case .openHealth:
            if let url = HealthAppLinks.healthAppURL {
                UIApplication.shared.open(url)
            }
        case .openAppSettings:
            onOpenSettings()
        case .none:
            break
        }
    }
}
