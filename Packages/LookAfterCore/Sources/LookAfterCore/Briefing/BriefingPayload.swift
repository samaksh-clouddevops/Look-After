import Foundation

// MARK: - Router payload (strict AI surface)

/// Unified Encoded surface the AIRouter may send to an external LLM.
/// No raw task titles — counts, energy, distilled macros, ephemerality tallies.
public struct BriefingRouterPayload: Codable, Sendable, Equatable {
    public let energyState: String
    public let anchoredCommitmentsCount: Int
    public let fluidHoursAvailable: Double
    /// Pre-scrubbed overnight mutation summaries (never raw PII/titles).
    public let systemActions: [String]
    public let decayedTaskCount: Int
    /// Semantic collision drops (duplicate activity already on the day).
    public let supersededTaskCount: Int
    /// Ephemeral reaper kills (meals, strict windows, end-of-day).
    public let expiredTaskCount: Int

    public init(
        energyState: String,
        anchoredCommitmentsCount: Int,
        fluidHoursAvailable: Double,
        systemActions: [String],
        decayedTaskCount: Int,
        supersededTaskCount: Int = 0,
        expiredTaskCount: Int = 0
    ) {
        self.energyState = energyState
        self.anchoredCommitmentsCount = anchoredCommitmentsCount
        self.fluidHoursAvailable = fluidHoursAvailable
        self.systemActions = systemActions.map { BriefingPIISanitizer.scrub($0) }
        self.decayedTaskCount = decayedTaskCount
        self.supersededTaskCount = max(0, supersededTaskCount)
        self.expiredTaskCount = max(0, expiredTaskCount)
    }

    /// Map full compiler payload → strict router surface.
    public init(from full: BriefingPayload) {
        let approxFluidHours = max(
            Double(full.fluidCount) * 0.75,
            max(0, Double(full.focusMinutes) / 60.0 * 0.25)
        ).rounded(toPlaces: 1)
        self.init(
            energyState: full.energyState,
            anchoredCommitmentsCount: full.anchoredCount,
            fluidHoursAvailable: approxFluidHours,
            systemActions: full.mutations.map(\.routerSummary) + full.telemetryLearnings,
            decayedTaskCount: full.somedayDecayCount,
            supersededTaskCount: full.supersededTaskCount,
            expiredTaskCount: full.expiredTaskCount
        )
    }

    /// Convenience chips for deterministic UI (non-AI).
    public func snapshotChips() -> [BriefingSnapshotChip] {
        var chips: [BriefingSnapshotChip] = [
            .init(id: "energy", icon: "bolt.fill", label: "Energy", value: energyState),
            .init(id: "anchored", icon: "calendar", label: "Anchored", value: "\(anchoredCommitmentsCount)"),
            .init(
                id: "fluid",
                icon: "hourglass",
                label: "Fluid",
                value: String(format: "%.1fh", fluidHoursAvailable)
            ),
        ]
        if expiredTaskCount > 0 {
            chips.append(.init(id: "expired", icon: "xmark.circle", label: "Expired", value: "\(expiredTaskCount)"))
        }
        if supersededTaskCount > 0 {
            chips.append(.init(id: "superseded", icon: "arrow.triangle.merge", label: "Deduped", value: "\(supersededTaskCount)"))
        }
        return chips
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let p = pow(10.0, Double(places))
        return (self * p).rounded() / p
    }
}

private extension BriefingMutationFact {
    var routerSummary: String {
        // Prefer CascadeDistiller calm copy when present.
        if !reason.isEmpty {
            return BriefingPIISanitizer.scrub(reason)
        }
        switch code {
        case "sabotage_recovery":
            return count > 1
                ? "Triggered Sabotage Auction x\(count): cleared time for recovery."
                : "Triggered Sabotage Auction: cleared time for recovery."
        case "shift_later":
            return count > 1
                ? "Shifted \(count) flexible blocks later to clear conflicts."
                : "Shifted a flexible block later to clear a conflict."
        case "compress":
            return "Compressed a block to its viable duration floor."
        case "defer_gap":
            return "Deferred work into the next open gap (fluid)."
        case "park":
            return count > 1
                ? "Parked \(count) items into the waiting room."
                : "Parked one item into the waiting room."
        case "resurrect":
            return "Filled free time from the waiting room (queue bid)."
        case "expired":
            return count > 1
                ? "\(count) time-bound routines were skipped when the day became over-anchored."
                : "A time-bound routine was skipped when the day became over-anchored."
        case "superseded":
            return count > 1
                ? "\(count) missed instances were dropped to avoid duplicate sessions."
                : "A missed instance was dropped to avoid stacking the same activity twice."
        default:
            return "Schedule adjusted overnight (\(code))."
        }
    }
}

// MARK: - Sanitized facts for AI (no raw task titles / PII)

/// Rigid struct the Brain compiles. LLM receives only this — never raw LifeTask JSON.
public struct BriefingPayload: Codable, Sendable, Equatable {
    public var generatedAt: Date
    public var dayKey: String
    public var energyState: String
    public var energyPercent: Int?
    public var sleepHours: Double?
    public var capacityBand: String
    public var anchoredCount: Int
    public var flexibleCount: Int
    public var fluidCount: Int
    public var focusMinutes: Int
    public var remainingTaskCount: Int
    public var completedTaskCount: Int
    public var overdueCount: Int
    public var nextEventCategory: String?
    public var minutesUntilNextEvent: Int?
    /// Overnight / runtime mutations (sabotage, compress, defer, park, resurrect).
    public var mutations: [BriefingMutationFact]
    /// Vault / telemetry learnings (category-level, never titles).
    public var telemetryLearnings: [String]
    public var somedayDecayCount: Int
    public var parkedRecoverableCount: Int
    public var hasRecoveryBlockToday: Bool
    public var supersededTaskCount: Int
    public var expiredTaskCount: Int
    /// Fingerprint of structural facts — cache invalidation without timestamps.
    public var structureFingerprint: String

    public init(
        generatedAt: Date = Date(),
        dayKey: String,
        energyState: String,
        energyPercent: Int? = nil,
        sleepHours: Double? = nil,
        capacityBand: String,
        anchoredCount: Int = 0,
        flexibleCount: Int = 0,
        fluidCount: Int = 0,
        focusMinutes: Int = 0,
        remainingTaskCount: Int = 0,
        completedTaskCount: Int = 0,
        overdueCount: Int = 0,
        nextEventCategory: String? = nil,
        minutesUntilNextEvent: Int? = nil,
        mutations: [BriefingMutationFact] = [],
        telemetryLearnings: [String] = [],
        somedayDecayCount: Int = 0,
        parkedRecoverableCount: Int = 0,
        hasRecoveryBlockToday: Bool = false,
        supersededTaskCount: Int = 0,
        expiredTaskCount: Int = 0,
        structureFingerprint: String = ""
    ) {
        self.generatedAt = generatedAt
        self.dayKey = dayKey
        self.energyState = energyState
        self.energyPercent = energyPercent
        self.sleepHours = sleepHours
        self.capacityBand = capacityBand
        self.anchoredCount = anchoredCount
        self.flexibleCount = flexibleCount
        self.fluidCount = fluidCount
        self.focusMinutes = focusMinutes
        self.remainingTaskCount = remainingTaskCount
        self.completedTaskCount = completedTaskCount
        self.overdueCount = overdueCount
        self.nextEventCategory = nextEventCategory
        self.minutesUntilNextEvent = minutesUntilNextEvent
        self.mutations = mutations
        self.telemetryLearnings = telemetryLearnings
        self.somedayDecayCount = somedayDecayCount
        self.parkedRecoverableCount = parkedRecoverableCount
        self.hasRecoveryBlockToday = hasRecoveryBlockToday
        self.supersededTaskCount = supersededTaskCount
        self.expiredTaskCount = expiredTaskCount
        self.structureFingerprint = structureFingerprint.isEmpty
            ? Self.fingerprint(
                dayKey: dayKey,
                energyState: energyState,
                capacityBand: capacityBand,
                anchoredCount: anchoredCount,
                flexibleCount: flexibleCount,
                fluidCount: fluidCount,
                focusMinutes: focusMinutes,
                remainingTaskCount: remainingTaskCount,
                completedTaskCount: completedTaskCount,
                overdueCount: overdueCount,
                mutations: mutations,
                somedayDecayCount: somedayDecayCount,
                parkedRecoverableCount: parkedRecoverableCount,
                supersededTaskCount: supersededTaskCount,
                expiredTaskCount: expiredTaskCount,
                hasRecoveryBlockToday: hasRecoveryBlockToday
            )
            : structureFingerprint
    }

    public static func fingerprint(
        dayKey: String,
        energyState: String,
        capacityBand: String,
        anchoredCount: Int,
        flexibleCount: Int,
        fluidCount: Int,
        focusMinutes: Int,
        remainingTaskCount: Int,
        completedTaskCount: Int,
        overdueCount: Int,
        mutations: [BriefingMutationFact],
        somedayDecayCount: Int,
        parkedRecoverableCount: Int,
        supersededTaskCount: Int = 0,
        expiredTaskCount: Int = 0,
        hasRecoveryBlockToday: Bool
    ) -> String {
        let mut = mutations.map(\.code).sorted().joined(separator: ",")
        return [
            dayKey, energyState, capacityBand,
            "\(anchoredCount)", "\(flexibleCount)", "\(fluidCount)",
            "\(focusMinutes)", "\(remainingTaskCount)", "\(completedTaskCount)",
            "\(overdueCount)", mut, "\(somedayDecayCount)",
            "\(parkedRecoverableCount)", "\(supersededTaskCount)", "\(expiredTaskCount)",
            "\(hasRecoveryBlockToday)"
        ].joined(separator: "|")
    }
}

public struct BriefingMutationFact: Codable, Sendable, Equatable, Identifiable {
    public var id: String { code + reason }
    /// Stable machine code: sabotage_recovery, shift_later, compress, defer_gap, park, resurrect
    public var code: String
    public var count: Int
    public var reason: String

    public init(code: String, count: Int = 1, reason: String = "") {
        self.code = code
        self.count = count
        self.reason = reason
    }
}

// MARK: - Snapshot chips (deterministic UI)

public struct BriefingSnapshotChip: Identifiable, Sendable, Equatable {
    public var id: String
    public var icon: String
    public var label: String
    public var value: String

    public init(id: String, icon: String, label: String, value: String) {
        self.id = id
        self.icon = icon
        self.label = label
        self.value = value
    }
}

public extension BriefingPayload {
    /// Non-AI grounding chips for progressive disclosure.
    func snapshotChips() -> [BriefingSnapshotChip] {
        var chips: [BriefingSnapshotChip] = []
        if let energyPercent {
            chips.append(.init(id: "energy", icon: "bolt.fill", label: "Energy", value: "\(energyPercent)%"))
        } else {
            chips.append(.init(id: "energy", icon: "bolt.fill", label: "Energy", value: energyState))
        }
        chips.append(.init(id: "anchored", icon: "calendar", label: "Anchored", value: "\(anchoredCount)"))
        if focusMinutes > 0 {
            let hours = focusMinutes / 60
            let mins = focusMinutes % 60
            let value = hours > 0 ? "\(hours)h\(mins > 0 ? " \(mins)m" : "")" : "\(mins)m"
            chips.append(.init(id: "focus", icon: "target", label: "Focus", value: value))
        }
        chips.append(.init(id: "left", icon: "checklist", label: "Left", value: "\(remainingTaskCount)"))
        if overdueCount > 0 {
            chips.append(.init(id: "overdue", icon: "exclamationmark.circle", label: "Overdue", value: "\(overdueCount)"))
        }
        if hasRecoveryBlockToday {
            chips.append(.init(id: "recovery", icon: "bed.double.fill", label: "Recovery", value: "Locked"))
        }
        if expiredTaskCount > 0 {
            chips.append(.init(id: "expired", icon: "xmark.circle", label: "Expired", value: "\(expiredTaskCount)"))
        }
        if supersededTaskCount > 0 {
            chips.append(.init(id: "superseded", icon: "arrow.triangle.merge", label: "Deduped", value: "\(supersededTaskCount)"))
        }
        return chips
    }

    /// Fallback when network fails — never show a broken spinner.
    func deterministicNarrative(userName: String = "") -> String {
        var sentences: [String] = []
        let greet = userName.isEmpty ? "" : "\(userName), "
        sentences.append("\(greet)capacity is \(capacityBand.lowercased()) with \(energyState.lowercased()) energy.")

        if anchoredCount > 0 || flexibleCount > 0 {
            sentences.append(
                "You have \(anchoredCount) anchored and \(flexibleCount) flexible blocks\(focusMinutes > 0 ? ", about \(focusMinutes) minutes of focus" : "")."
            )
        } else if remainingTaskCount > 0 {
            sentences.append("\(remainingTaskCount) tasks remain on the list.")
        } else {
            sentences.append("The calendar is open if you want to add something.")
        }

        // Prefer a material mutation sentence (sabotage / supersede / expire / park).
        let priorityCodes = ["sabotage_recovery", "superseded", "expired", "park", "shift_later"]
        if let mutation = priorityCodes.compactMap({ code in mutations.first { $0.code == code } }).first
            ?? mutations.first {
            sentences.append(Self.mutationSentence(mutation))
        } else if supersededTaskCount > 0 {
            sentences.append(
                supersededTaskCount == 1
                    ? "A missed instance was dropped because the same activity is already on today."
                    : "\(supersededTaskCount) missed instances were dropped to avoid duplicate sessions."
            )
        } else if expiredTaskCount > 0 {
            sentences.append(
                expiredTaskCount == 1
                    ? "One time-bound routine was skipped when the day became over-anchored."
                    : "\(expiredTaskCount) time-bound routines were skipped when the day became over-anchored."
            )
        }

        if somedayDecayCount > 0 {
            sentences.append(
                somedayDecayCount == 1
                    ? "One parked item is past two weeks. Review or move it to someday."
                    : "\(somedayDecayCount) parked items are past two weeks. Review or bulk-discard when ready."
            )
        } else if let cat = nextEventCategory, let mins = minutesUntilNextEvent, mins <= 120 {
            sentences.append("Next up is a \(cat) in \(mins) minutes.")
        }

        return sentences.prefix(4).joined(separator: " ")
    }

    private static func mutationSentence(_ m: BriefingMutationFact) -> String {
        if !m.reason.isEmpty { return BriefingPIISanitizer.scrub(m.reason) }
        switch m.code {
        case "sabotage_recovery":
            return "A recovery block was locked after sustained high load."
        case "shift_later":
            return m.count > 1
                ? "\(m.count) flexible items shifted later to clear conflicts."
                : "A flexible item shifted later to clear a conflict."
        case "compress":
            return "A block was compressed to a viable duration."
        case "defer_gap":
            return "Something deferred into the next open gap."
        case "park":
            return m.count > 1
                ? "\(m.count) items moved to the waiting room."
                : "One item moved to the waiting room."
        case "resurrect":
            return "Free time was filled from the waiting room."
        case "expired":
            return "A time-bound routine was skipped when the day got too full."
        case "superseded":
            return "A missed instance was dropped to avoid stacking the same activity twice."
        default:
            return "The schedule adjusted overnight."
        }
    }
}
