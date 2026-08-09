import Foundation
import LookAfterCore

/// Lenient parser for Executive Planning LLM JSON — never surfaces raw JSON to the user.
enum PlanningResponseParser {

    static func parse(
        _ raw: String,
        fallbackMessage: String,
        context: PlanningConversationContext,
        analysis: PlanningReasoningResult
    ) -> PlanningTurnResponse {
        let clean = sanitizeRawJSON(raw)

        if let decoded = decodeStrict(clean) {
            return finalize(decoded, analysis: analysis)
        }

        if let jsonObject = extractJSONObject(from: clean),
           let lenient = decodeLenient(jsonObject) {
            return finalize(lenient, analysis: analysis)
        }

        var offline = LLMPlanningEngine.offlineFallback(
            for: fallbackMessage,
            context: context,
            rawReply: looksLikeJSON(clean) ? "" : clean,
            analysis: analysis
        )
        offline.planningSource = .offline
        return offline
    }

    /// Ensures the user never sees raw JSON in the chat bubble.
    static func userFacingReply(_ response: PlanningTurnResponse) -> String {
        let reply = response.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reply.isEmpty, !looksLikeJSON(reply) {
            return reply
        }
        if let extracted = extractReplyField(from: reply), !extracted.isEmpty {
            return extracted
        }
        return summaryReply(for: response)
    }

    // MARK: - Strict decode

    private static func decodeStrict(_ clean: String) -> PlanningTurnResponse? {
        guard let data = clean.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PlanningTurnResponse.self, from: data)
    }

    // MARK: - Lenient dictionary decode

    private static func decodeLenient(_ json: [String: Any]) -> PlanningTurnResponse? {
        guard let reply = json["reply"] as? String, !reply.isEmpty else { return nil }

        let thinking = json["thinkingSteps"] as? [String] ?? []
        let mutationDicts = json["mutations"] as? [[String: Any]] ?? []
        let mutations = mutationDicts.compactMap { parseMutation($0) }

        var negotiation: PlanningNegotiation?
        if let neg = json["negotiation"] as? [String: Any],
           let question = neg["question"] as? String,
           let options = neg["options"] as? [String], !options.isEmpty {
            negotiation = PlanningNegotiation(
                question: question,
                options: options,
                optionVariantIDs: neg["optionVariantIDs"] as? [String]
            )
        }

        let deltaDicts = json["timelineDeltas"] as? [[String: Any]] ?? []
        let timelineDeltas = deltaDicts.compactMap { parseTimelineDelta($0) }

        var multiDayDraft: MultiDayPlanDraft?
        if let draftDict = json["multiDayDraft"] as? [String: Any] {
            multiDayDraft = parseMultiDayDraft(draftDict)
        }

        var multiDayPlanning: PlanningNegotiation?
        if let neg = json["multiDayPlanning"] as? [String: Any],
           let question = neg["question"] as? String,
           let options = neg["options"] as? [String], !options.isEmpty {
            multiDayPlanning = PlanningNegotiation(
                question: question,
                options: options,
                optionVariantIDs: neg["optionVariantIDs"] as? [String]
            )
        }

        var planVariants: [PlanVariant]?
        if let variantDicts = json["planVariants"] as? [[String: Any]], !variantDicts.isEmpty {
            planVariants = variantDicts.compactMap { parsePlanVariant($0) }
        }

        return PlanningTurnResponse(
            reply: reply,
            thinkingSteps: thinking,
            mutations: mutations,
            negotiation: negotiation,
            planVariants: planVariants,
            multiDayDraft: multiDayDraft,
            multiDayPlanning: multiDayPlanning,
            timelineDeltas: timelineDeltas,
            planningSource: .ai
        )
    }

    private static func parseMutation(_ dict: [String: Any]) -> PlanMutation? {
        let kindRaw = (dict["kind"] as? String) ?? (dict["type"] as? String) ?? (dict["action"] as? String)
        guard let kindRaw, let kind = PlanMutationKind.fromLLM(kindRaw) else { return nil }

        return PlanMutation(
            id: dict["id"] as? String ?? UUID().uuidString,
            kind: kind,
            taskID: (dict["taskID"] as? String) ?? (dict["taskId"] as? String) ?? (dict["task_id"] as? String),
            title: dict["title"] as? String,
            estimatedMinutes: dict["estimatedMinutes"] as? Int ?? dict["estimated_minutes"] as? Int,
            startHour: dict["startHour"] as? Int ?? dict["start_hour"] as? Int,
            startMinute: dict["startMinute"] as? Int ?? dict["start_minute"] as? Int,
            deferToTomorrow: dict["deferToTomorrow"] as? Bool ?? false,
            medicationID: (dict["medicationID"] as? String) ?? (dict["medicationId"] as? String),
            shoppingItemName: (dict["shoppingItemName"] as? String) ?? (dict["shopping_item_name"] as? String),
            captureNote: dict["captureNote"] as? String,
            reason: dict["reason"] as? String,
            dayCount: dict["dayCount"] as? Int ?? dict["day_count"] as? Int,
            deadlineISO: (dict["deadlineISO"] as? String) ?? (dict["deadline_iso"] as? String),
            sliceDrafts: parseSliceDrafts(from: dict)
        )
    }

    private static func parseSliceDrafts(from dict: [String: Any]) -> [MultiDaySliceDraft]? {
        let raw = (dict["slices"] as? [[String: Any]]) ?? (dict["sliceDrafts"] as? [[String: Any]])
        guard let raw else { return nil }
        return raw.compactMap { slice in
            guard let title = slice["title"] as? String else { return nil }
            let dayIndex = slice["dayIndex"] as? Int ?? slice["day_index"] as? Int ?? 0
            let minutes = slice["estimatedMinutes"] as? Int ?? slice["estimated_minutes"] as? Int ?? 45
            return MultiDaySliceDraft(
                dayIndex: dayIndex,
                title: title,
                estimatedMinutes: minutes,
                windowLabel: slice["windowLabel"] as? String ?? slice["window_label"] as? String
            )
        }
    }

    private static func parseMultiDayDraft(_ dict: [String: Any]) -> MultiDayPlanDraft? {
        guard let title = dict["title"] as? String else { return nil }
        let dayCount = dict["dayCount"] as? Int ?? dict["day_count"] as? Int ?? 3
        let lifeAreaRaw = dict["lifeArea"] as? String ?? dict["life_area"] as? String ?? LifeArea.work.rawValue
        let lifeArea = LifeArea(rawValue: lifeAreaRaw) ?? .work
        let reasoning = dict["reasoning"] as? String ?? ""
        var deadline: Date?
        if let iso = dict["deadlineISO"] as? String ?? dict["deadline_iso"] as? String {
            deadline = parseFlexibleISODate(iso)
        }
        let slices = parseSliceDrafts(from: dict) ?? []
        return MultiDayPlanDraft(
            id: dict["id"] as? String ?? UUID().uuidString,
            title: title,
            dayCount: dayCount,
            lifeArea: lifeArea,
            deadline: deadline,
            slices: slices,
            reasoning: reasoning
        )
    }

    private static func parsePlanVariant(_ dict: [String: Any]) -> PlanVariant? {
        guard let label = dict["label"] as? String else { return nil }
        let changesRaw = dict["scheduleChanges"] as? [[String: Any]] ?? []
        let changes = changesRaw.compactMap { change -> DayReplanScheduleChange? in
            guard let taskID = (change["taskID"] as? String) ?? (change["taskId"] as? String) else { return nil }
            return DayReplanScheduleChange(
                taskID: taskID,
                startHour: change["startHour"] as? Int ?? change["start_hour"] as? Int,
                startMinute: change["startMinute"] as? Int ?? change["start_minute"] as? Int,
                deferToTomorrow: change["deferToTomorrow"] as? Bool ?? false,
                reason: change["reason"] as? String ?? ""
            )
        }
        let deltaDicts = dict["timelineDeltas"] as? [[String: Any]] ?? []
        let deltas = deltaDicts.compactMap { parseTimelineDelta($0) }
        return PlanVariant(
            id: dict["id"] as? String ?? UUID().uuidString,
            label: label,
            summary: dict["summary"] as? String ?? label,
            tradeoffs: dict["tradeoffs"] as? [String] ?? [],
            scheduleChanges: changes,
            timelineDeltas: deltas,
            recommended: dict["recommended"] as? Bool ?? false
        )
    }

    private static func parseTimelineDelta(_ dict: [String: Any]) -> PlanningTimelineDelta? {
        guard let title = dict["title"] as? String else { return nil }
        let changeRaw = (dict["change"] as? String) ?? "added"
        let change = PlanningTimelineChange.fromLLM(changeRaw) ?? .added
        return PlanningTimelineDelta(
            id: dict["id"] as? String ?? UUID().uuidString,
            timeLabel: dict["timeLabel"] as? String ?? dict["time_label"] as? String ?? "—",
            title: title,
            subtitle: dict["subtitle"] as? String,
            change: change,
            isConflict: dict["isConflict"] as? Bool ?? dict["is_conflict"] as? Bool ?? false
        )
    }

    // MARK: - Helpers

    private static func sanitizeRawJSON(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractJSONObject(from text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        let slice = String(text[start...end])
        guard let data = slice.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func extractReplyField(from text: String) -> String? {
        guard let object = extractJSONObject(from: text) else { return nil }
        return object["reply"] as? String
    }

    static func looksLikeJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") && trimmed.hasSuffix("}")
    }

    private static func finalize(_ response: PlanningTurnResponse, analysis: PlanningReasoningResult) -> PlanningTurnResponse {
        var merged = response
        merged.reply = userFacingReply(response)
        merged.planningSource = .ai
        if merged.thinkingSteps.isEmpty {
            merged.thinkingSteps = analysis.thinkingSteps
        } else {
            let prefix = analysis.thinkingSteps.filter { !merged.thinkingSteps.contains($0) }
            merged.thinkingSteps = prefix + merged.thinkingSteps
        }
        return merged
    }

    private static func summaryReply(for response: PlanningTurnResponse) -> String {
        let created = response.mutations.filter { $0.kind == .createTask }.compactMap(\.title)
        if !created.isEmpty {
            let list = created.prefix(3).joined(separator: ", ")
            let suffix = created.count > 3 ? " and \(created.count - 3) more" : ""
            return "Done — I added \(list)\(suffix) to your plan and updated your timeline."
        }
        if !response.mutations.isEmpty {
            return "Got it — I updated your plan based on what you shared."
        }
        if let negotiation = response.negotiation, negotiation.isActive {
            return negotiation.question
        }
        if let multiDay = response.multiDayPlanning, multiDay.isActive {
            return multiDay.question
        }
        if response.multiDayDraft != nil {
            return "Here's a preview of your multi-day plan — let me know if it works."
        }
        return "I'm looking at your day and will adjust the plan based on what you shared."
    }

    private static func parseFlexibleISODate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }
        let dayOnly = DateFormatter()
        dayOnly.calendar = Calendar(identifier: .gregorian)
        dayOnly.locale = Locale(identifier: "en_US_POSIX")
        dayOnly.timeZone = TimeZone.current
        dayOnly.dateFormat = "yyyy-MM-dd"
        return dayOnly.date(from: String(trimmed.prefix(10)))
    }
}

// MARK: - LLM enum normalization

extension PlanMutationKind {
    static func fromLLM(_ raw: String) -> PlanMutationKind? {
        if let exact = PlanMutationKind(rawValue: raw) { return exact }

        let compact = raw
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")

        switch compact {
        case "reusetask": return .reuseTask
        case "createtask", "addtask", "newtask": return .createTask
        case "rescheduletask", "movetask", "scheduletask": return .rescheduleTask
        case "defertask", "postponetask", "snoozetask": return .deferTask
        case "completetask", "finishtask", "donetask": return .completeTask
        case "markmedicationtaken", "medicationtaken", "tookmedication": return .markMedicationTaken
        case "addshoppingitem", "shoppingitem", "addshopping": return .addShoppingItem
        case "capturenote", "addnote": return .captureNote
        case "removefromtoday", "removetask": return .removeFromToday
        case "createmultidaytask", "multidaytask", "multidayplan": return .createMultiDayTask
        default: return nil
        }
    }
}

extension PlanningTimelineChange {
    static func fromLLM(_ raw: String) -> PlanningTimelineChange? {
        if let exact = PlanningTimelineChange(rawValue: raw) { return exact }
        let compact = raw.lowercased().replacingOccurrences(of: "_", with: "")
        switch compact {
        case "add", "create", "new": return .added
        case "move", "reschedule", "shift": return .moved
        case "remove", "delete": return .removed
        case "reuse", "existing": return .reused
        case "conflict", "clash": return .conflict
        default: return PlanningTimelineChange(rawValue: raw)
        }
    }
}
