# Timeline feature audit

**Document ID:** QA-TIMELINE-01  
**Date:** 9 September 2026  
**Observed wall clock (report):** 12:51 PM IST  
**Observed NOW marker:** 11:45 / Wind down  
**Status:** Review complete — see [timeline-complete-fix-plan.md](timeline-complete-fix-plan.md) for T-01–T-37 and implementation phases. No product code in this audit pass.

**Related:** [TimelineService](../../Packages/LookAfterFeatures/Sources/LookAfterFeatures/Timeline/TimelineService.swift), [LifeTimelinePresenter](../../Packages/LookAfterCore/Sources/LookAfterCore/Experience/LifeTimelinePresenter.swift), [TimelineNowResolver](../../Packages/LookAfterCore/Sources/LookAfterCore/Experience/TimelineNowResolver.swift), [DaySchedulePlanner](../../Packages/LookAfterCore/Sources/LookAfterCore/Planning/DaySchedulePlanner.swift), [ConflictResolutionCascade](../../Packages/LookAfterCore/Sources/LookAfterCore/Planning/ConflictResolutionCascade.swift)

---

## 1. What the timeline is

Today’s live timeline (`ExecutiveLiveTimelineView` on Today / Briefing) is **not** a clock-proportional day map. It is a **sorted list of derived events** with a green “NOW” badge attached to **one row**. The lime rail fill stops at that row’s dot, not at the minute-of-day.

That single design choice explains most of the “wrong time” and “why is NOW on Wind down?” reports.

---

## 2. Source of truth (how data is stored, moved, and read)

There are **four clocks** in play. They are not kept in lockstep.

| Layer | Owner | What it stores | Freshness |
|---|---|---|---|
| Disk | `TaskSQLiteStore` (`tasks.sqlite`, JSON blob per task) | Canonical `LifeTask` including `scheduledDate`, `scheduledTime`, `scheduledEndTime`, `timeConstraint`, `userPlacedScheduleAt` | Survives process death |
| Memory cache | `TaskRepository.cachedAll` | Same structs | Can race disk during `warmLocalCache` |
| Cloud | Firestore `tasks` | Sync copy | Can lag; not used for timeline paint |
| Schedule repair | `TasksViewModel.reconcileTodaySchedule` | Mutates times then `taskRepo.update` | Runs on load, AI plan apply, commitment assemble |
| Derived UI | `TimelineService.snapshot` + `todayRows` | `LifeTimelineEvent` / `ExecutivePlanningTimelineRow` | Rebuilt from **in-memory** `tasksVM.tasks`, not a live clock |

**Write path (simplified):**

1. Create / AI mutation / drag / complete → `TasksViewModel`  
2. Persist → SQLite (and later Firestore)  
3. `AppShellState.rebuildTimelineFromTasks` → `TimelineService.rebuild`  
4. `LifeTimelinePresenter.build` maps tasks (+ bills, shopping, meds, calendar, **synthetic Wind down**) → events  
5. `TimelineRowProjector.rows` stamps `isNow` / `isPast` using the `now` passed into rebuild  

**Life model (gym 6pm, office, dinner block)** lives separately in `LifeModelStore` (compiled markdown). Reconcile *snaps* commitment tasks to those blocks; the timeline never reads the life model directly.

### Dual date fields (recurring fault)

`scheduledDate` is start-of-day. `scheduledTime` is a full `Date` whose **calendar day may not match** `scheduledDate` (especially recurrence materialization and “tomorrow” tasks). Several readers use one field and ignore the other:

- `IdealSleepPlanner.resolveTomorrowWakeAnchor` uses `task.scheduledTime` as the wake instant **without combining it onto tomorrow**.
- `groupedFinanceSession` uses `scheduledTime ?? scheduledDate` as a comparable instant.
- Drag offset (`TimelineConstraintViewModel.commitScheduleOffset`) adds the minute delta to **both** `scheduledTime` and `scheduledDate`.

---

## 3. Reported issues — root cause

### 3.1 Dinner (and similar) can move to morning

**Expected:** Dinner stays in the evening fence (about 17:00–21:00). Gym stays at the life-model block (6:00 PM).

**Actual paths that ignore the fence:**

| Path | File | Fault |
|---|---|---|
| Day planner phase 2 | `DaySchedulePlanner` → `DaySlotAllocator` | Meals are `treatAsFixed: false`, so they are allocated inside **office/creative work hours** (typically 9–18). 19:00 dinner **does not fit** office hours, so the allocator places it in the next open morning/afternoon slot. |
| Allocator fit test | `DaySlotAllocator.fits` | Checks work-hour bounds and occupied intervals only. **Does not** call `TaskReaper.allowsStart` / `TemporalBoundingBox`. |
| AI mutations | `PlanMutationApplier.isScheduleLocked` | Locks gym / life commitments / fixed events. **Meals are not locked.** `createTask` duplicate-match and `rescheduleTask` can move Dinner to any validated window hour. |
| Timeline drag | `TimelineConstraintViewModel.commitAbsoluteStart` | Writes `proposedStart` with **no bounding-box check**. Then `markUserPlaced` so `shouldRestore` **will not** snap Dinner back. |
| Drift correction bail-out | `TasksViewModel.correctRoutineScheduleDrift` | If Dinner’s 19:00 anchor overlaps an anchored blocker (gym 18:30–20:00), restore is **skipped**, leaving the drifted morning slot. |

Bounding boxes **do** exist (`TaskEphemeralityDefaults.boundingBox`: dinner 17–21, lunch 11–15, breakfast 5–11). The cascade uses them on **shift**. The allocator, AI applier, and drag **do not**.

**Reproduce:** Day with office 9–5, Dinner 19:00, Gym 18:00. Force a full replan (`requestForceReplan` / Plan). Dinner is a movable leftover → slotted into 10:00-class office time.

---

### 3.2 Multiple tasks at the same clock

Overlap can still appear on the timeline even after cascade work.

| Path | Fault |
|---|---|
| Planner phase 1 | `appendSlot(..., allowOverlap: true)` for meals so dinner can be planted **on top of** gym, hoping cascade will fix it. If cascade parks/expires the meal instead of shifting, the **original overlapping times remain** on the synthetic set until persist. |
| Planner phase 1 drop | Overlapping anchored slots are **silently discarded** from `slots` (`if occupied.contains overlap { return }`). The loser’s **original** `scheduledTime` is left on the task if it is not movable, then cascade must repair. |
| `isNow` / display | Two events can share `date` (both `when = startOfDay` for unslotted flexibles). The rail shows two cards with the same or empty time. |
| Shopping / finance grouping | Synthetic events (`shopping-trip`, grouped finance) are dated with `schedulingCursor` / next hour **without** occupying a real task interval, so they sit on top of real work. |
| Calendar + tasks | Calendar events are appended as `.meeting` with `isFixed: true` and **never run through** `ConflictResolutionCascade`. A 12:00 calendar block and a 12:00 task both paint. |
| Drag | No overlap test on commit. User (or a bad snap) can drop onto an occupied row. |

Cascade now shifts overlapping anchored losers (prior fix). That does **not** cover calendar events, shopping grouping, or allocator-created morning dinners that never enter cascade as collisions if they were placed in an empty morning slot.

---

### 3.3 Green NOW on “Wind down” while important work is unfinished

**NOW is not “what I should be doing.”** `TimelineNowResolver.currentEventIndex` picks:

1. First **slotted** event whose `[start, end]` contains `now`.  
2. Else, if `now` is in a gap, the first **unslotted flexible**.  
3. Else the first **future** slotted event (`date > now`).  
4. Else any remaining unslotted flexible.

Incomplete work whose **window already ended** is skipped (it is neither in-window nor future). Incomplete work that is **unslotted** (`when = startOfDay`, `scheduleKind = flexibleDay`) is skipped in step 1.

If nothing is in-window, step 3 selects the next future slotted event. The only remaining synthetic slotted event at the end of the list is often **`Wind down · Sleep`** (`DayBoundaryPlanner.sleepTimelineEvent`, id `sleep-boundary-*`).

So at 12:51 PM, with overdue morning tasks still pending:

- Those tasks are `isPast` (end < now) or unslotted.  
- NOW jumps to tonight’s wind-down row.  
- The lime rail paints to that row.  
- The card shows the NOW chip.

Wind-down is also **sorted last regardless of its clock** (`TimelineDisplaySort` always puts `sleep-boundary` after other events). Combined with step 3, it is the default “future” target.

`IdealSleepPlanner.recommend` is invoked from `DayBoundaryPlanner` with `showFromHour: 0`, so a bedtime row is injected **all day**, not only after 17:00. Tomorrow’s wake uses raw `scheduledTime` (see §2), which can compute a **morning** bedtime (e.g. 11:45 AM) if an evening `scheduledTime` is treated as tomorrow’s wake.

---

### 3.4 NOW pointing at 11:45 when the clock is 12:51

Three independent mechanisms produce this; they can stack.

**A. NOW is bound to a row’s start label, not wall clock.**  
If any event window contains 12:51 (e.g. a block that started 11:45 with duration ≥ 66 minutes, or office work whose display duration is the full remaining block), the green dot sits on that row. The time column still prints **11:45**, not 12:51. There is **no interpolation** of Y by minutes inside the block (`progressLineEndY` uses the current row’s dot center only).

**B. `isNow` is stamped at rebuild and does not tick.**  
`TimelineService.rebuild(now:)` defaults to `Date()` at rebuild. `todayRows[].isNow` is a stored bool. `ExecutiveLiveTimelineView` has **no timer**. The 60s `startContextLoop` *does* call `refreshContext` → `rebuildTimelineFromTasks`, but that loop **returns forever** if a refresh is in flight (`isContextRefreshInFlight`) or a focus session is active. A skipped tick leaves NOW frozen at the last successful rebuild (e.g. 11:45).

**C. Wrong bedtime painted as 11:45 AM.**  
If `IdealSleepPlanner` treats today’s 8:30 PM `scheduledTime` as tomorrow’s wake:  
`20:30 − 45m − 8h ≈ 11:45 AM` today. Wind-down’s time column shows 11:45. Combined with §3.3, NOW can sit on that row.

There is **no live “12:51 PM” needle**. Users reasonably read the NOW row’s time label as “what time the app thinks it is.”

---

## 4. Additional faults (same feature graph)

Severity: **P0** user-visible schedule/NOW wrong; **P1** data integrity; **P2** display/consistency.

| ID | Sev | Fault | Where |
|---|---|---|---|
| T-05 | P0 | Drag commit does not check bounding box, overlap, or protected gym window | `TimelineConstraintViewModel.commitAbsoluteStart` |
| T-06 | P1 | Drag offset mutates `scheduledDate` by the same minute delta as the clock (can cross midnight / desync day vs time) | `commitScheduleOffset` |
| T-07 | P0 | `markUserPlaced` after drag permanently disables routine restore | `TaskConstraintAlignment` + `shouldRestore` |
| T-08 | P1 | Tomorrow wake anchor uses `scheduledTime` without `combine(date:tomorrow)` | `IdealSleepPlanner.resolveTomorrowWakeAnchor` |
| T-09 | P1 | Wind-down injected from 00:00 via `showFromHour: 0` | `DayBoundaryPlanner.recommendedBedtime` |
| T-10 | P1 | Shopping trip without a scheduled task is dated at `schedulingCursor` (now+15 in work hours) and can steal NOW | `LifeTimelinePresenter.groupedShoppingTrip` |
| T-11 | P1 | Grouped finance dates from raw `scheduledTime` or “next clock hour” | `groupedFinanceSession` |
| T-12 | P1 | Calendar events never go through overlap cascade | `LifeTimelinePresenter.build` |
| T-13 | P2 | `DateFormatter` in `TimelineRowProjector` has no `timeZone` / `calendar` set (OK until a non-current calendar is passed elsewhere) | `TimelineService.swift` |
| T-14 | P1 | Unslotted tasks get `when = startOfDay` (midnight). Projector then special-cases 12:00 AM labels. Fragile; easy to show empty “—” or steal sort order | `makeTaskEvent` |
| T-15 | P2 | `isPast` uses `resolvedEndDate()` (subtitle parse / estimatedMinutes) which can disagree with stored `scheduledEndTime` | `TimelineRowProjector.row` |
| T-16 | P1 | `TimelineRowProjector.applyPatch(.rescheduled)` recomputes `isNow` with a **new** `Date()` but patch path can skip full presenter rebuild — mixed clocks | `TimelineService.applyPatch` |
| T-17 | P2 | Suggested-slot rows (`suggested-*`) are display-only; completing/dragging them can no-op or hit missing task IDs | `suggestedSlotRows` |
| T-18 | P1 | `TaskRepository.warmLocalCache` vs concurrent save: documented race; timeline can rebuild from stale `tasksVM` if snapshot applied out of order | `Repositories.swift` |
| T-19 | P2 | Timeline and Briefing hero use different “now” stories (hero via `ContextOrchestrator`, timeline via last rebuild) | `AppShellState.refreshContext` vs `refreshBriefingSurface` (briefing refresh **does not** rebuild timeline) |
| T-20 | P1 | `refreshBriefingSurface` explicitly skips schedule reconcile — user can pull Briefing while Today still shows old NOW | `AppShellState.swift` |

---

## 5. Connections to other features

```
LifeModelStore ──► DayAssembler / Reconcile snap
UserLifeProfile ──► SchedulingWindows, IdealSleepPlanner
TasksViewModel ──► TimelineService ──► Today rail, widgets, Live Activity, pin-to-lock
PlanMutationApplier / DayReplanEngine ──► same task rows
HealthSync / Brain ──► Briefing copy only (does not move clocks)
CalendarChangeDetector ──► reads timeline events; does not write times
```

Widgets and lock-screen NOW (`WidgetSyncService`, `TimelineNowResolver.currentNowEvent`) use the **same** frozen snapshot. A wrong NOW on Today is a wrong NOW on the widget until the next rebuild.

---

## 6. Test gaps

Existing coverage is row projection and sort, not the user-visible clock:

- `TimelineServiceTests` — slotted vs unslotted labels; no `isNow` vs wall clock.  
- `TimelineDisplaySortTests` — picks a current event in a fixture; no overdue-unfinished → wind-down case.  
- `DaySlotAllocatorTests` — work-hour placement; **no meal bounding box**; gym protection added recently for windows only.  
- No test that Dinner 19:00 survives `DaySchedulePlanner.plan` when office hours end at 18:00.  
- No test that `currentEventIndex` at 12:51 with incomplete 10:00 work does **not** return wind-down.  
- No test that NOW Y interpolates inside a 11:45–13:00 block.  
- No test that drag of Dinner to 10:00 is rejected.

---

## 6b. Second hunt (T-21–T-37)

See the [complete fix plan](timeline-complete-fix-plan.md) §3. Highlights:

- Completing NOW drops the chip and leaves widgets stale (T-21, T-22).
- Midnight **end** is treated as a date-only placeholder (T-23).
- Production rebuild never passes calendar events (T-25); the day filter also admits tomorrow (T-26).
- DayAssembler skips today’s Gym when any series match has `scheduledDate == nil` (T-29).
- Meds cache bypass (T-33); bills at midnight steal NOW (T-34).
- Former out of scope now in plan: clock-proportional rail (T-35), cloud/local merge (T-36), health/briefing NOW (T-37).

---

## 7. Recommended fix order

1. **NOW semantics (P0):** Treat overdue incomplete slotted work as current (or a dedicated “late” state). Never select `sleep-boundary` as NOW before 17:00 local, and never while incomplete non-recovery tasks remain. Drive the rail from **wall clock** (`Timeline` + 30s tick calling `projectRows(now: Date())`).  
2. **Meal / gym physics (P0):** Allocate meals in their bounding box, not office hours. Keep gym `never_schedule` occupied in `DaySlotAllocator`. Reject AI and drag placements outside the box unless the user confirms. Do not `markUserPlaced` for semantic meals unless the drop is inside the fence.  
3. **Overlap invariant (P0):** After every persist path (planner, cascade, drag, AI, calendar merge), `DayScheduleReconciler.hasOverlap == false` for the day. Include calendar and shopping synthetics or stop painting them as timed peers.  
4. **Sleep planner (P1):** Combine tomorrow’s date with time-of-day; keep `showFromHour: 17` for the wind-down **row**, or hide the row until evening.  
5. **Drag date math (P1):** Offset must not add minutes to `scheduledDate`; only time-of-day. Combine with `calendar.combine`.

---

## 8. Manual verification (device)

1. Set Dinner 7:00 PM, Gym 6:00 PM, a 45-minute work task at 11:45 AM. Leave the work task incomplete. At ~12:51 PM, NOW must **not** be Wind down; time column must not imply the device clock is 11:45 unless that block is still in progress — and if it is, the rail should sit **partway** through the block, not on the 11:45 label as “the time.”  
2. Trigger Plan / replan. Dinner must remain evening. No two cards may share a start minute.  
3. Drag Dinner toward 10:00 AM — drop should snap back or refuse.  
4. Wait 10 minutes without editing tasks; NOW must advance without a full app relaunch.
