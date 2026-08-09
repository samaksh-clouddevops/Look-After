import Foundation
import LookAfterCore
import LookAfterAI

/// LLM engine for Executive Planning conversations — returns structured plan mutations.
public final class LLMPlanningEngine {
    private let glm: GLMService

    public init(glmService: GLMService = .shared) {
        self.glm = glmService
    }

    public func processTurn(
        message: String,
        context: PlanningConversationContext,
        history: [PlanningConversationTurn],
        preAnalysis: PlanningReasoningResult? = nil,
        forceAI: Bool = false,
        voiceOptimized: Bool = false
    ) async throws -> PlanningTurnResponse {
        let analysis = preAnalysis ?? PlanningReasoningPipeline.analyze(message: message, context: context)

        do {
            let system = Self.planningSystemPrompt(context: context, voiceOptimized: voiceOptimized)
            let prompt = Self.planningUserPrompt(
                context: context,
                userMessage: message,
                analysis: analysis,
                voiceOptimized: voiceOptimized
            )
            let chatHistory = history.map { turn in
                ChatMessage(
                    role: turn.role == .user ? .user : .assistant,
                    content: turn.text
                )
            }

            let tier = Self.modelTier(for: analysis, voiceOptimized: voiceOptimized)
            let raw = try await glm.sendMessage(
                prompt,
                systemPrompt: system,
                history: chatHistory,
                tier: tier,
                maxTokens: voiceOptimized ? 1024 : 4096
            )

            var response = try decodeResponse(from: raw, fallbackMessage: message, context: context, analysis: analysis)
            response.planningSource = .ai
            return response
        } catch {
            if forceAI { throw error }
            print("[ExecutivePlanning] AI unavailable: \(error.localizedDescription)")
            return Self.offlineFallback(for: message, context: context, analysis: analysis, error: error)
        }
    }

    // MARK: - Prompts

    private static func planningSystemPrompt(context: PlanningConversationContext, voiceOptimized: Bool = false) -> String {
        let profile = context.lifeProfile
        let workHours = PlanningSchedulePolicy.WorkHours.from(profile: profile)
        return """
        You are the Executive Brain — a Chief of Staff for \(context.userName). This is NOT a chatbot.
        Users describe their life in natural language. You translate intent into an executable day plan.

        CORE RULES:
        1. Never ask users to create tasks, pick priorities, schedule blocks, or estimate duration.
        2. Inspect existing timeline, tasks, medications, meetings, and energy before changing anything.
        3. Reuse existing tasks ONLY when the user clearly refers to the same item — use kind "reuseTask", never duplicate on partial word overlap.
        4. Negotiate when the day is overloaded — use negotiation with clear options, do not silently add work.
        5. Explain only meaningful decisions in reply (1-3 sentences, warm, non-judgmental).
        6. Medication times come ONLY from the medication schedule provided — NEVER invent timing.
        7. For markMedicationTaken, use medicationID from the schedule list.
        8. Prefer deferTask/removeFromToday over deleting when user declines work.
        9. thinkingSteps: short labels shown while reasoning (e.g. "Checking timeline", "Finding free time").
        10. timelineDeltas: visual changes for the live timeline (added/moved/reused/removed/conflict).
        11. SCHEDULING: Never schedule before CURRENT TIME. Respect OFFICE HOURS, CREATIVE WINDOWS, and PROTECTED blocks from LIFE MODEL.
           Never schedule over gym or other never_schedule blocks. Schedule music/creative work inside CREATIVE WINDOWS.
           Work hours are \(Self.formatHour(workHours.startHour))–\(Self.formatHour(workHours.endHour)). Respect fixed commitments in LIFE MODEL.
        12. DURATION: If the user states a duration (e.g. "1 min"), use that exact estimatedMinutes. Do not inflate short tasks.
        13. MULTI-DAY: When user wants work spread across multiple days, use multiDayDraft + multiDayPlanning — NEVER createMultiDayTask until they confirm "Schedule it". See multi-day rules below.

        \(LookAfterPrompts.multiDayPlanningSystemBlock())

        Return ONLY valid JSON — no markdown fences, no prose outside JSON.
        The app executes your mutations automatically (creates tasks, updates timeline, shopping, medications).
        The "reply" field is the ONLY text the user sees — write warm plain English, never JSON or code.
        \(voiceOptimized ? "Keep reply to 1-2 short spoken sentences for voice." : "")
        \(SpeechVoiceSettings.preferSpokenStyle || voiceOptimized ? "\n        \(SpeechVoiceSettings.spokenDeliveryInstruction)\n        Apply SPOKEN DELIVERY rules to the \"reply\" field only." : "")
        """
    }

    private static func modelTier(for analysis: PlanningReasoningResult, voiceOptimized: Bool) -> AIModelTier {
        guard voiceOptimized else { return .premium }
        if analysis.multiDayDetection != nil { return .premium }
        switch analysis.intent {
        case .replan, .negotiate, .project, .postWake, .goingOut, .travel:
            return .premium
        default:
            return .standard
        }
    }

    private static func planningUserPrompt(
        context: PlanningConversationContext,
        userMessage: String,
        analysis: PlanningReasoningResult,
        voiceOptimized: Bool = false
    ) -> String {
        let profile = context.lifeProfile
        let now = Date()

        let matchLines = analysis.existingTaskMatches.prefix(5).map { "- REUSE id:\($0.id) | \($0.title)" }.joined(separator: "\n")
        let deferLines = analysis.deferCandidates.map { "- \($0.title)" }.joined(separator: "\n")

        let supplemental = voiceOptimized
            ? ""
            : PlanningPromptContextBuilder.supplementalContextBlock(
                analytics: context.analyticsContext,
                includeCalibration: true
            )
        let taskLimit = voiceOptimized ? 10 : 25
        let timelineLimit = voiceOptimized ? 8 : 20
        let cycleBlock = voiceOptimized
            ? ""
            : PlanningPromptContextBuilder.cycleBlock(
                snapshot: CycleEngine.snapshot(CycleEngine.Input()),
                logs: CycleLogStore.load()
            )

        return """
        \(PlanningPromptContextBuilder.temporalBlock(now: now, profile: profile))
        \(PlanningPromptContextBuilder.schedulingRulesBlock())
        \(voiceOptimized ? "" : "\(PlanningPromptContextBuilder.dailyRoutineBlock())\n")
        \(PlanningPromptContextBuilder.sleepBoundaryBlock(now: now, profile: profile))
        \(PlanningPromptContextBuilder.duplicateReuseRulesBlock())

        PRE-ANALYSIS (deterministic — follow this):
        - Classified intent: \(analysis.intent.label)
        \(analysis.intent == .reschedule ? "- User wants to RESCHEDULE an existing task — use rescheduleTask with taskID + startHour/startMinute, never createTask.\n" : "")
        - Capacity needed: ~\(analysis.capacityMinutesNeeded)m
        - Day overloaded: \(analysis.isOverloaded ? "YES — negotiate, do not silently add work" : "no")
        \(analysis.multiDayDetection.map { "- Multi-day planning: YES — suggested \($0.suggestedDayCount ?? 3) days" } ?? "- Multi-day planning: no")
        \(analysis.existingTaskMatches.isEmpty ? "" : "EXISTING MATCHES (reuse ONLY if user means the same task):\n\(matchLines)\n")
        \(analysis.deferCandidates.isEmpty ? "" : "DEFER OPTIONS if negotiating:\n\(deferLines)\n")
        \(PlanningPromptContextBuilder.proactiveSuggestionsBlock(analysis.proactiveSuggestions))

        \(PlanningPromptContextBuilder.combinedLifeContextBlock(profile: profile))
        \(supplemental.isEmpty ? "" : "\(supplemental)\n")
        \(PlanningPromptContextBuilder.healthBlock(context.healthSummary))
        \(cycleBlock.isEmpty ? "" : "\(cycleBlock)\n")
        \(PlanningPromptContextBuilder.executiveCapacityBlock(
            label: context.executiveCapacityLabel,
            reasons: context.executiveCapacityReasons,
            availableMinutes: context.availableMinutes,
            completedTodayCount: context.completedTodayCount,
            nextMeetingTitle: context.nextMeetingTitle,
            nextMeetingMinutes: context.nextMeetingMinutes,
            planSummary: context.planSummary
        ))

        \(PlanningPromptContextBuilder.tasksBlock(context.tasks, style: .planning, limit: taskLimit))
        \(PlanningPromptContextBuilder.timelineBlock(context.timelineItems, limit: timelineLimit))
        \(PlanningPromptContextBuilder.medicationsBlock(context.medications))

        USER MESSAGE:
        \(userMessage)

        Return JSON matching this schema (use actual ids/titles from data above — never copy placeholders literally):
        \(PlanningPromptContextBuilder.executivePlanningResponseSchema)
        Omit negotiation when not needed. mutations may be empty when only negotiating or advising.
        For multi-day planning, populate multiDayDraft + multiDayPlanning and keep mutations empty until user confirms.
        """
    }

    private static func formatHour(_ hour: Int) -> String {
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: min(max(hour, 0), 23), minute: 0, second: 0, of: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    // MARK: - Decode

    private func decodeResponse(
        from raw: String,
        fallbackMessage: String,
        context: PlanningConversationContext,
        analysis: PlanningReasoningResult
    ) throws -> PlanningTurnResponse {
        PlanningResponseParser.parse(raw, fallbackMessage: fallbackMessage, context: context, analysis: analysis)
    }

    static func offlineFallback(
        for message: String,
        context: PlanningConversationContext,
        analysis: PlanningReasoningResult,
        error: Error
    ) -> PlanningTurnResponse {
        var response = offlineFallback(for: message, context: context, rawReply: "", analysis: analysis)
        let prefix = aiUnavailablePrefix(for: error)
        if !prefix.isEmpty {
            response.reply = prefix + response.reply
        }
        response.planningSource = .offline
        return response
    }

    private static func aiUnavailablePrefix(for error: Error) -> String {
        if case GLMServiceError.licenseRequired = error {
            return "I couldn't reach the AI planner — activate your product key in Settings → License. Meanwhile, "
        }
        if case GLMServiceError.proxyNotConfigured = error {
            return "AI proxy is not configured — using offline planning. "
        }
        if case GLMServiceError.noKeysConfigured = error {
            return "I couldn't reach the AI planner — activate your product key in Settings → License. Meanwhile, "
        }
        if case GLMServiceError.allKeysExhausted = error {
            return "AI is temporarily unavailable — using offline planning. "
        }
        if GLMService.isQuotaOrRateLimitError(error) {
            return "AI quota is limited right now — using offline planning. "
        }
        if case GLMServiceError.invalidAPIKey = error {
            return "AI is unavailable — check Settings → License. Meanwhile, "
        }
        return "AI planner unavailable — using offline planning. "
    }

    static func offlineFallback(
        for message: String,
        context: PlanningConversationContext,
        rawReply: String,
        analysis: PlanningReasoningResult
    ) -> PlanningTurnResponse {
        let safeReply = PlanningResponseParser.looksLikeJSON(rawReply) ? "" : rawReply
        let lower = message.lowercased()

        if analysis.isOverloaded && !analysis.deferCandidates.isEmpty {
            let variants = PlanVariantBuilder.buildOfflinePlanningVariants(
                context: context,
                deferCandidates: analysis.deferCandidates
            )
            let negotiation = PlanVariantBuilder.negotiation(
                from: variants,
                question: "I don't think everything fits today. Pick a plan:"
            )
            return PlanningTurnResponse(
                reply: safeReply.isEmpty ? "I don't think everything fits today. Here are a few ways we could handle it." : safeReply,
                thinkingSteps: analysis.thinkingSteps,
                mutations: [],
                negotiation: negotiation,
                planVariants: variants
            )
        }

        switch analysis.intent {
        case .medication:
            if lower.contains("taken") || lower.contains("already") {
                return PlanningTurnResponse(
                    reply: safeReply.isEmpty ? "Got it — I'll mark that medication as taken and remove the reminder." : safeReply,
                    thinkingSteps: analysis.thinkingSteps,
                    mutations: [PlanMutation(kind: .markMedicationTaken, title: "medication")],
                    timelineDeltas: []
                )
            }
        case .negotiate:
            return PlanningTurnResponse(
                reply: safeReply.isEmpty ? "No problem. When would you like to move it — tomorrow, or combine it with another trip?" : safeReply,
                thinkingSteps: analysis.thinkingSteps,
                mutations: [],
                negotiation: PlanningNegotiation(
                    question: "When would you like to reschedule this?",
                    options: ["Tomorrow", "This weekend", "Next week"]
                )
            )
        case .reschedule:
            if let task = analysis.existingTaskMatches.first,
               let time = PlanningTimeParser.parseHourMinute(from: message) {
                return PlanningTurnResponse(
                    reply: safeReply.isEmpty ? "Got it — I'll move \"\(task.title)\" to the new time." : safeReply,
                    thinkingSteps: analysis.thinkingSteps,
                    mutations: [
                        PlanMutation(
                            kind: .rescheduleTask,
                            taskID: task.id,
                            title: task.title,
                            startHour: time.hour,
                            startMinute: time.minute
                        )
                    ],
                    timelineDeltas: [
                        PlanningTimelineDelta(timeLabel: "\(time.hour):\(String(format: "%02d", time.minute))", title: task.title, change: .moved)
                    ]
                )
            }
        case .energyAdapt:
            return PlanningTurnResponse(
                reply: safeReply.isEmpty ? "That makes sense. Based on your energy today, I'd avoid deep work. Would you rather review something lighter, answer emails, or take a short recovery walk?" : safeReply,
                thinkingSteps: analysis.thinkingSteps,
                mutations: [],
                negotiation: PlanningNegotiation(
                    question: "What feels doable right now?",
                    options: ["Review pull requests", "Answer emails", "Light creative work", "20-min recovery walk"]
                )
            )
        case .replan:
            if lower.contains("only have") {
                return PlanningTurnResponse(
                    reply: safeReply.isEmpty ? "I'll replan for a short window — focusing on the highest-value task you can finish without restart tax." : safeReply,
                    thinkingSteps: analysis.thinkingSteps,
                    mutations: [],
                    timelineDeltas: []
                )
            }
        case .shopping:
            if lower.contains("buy") || lower.contains("batteries") || lower.contains("remember") {
                return PlanningTurnResponse(
                    reply: safeReply.isEmpty ? "Added to your shopping list — no task needed." : safeReply,
                    thinkingSteps: analysis.thinkingSteps,
                    mutations: [PlanMutation(kind: .addShoppingItem, shoppingItemName: extractShoppingItem(from: message))],
                    timelineDeltas: []
                )
            }
        default:
            break
        }

        if let detection = analysis.multiDayDetection, detection.isMultiDay {
            return offlineMultiDayResponse(
                message: message,
                detection: detection,
                analysis: analysis,
                safeReply: safeReply,
                context: context
            )
        }

        if !analysis.existingTaskMatches.isEmpty,
           analysis.intent == .reschedule,
           let task = analysis.existingTaskMatches.first,
           let time = PlanningTimeParser.parseHourMinute(from: message) {
            return PlanningTurnResponse(
                reply: safeReply.isEmpty ? "Got it — I'll move \"\(task.title)\" to the new time." : safeReply,
                thinkingSteps: analysis.thinkingSteps,
                mutations: [
                    PlanMutation(
                        kind: .rescheduleTask,
                        taskID: task.id,
                        title: task.title,
                        startHour: time.hour,
                        startMinute: time.minute
                    )
                ],
                timelineDeltas: [
                    PlanningTimelineDelta(timeLabel: "\(time.hour):\(String(format: "%02d", time.minute))", title: task.title, change: .moved)
                ]
            )
        }

        if !analysis.existingTaskMatches.isEmpty, !createsTasksFromIntent(analysis.intent), analysis.intent != .reschedule {
            let reuse = analysis.existingTaskMatches.map {
                PlanMutation(kind: .reuseTask, taskID: $0.id, title: $0.title, reason: "Already on your plan")
            }
            return PlanningTurnResponse(
                reply: safeReply.isEmpty ? "I found existing items on your plan and reused them instead of creating duplicates." : safeReply,
                thinkingSteps: analysis.thinkingSteps,
                mutations: reuse,
                timelineDeltas: analysis.existingTaskMatches.map {
                    PlanningTimelineDelta(timeLabel: "—", title: $0.title, change: .reused)
                }
            )
        }

        let extracted = extractTaskPhrases(from: message)
        if !extracted.isEmpty, createsTasksFromIntent(analysis.intent) {
            return buildTaskCreationResponse(
                phrases: extracted,
                message: message,
                analysis: analysis,
                preamble: safeReply,
                lifeProfile: context.lifeProfile
            )
        }

        return PlanningTurnResponse(
            reply: safeReply.isEmpty ? "I'm looking at your day and will adjust the plan based on what you shared." : safeReply,
            thinkingSteps: analysis.thinkingSteps,
            mutations: [],
            timelineDeltas: []
        )
    }

    private static func extractShoppingItem(from message: String) -> String {
        let lower = message.lowercased()
        if let range = lower.range(of: "buy ") {
            let tail = message[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return tail.isEmpty ? "Item" : String(tail.prefix(80))
        }
        if lower.contains("batteries") { return "batteries" }
        return message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80).description
    }

    private static func createsTasksFromIntent(_ intent: PlanningIntent) -> Bool {
        switch intent {
        case .task, .project, .appointment, .goal, .outcome, .reminder, .habit, .idea:
            return true
        default:
            return false
        }
    }

    private static func extractTaskPhrases(from message: String) -> [String] {
        var text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 4 else { return [] }

        let stripPrefixes = [
            "today i need to ", "today i have to ", "today i want to ",
            "i need to ", "i have to ", "i want to ", "i also need to ",
            "i'm going to ", "im going to ", "i plan to ", "please ",
        ]
        var lowered = text.lowercased()
        for prefix in stripPrefixes where lowered.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            lowered = text.lowercased()
        }

        var parts = [text]
        for separator in [" and ", ", ", " also ", "; ", ". ", " then "] {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }

        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { phrase in
                let wordCount = phrase.split(separator: " ").count
                return phrase.count >= 4 && (wordCount >= 2 || (wordCount == 1 && phrase.count >= 4))
            }
            .prefix(5)
            .map { String($0.prefix(80)) }
    }

    private static func buildTaskCreationResponse(
        phrases: [String],
        message: String,
        analysis: PlanningReasoningResult,
        preamble: String,
        lifeProfile: UserLifeProfile
    ) -> PlanningTurnResponse {
        let workHours = PlanningSchedulePolicy.WorkHours.from(profile: lifeProfile)
        var slot = PlanningSchedulePolicy.nextAvailableSlot(workHours: workHours)
            ?? (workHours.startHour, 0)

        var mutations: [PlanMutation] = []
        var deltas: [PlanningTimelineDelta] = []

        for phrase in phrases {
            let minutes = TaskDurationPolicy.resolve(
                aiMinutes: nil,
                userMessage: message,
                phrase: phrase,
                defaultMinutes: TaskDurationPolicy.softDefaultMinutes
            )
            mutations.append(PlanMutation(
                kind: .createTask,
                title: phrase,
                estimatedMinutes: minutes,
                startHour: slot.hour,
                startMinute: slot.minute,
                reason: "From your update"
            ))
            deltas.append(PlanningTimelineDelta(
                timeLabel: timeLabel(hour: slot.hour, minute: slot.minute),
                title: phrase,
                change: .added
            ))
            slot = (
                min(slot.hour + max(1, minutes / 15), workHours.endHour),
                slot.minute
            )
        }

        let reply: String
        if preamble.isEmpty {
            reply = "Got it — I added \(phrases.count) item\(phrases.count == 1 ? "" : "s") to your plan and spaced them through the rest of today."
        } else {
            reply = preamble
        }

        return PlanningTurnResponse(
            reply: reply,
            thinkingSteps: analysis.thinkingSteps,
            mutations: mutations,
            negotiation: analysis.isOverloaded
                ? PlanningNegotiation(
                    question: "Your day looks tight — want to defer anything?",
                    options: analysis.deferCandidates.map(\.title) + ["Move new items to tomorrow"]
                )
                : nil,
            timelineDeltas: deltas
        )
    }

    private static func timeLabel(hour: Int, minute: Int = 0) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let calendar = Calendar.current
        let clampedHour = min(max(hour, 0), 23)
        let clampedMinute = min(max(minute, 0), 59)
        let date = calendar.date(bySettingHour: clampedHour, minute: clampedMinute, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }

    private static func offlineMultiDayResponse(
        message: String,
        detection: MultiDayDetectionResult,
        analysis: PlanningReasoningResult,
        safeReply: String,
        context: PlanningConversationContext
    ) -> PlanningTurnResponse {
        let lower = message.lowercased()
        let confirmPhrases = ["schedule it", "looks good", "let's do it", "lets do it", "go ahead"]
        if confirmPhrases.contains(where: { lower.contains($0) }) {
            let title = detection.titleHint ?? "Multi-day goal"
            let dayCount = detection.suggestedDayCount ?? 3
            let lifeArea = detection.inferredLifeArea ?? .work
            let slices = MultiDayTaskPlanner.offlineSlices(title: title, dayCount: dayCount, lifeArea: lifeArea, profile: context.lifeProfile)
            return PlanningTurnResponse(
                reply: safeReply.isEmpty ? "Done — your plan is spread across \(dayCount) days. Today: \(slices.first?.title ?? title)." : safeReply,
                thinkingSteps: analysis.thinkingSteps,
                mutations: [
                    PlanMutation(
                        kind: .createMultiDayTask,
                        title: title,
                        dayCount: dayCount,
                        sliceDrafts: slices
                    )
                ],
                timelineDeltas: slices.prefix(1).map {
                    PlanningTimelineDelta(timeLabel: "—", title: $0.title, change: .added)
                }
            )
        }

        if lower.contains("cancel") {
            return PlanningTurnResponse(
                reply: safeReply.isEmpty ? "No problem — multi-day planning cancelled." : safeReply,
                thinkingSteps: analysis.thinkingSteps,
                mutations: []
            )
        }

        let title = detection.titleHint ?? "your goal"
        let dayCount = detection.suggestedDayCount ?? 3
        let lifeArea = detection.inferredLifeArea ?? .work
        let slices = MultiDayTaskPlanner.offlineSlices(title: title, dayCount: dayCount, lifeArea: lifeArea, profile: context.lifeProfile)
        let draft = MultiDayPlanDraft(
            title: title,
            dayCount: dayCount,
            lifeArea: lifeArea,
            slices: slices,
            reasoning: "Spread across \(dayCount) days in your \(SchedulingWindowSelector.windowLabel(for: SchedulingWindowSelector.windowKind(for: lifeArea), profile: context.lifeProfile)) window."
        )

        if detection.suggestedDayCount != nil {
            return PlanningTurnResponse(
                reply: safeReply.isEmpty ? "Here's a \(dayCount)-day plan for \(title). Does this work?" : safeReply,
                thinkingSteps: analysis.thinkingSteps,
                mutations: [],
                multiDayDraft: draft,
                multiDayPlanning: PlanningNegotiation(
                    question: "Does this plan work for you?",
                    options: ["Schedule it", "Use fewer days", "Use more days", "Change the slices", "Cancel"]
                )
            )
        }

        return PlanningTurnResponse(
            reply: safeReply.isEmpty ? "How many days would you like to spread this over, and is it mostly office work or evening creative time?" : safeReply,
            thinkingSteps: analysis.thinkingSteps,
            mutations: [],
            multiDayPlanning: PlanningNegotiation(
                question: "Quick question before I draft a plan:",
                options: ["About 3 days", "About 5 days (a week)", "About 10 days", "Cancel"]
            )
        )
    }
}
