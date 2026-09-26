import XCTest
@testable import LookAfterCore

/// Sixty mornings in the life of Avery, an office worker with ADHD.
///
/// The store is the real task model. Each day materializes routines, builds the day plate,
/// asks the recommendation engine what to do, then the user completes, skips, leaves, adds,
/// or deletes a few things. Life changes (gym days, work start, sleep) are applied as single
/// edits, not as a rebuilt plan.
final class SixtyDayLifeSimulationTests: XCTestCase {
    private let calendar = TestCalendarFixtures.calendar
    private let userId = "avery"
    private let dayCount = 60

    func testAverySixtyDayHouseholdAdaptsWithoutRebuildingTheDay() async {
        let origin = TestCalendarFixtures.date(year: 2026, month: 8, day: 3, hour: 10)
        var tasks = seedTemplates(createdAt: calendar.date(byAdding: .day, value: -1, to: origin)!)
        var failures: [String] = []
        var userActions = 0
        var unnaturalActions = 0
        var quietDayActions: [Int] = []
        var recoveryMornings = 0
        var shortSleepMornings = 0
        var diary: [String] = []

        for offset in 0..<dayCount {
            let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: origin))!
            let phase = LifePhase(offset: offset)
            let now = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day)!
            var actionsToday = 0

            if offset == 21 {
                tasks = retargetGym(tasks, weekdays: [2, 4, 6])
                tasks = retargetWork(tasks, hour: 10, minute: 30, on: day)
                actionsToday += 2
            }
            if offset == 40 {
                tasks = retargetWork(tasks, hour: 8, minute: 30, on: day)
                actionsToday += 1
            }
            if offset == 50 {
                tasks.removeAll { $0.id == "dinner" }
                tasks.append(routine(
                    id: "late-dinner",
                    title: "Late dinner",
                    hour: 21,
                    minute: 0,
                    recurrence: .daily,
                    minutes: 40,
                    on: day
                ))
                actionsToday += 1
            }
            if offset == 15, !tasks.contains(where: { $0.id == "standup" }) {
                tasks.append(routine(
                    id: "standup",
                    title: "Team standup",
                    hour: 9,
                    minute: 15,
                    recurrence: .weekly,
                    minutes: 15,
                    on: day,
                    createdAt: day
                ))
                actionsToday += 1
            }
            if offset == 22 {
                tasks = retargetClock(tasks, id: "gym", hour: 7, minute: 0, on: day)
                actionsToday += 1
            }
            if offset == 51 {
                tasks = retargetClock(tasks, id: "late-dinner", hour: 20, minute: 30, on: day)
                actionsToday += 1
            }
            if offset == 52, !tasks.contains(where: { $0.id == "trash" }) {
                tasks.append(routine(
                    id: "trash",
                    title: "Trash night",
                    hour: 19,
                    minute: 0,
                    recurrence: .weekly,
                    minutes: 10,
                    on: day,
                    createdAt: day
                ))
                actionsToday += 1
            }
            if offset == 58, !tasks.contains(where: { $0.id == "walk" }) {
                tasks.append(routine(
                    id: "walk",
                    title: "Evening walk",
                    hour: 18,
                    minute: 15,
                    recurrence: .weekdays,
                    minutes: 25,
                    on: day,
                    createdAt: day
                ))
                actionsToday += 1
            }

            let fresh = TaskRecurrenceEngine.missingOccurrences(for: tasks, on: day, calendar: calendar)
            tasks.append(contentsOf: fresh)

            if offset == 4 {
                tasks.append(oneOff(id: "dentist", title: "Call dentist", on: day, hour: 11))
                actionsToday += 1
            }
            if offset == 7 {
                tasks.append(oneOff(id: "library", title: "Return library book", on: day, hour: 16))
                actionsToday += 1
            }
            if offset == 8 {
                let before = tasks.count
                tasks.removeAll { $0.id == "library" }
                if tasks.count != before - 1 { failures.append("D\(offset): library task was not removed") }
                actionsToday += 1
            }
            if offset == 10 {
                tasks.append(contentsOf: taxSlices(starting: day))
                actionsToday += 1
            }

            let events = DayPlateBuilder.events(
                from: tasks,
                now: now,
                referenceDay: day,
                calendar: calendar
            )
            let weekday = calendar.component(.weekday, from: day)

            expectOne(events, title: "Breakfast", day: offset, failures: &failures)
            expectOne(events, title: "Lunch", day: offset, failures: &failures)
            if offset < 50 {
                expectOne(events, title: "Dinner", day: offset, failures: &failures)
            } else {
                if events.contains(where: { $0.title == "Dinner" }) {
                    failures.append("D\(offset): retired Dinner still on the rail")
                }
                expectOne(events, title: "Late dinner", day: offset, failures: &failures)
            }
            expectOne(events, title: "Meds", day: offset, failures: &failures)

            let gymExpected = phase.gymWeekdays.contains(weekday)
            let gymCount = events.filter { $0.title == "Gym" }.count
            if gymExpected && gymCount != 1 {
                failures.append("D\(offset): expected 1 Gym, saw \(gymCount)")
            }
            if !gymExpected && gymCount != 0 {
                failures.append("D\(offset): Gym painted on a rest day (\(gymCount))")
            }

            if let work = events.first(where: { $0.title.contains("Implement") }) {
                let hour = calendar.component(.hour, from: work.date)
                let minute = calendar.component(.minute, from: work.date)
                if hour != phase.workHour || minute != phase.workMinute {
                    failures.append("D\(offset): work clock \(hour):\(minute) != \(phase.workHour):\(phase.workMinute)")
                }
            } else if isWeekday(weekday) {
                failures.append("D\(offset): weekday work block missing")
            }

            if (10...14).contains(offset) {
                let sliceTitle = "Tax packet · Day \(offset - 9)"
                if !events.contains(where: { $0.title == sliceTitle }) {
                    failures.append("D\(offset): missing \(sliceTitle)")
                }
                let otherSlices = events.filter { $0.title.hasPrefix("Tax packet") && $0.title != sliceTitle }
                if !otherSlices.isEmpty {
                    failures.append("D\(offset): other tax slices leaked onto today")
                }
            }
            if offset >= 23, gymExpected, let gym = events.first(where: { $0.title == "Gym" }) {
                let hour = calendar.component(.hour, from: gym.date)
                if hour != 7 { failures.append("D\(offset): gym stayed at \(hour):00 after the morning move") }
            }
            if offset == 15 || offset == 22 {
                expectOne(events, title: "Team standup", day: offset, failures: &failures)
            }
            if offset == 52 || offset == 59 {
                expectOne(events, title: "Trash night", day: offset, failures: &failures)
            }
            if offset >= 58, isWeekday(weekday) {
                expectOne(events, title: "Evening walk", day: offset, failures: &failures)
            }
            if offset >= 51, let dinner = events.first(where: { $0.title == "Late dinner" }) {
                let hour = calendar.component(.hour, from: dinner.date)
                let minute = calendar.component(.minute, from: dinner.date)
                if hour != 20 || minute != 30 {
                    failures.append("D\(offset): late dinner clock \(hour):\(minute) != 20:30")
                }
            }

            if offset == 5 {
                let carried = tasks.contains { $0.id == "dentist" && $0.isOverdueOneOffCarryForward(calendar: calendar, referenceDate: now) }
                if !carried { failures.append("D5: unfinished dentist did not carry onto today") }
                let visible = TaskScheduleQuery.uniqueActiveTasks(from: tasks.filter(\.status.isActive), context: tasks, calendar: calendar, referenceDate: now)
                if !visible.contains(where: { $0.id == "dentist" }) {
                    failures.append("D5: dentist missing from the active list")
                }
            }
            if offset > 8 && tasks.contains(where: { $0.id == "library" }) {
                failures.append("D\(offset): removed library book came back")
            }

            let openToday = tasks.filter {
                $0.status.isActive && TaskRecurrenceEngine.isActionableToday($0, in: tasks, calendar: calendar, referenceDate: now)
            }
            if let hero = openToday.first(where: { TaskHeroEligibility.isEligible(for: $0, now: now, calendar: calendar, allTasks: tasks) }) {
                if hero.status == .completed {
                    failures.append("D\(offset): completed \(hero.title) was offered as hero")
                }
            }

            let scripted = applyExtensiveActions(
                offset: offset,
                day: day,
                now: now,
                weekday: weekday,
                tasks: &tasks,
                failures: &failures
            )
            actionsToday += scripted
            unnaturalActions += exerciseEveryPossibleAction(
                offset: offset,
                day: day,
                now: now,
                weekday: weekday,
                tasks: &tasks,
                failures: &failures
            )

            if phase.fellOffSchedule {
                // The user does nothing. Tomorrow's routines must still appear on their own.
            } else {
                if let breakfast = todayTask(tasks, title: "Breakfast", on: day) {
                    tasks = complete(breakfast.id, in: tasks, at: now)
                    actionsToday += 1
                }
                if weekday != 1 && weekday != 7, let lunch = todayTask(tasks, title: "Lunch", on: day) {
                    tasks = complete(lunch.id, in: tasks, at: now)
                    actionsToday += 1
                }
                if gymExpected, phase.sleepHours < 6, let gym = todayTask(tasks, title: "Gym", on: day) {
                    tasks = skip(gym.id, in: tasks)
                    actionsToday += 1
                }
                if offset % 3 != 0, let dinner = todayTask(tasks, title: offset < 50 ? "Dinner" : "Late dinner", on: day) {
                    tasks = complete(dinner.id, in: tasks, at: now)
                    actionsToday += 1
                }
                if (10...14).contains(offset), let slice = tasks.first(where: { $0.id == "tax-\(offset - 9)" }) {
                    tasks = complete(slice.id, in: tasks, at: now)
                    actionsToday += 1
                }
            }

            let after = DayPlateBuilder.events(from: tasks, now: now, referenceDay: day, calendar: calendar)
            if !phase.fellOffSchedule, let breakfast = after.first(where: { $0.title == "Breakfast" }), !breakfast.isCompleted {
                failures.append("D\(offset): completed breakfast left the rail")
            }
            if after.filter({ $0.title == "Breakfast" }).count > 1 {
                failures.append("D\(offset): breakfast duplicated after completion")
            }
            auditSurfaces(
                tasks: tasks,
                events: after,
                now: now,
                day: day,
                offset: offset,
                fellOff: phase.fellOffSchedule,
                failures: &failures
            )

            if isWeekday(weekday), let work = todayTask(tasks, titlePrefix: "Implement", on: day) {
                var health = HealthSummary(date: now, userId: userId)
                health.totalSleepMinutes = phase.sleepHours * 60
                let snapshot = LifeContextSnapshot(
                    currentEnergy: phase.energy,
                    availableTimeMinutes: 90,
                    sleepQuality: phase.sleepHours < 6 ? .poor : .good,
                    healthReadiness: phase.energy
                )
                let advice = ExecutiveRecommendationEngine.recommend(from: .init(
                    task: work,
                    snapshot: snapshot,
                    healthSummary: health,
                    tasks: tasks.filter(\.status.isActive),
                    now: now,
                    calendar: calendar
                ))
                if phase.sleepHours < 6 {
                    shortSleepMornings += 1
                    let avoidedDeepWork = advice?.taskID != work.id
                        || (advice?.headline.contains("recovery") == true)
                        || (advice?.headline.contains("Protect") == true)
                    if avoidedDeepWork {
                        recoveryMornings += 1
                    } else {
                        failures.append("D\(offset): short sleep still started deep work (\(advice?.headline ?? "none"))")
                    }
                }
            }

            if !phase.isLifeEditDay && !phase.fellOffSchedule && scripted == 0 {
                quietDayActions.append(actionsToday)
            }
            userActions += actionsToday
            if offset % 7 == 0 {
                diary.append("D\(offset) \(phase.label) sleep \(phase.sleepHours)h actions \(actionsToday) rail \(events.count)")
            }
        }

        let meanQuiet = quietDayActions.isEmpty ? 0 : Double(userActions) / Double(dayCount)
        print("60-day diary:\n" + diary.joined(separator: "\n"))
        print("user actions \(userActions) over \(dayCount) days, mean \(String(format: "%.2f", meanQuiet))")
        print("unnatural action checks \(unnaturalActions)")
        print("short-sleep mornings \(shortSleepMornings), recovery recommendations \(recoveryMornings)")

        if recoveryMornings < shortSleepMornings {
            failures.append("Recovery advice missed \(shortSleepMornings - recoveryMornings) short-sleep mornings")
        }
        if let busiest = quietDayActions.max(), busiest > 6 {
            failures.append("A quiet day required \(busiest) manual actions")
        }

        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    // MARK: - Persona

    private struct LifePhase {
        let offset: Int
        var gymWeekdays: Set<Int> { offset < 21 ? [3, 5] : [2, 4, 6] }
        var workHour: Int {
            if offset < 21 { return 9 }
            if offset < 40 { return 10 }
            return 8
        }
        var workMinute: Int {
            if offset < 21 { return 30 }
            if offset < 40 { return 30 }
            return 30
        }
        var sleepHours: Double { (28...34).contains(offset) ? 4.5 : 7.5 }
        var energy: Double { sleepHours < 6 ? 0.32 : 0.72 }
        var fellOffSchedule: Bool { offset == 45 || offset == 46 }
        var isLifeEditDay: Bool { offset == 21 || offset == 40 || offset == 50 }
        var label: String {
            if fellOffSchedule { return "fell-off" }
            if sleepHours < 6 { return "short-sleep" }
            if offset >= 50 { return "late-dinner" }
            if offset >= 40 { return "early-work" }
            if offset >= 21 { return "new-gym" }
            return "baseline"
        }
    }

    // MARK: - Extensive user actions

    /// Extra actions beyond the daily meal marks: add, edit, undo, defer, skip, reschedule,
    /// dismiss to tomorrow, expire, in-progress, and a calendar block.
    private func applyExtensiveActions(
        offset: Int,
        day: Date,
        now: Date,
        weekday: Int,
        tasks: inout [LifeTask],
        failures: inout [String]
    ) -> Int {
        var actions = 0
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!

        switch offset {
        case 0:
            tasks.append(oneOff(id: "landlord", title: "Reply to landlord", on: day, hour: 11))
            tasks = complete("landlord", in: tasks, at: now)
            tasks = setStatus("landlord", in: tasks, status: .pending, clearCompletion: true)
            actions += 3
            if !todaySheet(tasks, now: now).contains(where: { $0.id == "landlord" }) {
                failures.append("D0: undone landlord left the Today sheet")
            }
            if !timeline(tasks, now: now, day: day).contains(where: { $0.title == "Reply to landlord" }) {
                failures.append("D0: undone landlord left the timeline")
            }
            tasks = complete("landlord", in: tasks, at: now)
            actions += 1

        case 1:
            guard isWeekday(weekday), let work = todayTask(tasks, titlePrefix: "Implement", on: day) else { break }
            tasks = setStatus(work.id, in: tasks, status: .inProgress)
            if !TaskHeroEligibility.isEligible(for: tasks.first { $0.id == work.id }!, now: now, calendar: calendar, allTasks: tasks) {
                failures.append("D1: in-progress work was not a valid hero")
            }
            tasks = setStatus(work.id, in: tasks, status: .paused)
            tasks = setStatus(work.id, in: tasks, status: .pending)
            actions += 3

        case 2:
            if let lunch = todayTask(tasks, title: "Lunch", on: day) {
                tasks = move(lunch.id, in: tasks, to: day, hour: 13, minute: 45)
                actions += 1
                let rail = timeline(tasks, now: now, day: day)
                if let event = rail.first(where: { $0.title == "Lunch" }) {
                    let hour = calendar.component(.hour, from: event.date)
                    let minute = calendar.component(.minute, from: event.date)
                    if hour != 13 || minute != 45 {
                        failures.append("D2: rescheduled lunch showed \(hour):\(minute)")
                    }
                } else {
                    failures.append("D2: rescheduled lunch missing from the timeline")
                }
            }

        case 3:
            if let meds = todayTask(tasks, title: "Meds", on: day) {
                tasks = setStatus(meds.id, in: tasks, status: .deferred)
                actions += 1
                if todaySheet(tasks, now: now).contains(where: { $0.id == meds.id }) {
                    failures.append("D3: deferred meds stayed on the Today sheet")
                }
            }

        case 6:
            tasks.append(oneOff(id: "oil", title: "Oil change", on: tomorrow, hour: 9))
            actions += 1
            if todaySheet(tasks, now: now).contains(where: { $0.id == "oil" }) {
                failures.append("D6: tomorrow's oil change landed on Today")
            }
            if !tomorrowSheet(tasks, now: now).contains(where: { $0.id == "oil" }) {
                failures.append("D6: oil change missing from Tomorrow")
            }
            if timeline(tasks, now: now, day: day).contains(where: { $0.title == "Oil change" }) {
                failures.append("D6: oil change painted on today's timeline")
            }

        case 9:
            let later = calendar.date(byAdding: .day, value: 5, to: day)!
            tasks.append(oneOff(id: "passport", title: "Renew passport", on: later, hour: 14))
            actions += 1
            if todaySheet(tasks, now: now).contains(where: { $0.id == "passport" }) {
                failures.append("D9: passport showed on Today")
            }
            if !upcomingSheet(tasks, now: now).contains(where: { $0.id == "passport" }) {
                failures.append("D9: passport missing from Upcoming")
            }

        case 11:
            if let oil = tasks.first(where: { $0.id == "oil" }) {
                tasks = rename(oil.id, in: tasks, title: "Email the accountant")
                actions += 1
                if !tasks.contains(where: { $0.id == "oil" && $0.title == "Email the accountant" }) {
                    failures.append("D11: rename did not stick")
                }
            }

        case 12:
            if let meds = todayTask(tasks, title: "Meds", on: day) {
                tasks = skip(meds.id, in: tasks)
                actions += 1
                if todaySheet(tasks, now: now).contains(where: { $0.id == meds.id }) {
                    failures.append("D12: skipped meds stayed on Today")
                }
            }

        case 15:
            if let standup = todayTask(tasks, title: "Team standup", on: day) {
                tasks = complete(standup.id, in: tasks, at: now)
                actions += 1
                let rail = timeline(tasks, now: now, day: day)
                if rail.first(where: { $0.title == "Team standup" })?.isCompleted != true {
                    failures.append("D15: completed standup left the timeline")
                }
            }

        case 18:
            tasks.append(oneOff(id: "invoice", title: "Pay invoice", on: day, hour: 16))
            actions += 1

        case 19:
            if tasks.contains(where: { $0.id == "invoice" && $0.status.isActive }) {
                tasks = move("invoice", in: tasks, to: tomorrow, hour: 16, minute: 0)
                actions += 1
                if todaySheet(tasks, now: now).contains(where: { $0.id == "invoice" }) {
                    failures.append("D19: dismissed invoice stayed on Today")
                }
                if !tomorrowSheet(tasks, now: now).contains(where: { $0.id == "invoice" }) {
                    failures.append("D19: dismissed invoice missing from Tomorrow")
                }
            }

        case 26:
            tasks.append(oneOff(id: "plants", title: "Water plants", on: day, hour: 17))
            tasks = setStatus("plants", in: tasks, status: .inProgress)
            tasks = complete("plants", in: tasks, at: now)
            actions += 3
            if timeline(tasks, now: now, day: day).first(where: { $0.title == "Water plants" })?.isCompleted != true {
                failures.append("D26: completed plants left the timeline or lost the done mark")
            }

        case 30:
            tasks.append(oneOff(id: "stretch", title: "Stretch", on: day, hour: 10))
            actions += 1

        case 33:
            if tasks.contains(where: { $0.id == "passport" && $0.status.isActive }) {
                tasks = setStatus("passport", in: tasks, status: .expired)
                actions += 1
                if allSheet(tasks, now: now).contains(where: { $0.id == "passport" }) {
                    failures.append("D33: expired passport stayed in All")
                }
            }

        case 38:
            tasks.append(oneOff(id: "notes", title: "Write release notes", on: day, hour: 15))
            actions += 1
            if !todaySheet(tasks, now: now).contains(where: { $0.id == "notes" }) {
                failures.append("D38: release notes missing from Today")
            }

        case 41:
            let carried = tasks.filter {
                $0.status.isActive && $0.isOverdueOneOffCarryForward(calendar: calendar, referenceDate: now)
            }
            for task in carried {
                tasks = complete(task.id, in: tasks, at: now)
                actions += 1
            }

        case 44:
            tasks.append(oneOff(id: "post", title: "Post office", on: day, hour: 12))
            actions += 1

        case 48:
            if let post = tasks.first(where: { $0.id == "post" && $0.status.isActive }) {
                if !post.isOverdueOneOffCarryForward(calendar: calendar, referenceDate: now) {
                    failures.append("D48: post office did not carry after the missed days")
                }
                tasks = complete(post.id, in: tasks, at: now)
                actions += 1
            }

        case 54:
            tasks.append(oneOff(id: "laundry", title: "Fold laundry", on: day, hour: 18))
            tasks = setStatus("laundry", in: tasks, status: .deferred)
            actions += 2
            if todaySheet(tasks, now: now).contains(where: { $0.id == "laundry" }) {
                failures.append("D54: deferred laundry stayed on Today")
            }

        case 55:
            tasks = setStatus("laundry", in: tasks, status: .pending, clearCompletion: true)
            tasks = move("laundry", in: tasks, to: day, hour: 18, minute: 0)
            actions += 2
            if !todaySheet(tasks, now: now).contains(where: { $0.id == "laundry" }) {
                failures.append("D55: restored laundry did not return to Today")
            }

        case 57:
            tasks.append(oneOff(id: "receipt", title: "File receipt", on: day, hour: 11))
            tasks = complete("receipt", in: tasks, at: now)
            actions += 2
            let done = completedSheet(tasks, now: now)
            if !done.contains(where: { $0.id == "receipt" }) {
                failures.append("D57: today's receipt missing from Completed")
            }
            if done.contains(where: { $0.id == "landlord" }) {
                failures.append("D57: the 7-day completed window still showed the landlord reply")
            }

        default:
            break
        }
        return actions
    }

    /// Every status, clock, recurrence, and field edit, including ones nobody would make.
    /// Disposable rows are removed before the day continues, so meals and the quiet-day budget stay intact.
    private func exerciseEveryPossibleAction(
        offset: Int,
        day: Date,
        now: Date,
        weekday: Int,
        tasks: inout [LifeTask],
        failures: inout [String]
    ) -> Int {
        var checks = 0
        let id = "chaos-\(offset)"
        let title = "Chaos probe \(offset)"
        let savedBreakfast = tasks.first { $0.id == "breakfast" }

        func fail(_ message: String) {
            failures.append("D\(offset): \(message)")
        }

        var probe = oneOff(id: id, title: title, on: day, hour: 12)
        probe.description = String(repeating: "note ", count: 80)
        probe.notes = "line one\nline two 🎂 \(String(repeating: "x", count: 400))"
        probe.priority = Priority.allCases[offset % Priority.allCases.count]
        probe.difficulty = TaskDifficulty.allCases[offset % TaskDifficulty.allCases.count]
        probe.requiredEnergy = EnergyLevel.allCases[offset % EnergyLevel.allCases.count]
        probe.lifeArea = .personal
        probe.workCategory = WorkTaskCategory.allCases[offset % WorkTaskCategory.allCases.count]
        probe.estimatedMinutes = 0
        probe.minimumViableDuration = 0
        probe.actualMinutes = -3
        probe.steps = [
            TaskStep(id: "\(id)-step", title: "Micro", estimatedMinutes: 0),
            TaskStep(id: "\(id)-done", title: "Already", isCompleted: true, completedAt: now, actualMinutes: 99_999)
        ]
        probe.tags = ["chaos", ""]
        probe.expirationPolicy = .strictWindow(minutes: 0)
        probe.collisionStrategy = .dropOldest
        probe.scheduledEndTime = clock(11, 0, on: day)
        probe.userPlacedScheduleAt = now
        probe.completionProbability = 2.5
        probe.aiReasoningNote = ""
        tasks.append(probe)
        checks += 1

        guard todaySheet(tasks, now: now).contains(where: { $0.id == id }) else {
            fail("fresh chaos probe missed Today")
            tasks.removeAll { $0.id == id || $0.parentTaskId == id }
            return checks
        }
        guard timeline(tasks, now: now, day: day).contains(where: { $0.id == id || $0.title == title }) else {
            fail("fresh chaos probe missed the timeline")
            tasks.removeAll { $0.id == id || $0.parentTaskId == id }
            return checks
        }

        tasks = patch(id, in: tasks) { $0.lifeArea = .finance }
        checks += 1
        let financeRail = timeline(tasks, now: now, day: day)
        if financeRail.contains(where: { $0.title == title }) {
            fail("a finance task kept its own timeline row")
        }
        if !financeRail.contains(where: { $0.title == "Finance session" }) {
            fail("a finance task did not join the finance session")
        }
        tasks = patch(id, in: tasks) { $0.lifeArea = .shopping }
        checks += 1
        if !timeline(tasks, now: now, day: day).contains(where: { $0.title == title }) {
            fail("a timed shopping task with no grocery list left the timeline")
        }
        tasks = patch(id, in: tasks) { $0.lifeArea = .personal }
        checks += 1
        if !timeline(tasks, now: now, day: day).contains(where: { $0.title == title }) {
            fail("returning the probe to Personal left it off the timeline")
        }

        for status in TaskStatus.allCases {
            if status == .completed {
                tasks = complete(id, in: tasks, at: now)
            } else {
                tasks = setStatus(id, in: tasks, status: status, clearCompletion: true)
            }
            checks += 1
            let onToday = todaySheet(tasks, now: now).contains { $0.id == id }
            let onAll = allSheet(tasks, now: now).contains { $0.id == id }
            let onRail = timeline(tasks, now: now, day: day).first { $0.title == title }
            if status.isActive {
                if !onToday { fail("\(status.rawValue) probe left Today") }
                if !onAll { fail("\(status.rawValue) probe left All") }
                if onRail == nil { fail("\(status.rawValue) probe left the timeline") }
                if onRail?.isCompleted == true { fail("\(status.rawValue) probe was painted done") }
            } else if status == .completed {
                if onToday { fail("completed probe stayed on Today") }
                if onAll { fail("completed probe stayed in All") }
                if onRail?.isCompleted != true { fail("completed probe was not marked done on the timeline") }
                if !completedSheet(tasks, now: now).contains(where: { $0.id == id }) {
                    fail("completed probe missed Completed")
                }
            } else {
                if onToday { fail("\(status.rawValue) probe stayed on Today") }
                if onAll { fail("\(status.rawValue) probe stayed in All") }
                if onRail != nil { fail("\(status.rawValue) probe stayed on the timeline") }
            }
        }

        tasks = complete(id, in: tasks, at: now)
        tasks = complete(id, in: tasks, at: now)
        checks += 2
        if timeline(tasks, now: now, day: day).filter({ $0.title == title }).count != 1 {
            fail("completing twice duplicated the probe")
        }

        tasks = setStatus(id, in: tasks, status: .pending, clearCompletion: true)
        checks += 1
        if timeline(tasks, now: now, day: day).first(where: { $0.title == title })?.isCompleted != false {
            fail("undo did not reopen the probe")
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: day)!
        let nextWeek = calendar.date(byAdding: .day, value: 14, to: day)!
        let placements: [(Date, Int, Int, String)] = [
            (day, 0, 0, "midnight"),
            (day, 23, 59, "last minute"),
            (tomorrow, 4, 5, "tomorrow"),
            (nextWeek, 1, 1, "next fortnight"),
            (yesterday, 15, 0, "yesterday")
        ]
        for (placedDay, hour, minute, label) in placements {
            tasks = move(id, in: tasks, to: placedDay, hour: hour, minute: minute)
            tasks = setStatus(id, in: tasks, status: .pending, clearCompletion: true)
            checks += 1
            let onToday = todaySheet(tasks, now: now).contains { $0.id == id }
            let onTomorrow = tomorrowSheet(tasks, now: now).contains { $0.id == id }
            let onUpcoming = upcomingSheet(tasks, now: now).contains { $0.id == id }
            let onRail = timeline(tasks, now: now, day: day).contains { $0.title == title }
            switch label {
            case "midnight", "last minute":
                if !onToday || !onRail { fail("\(label) probe left today") }
                if onTomorrow { fail("\(label) probe also landed on Tomorrow") }
            case "tomorrow":
                if onToday || onRail { fail("tomorrow probe painted on today") }
                if !onTomorrow { fail("tomorrow probe missed Tomorrow") }
            case "next fortnight":
                if onToday || onTomorrow || onRail { fail("far probe leaked onto today or tomorrow") }
                if !onUpcoming { fail("far probe missed Upcoming") }
                if scheduledSheet(tasks, now: now).contains(where: { $0.id == id }) {
                    fail("far probe counted as scheduled this week")
                }
            case "yesterday":
                if !onToday || !onRail { fail("yesterday probe did not carry onto today") }
                if onTomorrow { fail("yesterday probe also sat on Tomorrow") }
            default:
                break
            }
        }

        tasks = patch(id, in: tasks) {
            $0.scheduledDate = nil
            $0.scheduledTime = nil
            $0.scheduledEndTime = nil
            $0.deadline = nil
            $0.status = .pending
            $0.completedAt = nil
        }
        checks += 1
        if todaySheet(tasks, now: now).contains(where: { $0.id == id })
            || timeline(tasks, now: now, day: day).contains(where: { $0.title == title })
            || tasks.first { $0.id == id }?.isActiveBacklog(calendar: calendar, referenceDate: now) != true {
            fail("unscheduled probe did not become backlog")
        }

        tasks = patch(id, in: tasks) {
            $0.deadline = clock(18, 0, on: day)
        }
        checks += 1
        if !todaySheet(tasks, now: now).contains(where: { $0.id == id }) {
            fail("deadline-only probe due today missed Today")
        }

        tasks = patch(id, in: tasks) { $0.deadline = clock(9, 0, on: tomorrow) }
        checks += 1
        if todaySheet(tasks, now: now).contains(where: { $0.id == id })
            || !tomorrowSheet(tasks, now: now).contains(where: { $0.id == id }) {
            fail("tomorrow deadline painted on the wrong sheet")
        }

        tasks = patch(id, in: tasks) { $0.deadline = clock(9, 0, on: nextWeek) }
        checks += 1
        if !upcomingSheet(tasks, now: now).contains(where: { $0.id == id }) {
            fail("far deadline missed Upcoming")
        }

        tasks = move(id, in: tasks, to: day, hour: 12, minute: 0)
        tasks = patch(id, in: tasks) {
            $0.deadline = nil
            $0.applyTimeConstraint(.fluid)
            $0.schedulingMode = .flexible
            $0.estimatedMinutes = -15
        }
        checks += 1
        if timeline(tasks, now: now, day: day).filter({ $0.title == title }).count != 1 {
            fail("fluid probe dropped off or duplicated")
        }
        tasks = patch(id, in: tasks) {
            $0.applyUserSchedulingModeEdit(.fixedTime, fixedStartTime: clock(12, 0, on: day), fixedEndTime: clock(12, 5, on: day))
            $0.scheduledDate = calendar.startOfDay(for: day)
            $0.estimatedMinutes = 15
        }
        checks += 1

        let blankTitle = " "
        tasks = rename(id, in: tasks, title: blankTitle)
        checks += 1
        if timeline(tasks, now: now, day: day).contains(where: { $0.title == title }) {
            fail("rename left the old title on the timeline")
        }
        tasks = rename(id, in: tasks, title: title)
        tasks = patch(id, in: tasks) { $0.parentTaskId = "missing-parent" }
        checks += 1
        if todaySheet(tasks, now: now).contains(where: { $0.id == id }) {
            fail("a probe whose parent does not exist stayed on Today")
        }
        tasks = patch(id, in: tasks) { $0.parentTaskId = id }
        checks += 1
        if todaySheet(tasks, now: now).contains(where: { $0.id == id }) {
            fail("a probe parented to itself stayed on Today")
        }
        tasks = patch(id, in: tasks) { $0.parentTaskId = nil }
        checks += 1
        if !todaySheet(tasks, now: now).contains(where: { $0.id == id }) {
            fail("clearing a nonsense parent did not return the probe to Today")
        }

        for area in LifeArea.allCases {
            tasks = patch(id, in: tasks) { $0.lifeArea = area }
        }
        for priority in Priority.allCases {
            tasks = patch(id, in: tasks) { $0.priority = priority }
        }
        for difficulty in TaskDifficulty.allCases {
            tasks = patch(id, in: tasks) { $0.difficulty = difficulty }
        }
        for energy in EnergyLevel.allCases {
            tasks = patch(id, in: tasks) { $0.requiredEnergy = energy }
        }
        for constraint in TimeConstraint.allCases {
            tasks = patch(id, in: tasks) { $0.timeConstraint = constraint }
        }
        for policy in [TaskExpirationPolicy.infinite, .endOfDay, .strictWindow(minutes: 1), .strictWindow(minutes: -4)] {
            tasks = patch(id, in: tasks) { $0.expirationPolicy = policy }
        }
        checks += 5
        tasks = patch(id, in: tasks) { task in
            task.steps = task.steps.map { step in
                var copy = step
                copy.isCompleted.toggle()
                return copy
            }
        }
        checks += 1
        if !todaySheet(tasks, now: now).contains(where: { $0.id == id }) {
            fail("field edits knocked the probe off Today")
        }

        let twinID = "chaos-twin-\(offset)"
        var twin = oneOff(id: twinID, title: "Chaos twin \(offset)", on: day, hour: 12)
        twin.estimatedMinutes = 10_000
        twin.scheduledEndTime = clock(12, 0, on: day)
        tasks.append(twin)
        checks += 1
        let rail = timeline(tasks, now: now, day: day)
        if rail.filter({ $0.id == twinID || $0.title == twin.title }).count != 1 {
            fail("same-clock twin was dropped or duplicated")
        }
        let fixedTimes = rail.filter { $0.scheduleKind == .fixedWindow }.map(\.date)
        if fixedTimes != fixedTimes.sorted() {
            fail("same-clock twin unsorted the timeline")
        }

        if let breakfast = savedBreakfast {
            let breakfastIDs = tasks.compactMap { task -> String? in
                if task.id == "breakfast" { return task.id }
                guard task.parentTaskId == "breakfast" else { return nil }
                let placed = task.scheduledDate ?? task.scheduledTime
                return placed.map { calendar.isDate($0, inSameDayAs: day) } == true ? task.id : nil
            }
            for breakfastID in breakfastIDs {
                tasks = rename(breakfastID, in: tasks, title: "")
            }
            checks += 1
            if timeline(tasks, now: now, day: day).contains(where: { $0.title == "Breakfast" }) {
                fail("blanking the breakfast title left the old name on the rail")
            }
            for breakfastID in breakfastIDs {
                tasks = patch(breakfastID, in: tasks) { task in
                    task.title = breakfast.title
                    task.estimatedMinutes = breakfastID == "breakfast" ? breakfast.estimatedMinutes : task.estimatedMinutes
                    if breakfastID == "breakfast" { task.scheduledTime = breakfast.scheduledTime }
                }
            }
            checks += 1
            if timeline(tasks, now: now, day: day).filter({ $0.title == "Breakfast" }).count != 1 {
                fail("restoring breakfast did not put one row back")
            }
        }

        let seriesID = "chaos-series-\(offset)"
        var series = routine(
            id: seriesID,
            title: "Chaos series \(offset)",
            hour: 20,
            minute: 30,
            recurrence: .daily,
            minutes: 5,
            on: day,
            createdAt: day
        )
        series.status = .completed
        series.completedAt = yesterday
        tasks.append(series)
        checks += 1
        let spawned = TaskRecurrenceEngine.missingOccurrences(for: tasks, on: day, calendar: calendar)
            .filter { $0.parentTaskId == seriesID }
        if spawned.count != 1 {
            fail("completed series clock hid today's occurrence (\(spawned.count))")
        } else {
            tasks.append(contentsOf: spawned)
            let shown = timeline(tasks, now: now, day: day).filter { $0.title == series.title }
            if shown.count != 1 || shown.first?.isCompleted == true {
                fail("completed series clock did not leave an open occurrence on the rail")
            }
        }
        tasks.removeAll { $0.id == seriesID || $0.parentTaskId == seriesID }

        for rule in TaskRecurrence.allCases {
            let ruleID = "chaos-rule-\(offset)-\(rule.rawValue)"
            let weekdaysForRule = rule == .custom ? [weekday == 1 ? 2 : 1] : nil
            var template = routine(
                id: ruleID,
                title: "Chaos \(rule.rawValue) \(offset)",
                hour: 6,
                minute: offset % 60,
                recurrence: rule,
                weekdays: weekdaysForRule,
                minutes: 5,
                on: day,
                createdAt: day
            )
            if rule == .daily { template.recurrenceInterval = max(offset % 5, 2) }
            template.status = .pending
            tasks.append(template)
            let made = TaskRecurrenceEngine.missingOccurrences(for: tasks, on: day, calendar: calendar)
                .filter { $0.parentTaskId == ruleID }
            let expectsRow: Bool = {
                switch rule {
                case .none:
                    return false
                case .weekdays:
                    return isWeekday(weekday)
                case .weekends:
                    return !isWeekday(weekday)
                case .custom:
                    return false
                case .daily, .weekly, .monthly, .yearly:
                    return true
                }
            }()
            if expectsRow != (made.count == 1) {
                fail("\(rule.rawValue) materialized \(made.count) rows")
            }
            tasks.append(contentsOf: made)
            if let occurrence = made.first {
                tasks = complete(occurrence.id, in: tasks, at: now)
                if timeline(tasks, now: now, day: day).first(where: { $0.title == template.title })?.isCompleted != true {
                    fail("completing a \(rule.rawValue) occurrence left the rail open")
                }
                if tasks.first(where: { $0.id == ruleID })?.status != .pending {
                    fail("completing a \(rule.rawValue) occurrence finished the series")
                }
            }
            checks += 1
            tasks.removeAll { $0.id == ruleID || $0.parentTaskId == ruleID }
        }

        tasks.removeAll { $0.id == id || $0.id == twinID || $0.id.hasPrefix("chaos-") || $0.parentTaskId?.hasPrefix("chaos-") == true }
        checks += 1
        if tasks.contains(where: { $0.id.hasPrefix("chaos-") || $0.title.hasPrefix("Chaos") }) {
            fail("deleting the chaos rows did not clear them")
        }
        if timeline(tasks, now: now, day: day).contains(where: { $0.title.hasPrefix("Chaos") }) {
            fail("deleted chaos rows stayed on the timeline")
        }
        return checks
    }

    private func auditSurfaces(
        tasks: [LifeTask],
        events: [LifeTimelineEvent],
        now: Date,
        day: Date,
        offset: Int,
        fellOff: Bool,
        failures: inout [String]
    ) {
        let today = todaySheet(tasks, now: now)
        if today.contains(where: { $0.isRecurrenceTemplateTask || !$0.status.isActive }) {
            failures.append("D\(offset): Today sheet included a template or a finished task")
        }
        let all = allSheet(tasks, now: now)
        if all.contains(where: { $0.isRecurrenceTemplateTask }) {
            failures.append("D\(offset): All sheet showed a recurrence template")
        }
        if Set(all.map(\.id)).count != all.count {
            failures.append("D\(offset): All sheet listed the same task twice")
        }
        let tomorrow = tomorrowSheet(tasks, now: now)
        let todayIDs = Set(today.map(\.id))
        if tomorrow.contains(where: { todayIDs.contains($0.id) }) {
            failures.append("D\(offset): a Today task was also on Tomorrow")
        }

        let fixedTimes = events.filter { $0.scheduleKind == .fixedWindow }.map(\.date)
        if fixedTimes != fixedTimes.sorted() {
            failures.append("D\(offset): timeline clocks are out of order")
        }
        let routineTitles = ["Breakfast", "Lunch", "Dinner", "Late dinner", "Meds", "Gym", "Evening walk", "Team standup", "Trash night"]
        for title in routineTitles where events.filter({ $0.title == title }).count > 1 {
            failures.append("D\(offset): timeline duplicated \(title)")
        }

        if !fellOff, let breakfast = events.first(where: { $0.title == "Breakfast" }), breakfast.isCompleted {
            if today.contains(where: { $0.title == "Breakfast" && calendar.isDate($0.scheduledDate ?? $0.scheduledTime ?? now, inSameDayAs: day) }) {
                failures.append("D\(offset): completed breakfast stayed in the Today sheet")
            }
        }

        if offset == 43 {
            let school = BriefingCalendarEvent(
                id: "school",
                title: "School run",
                startDate: clock(16, 0, on: day),
                timeLabel: "4:00 PM",
                endDate: clock(16, 20, on: day)
            )
            let withCalendar = DayPlateBuilder.events(
                from: tasks,
                calendarEvents: [school],
                now: now,
                referenceDay: day,
                calendar: calendar
            )
            if withCalendar.filter({ $0.title == "School run" }).count != 1 {
                failures.append("D43: calendar block missing from the timeline")
            }
        }

        if (10...14).contains(offset) {
            let sliceID = "tax-\(offset - 9)"
            if !all.contains(where: { $0.id == sliceID }) && !tasks.contains(where: { $0.id == sliceID && $0.status == .completed }) {
                failures.append("D\(offset): tax slice missing from All")
            }
        }
    }

    private func todaySheet(_ tasks: [LifeTask], now: Date) -> [LifeTask] {
        tasks.filter {
            $0.status.isActive
                && !$0.isRecurrenceTemplateTask
                && $0.isActionableToday(allTasks: tasks, calendar: calendar, referenceDate: now)
        }
    }

    private func tomorrowSheet(_ tasks: [LifeTask], now: Date) -> [LifeTask] {
        tasks.filter {
            $0.status.isActive
                && !$0.isRecurrenceTemplateTask
                && $0.isActionableTomorrow(allTasks: tasks, calendar: calendar, referenceDate: now)
        }
    }

    private func upcomingSheet(_ tasks: [LifeTask], now: Date) -> [LifeTask] {
        tasks.filter {
            $0.status.isActive
                && !$0.isRecurrenceTemplateTask
                && $0.isUpcoming(allTasks: tasks, calendar: calendar, referenceDate: now)
        }
    }

    private func allSheet(_ tasks: [LifeTask], now: Date) -> [LifeTask] {
        let active = tasks.filter { $0.status.isActive && !$0.isRecurrenceTemplateTask }
        return TaskScheduleQuery.uniqueActiveTasks(from: active, context: tasks, calendar: calendar, referenceDate: now)
    }

    private func completedSheet(_ tasks: [LifeTask], now: Date) -> [LifeTask] {
        let cutoff = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now))!
        return tasks.filter {
            !$0.status.isActive
                && !$0.isRecurrenceTemplateTask
                && $0.isInactiveWithNoFutureOccurrence(allTasks: tasks, calendar: calendar, referenceDate: now)
                && ($0.completedAt ?? $0.updatedAt) >= cutoff
        }
    }

    private func timeline(_ tasks: [LifeTask], now: Date, day: Date) -> [LifeTimelineEvent] {
        DayPlateBuilder.events(from: tasks, now: now, referenceDay: day, calendar: calendar)
    }

    private func scheduledSheet(_ tasks: [LifeTask], now: Date) -> [LifeTask] {
        tasks.filter {
            $0.isScheduledThisWeek(calendar: calendar, referenceDate: now)
        }
    }

    private func patch(_ id: String, in tasks: [LifeTask], _ edit: (inout LifeTask) -> Void) -> [LifeTask] {
        tasks.map { task in
            guard task.id == id else { return task }
            var copy = task
            edit(&copy)
            return copy
        }
    }

    // MARK: - Store helpers

    private func seedTemplates(createdAt: Date) -> [LifeTask] {
        let day = calendar.startOfDay(for: createdAt)
        return [
            routine(id: "breakfast", title: "Breakfast", hour: 8, minute: 0, recurrence: .daily, minutes: 20, on: day, createdAt: createdAt),
            routine(id: "lunch", title: "Lunch", hour: 13, minute: 0, recurrence: .daily, minutes: 30, on: day, createdAt: createdAt),
            routine(id: "dinner", title: "Dinner", hour: 19, minute: 30, recurrence: .daily, minutes: 40, on: day, createdAt: createdAt),
            routine(id: "meds", title: "Meds", hour: 21, minute: 30, recurrence: .daily, minutes: 5, on: day, createdAt: createdAt),
            routine(id: "gym", title: "Gym", hour: 18, minute: 0, recurrence: .custom, weekdays: [3, 5], minutes: 50, on: day, createdAt: createdAt),
            routine(id: "work", title: "Implement feature slice", hour: 9, minute: 30, recurrence: .weekdays, minutes: 90, on: day, createdAt: createdAt)
        ]
    }

    private func routine(
        id: String,
        title: String,
        hour: Int,
        minute: Int,
        recurrence: TaskRecurrence,
        weekdays: [Int]? = nil,
        minutes: Int,
        on day: Date,
        createdAt: Date? = nil
    ) -> LifeTask {
        var task = LifeTask(
            id: id,
            title: title,
            difficulty: title.contains("Implement") ? .hard : .easy,
            estimatedMinutes: minutes,
            requiredEnergy: title.contains("Implement") ? .high : .low,
            scheduledTime: clock(hour, minute, on: day),
            tags: ["daily-routine"],
            recurrence: recurrence,
            recurrenceWeekdays: weekdays,
            schedulingMode: .fixedTime,
            userId: userId,
            isRecurrenceTemplate: true
        )
        task.createdAt = createdAt ?? day
        if title.contains("Implement") {
            task.semanticProfile = TaskSemanticProfileBuilder.build(from: task)
        }
        return task
    }

    private func oneOff(id: String, title: String, on day: Date, hour: Int) -> LifeTask {
        LifeTask(
            id: id,
            title: title,
            status: .pending,
            estimatedMinutes: 15,
            scheduledDate: calendar.startOfDay(for: day),
            scheduledTime: clock(hour, 0, on: day),
            schedulingMode: .fixedTime,
            userId: userId
        )
    }

    private func taxSlices(starting day: Date) -> [LifeTask] {
        let root = LifeTask(
            id: "tax-root",
            title: "Tax packet",
            tags: [MultiDayTaskTags.root],
            userId: userId
        )
        let slices = (1...5).map { index -> LifeTask in
            let sliceDay = calendar.date(byAdding: .day, value: index - 1, to: day)!
            return LifeTask(
                id: "tax-\(index)",
                title: "Tax packet · Day \(index)",
                scheduledDate: sliceDay,
                scheduledTime: clock(15, 0, on: sliceDay),
                tags: [MultiDayTaskTags.slice],
                parentTaskId: root.id,
                userId: userId
            )
        }
        return [root] + slices
    }

    private func retargetGym(_ tasks: [LifeTask], weekdays: [Int]) -> [LifeTask] {
        tasks.map { task in
            guard task.id == "gym" else { return task }
            var copy = task
            copy.recurrenceWeekdays = weekdays
            return copy
        }
    }

    private func retargetWork(_ tasks: [LifeTask], hour: Int, minute: Int, on day: Date) -> [LifeTask] {
        retargetClock(tasks, id: "work", hour: hour, minute: minute, on: day)
    }

    private func retargetClock(_ tasks: [LifeTask], id: String, hour: Int, minute: Int, on day: Date) -> [LifeTask] {
        tasks.map { task in
            guard task.id == id else { return task }
            var copy = task
            copy.scheduledTime = clock(hour, minute, on: day)
            return copy
        }
    }

    private func move(_ id: String, in tasks: [LifeTask], to day: Date, hour: Int, minute: Int) -> [LifeTask] {
        tasks.map { task in
            guard task.id == id else { return task }
            var copy = task
            copy.scheduledDate = calendar.startOfDay(for: day)
            copy.scheduledTime = clock(hour, minute, on: day)
            return copy
        }
    }

    private func rename(_ id: String, in tasks: [LifeTask], title: String) -> [LifeTask] {
        tasks.map { task in
            guard task.id == id else { return task }
            var copy = task
            copy.title = title
            return copy
        }
    }

    private func setStatus(_ id: String, in tasks: [LifeTask], status: TaskStatus, clearCompletion: Bool = false) -> [LifeTask] {
        tasks.map { task in
            guard task.id == id else { return task }
            var copy = task
            copy.status = status
            if clearCompletion { copy.completedAt = nil }
            if status == .completed, copy.completedAt == nil { copy.completedAt = Date() }
            return copy
        }
    }

    private func todayTask(_ tasks: [LifeTask], title: String? = nil, titlePrefix: String? = nil, on day: Date) -> LifeTask? {
        tasks.first { task in
            guard task.status.isActive, !task.isRecurrenceTemplateTask else { return false }
            let nameMatches = title.map { task.title == $0 } ?? titlePrefix.map { task.title.hasPrefix($0) } ?? false
            guard nameMatches else { return false }
            let scheduled = task.scheduledDate ?? task.scheduledTime
            return scheduled.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        }
    }

    private func complete(_ id: String, in tasks: [LifeTask], at now: Date) -> [LifeTask] {
        tasks.map { task in
            guard task.id == id else { return task }
            var copy = task
            copy.status = .completed
            copy.completedAt = now
            return copy
        }
    }

    private func skip(_ id: String, in tasks: [LifeTask]) -> [LifeTask] {
        tasks.map { task in
            guard task.id == id else { return task }
            var copy = task
            copy.status = .skipped
            return copy
        }
    }

    private func clock(_ hour: Int, _ minute: Int, on day: Date) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.startOfDay(for: day))!
    }

    private func isWeekday(_ weekday: Int) -> Bool {
        weekday != 1 && weekday != 7
    }

    private func expectOne(_ events: [LifeTimelineEvent], title: String, day: Int, failures: inout [String]) {
        let count = events.filter { $0.title == title }.count
        if count != 1 {
            failures.append("D\(day): expected 1 \(title), saw \(count)")
        }
    }
}
