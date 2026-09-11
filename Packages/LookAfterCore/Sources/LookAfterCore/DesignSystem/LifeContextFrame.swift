import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Frame model (real user context only)

public struct LifeContextFrame: Sendable, Equatable {
    public var sourceLabel: String?
    public var primaryText: String?
    public var secondaryText: String?
    public var previewImageData: Data?

    public var hasContent: Bool {
        if previewImageData != nil { return true }
        guard let primaryText else { return false }
        return !primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init(
        sourceLabel: String? = nil,
        primaryText: String? = nil,
        secondaryText: String? = nil,
        previewImageData: Data? = nil
    ) {
        self.sourceLabel = sourceLabel
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.previewImageData = previewImageData
    }
}

public enum LifeContextFrameBuilder {
    public static func build(resume: ResumeSnapshot?, task: LifeTask?) -> LifeContextFrame {
        if let resume {
            if let data = resume.previewImageData {
                return LifeContextFrame(
                    sourceLabel: sourceLabel(for: resume),
                    primaryText: resume.workingContext?.title ?? resume.resumeDetail,
                    secondaryText: metaLine(resume: resume, task: task),
                    previewImageData: data
                )
            }
            if let context = resume.workingContext {
                return LifeContextFrame(
                    sourceLabel: sourceLabel(for: context),
                    primaryText: context.title,
                    secondaryText: context.subtitle ?? metaLine(resume: resume, task: task)
                )
            }
            if let detail = resume.resumeDetail {
                return LifeContextFrame(
                    sourceLabel: sourceLabel(for: resume),
                    primaryText: detail,
                    secondaryText: metaLine(resume: resume, task: task)
                )
            }
        }
        if let task {
            return LifeContextFrame(
                sourceLabel: "Task",
                primaryText: task.title,
                secondaryText: task.progress > 0 ? "\(Int(task.progress * 100))% complete" : nil
            )
        }
        return LifeContextFrame()
    }

    public static func heroConcreteLine(briefing: HeroBriefing) -> String {
        if let line = briefing.contextLine, !line.isEmpty { return line }
        return briefing.whyNowReasons.first ?? ""
    }

    public static func metaLine(resume: ResumeSnapshot?, task: LifeTask?) -> String? {
        var parts: [String] = []
        if let resume {
            if Calendar.current.isDateInYesterday(resume.savedAt) {
                parts.append("Yesterday")
            } else if !Calendar.current.isDateInToday(resume.savedAt) {
                parts.append(relativeDay(resume.savedAt))
            }
        }
        if let task, task.progress > 0 {
            parts.append("\(Int(task.progress * 100))% complete")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public static func dayPreviewRows(
        timelineItems: [LifeTimelineEvent],
        storySegments: [StorySegment],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DayPreviewRow] {
        let calendarToday = timelineItems
            .filter { $0.kind == .meeting && calendar.isDate($0.date, inSameDayAs: now) && !$0.isCompleted }
            .sorted { $0.date < $1.date }
            .prefix(4)

        if !calendarToday.isEmpty {
            return calendarToday.map { item in
                DayPreviewRow(
                    id: item.id,
                    timeLabel: item.date.formatted(date: .omitted, time: .shortened),
                    title: item.title
                )
            }
        }

        return storySegments.prefix(4).map { segment in
            DayPreviewRow(id: segment.id, timeLabel: segment.periodLabel, title: segment.title)
        }
    }

    public static func sleepHoursLabel(from health: HealthSummary?) -> String? {
        guard let minutes = health?.totalSleepMinutes, minutes > 0 else { return nil }
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        return "\(hours)h \(String(format: "%02d", mins))m"
    }

    private static func relativeDay(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
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

    private static func sourceLabel(for resume: ResumeSnapshot) -> String {
        if let context = resume.workingContext { return sourceLabel(for: context) }
        if resume.lastBrowserLink != nil { return "Safari" }
        if resume.lastNote != nil { return "Notes" }
        if resume.lastDocument != nil { return "Document" }
        if resume.lastAIConversationPreview != nil { return "Conversation" }
        return "Task"
    }
}

// MARK: - Backdrop (real text or image — never fake UI)

public struct ResumeContextBackdrop: View {
    let frame: LifeContextFrame

    public init(frame: LifeContextFrame) {
        self.frame = frame
    }

    public var body: some View {
        ZStack {
            if frame.hasContent {
                contentLayer
                veil
            } else {
                FallbackGradient(style: .neutral)
            }
        }
    }

    @ViewBuilder
    private var contentLayer: some View {
        #if canImport(UIKit)
        if let data = frame.previewImageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .blur(radius: 28)
                .clipped()
        } else if let text = frame.primaryText {
            ZStack(alignment: .topLeading) {
                FallbackGradient(style: .context)
                Text(text)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundColor(DesignSystem.textPrimary.opacity(0.22))
                    .multilineTextAlignment(.leading)
                    .lineLimit(6)
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .blur(radius: 6)
            }
        }
        #else
        if let text = frame.primaryText {
            ZStack(alignment: .topLeading) {
                FallbackGradient(style: .context)
                Text(text)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundColor(DesignSystem.textPrimary.opacity(0.22))
                    .padding(28)
            }
        }
        #endif
    }

    private var veil: some View {
        LinearGradient(
            colors: [
                DesignSystem.backgroundPrimary.opacity(0.5),
                DesignSystem.backgroundPrimary.opacity(0.88),
                DesignSystem.backgroundPrimary.opacity(0.96)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Fallback gradients (only when no life context)

public enum FallbackGradientStyle {
    case neutral, context, sleep, remember
}

public struct FallbackGradient: View {
    let style: FallbackGradientStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe: Double = 0

    public init(style: FallbackGradientStyle) {
        self.style = style
    }

    public var body: some View {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .opacity(style == .sleep ? (reduceMotion ? 0.94 : 0.88 + breathe * 0.12) : 1)
            .onAppear {
                guard style == .sleep, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                    breathe = 1
                }
            }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced {
                    breathe = 0
                } else if style == .sleep {
                    withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                        breathe = 1
                    }
                }
            }
    }

    private var colors: [Color] {
        switch style {
        case .neutral:
            return [Color(hex: "12141A"), DesignSystem.backgroundPrimary]
        case .context:
            return [Color(hex: "141820"), Color(hex: "0C0D0F")]
        case .sleep:
            return [Color(hex: "1A1410"), Color(hex: "0E0C0A"), Color(hex: "080809")]
        case .remember:
            return [Color(hex: "161412"), Color(hex: "0C0D0F")]
        }
    }
}

// MARK: - Day preview (content, not poster)

public struct DayPreviewRow: Identifiable, Sendable {
    public let id: String
    public let timeLabel: String
    public let title: String

    public init(id: String, timeLabel: String, title: String) {
        self.id = id
        self.timeLabel = timeLabel
        self.title = title
    }
}

public struct DayPreviewCard: View {
    let rows: [DayPreviewRow]
    let action: () -> Void

    public init(rows: [DayPreviewRow], action: @escaping () -> Void) {
        self.rows = rows
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Today")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(DesignSystem.textMuted)
                    .padding(.bottom, 12)

                divider

                VStack(spacing: 14) {
                    ForEach(rows.prefix(4)) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(row.timeLabel)
                                .font(.system(size: 14, weight: .regular, design: .monospaced))
                                .foregroundColor(DesignSystem.textMuted)
                                .frame(width: 52, alignment: .leading)
                            Text(row.title)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(DesignSystem.textPrimary.opacity(0.9))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.vertical, 16)

                divider
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.contentSurface)
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(DesignSystem.border, lineWidth: 1)
            )
        }
        .buttonStyle(PremiumPressStyle())
    }

    private var divider: some View {
        Rectangle().fill(DesignSystem.divider).frame(height: 1)
    }
}

// MARK: - Remember preview (real note text)

public struct RememberPreviewCard: View {
    let notePreview: String?
    let action: () -> Void

    public init(notePreview: String?, action: @escaping () -> Void) {
        self.notePreview = notePreview
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                if let notePreview, !notePreview.isEmpty {
                    Text(notePreview)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(DesignSystem.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("Don't let me forget…")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(DesignSystem.textMuted)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.contentSurfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(DesignSystem.border, lineWidth: 1)
            )
        }
        .buttonStyle(PremiumPressStyle())
    }
}

// MARK: - Sleep preview (breathing gradient + real hours)

public struct SleepPreviewCard: View {
    let sleepLabel: String?
    let action: () -> Void

    public init(sleepLabel: String?, action: @escaping () -> Void) {
        self.sleepLabel = sleepLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                FallbackGradient(style: .sleep)

                if let sleepLabel {
                    Text(sleepLabel)
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(DesignSystem.textPrimary.opacity(0.75))
                        .padding(24)
                }
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(DesignSystem.border, lineWidth: 1)
            )
        }
        .buttonStyle(PremiumPressStyle())
    }
}
