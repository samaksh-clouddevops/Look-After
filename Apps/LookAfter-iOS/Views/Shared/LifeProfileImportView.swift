import SwiftUI
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterFeatures

/// Import and compile persistent life profile markdown into a LifeModel.
struct LifeProfileImportView: View {
    @EnvironmentObject private var shell: AppShellState

    @Binding var markdown: String
    @State private var compiledModel: LifeModel?
    @State private var isCompiling = false
    @State private var compileMessage: String?
    @State private var showAdvancedEditor = false
    @State private var structuredProfileSections = StructuredLifeProfileSections()
    @State private var organizeError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Paste your full life profile — identity, mission, schedule, and commitments. The brain compiles this into time blocks and auto-schedules your day.")
                .font(.system(size: 13))
                .foregroundColor(DesignSystem.textSecondary)

            if let model = compiledModel ?? LifeModelStore.load() {
                LifeModelSummaryView(model: model)
            }

            TextEditor(text: $markdown)
                .frame(minHeight: 160)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                .foregroundColor(DesignSystem.textPrimary)

            HStack(spacing: 12) {
                Button("Load example") {
                    if let example = loadExampleProfile() {
                        markdown = example
                        compileMessage = "Example loaded — replace with your own details."
                    }
                }
                .font(.system(size: 13))

                Spacer()

                Button(action: {
                    Task { await recompile() }
                }, label: {
                    HStack {
                        if isCompiling {
                            ProgressView().scaleEffect(0.8)
                        }
                        Text(isCompiling ? "Teaching brain…" : "Recompile brain")
                    }
                })
                .buttonStyle(.borderedProminent)
                .disabled(markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCompiling)
            }

            if let compileMessage {
                Text(compileMessage)
                    .font(.system(size: 12))
                    .foregroundColor(DesignSystem.accentPrimary)
            }

            DisclosureGroup("Advanced: section editor", isExpanded: $showAdvancedEditor) {
                StructuredLifeProfileEditor(
                    sections: $structuredProfileSections,
                    minSectionHeight: 72,
                    showsOrganizeButton: true,
                    onOrganize: { await organizeWithAI() },
                    onOrganizeLocally: {
                        structuredProfileSections = LifeProfileComposer.organizeLocally(structuredProfileSections)
                        markdown = LifeProfileComposer.compile(structuredProfileSections)
                    }
                )

                if let organizeError {
                    Text(organizeError)
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.error)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(DesignSystem.textSecondary)
        }
        .onAppear {
            compiledModel = LifeModelStore.load()
            if markdown.isEmpty {
                markdown = UserLifeProfileStore.load().profileText
            }
            structuredProfileSections = LifeProfileComposer.parse(markdown.isEmpty ? UserLifeProfileStore.load().profileText : markdown)
        }
        .onChange(of: structuredProfileSections.personality) { _, _ in syncMarkdownFromSections() }
        .onChange(of: structuredProfileSections.adhdFocusPatterns) { _, _ in syncMarkdownFromSections() }
        .onChange(of: structuredProfileSections.dailySchedule) { _, _ in syncMarkdownFromSections() }
        .onChange(of: structuredProfileSections.planningPreferences) { _, _ in syncMarkdownFromSections() }
    }

    private func syncMarkdownFromSections() {
        markdown = LifeProfileComposer.compile(structuredProfileSections)
    }

    private func organizeWithAI() async {
        organizeError = nil
        let prompt = LifeProfileComposer.organizeStructuredPrompt(structuredProfileSections)
        do {
            let polished = try await GLMService.shared.complete(
                prompt: prompt,
                systemPrompt: LookAfterPrompts.profileOrganizeSystem,
                tier: .economy
            )
            let trimmed = polished.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                structuredProfileSections = LifeProfileComposer.organizeLocally(structuredProfileSections)
                organizeError = "AI returned empty — formatted locally."
                syncMarkdownFromSections()
                return
            }
            structuredProfileSections = LifeProfileComposer.parse(trimmed)
            syncMarkdownFromSections()
            HapticManager.notification(.success)
        } catch {
            structuredProfileSections = LifeProfileComposer.organizeLocally(structuredProfileSections)
            organizeError = "AI unavailable — formatted locally."
            syncMarkdownFromSections()
        }
    }

    private func recompile() async {
        isCompiling = true
        compileMessage = nil
        defer { isCompiling = false }

        let model = await shell.compileAndSaveLifeModel(markdown: markdown)
        compiledModel = model

        let userId = FirebaseManager.shared.resolvedUserId
        if !userId.isEmpty {
            await shell.assembleDayFromLifeModel(userId: userId)
        }

        compileMessage = "Brain updated — \(model.commitments.count) commitments, \(model.timeBlocks.count) time blocks."
        HapticManager.notification(.success)
    }

    private func loadExampleProfile() -> String? {
        guard let url = Bundle.main.url(forResource: "example-life-profile", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text
    }
}

struct LifeModelSummaryView: View {
    let model: LifeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("What my brain knows", systemImage: "brain.head.profile")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(DesignSystem.textPrimary)

            if !model.identity.mission.isEmpty {
                Text(model.identity.mission)
                    .font(.system(size: 12))
                    .foregroundColor(DesignSystem.textSecondary)
            }

            if !model.timeBlocks.isEmpty {
                Text("TIME BLOCKS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(DesignSystem.textMuted)
                ForEach(model.timeBlocks.prefix(6)) { block in
                    HStack {
                        Text(block.label)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(block.timeRangeLabel())
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
            }

            if !model.commitments.isEmpty {
                Text("COMMITMENTS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(DesignSystem.textMuted)
                    .padding(.top, 4)
                ForEach(model.commitments.sorted(by: { $0.priority < $1.priority }).prefix(8)) { commitment in
                    HStack(spacing: 6) {
                        Image(systemName: commitment.isNonNegotiable ? "lock.fill" : "sparkles")
                            .font(.system(size: 10))
                            .foregroundColor(DesignSystem.accentPrimary)
                        Text(commitment.title)
                            .font(.system(size: 12))
                        Spacer()
                        Text("\(commitment.defaultMinutes)m")
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
            }

            Text("Compiled \(model.compiledAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 10))
                .foregroundColor(DesignSystem.textMuted)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }
}
