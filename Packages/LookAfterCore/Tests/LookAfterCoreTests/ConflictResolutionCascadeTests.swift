import XCTest
@testable import LookAfterCore

final class ConflictResolutionCascadeTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    private let day = Date(timeIntervalSince1970: 1_720_000_000) // fixed

    func testAnchoredWinsFlexibleShiftsLater() {
        let anchored = task(
            id: "a", title: "Standup", hour: 10, minutes: 60,
            constraint: .anchored, priority: .high
        )
        let flexible = task(
            id: "b", title: "Deep work", hour: 10, minutes: 90,
            constraint: .flexible, priority: .medium
        )
        let result = ConflictResolutionCascade.resolve(
            tasks: [flexible, anchored], on: day, calendar: calendar
        )
        let byID = Dictionary(uniqueKeysWithValues: result.tasks.map { ($0.id, $0) })
        XCTAssertEqual(byID["a"]?.scheduledTime, anchored.scheduledTime)
        XCTAssertNotEqual(byID["b"]?.scheduledTime, flexible.scheduledTime)
        XCTAssertGreaterThan(byID["b"]!.scheduledTime!, anchored.scheduledEndTime!)
        XCTAssertEqual(decision(result, "a"), .keep)
        XCTAssertEqual(decision(result, "b"), .shiftLater)
        XCTAssertTrue(result.unresolvedTaskIDs.isEmpty)
        XCTAssertFalse(DayScheduleReconciler.hasOverlap(result.tasks, on: day, calendar: calendar))
    }

    func testFluidDefersToNextGapNotSameClock() {
        let blocks = (9..<18).map { h in
            task(id: "fix-\(h)", title: "Meeting \(h)", hour: h, minutes: 55, constraint: .anchored)
        }
        let fluid = task(id: "fluid", title: "Errand", hour: 10, minutes: 60, constraint: .fluid)
        let park = ParkedTaskQueueStore.inMemory()
        let result = ConflictResolutionCascade.resolve(
            tasks: blocks + [fluid],
            on: day,
            calendar: calendar,
            parkedQueue: park
        )
        let f = result.tasks.first { $0.id == "fluid" }!
        let action = decision(result, "fluid")
        XCTAssertTrue([ConflictCascadeAction.deferNextGap, .park, .shiftLater, .compress].contains(action))
        if action == .deferNextGap {
            XCTAssertFalse(calendar.isDate(f.scheduledDate!, inSameDayAs: day))
            XCTAssertEqual(f.timeConstraintValue, .fluid)
            // Must NOT be forced to the original 10:00 clock if that slot is occupied tomorrow.
        }
        if action == .park {
            XCTAssertTrue(result.parkedTaskIDs.contains("fluid"))
            XCTAssertEqual(park.snapshot().entries.count, 1)
        }
        XCTAssertTrue(result.unresolvedTaskIDs.isEmpty)
        let sameDay = result.tasks.filter {
            guard let d = $0.scheduledDate, $0.scheduledTime != nil else { return false }
            return calendar.isDate(d, inSameDayAs: day)
        }
        XCTAssertFalse(DayScheduleReconciler.hasOverlap(sameDay, on: day, calendar: calendar))
    }

    func testCompressRespectsMinimumViableDuration() {
        let anchored = task(id: "meet", title: "Sync", hour: 10, minutes: 90, constraint: .anchored)
        var therapy = task(id: "therapy", title: "Therapy", hour: 10, minutes: 50, constraint: .flexible)
        therapy.minimumViableDuration = 45 // cannot become a useless 15m stub
        let park = ParkedTaskQueueStore.inMemory()
        let result = ConflictResolutionCascade.resolve(
            tasks: [anchored, therapy], on: day, calendar: calendar, parkedQueue: park
        )
        let t = result.tasks.first { $0.id == "therapy" }!
        if decision(result, "therapy") == .compress {
            XCTAssertGreaterThanOrEqual(t.estimatedMinutes, 45)
        } else {
            // Shift / defer / park are all valid when no viable compress gap exists.
            XCTAssertNotEqual(decision(result, "therapy"), .keep)
        }
    }

    func testDominoDampenerSkipsExcessShifts() {
        // Many flexible blocks stacked; dampener should prevent endless shift chain.
        let anchored = task(id: "root", title: "Delayed flight", hour: 9, minutes: 120, constraint: .anchored)
        let flex = (0..<5).map { i in
            task(id: "f\(i)", title: "Flex \(i)", hour: 9 + i, minutes: 50, constraint: .flexible)
        }
        let park = ParkedTaskQueueStore.inMemory()
        let result = ConflictResolutionCascade.resolve(
            tasks: [anchored] + flex, on: day, calendar: calendar, parkedQueue: park
        )
        let shifts = result.decisions.filter { $0.action == .shiftLater }.count
        XCTAssertLessThanOrEqual(shifts, ConflictResolutionCascade.maxDominoShifts)
        XCTAssertTrue(result.unresolvedTaskIDs.isEmpty)
        XCTAssertFalse(DayScheduleReconciler.hasOverlap(
            result.tasks.filter {
                ($0.scheduledDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false)
                    && $0.scheduledTime != nil
            },
            on: day,
            calendar: calendar
        ))
    }

    func testParkedQueueEnqueuesOnPark() {
        let park = ParkedTaskQueueStore.inMemory()
        let a = task(id: "a", title: "A", hour: 10, minutes: 60, constraint: .anchored, priority: .critical)
        var b = task(id: "b", title: "B", hour: 10, minutes: 60, constraint: .flexible, priority: .low)
        b.tags = [LifeModel.commitmentTaskTag]
        let result = ConflictResolutionCascade.resolve(
            tasks: [a, b], on: day, calendar: calendar, parkedQueue: park
        )
        if result.parkedTaskIDs.contains("b") {
            XCTAssertEqual(park.snapshot().entries.first?.taskID, "b")
            XCTAssertEqual(park.candidatesForReintegration().count, 1)
        }
        XCTAssertTrue(result.unresolvedTaskIDs.isEmpty)
    }

    func testOverlappingAnchoredTasksPreserveClockTimes() {
        let park = ParkedTaskQueueStore.inMemory()
        let first = task(id: "t1", title: "Task 1", hour: 10, minutes: 120, constraint: .anchored, priority: .high)
        let second = task(id: "t2", title: "Task 2", hour: 11, minutes: 60, constraint: .anchored, priority: .medium)
        let third = task(id: "t3", title: "Task 3", hour: 13, minutes: 60, constraint: .anchored, priority: .medium)

        let result = ConflictResolutionCascade.resolve(
            tasks: [first, second, third],
            on: day,
            calendar: calendar,
            parkedQueue: park
        )

        let byID = Dictionary(uniqueKeysWithValues: result.tasks.map { ($0.id, $0) })
        XCTAssertNotNil(byID["t2"]?.scheduledTime)
        XCTAssertEqual(byID["t2"]?.timeConstraintValue, .anchored)
        XCTAssertFalse(result.parkedTaskIDs.contains("t2"))
        XCTAssertEqual(decision(result, "t2"), .keep)
        XCTAssertEqual(park.snapshot().entries.count, 0)
    }

    func testSequentialAnchoredTasksUnchangedAfterReconcile() {
        let first = task(id: "t1", title: "Task 1", hour: 10, minutes: 45, constraint: .anchored)
        let second = task(id: "t2", title: "Task 2", hour: 11, minutes: 45, constraint: .anchored)
        let third = task(id: "t3", title: "Task 3", hour: 13, minutes: 45, constraint: .anchored)

        let result = DayScheduleReconciler.reconcile(
            tasks: [first, second, third],
            on: day,
            calendar: calendar
        )

        XCTAssertTrue(result.changedTaskIDs.isEmpty)
        let byID = Dictionary(uniqueKeysWithValues: result.tasks.map { ($0.id, $0) })
        XCTAssertEqual(byID["t1"]?.scheduledTime, first.scheduledTime)
        XCTAssertEqual(byID["t2"]?.scheduledTime, second.scheduledTime)
        XCTAssertEqual(byID["t3"]?.scheduledTime, third.scheduledTime)
    }

    func testFluidDecayAfter14Days() {
        let park = ParkedTaskQueueStore.inMemory()
        park.enqueue(
            ParkedTaskEntry(
                taskID: "old",
                title: "Old reading",
                parkedAt: day.addingTimeInterval(-15 * 86_400),
                decayState: .recoverable
            )
        )
        park.enqueue(
            ParkedTaskEntry(
                taskID: "fresh",
                title: "Fresh",
                parkedAt: day.addingTimeInterval(-2 * 86_400),
                decayState: .recoverable
            )
        )
        let result = park.applyFluidDecay(now: day, decayAfterDays: 14)
        XCTAssertEqual(result.decayed.map(\.taskID), ["old"])
        XCTAssertEqual(park.snapshot().entries.first { $0.taskID == "old" }?.decayState, .decayed)
        XCTAssertEqual(park.candidatesForReintegration().map(\.taskID), ["fresh"])
    }

    func testQueueBiddingPrefersHighPriorityFit() {
        let park = ParkedTaskQueueStore.inMemory()
        park.enqueue(ParkedTaskEntry(
            taskID: "low", title: "Someday tidy", originalDurationMinutes: 20,
            parkedAt: day.addingTimeInterval(-1 * 86_400), priority: .low, lifeArea: .home
        ))
        park.enqueue(ParkedTaskEntry(
            taskID: "high", title: "Ship proposal", originalDurationMinutes: 45,
            parkedAt: day.addingTimeInterval(-3 * 86_400), priority: .critical, lifeArea: .work
        ))
        park.enqueue(ParkedTaskEntry(
            taskID: "toolong", title: "All day", originalDurationMinutes: 240,
            parkedAt: day.addingTimeInterval(-10 * 86_400), priority: .high, lifeArea: .work
        ))
        let winners = park.bidWinners(gapMinutes: 60, energy: .peak, now: day, limit: 2)
        XCTAssertEqual(winners.first?.taskID, "high")
        XCTAssertFalse(winners.contains { $0.taskID == "toolong" })
    }

    func testEnergyAwareBiddingPenalizesDeepWorkFridayAfternoon() {
        let deep = ParkedTaskEntry(
            taskID: "dw", title: "Deep work", originalDurationMinutes: 60,
            priority: .high, lifeArea: .work
        )
        let light = ParkedTaskEntry(
            taskID: "rd", title: "Light reading", originalDurationMinutes: 45,
            priority: .medium, lifeArea: .personal
        )
        // Friday = weekday 6 in Gregorian
        let ctx = GapAuctionContext(
            energy: .moderate,
            hour: 16,
            weekday: 6,
            gapMinutes: 90,
            now: day
        )
        let outcome = GapAuctionEngine.run(pool: [deep, light], context: ctx, limit: 1)
        if case .filled(let winners) = outcome {
            XCTAssertEqual(winners.first?.taskID, "rd")
        } else {
            XCTFail("Expected filled auction")
        }
    }

    func testSabotageAuctionLocksRecoveryAfterHighLoadStreak() {
        let parked = ParkedTaskEntry(
            taskID: "p", title: "Inbox zero", originalDurationMinutes: 60,
            priority: .high, lifeArea: .work
        )
        let ctx = GapAuctionContext(
            energy: .high,
            hour: 14,
            weekday: 3,
            consecutiveHighLoadDays: 5,
            gapMinutes: 90,
            now: day
        )
        let outcome = GapAuctionEngine.run(pool: [parked], context: ctx, limit: 3)
        if case .sabotageRecovery = outcome {
            // expected
        } else {
            XCTFail("Expected sabotage recovery lock")
        }
        let block = GapAuctionEngine.makeRecoveryBlock(
            gapStart: day, gapMinutes: 90, day: day, userId: "u", calendar: calendar
        )
        XCTAssertEqual(block.timeConstraintValue, .anchored)
        XCTAssertTrue(block.tags.contains("recovery-block"))
    }

    func testSomedayVaultReceivesDecayed() {
        let vault = SomedayVaultStore.inMemory()
        let parked = ParkedTaskEntry(taskID: "x", title: "Idea", lifeArea: .creativity)
        vault.add(from: parked, now: day)
        XCTAssertEqual(vault.count, 1)
        XCTAssertEqual(vault.snapshot().entries.first?.priority, .someday)
    }

    func testPoisonFilterDropsBirthdaysPTOSubscribed() {
        let keep = CalendarHistoryEvent(
            id: "1", start: day, end: day.addingTimeInterval(3600), title: "Design critique"
        )
        let bday = CalendarHistoryEvent(
            id: "2", start: day, end: day.addingTimeInterval(3600), title: "Mom Birthday"
        )
        let pto = CalendarHistoryEvent(
            id: "3", start: day, end: day.addingTimeInterval(3600), title: "PTO"
        )
        let allDay = CalendarHistoryEvent(
            id: "4", start: day, end: day.addingTimeInterval(86400), isAllDay: true, title: "Conference"
        )
        let meta: [String: CalendarEventSourceMeta] = [
            "1": .init(eventTitle: "Design critique"),
            "2": .init(eventTitle: "Mom Birthday"),
            "3": .init(eventTitle: "PTO"),
            "5": .init(isSubscribedCalendar: true, eventTitle: "Regional Holiday"),
        ]
        let subscribed = CalendarHistoryEvent(
            id: "5", start: day, end: day.addingTimeInterval(3600), title: "Regional Holiday"
        )
        let filtered = CalendarEventPoisonFilter.filter(
            [keep, bday, pto, allDay, subscribed],
            metaByID: meta
        )
        XCTAssertEqual(filtered.map(\.id), ["1"])
    }

    func testSabotageCooldownSuppressesRecovery() {
        let policy = SabotagePolicyStore.inMemory()
        policy.recordSabotageOverride(now: day, cooldownDays: 7)
        XCTAssertTrue(policy.isCoolingDown(now: day.addingTimeInterval(3600)))
        let parked = ParkedTaskEntry(
            taskID: "p", title: "Inbox", originalDurationMinutes: 60, priority: .high, lifeArea: .work
        )
        let ctx = GapAuctionContext(
            energy: .high,
            hour: 14,
            weekday: 3,
            consecutiveHighLoadDays: 5,
            gapMinutes: 90,
            now: day,
            sabotageCooldownActive: true
        )
        let outcome = GapAuctionEngine.run(pool: [parked], context: ctx, limit: 3)
        if case .sabotageRecovery = outcome {
            XCTFail("Cooldown must suppress sabotage")
        }
    }

    func testHighLoadDayEvaluatorStreak() {
        // Build 3 consecutive high-load days (lots of anchored, no fluid).
        var tasks: [LifeTask] = []
        for offset in 1...3 {
            let d = calendar.date(byAdding: .day, value: -offset, to: day)!
            for h in 9..<17 {
                let s = calendar.date(bySettingHour: h, minute: 0, second: 0, of: d)!
                tasks.append(LifeTask(
                    id: "t-\(offset)-\(h)",
                    title: "Work",
                    status: .pending,
                    estimatedMinutes: 55,
                    scheduledDate: calendar.startOfDay(for: d),
                    scheduledTime: s,
                    timeConstraint: .anchored,
                    scheduledEndTime: s.addingTimeInterval(55 * 60),
                    userId: "u"
                ))
            }
        }
        let streak = HighLoadDayEvaluator.consecutiveHighLoadDays(
            tasks: tasks, now: day, lookback: 5, calendar: calendar
        )
        XCTAssertEqual(streak, 3)
    }

    func testNextGapUsesBufferAroundBlockers() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
        let anchorStart = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow)!
        let anchor = LifeTask(
            id: "tm-a",
            title: "Anchored",
            status: .pending,
            estimatedMinutes: 60,
            scheduledDate: calendar.startOfDay(for: tomorrow),
            scheduledTime: anchorStart,
            timeConstraint: .anchored,
            scheduledEndTime: anchorStart.addingTimeInterval(3600),
            userId: "u"
        )
        let gap = ConflictResolutionCascade.findNextAvailableGap(
            durationMinutes: 30,
            from: calendar.startOfDay(for: day),
            excludingTaskID: "x",
            universe: [anchor],
            horizonDays: 3,
            bufferMinutes: 10,
            calendar: calendar
        )
        XCTAssertNotNil(gap)
        if let gap {
            let buf: TimeInterval = 10 * 60
            let zoneStart = anchorStart.addingTimeInterval(-buf)
            let zoneEnd = anchorStart.addingTimeInterval(3600 + buf)
            let placedEnd = gap.start.addingTimeInterval(30 * 60)
            let overlapsBufferZone = gap.start < zoneEnd && zoneStart < placedEnd
            XCTAssertFalse(overlapsBufferZone, "Placement must respect buffer around anchored block")
        }
    }

    func testDeferralHorizonAllowsBeyondSevenDays() {
        // Fill next 8 mornings with anchors so gap is only on day 9.
        var universe: [LifeTask] = []
        for offset in 1...8 {
            let d = calendar.date(byAdding: .day, value: offset, to: day)!
            let start = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: d)!
            // Block entire workday
            for h in 8..<21 {
                let s = calendar.date(bySettingHour: h, minute: 0, second: 0, of: d)!
                universe.append(LifeTask(
                    id: "b-\(offset)-\(h)",
                    title: "Busy",
                    status: .pending,
                    estimatedMinutes: 55,
                    scheduledDate: calendar.startOfDay(for: d),
                    scheduledTime: s,
                    timeConstraint: .anchored,
                    scheduledEndTime: s.addingTimeInterval(55 * 60),
                    userId: "u"
                ))
            }
            _ = start
        }
        let gap = ConflictResolutionCascade.findNextAvailableGap(
            durationMinutes: 30,
            from: calendar.startOfDay(for: day),
            excludingTaskID: "x",
            universe: universe,
            horizonDays: 28,
            bufferMinutes: 5,
            calendar: calendar
        )
        XCTAssertNotNil(gap)
        if let gap {
            let daysOut = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: gap.day).day ?? 0
            XCTAssertGreaterThan(daysOut, 7)
        }
    }

    func testRankPrefersAnchoredOverFluid() {
        let a = task(id: "1", title: "A", hour: 9, minutes: 30, constraint: .anchored)
        let f = task(id: "2", title: "F", hour: 9, minutes: 30, constraint: .fluid)
        XCTAssertGreaterThan(ConflictResolutionCascade.rank(a), ConflictResolutionCascade.rank(f))
    }

    func testReconcilerSurfacesNoManualConflicts() {
        let a = task(id: "a", title: "A", hour: 11, minutes: 60, constraint: .anchored)
        let b = task(id: "b", title: "B", hour: 11, minutes: 45, constraint: .flexible)
        let result = DayScheduleReconciler.reconcile(tasks: [a, b], on: day, calendar: calendar)
        XCTAssertTrue(result.conflictTaskIDs.isEmpty, "Cascade must eliminate manual conflict IDs")
        XCTAssertFalse(DayScheduleReconciler.hasOverlap(result.tasks, on: day, calendar: calendar))
    }

    func testCompressWhenShiftWouldExceedDay() {
        // Anchored occupies most of the afternoon; flexible long block starts mid-way.
        let anchored = task(id: "meet", title: "All hands", hour: 14, minutes: 180, constraint: .anchored)
        var long = task(id: "long", title: "Write", hour: 14, minutes: 120, constraint: .flexible)
        long.estimatedMinutes = 120
        let result = ConflictResolutionCascade.resolve(
            tasks: [anchored, long], on: day, calendar: calendar
        )
        XCTAssertTrue(result.unresolvedTaskIDs.isEmpty)
        let action = decision(result, "long")
        XCTAssertNotEqual(action, .keep)
        XCTAssertTrue([ConflictCascadeAction.shiftLater, .compress, .deferNextGap, .park].contains(action))
    }

    func testEqualStartFlexiblePairStableAcrossInputOrder() {
        let first = task(id: "aaa-flex", title: "Alpha task", hour: 14, minutes: 45, constraint: .flexible)
        let second = task(id: "zzz-flex", title: "Zulu task", hour: 14, minutes: 45, constraint: .flexible)

        let forward = ConflictResolutionCascade.resolve(
            tasks: [first, second], on: day, calendar: calendar
        )
        let reverse = ConflictResolutionCascade.resolve(
            tasks: [second, first], on: day, calendar: calendar
        )

        let forwardByID = Dictionary(uniqueKeysWithValues: forward.tasks.map { ($0.id, $0.scheduledTime) })
        let reverseByID = Dictionary(uniqueKeysWithValues: reverse.tasks.map { ($0.id, $0.scheduledTime) })

        XCTAssertEqual(forwardByID["aaa-flex"], reverseByID["aaa-flex"])
        XCTAssertEqual(forwardByID["zzz-flex"], reverseByID["zzz-flex"])
        XCTAssertFalse(DayScheduleReconciler.hasOverlap(forward.tasks, on: day, calendar: calendar))
        XCTAssertFalse(DayScheduleReconciler.hasOverlap(reverse.tasks, on: day, calendar: calendar))
    }

    func testReconcileTwiceIsIdempotentOnCleanSchedule() {
        let morning = task(id: "morning", title: "Morning block", hour: 9, minutes: 60, constraint: .anchored)
        let afternoon = task(id: "afternoon", title: "Afternoon block", hour: 14, minutes: 60, constraint: .flexible)

        let first = DayScheduleReconciler.reconcile(tasks: [morning, afternoon], on: day, calendar: calendar)
        let second = DayScheduleReconciler.reconcile(tasks: first.tasks, on: day, calendar: calendar)

        XCTAssertTrue(second.changedTaskIDs.isEmpty)
        XCTAssertFalse(DayScheduleReconciler.hasOverlap(second.tasks, on: day, calendar: calendar))
    }

    // MARK: - Helpers

    private func decision(_ result: ConflictCascadeResult, _ id: String) -> ConflictCascadeAction? {
        result.decisions.first { $0.taskID == id }?.action
    }

    private func task(
        id: String,
        title: String,
        hour: Int,
        minutes: Int,
        constraint: TimeConstraint,
        priority: Priority = .medium
    ) -> LifeTask {
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        return LifeTask(
            id: id,
            title: title,
            priority: priority,
            status: .pending,
            estimatedMinutes: minutes,
            scheduledDate: calendar.startOfDay(for: day),
            scheduledTime: start,
            schedulingMode: constraint.asSchedulingMode,
            timeConstraint: constraint,
            scheduledEndTime: end,
            userId: "u"
        )
    }
}
