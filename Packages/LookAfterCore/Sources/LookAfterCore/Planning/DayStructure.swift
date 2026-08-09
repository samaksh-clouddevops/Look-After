import Foundation

/// Compiled day anchors from profile sources — single contract for when routines should occur.
public struct DayStructure: Sendable, Equatable {
    public struct Anchor: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let startHour: Int
        public let startMinute: Int
        public let durationMinutes: Int
        public let treatAsFixed: Bool

        public init(
            id: String,
            title: String,
            startHour: Int,
            startMinute: Int,
            durationMinutes: Int,
            treatAsFixed: Bool = true
        ) {
            self.id = id
            self.title = title
            self.startHour = min(max(startHour, 0), 23)
            self.startMinute = min(max(startMinute, 0), 59)
            self.durationMinutes = max(durationMinutes, TaskDurationPolicy.minimumMinutes)
            self.treatAsFixed = treatAsFixed
        }

        public func start(on day: Date, calendar: Calendar = .current) -> Date? {
            calendar.date(
                bySettingHour: startHour,
                minute: startMinute,
                second: 0,
                of: calendar.startOfDay(for: day)
            )
        }
    }

    public var anchors: [Anchor]
    public var officeHours: PlanningSchedulePolicy.WorkHours

    public init(
        anchors: [Anchor] = [],
        officeHours: PlanningSchedulePolicy.WorkHours = PlanningSchedulePolicy.WorkHours(startHour: 9, endHour: 18)
    ) {
        self.anchors = anchors
        self.officeHours = officeHours
    }

    public func anchor(matching task: LifeTask) -> Anchor? {
        if let id = task.scheduleAnchorID,
           let match = anchors.first(where: { $0.id == id }) {
            return match
        }
        let normalized = normalize(task.title)
        return anchors.first { anchor in
            let key = normalize(anchor.title)
            return key == normalized || normalized.contains(key) || key.contains(normalized)
        }
    }

    private func normalize(_ title: String) -> String {
        title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Compiles `DayStructure` from LifeModel, UserLifeProfile, and onboarding defaults.
public enum DayStructureCompiler {

    public static func compile(
        profile: UserLifeProfile = UserLifeProfileStore.load(),
        model: LifeModel? = LifeModelStore.load(),
        calendar: Calendar = .current
    ) -> DayStructure {
        let day = calendar.startOfDay(for: Date())
        var anchors: [DayStructure.Anchor] = []
        var seenIDs = Set<String>()

        func append(_ anchor: DayStructure.Anchor) {
            guard seenIDs.insert(anchor.id).inserted else { return }
            anchors.append(anchor)
        }

        for slot in ["Breakfast", "Lunch", "Dinner", "Brush teeth — morning", "Brush teeth — evening", "Snacks"] {
            if let time = OnboardingTaskSeeder.routineAnchorTime(forTitle: slot, on: day, calendar: calendar) {
                append(DayStructure.Anchor(
                    id: "routine.\(slot.lowercased().replacingOccurrences(of: " ", with: "-"))",
                    title: slot,
                    startHour: calendar.component(.hour, from: time.start),
                    startMinute: calendar.component(.minute, from: time.start),
                    durationMinutes: time.durationMinutes,
                    treatAsFixed: true
                ))
            }
        }

        if !profile.fixedScheduleNotes.isEmpty {
            for note in profile.fixedScheduleNotes
                .replacingOccurrences(of: "\n", with: ",")
                .split(whereSeparator: { $0 == "," || $0 == ";" })
                .map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
                .filter({ !$0.isEmpty }) {
                if let parsed = parseFixedNote(note, on: day, calendar: calendar) {
                    append(parsed)
                }
            }
        }

        if let model, model.hasContent {
            for block in model.timeBlocks {
                append(DayStructure.Anchor(
                    id: "block.\(block.id)",
                    title: block.label,
                    startHour: block.startHour,
                    startMinute: block.startMinute,
                    durationMinutes: max(block.endMinutesFromMidnight - block.startMinutesFromMidnight, 30),
                    treatAsFixed: block.protection == .neverSchedule || block.protection == .priorityOnly
                ))
            }
            for commitment in model.commitments {
                guard let blockLabel = commitment.preferredBlockLabel,
                      let block = model.block(matching: blockLabel) else { continue }
                append(DayStructure.Anchor(
                    id: "commitment.\(model.commitmentID(for: commitment.title))",
                    title: commitment.title,
                    startHour: block.startHour,
                    startMinute: block.startMinute,
                    durationMinutes: commitment.defaultMinutes,
                    treatAsFixed: commitment.isNonNegotiable
                ))
            }
        }

        let windows = SchedulingWindows.from(profile: profile, lifeModel: model)
        return DayStructure(anchors: anchors.sorted { $0.startHour * 60 + $0.startMinute < $1.startHour * 60 + $1.startMinute },
                            officeHours: windows.officeHours)
    }

    /// Backfills `scheduleAnchorID` on tasks missing it.
    public static func backfillAnchorIDs(
        tasks: [LifeTask],
        structure: DayStructure,
        calendar: Calendar = .current
    ) -> [LifeTask] {
        let day = calendar.startOfDay(for: Date())
        return tasks.map { task in
            guard task.scheduleAnchorID == nil else { return task }
            guard let anchor = structure.anchor(matching: task) else { return task }
            var updated = task
            updated.scheduleAnchorID = anchor.id
            if anchor.treatAsFixed, task.scheduledTime == nil,
               let start = anchor.start(on: day, calendar: calendar) {
                updated.scheduledDate = day
                updated.scheduledTime = start
                updated.scheduledEndTime = start.addingTimeInterval(TimeInterval(anchor.durationMinutes * 60))
                updated.applyTimeConstraint(.anchored)
            }
            return updated
        }
    }

    private static func parseFixedNote(_ note: String, on day: Date, calendar: Calendar) -> DayStructure.Anchor? {
        guard let parsed = OnboardingTaskSeeder.fixedTimeAnchor(
            matchingTitle: note,
            fixedNotes: note,
            on: day,
            calendar: calendar
        ) else { return nil }
        let title = note.components(separatedBy: CharacterSet.decimalDigits).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.isEmpty ? note : title
        return DayStructure.Anchor(
            id: "fixed.\(cleanTitle.lowercased().prefix(40))",
            title: String(cleanTitle.prefix(60)),
            startHour: calendar.component(.hour, from: parsed.start),
            startMinute: calendar.component(.minute, from: parsed.start),
            durationMinutes: parsed.durationMinutes,
            treatAsFixed: true
        )
    }
}
