import SwiftUI
import LifeOSCore
import LifeOSAI
import LifeOSFeatures

/// End-of-day reflection below the timeline — separate from schedule rows; feeds the brain.
struct TodayEndOfDayJournalCard: View {
    @ObservedObject var modulesVM: LifeModulesViewModel
    @ObservedObject var tasksVM: TasksViewModel
    @ObservedObject var speechManager: SpeechRecognitionManager

    @State private var entryText = ""
    @State private var calibrationBadge: String?
    @State private var isProcessingAI = false
    @FocusState private var isFieldFocused: Bool

    private var recentCalibrations: [UserCalibrationEntry] {
        Array(UserCalibrationStore.load().prefix(3))
    }

    private var completedToday: [LifeTask] { tasksVM.completedToday }
    private var inProgressToday: [LifeTask] {
        tasksVM.tasks.filter { $0.status == .inProgress }
    }
    private var pendingToday: [LifeTask] {
        tasksVM.tasks.filter { $0.status == .pending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
            sectionDivider
            cardBody
        }
    }

    // MARK: - Layout (timeline ends → reflection begins)

    private var sectionDivider: some View {
        HStack(spacing: DesignSystem.spacingSM) {
            Rectangle()
                .fill(DesignSystem.divider.opacity(0.6))
                .frame(height: 1)
            Text("END OF DAY")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(DesignSystem.textMuted)
                .tracking(0.8)
            Rectangle()
                .fill(DesignSystem.divider.opacity(0.6))
                .frame(height: 1)
        }
        .padding(.top, DesignSystem.spacingLG)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("End of day reflection")
    }

    private var cardBody: some View {
        ElevatedSurface(padding: DesignSystem.spacingMD, emphasis: .subtle) {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                header
                learnedStrip
                inputSection
                if let calibrationBadge {
                    calibrationBanner(calibrationBadge)
                }
                saveButton
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("How did today go?", systemImage: "moon.stars.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(DesignSystem.textPrimary)
                .labelStyle(.titleAndIcon)

            Text("Not a task — this teaches your brain. What worked, what drained you, how long things really took.")
                .font(.system(size: 12))
                .foregroundColor(DesignSystem.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var learnedStrip: some View {
        if !recentCalibrations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR BRAIN REMEMBERS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(DesignSystem.textMuted)
                    .tracking(0.6)

                ForEach(recentCalibrations) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.accentPrimary)
                            .padding(.top, 2)
                        Text(entry.summary)
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                    .fill(DesignSystem.backgroundSecondary.opacity(0.5))
            )
        }
    }

    /// Text field + compact mic — never overlay the full VoiceCapture stack on the field.
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
                TextField(
                    "Speak or type — e.g. \"Report took 2 hours, gym felt easy\"…",
                    text: $entryText,
                    axis: .vertical
                )
                .lineLimit(3...5)
                .font(.system(size: 14))
                .foregroundColor(DesignSystem.textPrimary)
                .focused($isFieldFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                        .fill(DesignSystem.backgroundSecondary.opacity(0.65))
                )

                journalMicButton
            }

            if speechManager.isListening {
                AudioWaveformView(levels: speechManager.audioLevels)
                    .padding(.horizontal, 4)

                if !speechManager.transcript.isEmpty {
                    Text(speechManager.transcript)
                        .font(.system(size: 13))
                        .foregroundColor(DesignSystem.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                }
            }

            if let error = speechManager.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(DesignSystem.error)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.error)
                }
            }
        }
    }

    private var journalMicButton: some View {
        Button(action: toggleVoiceCapture) {
            Image(systemName: speechManager.isListening ? "stop.circle.fill" : "mic.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(speechManager.isListening ? DesignSystem.error : DesignSystem.accentPrimary)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(DesignSystem.backgroundSecondary.opacity(0.85))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speechManager.isListening ? "Stop recording" : "Voice capture")
    }

    private func calibrationBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundColor(DesignSystem.accentPrimary)
            Text("Learned: \(text)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignSystem.accentPrimary.opacity(0.12))
        )
    }

    private var saveButton: some View {
        Button(action: submitReflection) {
            HStack {
                if isProcessingAI {
                    ProgressView()
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "brain.head.profile")
                }
                Text(isProcessingAI ? "Teaching your brain…" : "Save & teach my brain")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PremiumPrimaryButtonStyle())
        .disabled(entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessingAI)
    }

    private func toggleVoiceCapture() {
        HapticManager.impact(.medium)
        Task {
            if speechManager.isListening {
                speechManager.stopListening()
                if !speechManager.transcript.isEmpty {
                    let prefix = entryText.isEmpty ? "" : " "
                    entryText += prefix + speechManager.transcript
                }
            } else {
                isFieldFocused = false
                await speechManager.startListening()
            }
        }
    }

    private func submitReflection() {
        let text = entryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        entryText = ""
        KeyboardDismiss.dismiss()
        isProcessingAI = true

        Task {
            await modulesVM.addJournalEntry(content: text, mood: "Reflective", gratitudes: [])

            let taskSummaryContext = """
            TODAY'S TASKS CONTEXT:
            Completed: \(completedToday.map(\.title).joined(separator: ", "))
            In-Progress: \(inProgressToday.map(\.title).joined(separator: ", "))
            Pending: \(pendingToday.map(\.title).joined(separator: ", "))

            USER REFLECTION:
            \(text)
            """

            let prompt = LifeOSPrompts.journalFeedbackAnalysisPrompt(journalText: taskSummaryContext)

            if let calibration = try? await GLMService.shared.complete(
                prompt: prompt,
                systemPrompt: LifeOSPrompts.structuredOutputSystem
            ) {
                let trimmed = calibration.trimmingCharacters(in: .whitespacesAndNewlines)
                UserCalibrationStore.append(summary: trimmed, source: .journal, rawInput: text)
                calibrationBadge = trimmed
                HapticManager.notification(.success)
            }

            isProcessingAI = false
        }
    }
}

// MARK: - Layout preview (structure reference)

#if DEBUG
#Preview("Journal below timeline") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            // Timeline stub
            VStack(alignment: .leading, spacing: 14) {
                Text("Your Day")
                    .font(.headline)
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(Color.green).frame(width: 10, height: 10).padding(.top, 6)
                    VStack(alignment: .leading) {
                        Text("Gym").font(.body.bold())
                        Text("6:30 PM · Fixed").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    Circle().stroke(Color.gray).frame(width: 10, height: 10).padding(.top, 6)
                    VStack(alignment: .leading) {
                        Text("Music production").font(.body.bold())
                        Text("9:00 PM · Creative").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            TodayEndOfDayJournalCard(
                modulesVM: LifeModulesViewModel(),
                tasksVM: TasksViewModel(decomposer: TaskDecomposer()),
                speechManager: SpeechRecognitionManager()
            )
        }
        .padding()
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
#endif
