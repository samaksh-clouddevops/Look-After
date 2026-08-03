import SwiftUI
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterFeatures

/// Brain tab — one clear action, capacity context, and lightweight scaffolding.
struct BrainDashboardView: View {

    @ObservedObject var brainVM: BrainViewModel
    @ObservedObject var adhdVM: ADHDViewModel
    let userId: String
    let onStartHero: (LifeTask?) -> Void
    let onRescheduleHero: (LifeTask) -> Void
    let onDecideForMe: () -> Void
    let onCapture: () -> Void
    let onResume: (String?) -> Void
    let onMarkMedicationTaken: (String) -> Void
    let onNavigateToTasks: () -> Void
    let onNavigateToCoach: () -> Void
    let onRefresh: () async -> Void

    @State private var showWhyNow = false
    @State private var showEnergyLog = false

    private var presentation: BrainPresentation { brainVM.presentation }

    var body: some View {
        ZStack {
            PremiumBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: DesignSystem.spacingXL) {
                    headerSection
                    askBrainSection
                    heroSection
                    secondarySections
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, DesignSystem.screenHorizontal)
                .padding(.top, DesignSystem.spacingSM)
            }
        }
        .accessibilityIdentifier("screen-brain-dashboard")
        .task {
            await brainVM.refresh(userId: userId)
            await onRefresh()
        }
        .sheet(isPresented: $showEnergyLog) {
            BrainEnergyLogSheet(brainVM: brainVM, userId: userId)
        }
    }

    // MARK: - Ask Brain (primary path)

    private var askBrainSection: some View {
        Button(action: onNavigateToCoach) {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(DesignSystem.accentPrimary)
                    Text("Ask Brain")
                        .font(.dsHeadline())
                        .foregroundColor(DesignSystem.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.textMuted)
                }

                Text("What's on your mind? I can help you plan, prioritize, or untangle the day.")
                    .font(.dsSecondary())
                    .foregroundColor(DesignSystem.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DesignSystem.cardPaddingMin)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                    .fill(DesignSystem.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                    .stroke(DesignSystem.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("brain-ask-entry")
        .accessibilityLabel("Ask Brain")
    }

    @ViewBuilder
    private var secondarySections: some View {
        resumeSection
        capacitySection

        DisclosureGroup("Tools & shortcuts") {
            VStack(spacing: DesignSystem.spacingMD) {
                scaffoldingSection
                headsUpSection
                backupSection
                capturePill
            }
            .padding(.top, DesignSystem.spacingSM)
        }
        .font(.dsCaption(weight: .semibold))
        .foregroundColor(DesignSystem.textSecondary)
        .tint(DesignSystem.accentPrimary)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center) {
            Text(presentation.greeting)
                .font(.system(size: 28, weight: .bold, design: .default))
                .foregroundColor(DesignSystem.textPrimary)

            Spacer()

            Text(presentation.readinessLabel)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundColor(DesignSystem.accentPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(DesignSystem.accentPrimary.opacity(0.12))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(DesignSystem.accentPrimary.opacity(0.25), lineWidth: 1)
                        )
                )
        }
    }

    // MARK: - Resume

    @ViewBuilder
    private var resumeSection: some View {
        if let resume = presentation.resume {
            Button {
                onResume(resume.taskID)
            } label: {
                VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                    HStack {
                        Label("Continue", systemImage: "arrow.uturn.forward")
                            .font(.dsMetadata(weight: .semibold))
                            .foregroundColor(DesignSystem.accentPrimary)
                        Spacer()
                        if let paused = resume.pausedAgoLabel {
                            Text(paused)
                                .font(.dsMetadata())
                                .foregroundColor(DesignSystem.textMuted)
                        }
                    }

                    Text(resume.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(DesignSystem.textPrimary)
                        .multilineTextAlignment(.leading)

                    Text(resume.detail)
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textSecondary)
                        .lineLimit(2)

                    if let elapsed = resume.elapsedLabel {
                        Text(elapsed)
                            .font(.dsMetadata())
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .elevatedSurface()
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroSection: some View {
        if let hero = presentation.hero {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                if hero.hasTask {
                    Label("DO THIS NOW", systemImage: "target")
                        .font(.dsMetadata(weight: .semibold))
                        .foregroundColor(DesignSystem.accentPrimary)
                }

                Text(hero.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(DesignSystem.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !hero.supportingLine.isEmpty {
                    Text(hero.supportingLine)
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                heroMetaRow(hero)

                if let coach = presentation.coachMoment {
                    Text(coach)
                        .font(.dsMetadata())
                        .foregroundColor(DesignSystem.textMuted)
                        .italic()
                }

                if let confidence = presentation.confidenceLabel {
                    Text(confidence)
                        .font(.dsMetadata())
                        .foregroundColor(DesignSystem.textMuted)
                }

                PremiumPrimaryButton(
                    hero.buttonLabel,
                    icon: hero.hasTask ? "play.fill" : "plus.circle.fill"
                ) {
                    onStartHero(hero.task)
                }

                if hero.hasTask, let task = hero.task {
                    HStack(spacing: DesignSystem.spacingSM) {
                        Button("Reschedule") {
                            onRescheduleHero(task)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.textSecondary)

                        Spacer()

                        Button("Decide for me") {
                            onDecideForMe()
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.accentPrimary)
                    }
                } else {
                    Button("Decide for me") {
                        onDecideForMe()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DesignSystem.accentPrimary)
                }

                if !hero.whyReasons.isEmpty {
                    whyNowSection(reasons: hero.whyReasons)
                }
            }
            .elevatedSurface()
        } else if brainVM.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.spacingXL)
        }
    }

    private func heroMetaRow(_ hero: BrainHeroPresentation) -> some View {
        HStack(spacing: DesignSystem.spacingMD) {
            if let scheduled = hero.scheduledLabel {
                metaChip(icon: "clock", label: scheduled, highlight: hero.isPastDue)
            }
            if let minutes = hero.durationMinutes, minutes > 0 {
                metaChip(icon: "hourglass", label: "\(minutes) min")
            }
            if let window = presentation.flowWindowLabel {
                metaChip(icon: "sparkles", label: window)
            }
        }
    }

    private func metaChip(icon: String, label: String, highlight: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
            Text(label)
                .font(.dsMetadata())
        }
        .foregroundColor(highlight ? DesignSystem.warning : DesignSystem.accentPrimary)
    }

    private func whyNowSection(reasons: [String]) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { showWhyNow.toggle() }
            } label: {
                HStack {
                    Image(systemName: "questionmark.circle")
                    Text(showWhyNow ? "Hide why now" : "Why now?")
                        .font(.dsMetadata())
                    Spacer()
                    Image(systemName: showWhyNow ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(DesignSystem.textMuted)
            }
            .buttonStyle(.plain)

            if showWhyNow {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(reasons, id: \.self) { reason in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(DesignSystem.accentPrimary.opacity(0.6))
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            Text(reason)
                                .font(.dsCaption())
                                .foregroundColor(DesignSystem.textSecondary)
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Capacity

    private var capacitySection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.capacity.bandLabel)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DesignSystem.textPrimary)
                    Text(presentation.capacity.tagline)
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textSecondary)
                }
                Spacer()
            }

            HStack(spacing: DesignSystem.spacingSM) {
                if let free = presentation.capacity.freeMinutesLabel {
                    capacityChip(free)
                }
                if let sleep = presentation.capacity.sleepLabel {
                    capacityChip(sleep)
                }
                Spacer()
                Button("Log how I feel") {
                    showEnergyLog = true
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.accentPrimary)
            }
        }
        .elevatedSurface(padding: DesignSystem.spacingMD, cornerRadius: DesignSystem.radiusMD)
    }

    private func capacityChip(_ label: String) -> some View {
        Text(label)
            .font(.dsMetadata())
            .foregroundColor(DesignSystem.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(DesignSystem.backgroundElevated.opacity(0.85))
            )
    }

    // MARK: - Scaffolding

    private var scaffoldingSection: some View {
        HStack(spacing: DesignSystem.spacingSM) {
            scaffoldButton(icon: "play.fill", label: "Start focus") {
                onStartHero(presentation.hero?.task)
            }
            scaffoldButton(icon: "exclamationmark.triangle.fill", label: "Emergency") {
                adhdVM.activateEmergencyMode(allTasks: brainVM.topTasks)
            }
            scaffoldButton(icon: "bubble.left.fill", label: UserFacingCopy.chatTitle) {
                onNavigateToCoach()
            }
        }
    }

    private func scaffoldButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(DesignSystem.textMuted)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DesignSystem.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .elevatedSurface(padding: 8, cornerRadius: DesignSystem.radiusMD)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Heads up

    @ViewBuilder
    private var headsUpSection: some View {
        if !presentation.headsUp.isEmpty {
            VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                Text("Heads up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(DesignSystem.textPrimary)

                ForEach(presentation.headsUp) { item in
                    headsUpRow(item)
                }
            }
            .elevatedSurface()
        }
    }

    private func headsUpRow(_ item: BrainHeadsUpItem) -> some View {
        HStack(spacing: DesignSystem.spacingSM) {
            Image(systemName: headsUpIcon(item.kind))
                .font(.system(size: 14))
                .foregroundColor(DesignSystem.textMuted)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.textPrimary)
                Text(item.subtitle)
                    .font(.dsMetadata())
                    .foregroundColor(DesignSystem.textSecondary)
            }

            Spacer()

            if item.kind == .medication, let medID = item.medicationID {
                Button(item.actionLabel ?? "Taken") {
                    onMarkMedicationTaken(medID)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.accentPrimary)
            }
        }
        .padding(.vertical, 4)
    }

    private func headsUpIcon(_ kind: BrainHeadsUpItem.Kind) -> String {
        switch kind {
        case .medication: return "pills.fill"
        case .bill: return "creditcard"
        case .calendar: return "calendar"
        }
    }

    // MARK: - Backup

    @ViewBuilder
    private var backupSection: some View {
        if !presentation.backupTasks.isEmpty {
            VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                HStack {
                    Text("If you finish early")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DesignSystem.textPrimary)
                    Spacer()
                    Button("All tasks", action: onNavigateToTasks)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.accentPrimary)
                }

                ForEach(presentation.backupTasks) { task in
                    CompactTaskRowView(task: task)
                }
            }
            .elevatedSurface()
        }
    }

    // MARK: - Capture

    private var capturePill: some View {
        Button(action: onCapture) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .medium))
                Text("Capture a thought")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(DesignSystem.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule(style: .continuous)
                    .fill(DesignSystem.backgroundElevated.opacity(0.9))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(DesignSystem.divider.opacity(0.6), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Energy log

private struct BrainEnergyLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var brainVM: BrainViewModel

    let userId: String

    @State private var energy: EnergyLevel = .moderate
    @State private var focusNote = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                        Text("How are you feeling right now?")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(DesignSystem.textPrimary)

                        VStack(spacing: DesignSystem.spacingSM) {
                            ForEach(EnergyLevel.allCases) { level in
                                Button {
                                    energy = level
                                } label: {
                                    HStack(spacing: DesignSystem.spacingMD) {
                                        Image(systemName: level.icon)
                                            .font(.system(size: 18))
                                            .foregroundColor(
                                                energy == level
                                                    ? DesignSystem.accentPrimary
                                                    : DesignSystem.textMuted
                                            )
                                            .frame(width: 28)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(level.rawValue)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(DesignSystem.textPrimary)
                                            Text(level.description)
                                                .font(.dsMetadata())
                                                .foregroundColor(DesignSystem.textSecondary)
                                                .multilineTextAlignment(.leading)
                                        }

                                        Spacer()

                                        if energy == level {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(DesignSystem.accentPrimary)
                                        }
                                    }
                                    .padding(DesignSystem.spacingMD)
                                    .background(
                                        RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                                            .fill(
                                                energy == level
                                                    ? DesignSystem.accentPrimary.opacity(0.1)
                                                    : DesignSystem.backgroundElevated.opacity(0.6)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                                                    .stroke(
                                                        energy == level
                                                            ? DesignSystem.accentPrimary.opacity(0.35)
                                                            : DesignSystem.divider.opacity(0.5),
                                                        lineWidth: 1
                                                    )
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Optional note")
                                .font(.dsMetadata(weight: .semibold))
                                .foregroundColor(DesignSystem.textMuted)
                            TextField("Scattered, locked in, tired…", text: $focusNote, axis: .vertical)
                                .lineLimit(2...4)
                                .textFieldStyle(.plain)
                                .padding(DesignSystem.spacingMD)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                                        .fill(DesignSystem.backgroundElevated.opacity(0.85))
                                )
                        }

                        PremiumPrimaryButton(isSaving ? "Saving…" : "Save check-in", icon: "checkmark") {
                            Task { await save() }
                        }
                        .disabled(isSaving)
                    }
                    .padding(DesignSystem.spacingMD)
                }
            }
            .navigationTitle("Log how I feel")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true
        let note = focusNote.trimmingCharacters(in: .whitespacesAndNewlines)
        await brainVM.logEnergyReport(
            energy: energy,
            focusNote: note.isEmpty ? nil : note,
            userId: userId
        )
        isSaving = false
        dismiss()
    }
}

/// A compact task row for the dashboard.
struct TaskRowView: View {
    let task: LifeTask

    var body: some View {
        CompactTaskRowView(task: task)
    }
}
