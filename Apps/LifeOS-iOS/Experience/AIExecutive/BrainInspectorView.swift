import SwiftUI
import LifeOSCore
import LifeOSFeatures
import ExecutiveBrain

/// Chrome DevTools for the Executive Brain — inspect every recommendation.
struct BrainInspectorView: View {
    @EnvironmentObject private var shell: AppShellState
    @State private var selectedSection: InspectorSection = .lifeState

    enum InspectorSection: String, CaseIterable, Identifiable {
        case lifeState = "Life State"
        case intent = "Intent"
        case cost = "Executive Cost"
        case simulations = "Simulations"
        case plan = "Chosen Plan"
        case reasoning = "Why"
        case history = "Decision History"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0D1117").ignoresSafeArea()

                VStack(spacing: 0) {
                    sectionPicker

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            headerMeta
                            sectionContent
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Brain Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        Task { await shell.refreshContextFromInspector() }
                    }
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
            }
        }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(InspectorSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Text(section.rawValue)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(
                                    selectedSection == section
                                        ? Color(hex: "3FB950").opacity(0.25)
                                        : Color.white.opacity(0.06)
                                )
                            )
                            .foregroundColor(
                                selectedSection == section ? Color(hex: "3FB950") : Color.white.opacity(0.6)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var headerMeta: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tick")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "8B949E"))
                if let at = shell.contextOrchestrator.brainState?.generatedAt {
                    Text(at.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white)
                } else {
                    Text("—")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            Spacer()
            if let confidence = shell.contextOrchestrator.brainState?.decision.confidence {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Confidence")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "8B949E"))
                    Text(String(format: "%.0f%%", confidence * 100))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "58A6FF"))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .lifeState:
            lifeStateSection
        case .intent:
            intentSection
        case .cost:
            costSection
        case .simulations:
            simulationsSection
        case .plan:
            planSection
        case .reasoning:
            reasoningSection
        case .history:
            historySection
        }
    }

    private var lifeStateSection: some View {
        inspectorBlock("WorldState") {
            if let world = shell.contextOrchestrator.brainState?.world {
                kv("Energy", String(format: "%.0f%%", world.currentEnergy * 100))
                kv("Cognitive load", world.cognitiveLoad.rawValue)
                kv("Available min", "\(world.availableMinutes)")
                if let sleep = world.sleepHoursLastNight {
                    kv("Sleep", String(format: "%.1fh", sleep))
                }
                kv("In flow", world.isInFlowSession ? "yes" : "no")
                if let event = world.nextEventTitle, let mins = world.minutesUntilNextEvent {
                    kv("Next event", "\(event) in \(mins)m")
                }
                if let mission = world.currentMission {
                    kv("Current task", mission.title)
                }
                kv("Top tasks", "\(world.topTasks.count)")
            } else {
                emptyHint("Run a context refresh to populate Life State.")
            }

            if let snapshot = shell.contextOrchestrator.snapshot {
                divider
                kv("Health readiness", String(format: "%.0f%%", snapshot.healthReadiness * 100))
                kv("Completion prob.", String(format: "%.0f%%", snapshot.completionProbability * 100))
                kv("Free minutes", "\(snapshot.availableTimeMinutes)")
            }
        }
    }

    private var intentSection: some View {
        inspectorBlock("ExecutiveIntent") {
            if let intent = shell.contextOrchestrator.brainState?.decision.intent {
                kv("Future state", intent.futureState)
                kv("Intention", intent.intention)
                kv("Intervention", intent.intervention)
                kv("Expected outcome", intent.expectedOutcome)
                kv("Autonomy", intent.autonomyLevel.rawValue)
                kv("Reversibility", String(format: "%.0f%%", intent.reversibility * 100))

                divider
                Text("Hero render preview")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "8B949E"))
                let hero = IntentRenderer.hero(from: intent, snapshot: shell.contextOrchestrator.snapshot)
                kv("Title", hero.title)
                kv("Subtitle", hero.subtitle)
                kv("Duration", hero.durationLabel)
                kv("Button", hero.primaryButton)
            } else {
                emptyHint("No intent yet.")
            }
        }
    }

    private var costSection: some View {
        inspectorBlock("Executive Cost") {
            if let intent = shell.contextOrchestrator.brainState?.decision.intent {
                Text("Expected reduction if intent succeeds")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "8B949E"))
                ForEach(intent.expectedCostReduction.summaryLines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color(hex: "3FB950"))
                }
                if intent.expectedCostReduction.summaryLines.isEmpty {
                    Text("No cost delta modeled yet")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
    }

    private var simulationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sims = shell.contextOrchestrator.brainState?.decision.simulations, !sims.isEmpty {
                ForEach(sims) { sim in
                    inspectorBlock(sim.label) {
                        if sim.wasChosen {
                            Text("✓ CHOSEN")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "3FB950"))
                        }
                        kv("Score", String(format: "%.2f", sim.score))
                        kv("Future", sim.intent.futureState)
                        kv("Intervention", sim.intent.intervention)
                        kv("Total burden", String(format: "%.0f", sim.projectedCost.totalBurden))
                    }
                }
            } else {
                emptyHint("No simulations recorded.")
            }
        }
    }

    private var planSection: some View {
        inspectorBlock("DayPlan") {
            if let plan = shell.contextOrchestrator.brainState?.plan {
                if !plan.narrativeSummary.isEmpty {
                    kv("Summary", plan.narrativeSummary)
                }
                ForEach(plan.blocks) { block in
                    divider
                    kv(block.startLabel, block.title)
                    if let r = block.reasoning {
                        Text(r)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(hex: "8B949E"))
                    }
                }
            } else {
                emptyHint("No plan generated.")
            }
        }
    }

    private var reasoningSection: some View {
        inspectorBlock("ReasoningTrace") {
            if let trace = shell.contextOrchestrator.brainState?.decision.reasoning {
                Text("Factors (\(trace.factors.count))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "8B949E"))
                ForEach(trace.factors) { factor in
                    HStack(alignment: .top, spacing: 8) {
                        Text(factor.impact.rawValue)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(impactColor(factor.impact))
                            .frame(width: 72, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("[\(factor.domain.rawValue)]")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Color(hex: "8B949E"))
                            Text(factor.observation)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    .padding(.vertical, 4)
                }
                if !trace.conclusions.isEmpty {
                    divider
                    Text("Conclusions")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "8B949E"))
                    ForEach(trace.conclusions, id: \.self) { c in
                        Text("→ \(c)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(hex: "58A6FF"))
                    }
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if shell.contextOrchestrator.decisionHistory.isEmpty {
                emptyHint("Decision history fills as the Brain ticks.")
            } else {
                ForEach(shell.contextOrchestrator.decisionHistory) { record in
                    inspectorBlock(record.issuedAt.formatted(date: .omitted, time: .shortened)) {
                        kv("Intervention", record.intent.intervention)
                        kv("Disposition", record.disposition.rawValue)
                        kv("Factors", "\(record.factorCount)")
                        if let result = record.result {
                            if result.completed, let mins = result.actualMinutes {
                                kv("Result", "Finished in \(mins) min")
                            } else if let reason = result.ignoreReason {
                                kv("Ignored", reason)
                            }
                        }
                        if let lesson = record.lesson {
                            divider
                            Text(lesson.policy)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(hex: "D29922"))
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Mark accepted") { shell.contextOrchestrator.recordDecisionAccepted() }
                Button("Mark ignored") { shell.contextOrchestrator.recordDecisionIgnored(reason: "Meeting overran") }
                Button("Mark done (16m)") { shell.contextOrchestrator.recordDecisionCompleted(actualMinutes: 16) }
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(Color(hex: "58A6FF"))
            .padding(.top, 8)
        }
    }

    // MARK: - Components

    private func inspectorBlock(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "3FB950"))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: "30363D"), lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "161B22")))
        )
    }

    private func kv(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(hex: "8B949E"))
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var divider: some View {
        Rectangle().fill(Color(hex: "30363D")).frame(height: 1).padding(.vertical, 4)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.white.opacity(0.45))
    }

    private func impactColor(_ impact: ReasoningImpact) -> Color {
        switch impact {
        case .supports: return Color(hex: "3FB950")
        case .opposes: return Color(hex: "F85149")
        case .constrains: return Color(hex: "D29922")
        case .neutral: return Color(hex: "8B949E")
        }
    }
}

// MARK: - AppShell helper

extension AppShellState {
    @MainActor
    func refreshContextFromInspector() async {
        let userId = UserDefaults.standard.string(forKey: "userId") ?? ""
        let userName = UserDefaults.standard.string(forKey: "userName") ?? ""
        let peakStart = UserDefaults.standard.integer(forKey: "peakStartHour")
        await refreshContext(
            userId: userId,
            userName: userName,
            peakStartHour: peakStart > 0 ? peakStart : 9
        )
    }
}
