# Day planning & scheduling subsystem audit

**Document ID:** QA-PLANNING-01
**Related:** [DayAuditService](../../Packages/LookAfterCore/Sources/LookAfterCore/Planning/DayAudit/DayAuditService.swift), [DaySchedulePlanner](../../Packages/LookAfterCore/Sources/LookAfterCore/Planning/DaySchedulePlanner.swift), [DayScheduleReconciler](../../Packages/LookAfterCore/Sources/LookAfterCore/Planning/DayScheduleReconciler.swift), [ConflictResolutionCascade](../../Packages/LookAfterCore/Sources/LookAfterCore/Planning/ConflictResolutionCascade.swift), [DaySlotAllocator](../../Packages/LookAfterCore/Sources/LookAfterCore/Planning/DaySlotAllocator.swift), [DayAuditApplier](../../Packages/LookAfterFeatures/Sources/LookAfterFeatures/Planning/DayAuditApplier.swift), [TasksViewModel](../../Packages/LookAfterFeatures/Sources/LookAfterFeatures/Tasks/ViewModels/TasksViewModel.swift)

---

## 1. How a task's schedule is kept and moved

Five independent engines write `scheduledDate` / `scheduledTime` / `scheduledEndTime` on the same `LifeTask`, at different call sites, with different invariants:

| Engine | Trigger | Invariant it enforces |
|---|---|---|
| `DaySchedulePlanner.plan/apply` | `TasksViewModel.reconcileTodaySchedule` (planner branch) | Snap anchored/user-placed, then allocate remaining via `DaySlotAllocator`, then cascade-resolve overlaps on a **synthetic** copy |
| `DayScheduleReconciler.reconcile` | Legacy branch of `reconcileTodaySchedule`, `resolveOverlapsIfNeeded`, `DayAuditApplier.apply` (final step) | Sync commitment blocks, then run `ConflictResolutionCascade` |
| `ConflictResolutionCascade.resolve` | Called by both of the above | Anchored > flexible > fluid triage: keep / shift / compress / defer / park / expire / supersede |
| `TimelineConstraintViewModel` (drag / offset) | User gesture | `SchedulePlacementGuard.evaluate` then direct field writes, bypassing the cascade entirely |
| `RoutineScheduleAnchorResolver` / `applyRoutineAnchorRepair` | `repairMidnightPlaceholderSchedules` | Restores placeholder/midnight-scheduled routines to a resolved anchor |

Because these five write paths do not share one "commit" function, a task can be valid to one engine and invalid to another at the moment it is displayed.

---

## 2. Findings — root cause per bug

### 2.1 Planner Phase 1 can seed overlapping anchored slots

`DaySchedulePlanner.plan` Phase 1 (`for task in active`) appends every anchored/user-placed task's slot via `appendSlot`, tracking `occupied` only **within Phase 1's own loop**. Two anchored tasks (e.g. a user-placed 9:00 event and a life-model anchor also resolving to 9:00) are both appended before any overlap check runs against each other — the overlap is only discovered later in Phase 3 when the cascade runs on the synthetic set. Until that cascade completes, `DaySchedulePlanner.apply` may persist times that momentarily coexisted as overlapping in `slots` before `slotResolvesOverlap` re-diffed them (`DaySchedulePlanner.swift:158-180`).

**Root cause:** Phase 1 has no early overlap rejection; it depends entirely on Phase 3 cascade to retroactively fix what Phase 1 already committed to `slots`.

### 2.2 `ConflictResolutionCascade` silently skips tasks with no resolvable window

`resolve()` calls `TaskScheduleInterval.window(for:on:calendar:)` per task and does `continue` when it returns `nil` (`ConflictResolutionCascade.swift:166-168`). `window` returns `nil` for placeholder-midnight schedules (`isPlaceholderMidnightSchedule`) **and** whenever `scheduledDate`'s day doesn't match, or `scheduledTime` is missing. These skipped tasks are left in `byID` unchanged — no `keep`/`park`/`expired` decision is recorded, and they are never added to `blocked`, so a later task in the same loop can be placed directly on top of a skipped task's real (but un-windowed) time.

**Root cause:** "no window" is treated as "ignore" rather than "needs anchor repair before cascade," letting stale/placeholder-timed tasks silently coexist with newly placed ones.

### 2.3 `DayScheduleReconciler` reconcile trigger misses non-overlap regressions

In `TasksViewModel` (legacy branch, ~line 2066-2107), reconcile only runs when `commitmentDrift` is true or `DayScheduleReconciler.hasOverlap` is true. A task that has drifted outside its `TemporalBoundingBox` (e.g. dinner slid to 10:00 AM by an AI mutation or drag) but does **not** currently overlap anything is never picked up by this gate — `hasOverlap` only detects clashes between tasks/calendar, not box violations. `RoutineScheduleAnchorResolver.shouldRestore` exists to catch this, but it is invoked only from `repairMidnightPlaceholderSchedules`/`applyRoutineAnchorRepair`, which is gated by `needsRoutineAnchorRepair` — itself only true for placeholder-midnight or no-clock-time named routines, not for a task that already has a concrete (but fence-violating) clock time.

**Root cause:** overlap and bounding-box validity are treated as separate, non-overlapping trigger conditions; a fence violation with no clock collision falls through every reconcile gate.

### 2.4 `DayAuditApplier` pull-parked/pull-yesterday fixes ignore the fix's own metadata

`DayAuditApplier.apply` switches on `fix.kind` for `acceptedFixes`, and for `.pullParked, .pullYesterday` does nothing (`break`) — the actual pull is instead re-derived from a **separate** `selectedPulls` array matched by `pull.origin` (`.parked/.fluid/.yesterday`). If a caller ever adds a `DayAuditFix` of kind `.pullParked`/`.pullYesterday` to `acceptedFixes` without also adding a matching `DayAuditPullCandidate` to `selectedPulls`, the accepted fix is silently dropped with no error and no persisted change. `DayAuditService.run` never actually returns fixes of `.pullParked/.pullYesterday` kind today (pulls only ever flow through `possiblePulls`), so this is currently dead/defensive code — but it is a latent trap for any future caller that assumes accepting the fix is sufficient.

**Root cause:** two parallel data shapes (`DayAuditFix.kind` vs `DayAuditPullCandidate.origin`) represent the same "bring this task into today" action, and only one of them is actually wired to a mutation.

### 2.5 Dual date/time fields diverge across engines (recurring pattern)

Consistent with the timeline audit (`Documentation/qa/timeline-feature-audit.md` §2), every planning engine reads `scheduledTime` as an absolute `Date` and separately reads `scheduledDate` as the calendar-day anchor, then re-combines them per-call (`calendar.combine(date:timeFrom:)`). `TaskScheduleInterval.window` does this combine once; `SchedulePlacementGuard.evaluate` does it again independently using `task.scheduledDate ?? proposedStart` as the day. If a caller updates `scheduledTime` to a new absolute Date (which carries its own day component) without also updating `scheduledDate`, the two combine sites can disagree on which day the resulting interval falls on, since `combine` uses `scheduledDate` for day-of and `scheduledTime` only for hour/minute — but callers occasionally pass `scheduledTime` directly as `proposedStart` (e.g. `IdealSleepPlanner.resolveTomorrowWakeAnchor`, per the timeline audit) which conflates the two.

**Root cause:** no single "canonical instant" accessor exists; every engine hand-rolls date+time combination with slightly different fallback rules.

### 2.6 `DaySlotAllocator` does not consult `TaskEphemeralityDefaults.boundingBox` directly

`isSearchableSlot` (`DaySlotAllocator.swift:369-381`) delegates fence-checking entirely to `SemanticPlacementSense.judge`, whose bounding-box check (`SemanticPlacementSense.swift:95-97`) only rejects when a box exists **and** the proposed start falls outside it — but the allocator's `fits`/`advancePastBlocks` cursor logic that generates candidate `start` values in the first place is driven purely by `workHours` (office/creative hours), not the task's own box. For non-meal tasks with a box but low semantic confidence, or where `hourBounds`/`workHours(forBox:)` diverges from the office-hours cursor range, the allocator can spend its entire candidate search inside office hours and never present a candidate inside the task's real box, resulting in the task being parked/deferred rather than placed in its (unreached) valid window.

**Root cause:** the search-space cursor and the acceptance test use two different notions of "valid hours" (`workHours` vs. per-task `boundingBox`), so validation and search are not aligned.

---

## 3. Fix plan

| ID | Sev | Fix | File |
|---|---|---|---|
| P-01 | P0 | Phase 1 of `DaySchedulePlanner.plan` must check `occupied` before `appendSlot` for anchored/user-placed tasks and defer the loser to Phase 2/3 instead of appending an overlapping slot | `DaySchedulePlanner.swift` |
| P-02 | P0 | `ConflictResolutionCascade.resolve` must not `continue` silently on `window == nil`; either route the task through `RoutineScheduleAnchorResolver` first or emit a `park`/`expired` decision so it is not left as an invisible collision risk | `ConflictResolutionCascade.swift` |
| P-03 | P0 | Add a bounding-box validity check (not just overlap) as a reconcile trigger in `TasksViewModel.reconcileTodaySchedule`'s legacy branch, using `RoutineScheduleAnchorResolver.shouldRestore` against the active pool, not only placeholder/no-clock-time routines | `TasksViewModel.swift` |
| P-04 | P1 | Either wire `DayAuditFix.pullParked/.pullYesterday` to perform the same mutation as the matching `selectedPulls` entry, or remove the dead cases and assert `DayAuditService` never emits them, to remove the parallel-data-shape trap | `DayAuditApplier.swift`, `DayAuditService.swift` |
| P-05 | P1 | Introduce one canonical `LifeTask.scheduledInstant(calendar:)` accessor that combines `scheduledDate` + `scheduledTime` once, and migrate `TaskScheduleInterval.window`, `SchedulePlacementGuard.evaluate`, and `IdealSleepPlanner` to use it instead of re-implementing `combine` | `TaskScheduleInterval.swift`, `SchedulePlacementGuard.swift`, `IdealSleepPlanner.swift` |
| P-06 | P1 | Align `DaySlotAllocator`'s candidate-cursor range with `SemanticPlacementSense.hourBounds(for:)` per task (fall back to `workHours` only when no box/profile bounds exist) instead of always cursoring within office hours | `DaySlotAllocator.swift` |

---

## 4. Test gaps

- No test that two anchored tasks resolving to the same start time in Phase 1 are separated before `DaySchedulePlanner.apply` persists.
- No test for `ConflictResolutionCascade.resolve` with a placeholder-midnight task colliding with a newly-cascaded task at the same real clock time.
- No test that a fence-violating (but non-overlapping) task is corrected by `reconcileTodaySchedule` without depending on `needsRoutineAnchorRepair`'s midnight/no-clock-time gate.
- No test that `DayAuditFix(kind: .pullParked)` in `acceptedFixes` without a matching `selectedPulls` entry either performs the pull or is rejected loudly (currently silent no-op).
- No test that `DaySlotAllocator` finds a valid slot for a boxed task whose box falls entirely outside `workHours`.
