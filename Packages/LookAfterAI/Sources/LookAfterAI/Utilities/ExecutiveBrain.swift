import Foundation
import LookAfterCore

/// The Executive Brain — the heart of LifeOS.
/// Analyzes all available data and recommends the single best action for the user right now.
@MainActor
public final class ExecutiveBrain: ObservableObject {
    
    @Published public var currentRecommendation: String = ""
    @Published public var isThinking: Bool = false
    @Published public var lastSnapshot: CognitiveSnapshot?
    @Published public var chatHistory: [ChatMessage] = []
    @Published public var error: String?
    
    private let glm: GLMService

    public init(glmService: GLMService = .shared) {
        self.glm = glmService
    }
    
    // MARK: - Core Functions
    
    /// Deterministic next-step summary — **no LLM**. Use `chat(message:)` for open-ended coaching.
    public func getNextAction(
        snapshot: CognitiveSnapshot,
        healthSummary: HealthSummary?,
        pendingTasks: [LifeTask],
        recentProductivity: [ProductivitySession]
    ) async {
        lastSnapshot = snapshot

        if let task = pendingTasks.first {
            let semantics = SemanticDecisionBuilder.from(
                task: task,
                healthSummary: healthSummary
            )
            currentRecommendation = HumanLanguage.recommendationSummary(from: semantics)
        } else {
            currentRecommendation = HumanLanguage.defaultWhyNow()
        }

        isThinking = false
    }
    
    @Published public var personalizationContext: String? = nil
    @Published public var liveProgressContext: String? = nil
    @Published public var userName: String = UserDefaults.standard.string(forKey: "userName") ?? ""
    
    public func updateLiveProgress(
        completedTasks: [LifeTask],
        pendingTasks: [LifeTask],
        focusMinutes: Int,
        health: HealthSummary?,
        medications: [Medication] = MedicationStore.load(),
        executiveCapacityLabel: String? = nil,
        actualFocusMinutes: Int? = nil
    ) {
        let completedTitles = completedTasks.prefix(8).map { "✓ \($0.title)" }.joined(separator: "\n")
        let pendingTitles = pendingTasks.prefix(8).map { "• \($0.title)" }.joined(separator: "\n")

        let focusChallenge = ADHDFocusChallenge.load().label
        let aiTone = UserDefaults.standard.string(forKey: "aiCoachTone") ?? "Encouraging & Gentle"
        let keyGoals = UserDefaults.standard.string(forKey: "userKeyGoals") ?? "Focus & Consistent Flow"
        let profile = UserLifeProfileStore.load()
        let now = Date()

        let reportedFocus = actualFocusMinutes ?? focusMinutes
        var summary = """
        - Current Time: \(now.formatted(date: .omitted, time: .shortened))
        - User Name: \(userName)
        - ADHD Focus Profile Challenge: \(focusChallenge)
        - Preferred AI Coaching Tone: \(aiTone)
        - Primary Life Goals: \(keyGoals)
        """

        if let capacity = executiveCapacityLabel, !capacity.isEmpty {
            summary += "\n- Executive Capacity: \(capacity)"
        }

        if !profile.promptBlock.isEmpty {
            summary += "\n\n- Life Profile Summary:\n\(profile.promptBlock.prefix(600))"
        }

        summary += """

        - Completed Tasks Today (\(completedTasks.count)):
        \(completedTitles.isEmpty ? "None yet" : completedTitles)

        - Pending Tasks Remaining (\(pendingTasks.count)):
        \(pendingTitles.isEmpty ? "None" : pendingTitles)

        - Deep Focus Time Today: \(reportedFocus) minutes (tracked)
        """

        if !medications.isEmpty {
            summary += "\n- Medications configured: \(medications.count)"
        }

        if let h = health {
            if let sleep = h.totalSleepMinutes {
                summary += "\n- Sleep: \(String(format: "%.1f", sleep / 60.0)) hours"
            }
            if let hrv = h.hrvAverage {
                summary += "\n- HRV Recovery: \(Int(hrv))ms"
            }
        }

        self.liveProgressContext = summary
    }
    
    /// Chat with the AI Coach.
    public func chat(message: String) async -> String {
        let userMessage = ChatMessage(role: .user, content: message)
        chatHistory.append(userMessage)
        saveChatHistory()
        isThinking = true
        error = nil
        
        do {
            let previousHistory = Array(chatHistory.dropLast())
            let profile = UserLifeProfileStore.load()
            var systemPrompt = LookAfterPrompts.coachSystemPrompt(
                userName: userName,
                liveProgress: liveProgressContext,
                lifeProfile: profile
            )
            if let pContext = personalizationContext, !pContext.isEmpty {
                systemPrompt += "\n\nLONG-TERM HISTORICAL USER INSIGHTS (Use for deep personalization):\n\(pContext)"
            }
            let calibration = UserCalibrationStore.promptBlock(maxEntries: 6)
            if !calibration.isEmpty {
                systemPrompt += "\n\n\(calibration)"
            }
            
            let response = try await glm.sendMessage(
                message,
                systemPrompt: systemPrompt,
                history: previousHistory,
                tier: .premium
            )

            let assistantMessage = ChatMessage(role: .assistant, content: response)
            chatHistory.append(assistantMessage)
            saveChatHistory()
            isThinking = false
            return response
        } catch {
            self.error = error.localizedDescription
            isThinking = false
            let fallback = "Error: \(error.localizedDescription)"
            chatHistory.append(ChatMessage(role: .assistant, content: fallback))
            saveChatHistory()
            return fallback
        }
    }
    
    /// Clear chat history.
    public func clearChat() {
        chatHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: "saved_coach_chat_history")
    }

    /// Full factory reset — wipe all in-memory brain state.
    public func resetForFactoryReset() {
        clearChat()
        currentRecommendation = ""
        lastSnapshot = nil
        personalizationContext = nil
        liveProgressContext = nil
        error = nil
        isThinking = false
    }
    
    // MARK: - Session History Persistence
    
    private func saveChatHistory() {
        if let data = try? SharedFormatters.jsonEncoderSeconds.encode(chatHistory) {
            UserDefaults.standard.set(data, forKey: "saved_coach_chat_history")
        }
    }
    
    public func loadChatHistory() {
        if let data = UserDefaults.standard.data(forKey: "saved_coach_chat_history"),
           let history = try? SharedFormatters.jsonDecoderSeconds.decode([ChatMessage].self, from: data) {
            self.chatHistory = history
        }
    }
}
