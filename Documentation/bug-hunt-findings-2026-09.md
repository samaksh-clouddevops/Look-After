# Functional Bug Hunt Findings — Wave 1

**Scope:** Persistence, Identity, Task Domain, and cache-warming/CRUD lifecycle.
No production code was modified during this investigation.

## Summary

| Severity | Bug | Status | Details |
|---|---|---|---|
| CRITICAL | Cold-launch task creation before cache warm-up wipes the entire local task table | CONFIRMED | See `Documentation/critical-bug-cold-launch-task-loss-2026-09.md` |
| HIGH | Tasks with empty `userId` are visible to every user on a shared device | POSSIBLE — needs Wave 2 confirmation | See below |

## [HIGH] — Tasks with empty `userId` are visible to every user on a shared device

**Status:** POSSIBLE FUNCTIONAL BUG — insufficiently verified this wave
**Feature:** Task persistence / user isolation
**File:** `Packages/LookAfterData/Sources/LookAfterData/Repositories/Repositories.swift`, `tasksForUser(_:userId:)` (line 253-262)

**Exact location:**
```swift
return visible.filter { $0.userId.isEmpty || $0.userId == userId }
```

**Expected behavior:** A task belonging to User A must never be shown to User B.

**Actual behavior:** Any task whose `userId` field is empty is treated as belonging to *every* user and returned in `tasksForUser` regardless of which `userId` is requested.

**Trigger:** Any task ever persisted with `userId == ""` (e.g. `create()` falling through to `firebase.resolvedUserId` when that itself resolves empty — a guest/pre-auth edge case) remains in storage and becomes visible to whichever user is signed in next, including a different account on a shared/reused device.

**Preconditions:** A task gets written with an empty `userId` (plausible during guest mode before first sign-in, or a race during account bootstrap), and is not later reassigned via `reassignTasks`/`migrateAllTasksToCanonicalUserId`.

**Reproduction (needs confirmation):**
```text
1. Use the app in a state where firebase.currentUserId/resolvedUserId is empty
   (e.g. very early in app lifecycle) and create a task.
2. Confirm whether such a state is actually reachable in production (Wave 2 task).
3. If reachable: sign in as a different user on the same device.
4. Observe whether the empty-userId task appears in the second user's task list.
```

**Root cause:** The "empty userId = visible to all" filter appears intended as a bootstrap/migration convenience (so tasks created before the UID resolves aren't hidden from their eventual owner), but it does not get reconciled until `migrateAllTasksToCanonicalUserId()` runs, and in the meantime it is a cross-user data leak by design of the filter.

**User impact:** Potential privacy leak of task titles/content across accounts on a shared device, until migration reassigns the task.

**Confidence:** Medium — the leak condition in the filter is real and directly evidenced in code; what's unverified is how often `userId` can actually end up empty in production and how quickly `migrateAllTasksToCanonicalUserId()` runs relative to a second user's first load. Flagged for Wave 2 (Identity/Account agent) to trace all `create()` callers and confirm reachability.

**Suggested Regression Test:**
```text
Test: TaskRepository_EmptyUserIdTaskNotVisibleToOtherUser
1. Persist a task with userId == "".
2. Call tasksForUser(_:, userId: "userB").
Expected: task NOT included (or is auto-migrated to the canonical user first).
```

## Coverage Matrix (honest, Wave 1 only)

| Area | Files in scope | Reviewed (line-by-line) | Candidate Bugs | Confirmed Bugs |
|---|---:|---:|---:|---:|
| Task persistence core (`TaskSQLiteStore`, `TaskStore`, `Repositories.swift`) | 3 | 3 | 2 | 1 |
| Task/Inbox creation call sites (`TasksViewModel`, `InboxViewModel`, `AppShellState` bootstrap) | 3 (targeted sections) | partial | 0 additional | 0 |
| Identity (`AccountIdentity`, `GuestLocalIdentity`, sign-in coordinators, `LicenseManager`) | 6 | 0 | — | — |
| Scheduling (`FlowSchedulingEngine`, `TaskRecurrenceEngine`, `DaySchedulePlanner`, etc., ~35 files) | ~35 | 0 | — | — |
| AI (`GLMService`, `TaskAutoFiller`, `TaskImporter`, `TaskDecomposer`, `FlowDirector`, ~20 files) | ~20 | 0 | — | — |
| Everything else (Features UI, Integrations, Health, Notifications/Widgets, macOS, ~670 files) | ~670 | 0 | — | — |

## Unreviewed Areas (explicit, updated after Wave 2)

Not yet inspected: `LookAfterCore/Planning`, remaining `LookAfterAI` files (`Briefing`, `Flow/FlowDirector.swift`, `Memory`, `Profile/LifeModelCompiler.swift`, `Proxy`, `Security`, `Utilities/TaskAutoFiller.swift`, `TaskImporter.swift`, `TaskSemanticAnalyzer.swift`), `LookAfterFeatures` UI/ViewModels beyond Tasks/Inbox create paths, `LookAfterIntegrations`, `LookAfterHealth`, notifications/widgets/background tasks, and both `Apps/LookAfter-iOS` and `Apps/LookAfter-macOS` app-shell code beyond the bootstrap ordering traced above.

## Wave 2 — Scheduling Rules & GLM Core (no new confirmed bugs)

**Files reviewed line-by-line:**
- `Packages/LookAfterCore/Sources/LookAfterCore/Scheduling/FlowSchedulingEngine.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Scheduling/TaskRecurrenceEngine.swift` (726 lines, full)
- `Packages/LookAfterCore/Sources/LookAfterCore/Scheduling/Rules/ContinueTaskRule.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Scheduling/Rules/FixedTimeEventRule.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Scheduling/Rules/MeetingSoonRule.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Scheduling/Rules/LowEnergyRule.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Scheduling/Rules/DeepWorkWindowRule.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Scheduling/Rules/DeferralRule.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Scheduling/Rules/BatteryRule.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Scheduling/Rules/CalendarGapRule.swift`
- `Packages/LookAfterAI/Sources/LookAfterAI/GLM/Service/GLMService.swift` (594 lines, full)
- `Packages/LookAfterAI/Sources/LookAfterAI/Utilities/TaskDecomposer.swift`
- `Packages/LookAfterData/Sources/LookAfterData/Identity/AccountIdentity.swift`
- `Packages/LookAfterData/Sources/LookAfterData/Firebase/FirebaseManager.swift` (targeted sections: init, auth listener, `resolvedUserId`)
- `Packages/LookAfterData/Sources/LookAfterData/Firebase/GuestLocalIdentity.swift`

**Findings:**
- No new confirmed or candidate bugs in the 8 scheduling rules or `FlowSchedulingEngine` — rule ordering, hero-task overriding, and state mutation are internally consistent (verified `OccurrenceDayIndex` key derivation in `TaskRecurrenceEngine` against `templateTaskId`/`parentTaskId` semantics — no mismatch).
- `GLMService`: retry/fallback/key-rotation logic correctly distinguishes quota/rate-limit errors (retryable across keys/models) from other errors (thrown immediately) — no "reports success when it actually failed" pattern found. `TaskDecomposer` falls back to a single generic step on parse failure rather than throwing or silently losing the task — acceptable degraded-mode behavior, not a defect.
- **Reinforces existing HIGH finding:** tracing `FirebaseManager.resolvedUserId` / `AccountIdentity.resolved()` confirms `""` is a legitimately reachable return value during early cold launch (before Firebase Auth resolves, no `saved_user_uid`, no `currentUserId`), which is the precondition needed for the empty-`userId` cross-user visibility bug documented above.

## Wave 3 — Planning (`DaySchedulePlanner`) & AI Orchestration (`FlowDirector`)

**Files reviewed line-by-line:**
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/DaySchedulePlanner.swift` (256 lines, full)
- `Packages/LookAfterAI/Sources/LookAfterAI/Flow/FlowDirector.swift` (140 lines, full)
- `Packages/LookAfterCore/Sources/LookAfterCore/Scheduling/TimeConstraint.swift`, `TaskSchedulingHelpers.swift` (targeted: `isSchedulerMovable`)
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/DaySlotAllocator.swift`, `ConflictResolutionCascade.swift` (targeted: `resolve`, `canMove`, `allocateAcrossWindows`)

**Findings:**

### [MEDIUM] — Anchored/fixed tasks can silently vanish from a day's plan on anchor overlap

**Status:** CONFIRMED (by code trace; not yet reproduced at runtime)
**File:** `Packages/LookAfterCore/Sources/LookAfterCore/Planning/DaySchedulePlanner.swift`, `plan(...)` Phase 1 (lines 55–80) and `appendSlot` (lines 215–234)

**Mechanism:**
1. Phase 1 iterates `active` tasks in their incoming array order and calls `appendSlot` for each anchored/user-placed/structure-fixed task. `appendSlot` silently **drops** the slot (no-op, no error, no log) if it overlaps anything already in `occupied` (line 224: `if !allowOverlap, occupied.contains(where: { interval.overlaps($0) }) { return }`).
2. Phase 2 only picks up tasks not yet slotted **and** `isSchedulerMovable` (line 84: `remaining = active.filter { !slottedIDs.contains($0.id) && $0.isSchedulerMovable }`).
3. `isSchedulerMovable` is `false` for any task with `timeConstraintValue == .anchored` or `isLifeCommitmentTask` or `isFixedTimeEvent` (`TaskSchedulingHelpers.swift`).
4. Therefore, when two anchored/fixed tasks (e.g. two `LifeModel` commitment blocks, or a structural routine anchor colliding with a user-placed fixed event) overlap on the same day, whichever one is encountered **first** in the `active` array wins its slot; the second one is dropped by `appendSlot` in Phase 1 and is **not eligible** for Phase 2 (not movable) or Phase 3's cascade (cascade only operates on `synthetic.filter { $0.scheduledTime != nil }` — a task whose placement came purely from a structural anchor, not `task.scheduledTime`, never enters `synthetic` with a non-nil `scheduledTime` unless it already had one from a previous day). The task is simply **absent from `PlanResult.slots`** for that day, with no compression, no shift, no park, and no reasoning line recorded anywhere.

**Trigger conditions:**
- Two `LifeModel` commitments (e.g. gym + a recurring class) whose windows overlap on a given day.
- A structural routine anchor (e.g. `compiled.anchor(matching:)` for dinner) colliding with a user-placed fixed-time task at the same clock time.
- Any edit to `LifeModel`/`UserLifeProfile` that produces two `treatAsFixed` anchors with overlapping windows.

**Expected behavior:** Overlapping fixed commitments should be surfaced to the user (conflict banner, "You have two things at 6pm") or resolved deterministically (e.g. via `ConflictResolutionCascade`), not silently dropped.

**Actual behavior:** The losing anchored task disappears from the planned schedule for that day with no diagnostic trail — from the user's perspective, a real commitment (e.g. a gym class or a fixed medication reminder) simply does not show up on the timeline that day.

**User impact:** For safety/time-critical anchored tasks (e.g. medication with `.anchored` constraint, or fixed life commitments), silent disappearance from the schedule is worse than a visible conflict — the user has no indication anything was skipped.

**Confidence:** Medium-High — the control-flow trace is exact and reproducible from the code; not yet confirmed whether overlapping anchors are common in practice (depends on how often `DayStructureCompiler.compile` or user fixed-time entry produces true anchor collisions), so severity is capped at MEDIUM pending a concrete repro.

**Suggested Regression Test:**
```text
Test: DaySchedulePlanner_OverlappingAnchoredTasksBothIncludedOrFlagged
1. Build two LifeTasks with timeConstraint = .anchored (or isLifeCommitmentTask == true)
   whose scheduledTime/anchor windows overlap on the same day.
2. Call DaySchedulePlanner.plan(tasks:on:...).
3. Expected: both tasks appear in PlanResult.slots (possibly adjusted), OR the result
   surfaces a conflict/changedTaskIDs signal — NOT silent omission of one task with
   zero trace.
Actual (current code): the second task is absent from result.slots with no signal.
```

### FlowDirector.swift — no new findings

`FlowDirector.orchestrate(session:)` was read in full. Error handling in `fetchBriefing` swallows briefing-generation errors into an empty `FlowBriefingCopy()` (graceful degradation, consistent with `GLMService`/`TaskDecomposer` patterns already verified in Wave 2 — not a defect). Scheduling, confidence, and briefing are correctly threaded through `enrichedScheduling` before being passed to `FlowSurfaceBuilder`. No state mutation ordering issues found; `isOrchestrating`/`surface` are updated on the `@MainActor` as expected.

**Coverage still open after Wave 3:** most of `LookAfterCore/Planning` (40+ files: `DaySlotAllocator` internals, `ConflictResolutionCascade` internals beyond `canMove`/`resolve` signature, `Proactive/*` 20 files, `Recovery/*`, `DayAudit/*`), remaining `LookAfterAI` (`Briefing`, `Memory`, `Profile/LifeModelCompiler.swift`, `Proxy`, `Security`, `Utilities/TaskAutoFiller.swift`, `TaskImporter.swift`, `TaskSemanticAnalyzer.swift`), `LookAfterFeatures` UI/ViewModels, `LookAfterIntegrations`, `LookAfterHealth`, notifications/widgets, macOS shell.

## Wave 4 — Proactive Orchestration, AI Utilities, Memory, DayAudit (no new confirmed/candidate bugs)

**Files reviewed line-by-line:**

- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/Proactive/ProactiveOrchestrator.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/Proactive/CircuitBreakerAnalyzer.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/Proactive/WaitingModeAnalyzer.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/Proactive/ProactiveDismissStore.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/DayAudit/DayAuditService.swift` (318 lines, full)
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/ParkedTaskQueue.swift` (323 lines, full)
- `Packages/LookAfterAI/Sources/LookAfterAI/Utilities/TaskAutoFiller.swift`
- `Packages/LookAfterAI/Sources/LookAfterAI/Utilities/TaskImporter.swift`
- `Packages/LookAfterAI/Sources/LookAfterAI/Utilities/TaskSemanticAnalyzer.swift`
- `Packages/LookAfterAI/Sources/LookAfterAI/Profile/LifeModelCompiler.swift`
- `Packages/LookAfterAI/Sources/LookAfterAI/Memory/SemanticMemoryStore.swift`

**Findings:**

- No new confirmed or candidate functional bugs. `ProactiveOrchestrator.analyze` correctly fuses all sub-analyzers, dedupes by `kind+message`, and ranks/limits deterministically; `ADHDProactiveRouting.rankFiltered` runs before dedupe/limit so ordering is preserved correctly.
- `ParkedTaskQueueStore` is correctly thread-safe: all mutation methods take the `NSLock`, copy the envelope to a local `snap`, release the lock, then persist `snap` outside the critical section — no lock held during file I/O, no torn-read risk.
- `DayAuditService.run` composes overlap/fit/proactive/capacity/pull-candidate faults deterministically with hard caps (`maxQuestions`, `maxPulls`, fault dedupe capped at 8) — no unbounded growth or ordering bug found.
- `TaskAutoFiller`, `TaskImporter`, `TaskSemanticAnalyzer`, `LifeModelCompiler` all follow the same safe pattern already validated for `TaskDecomposer` in Wave 2: strip code fences, parse JSON defensively with per-field fallback defaults, and degrade gracefully (generic step / empty result / local-compile fallback) rather than corrupting state on a bad/missing AI response. `LifeModelCompiler.compile` correctly falls through `.standard` → `.premium` → local heuristic compile without ever returning a nil/undefined model.
- **Minor (non-functional) observation, not filed as a bug:** `ProactiveDismissStore`'s `dismissedKindsKey` `Set<String>` in `UserDefaults` only shrinks on `resetForFactoryReset()` — daily dismiss records (`"\(kind)|\(dayKey)"`) accumulate indefinitely with no pruning of old day-keys. This is unbounded `UserDefaults` growth over long app lifetimes, not a correctness defect (old entries are simply inert), so it is noted but not tracked as a bug.

**Coverage still open after Wave 4:** `DaySlotAllocator.allocate` internals (buffer/gap-finding logic itself, not just its callers), `ConflictResolutionCascade.resolve` full 370-line body beyond the traced Stage 0/pool-filter/keep paths, remaining `Proactive/*` files (`ADHDProactiveRouting`, `CalendarChangeDetector`, `CaptureClusterAnalyzer`, `CaptureResurrectionAnalyzer`, `CrossDomainFusionAnalyzer`, `DeferralRecoveryWeeklyAgent`, `ExperimentFollowThroughDetector`, `InitiationBridgeDetector`, `PatternCoachAnalyzer`, `ProactiveFeedbackStore`, `ProactiveNotificationAdapter`, `ProactiveSnapshotStore`, `TransitionShieldBuilder`, `WakeRecoveryDetector`, `WeekPrimerDetector`, `Agents/*`), `Recovery/*`, `Travel/TravelDisruptionDetector.swift`, `LookAfterAI/Briefing`, `Proxy`, `Security`, `LookAfterFeatures` UI/ViewModels, `LookAfterIntegrations`, `LookAfterHealth`, notifications/widgets, macOS shell.

## Wave 5 — `DaySlotAllocator`, `ConflictResolutionCascade` (full), Proactive Detectors, Orchestrator Fan-in (no new confirmed bugs)

**Files reviewed line-by-line:**

- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/DaySlotAllocator.swift` (403 lines, `allocate` entry + slot search)
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/ConflictResolutionCascade.swift` (578 lines, full — all 5 stages: shift/compress/ephemeral-kill/defer/park, `rank`, `canMove`, `canCompress`, `canDefer`, `findOpenStart`, `findCompressibleGap`, `findNextAvailableGap`)
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/Proactive/TransitionShieldBuilder.swift` (full)
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/Proactive/InitiationBridgeDetector.swift` (full)
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/Proactive/WakeRecoveryDetector.swift` (full)
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/Proactive/ProactiveOrchestrator.swift` (full, `analyze`/`dedupe`/`topBannerAction`)
- `Packages/LookAfterFeatures/Sources/LookAfterFeatures/Planning/ProactiveActionsBuilder.swift` (full, app-layer fan-in on top of `ProactiveOrchestrator`)

**Findings:**

- No new confirmed or candidate functional bugs.
- **Cross-check confirms the existing Wave 3 finding (overlapping anchored tasks silently dropped):** `ConflictResolutionCascade.resolve` itself is *capable* of correctly resolving overlaps for anchored tasks — Stage 1 (`shiftLater`) is gated only by the domino-dampener counter (`allowShift`) and `TaskReaper.allowsStart`, **not** by `canMove(task)`, so an anchored task that loses a same-day collision inside the cascade can still be shifted later, compressed (blocked for anchored via `canCompress`), or parked. This confirms the Wave 3 bug is specifically that `DaySchedulePlanner` Phase 1 never routes anchored-vs-anchored overlaps into this cascade at all — the repair mechanism exists and works, it's just unreachable for that specific collision shape. No update needed to the Wave 3 write-up; this is corroborating evidence, not a new bug.
- `ConflictResolutionCascade.resolve` correctly copies `byID[$0.id] ?? $0` at every exit path (expire/supersede/keep/shift/compress/defer/park) and merges via `tasks.map { byID[$0.id] ?? $0 }` at the end — no task is ever dropped from the final `merged` array, including ones left `unresolved_window_no_anchor` (explicitly kept, not silently omitted, per the code comment at line 181-186).
- `DaySlotAllocator.allocate`'s cursor/blocked-interval bookkeeping is internally consistent: `blocked` and `cursor` are both updated after each placement in lockstep (`blocked.append` + `advancePastBlocks`), and requests are sorted deterministically (priority desc, then preferred-start asc, then id asc) so allocation order is reproducible.
- `ProactiveOrchestrator.analyze` and `ProactiveActionsBuilder.analyze` both apply `ADHDProactiveRouting.rankFiltered` → `dedupe` (by `kind.rawValue + message`) → `prefix(limit)` in the correct order at their respective fan-in points; the builder's extra post-orchestrator detectors (`LifeAdminBatchCurator`, `BadDayDetector`, `CaptureClusterAnalyzer`, `CrossDomainFusionAnalyzer`, `ExperimentFollowThroughDetector`, `WeekShapeAnalyzer`, `DeferralRecoveryWeeklyAgent`, `WakeRecoveryDetector`, `WeekPrimerDetector`, `PostCompletionAgent`, `ProactiveBundleBuilder`) are all folded in *before* the final rank/dedupe/limit call, so no unbounded/undeduped list can reach the UI.
- Verified `WakeRecoveryDetector` is not orphaned: it's invoked from `ProactiveActionsBuilder.analyze` (app-layer), not `ProactiveOrchestrator.analyze` (core-layer) — an intentional layering split, not a missing wiring bug.
- `TransitionShieldBuilder.transitions` only ever escalates for the single nearest anchor (`anchors.first`) per call — by design (one active transition shield at a time), not a bug.

**Coverage still open after Wave 5:** remaining `Proactive/*` detectors not yet read line-by-line (`ADHDProactiveRouting`, `CalendarChangeDetector`, `CaptureClusterAnalyzer`, `CaptureResurrectionAnalyzer`, `CrossDomainFusionAnalyzer`, `DeferralRecoveryWeeklyAgent`, `ExperimentFollowThroughDetector`, `PatternCoachAnalyzer`, `ProactiveFeedbackStore`, `ProactiveNotificationAdapter`, `ProactiveSnapshotStore`, `WeekPrimerDetector`, `LifeAdminBatchCurator`, `BadDayDetector`, `ProactiveBundleBuilder`, `Agents/*`), `Recovery/*`, `Travel/TravelDisruptionDetector.swift`, `LookAfterAI/Briefing`, `Proxy`, `Security`, `LookAfterFeatures` UI/ViewModels, `LookAfterIntegrations`, `LookAfterHealth`, notifications/widgets, macOS shell.

## Wave 6 — Remaining Proactive Detectors, `BadDayDetector`, `ProactiveFeedbackStore`, `TravelDisruptionDetector` (1 new MEDIUM bug)

**Files reviewed (full):**

- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/Proactive/CrossDomainFusionAnalyzer.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/Proactive/CalendarChangeDetector.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/Proactive/CaptureResurrectionAnalyzer.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/Proactive/ADHDProactiveRouting.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/Proactive/DeferralRecoveryWeeklyAgent.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/Proactive/WeekPrimerDetector.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/Proactive/ExperimentFollowThroughDetector.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/Proactive/ProactiveFeedbackStore.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/Recovery/RecoveryDayTemplate.swift` (`BadDayDetector`)
- `Packages/LookAfterCore/Sources/LookAfterCore/Planning/Travel/TravelDisruptionDetector.swift`
- `Packages/LookAfterFeatures/Sources/LookAfterFeatures/LifeAdmin/LifeAdminBatchCurator.swift`
- `Packages/LookAfterFeatures/Sources/LookAfterFeatures/Integrations/IntegrationProactiveBridge.swift`
- `Packages/LookAfterFeatures/Sources/LookAfterFeatures/Planning/ProactiveActionsBuilder.swift` (re-read for fan-in ordering with new detectors)
- Targeted reads of `AppShellState.swift` (`storeAutoApplyPreviewTimeouts`, `emitExpiredPreviewConfirmationIfNeeded`), `ProactiveActionRouter.swift`, `ProactiveAction.swift` to confirm what `.autoApplyPreview` surface actually does downstream (confirmed: it only schedules a 15-min "confirm before applying" reminder notification — it never silently auto-applies a replan without user confirmation, so no CRITICAL escalation here).

**New finding — MEDIUM, confirmed by code trace:**

`TravelDisruptionDetector.evaluate` (`Packages/LookAfterCore/Sources/LookAfterCore/Planning/Travel/TravelDisruptionDetector.swift`, lines 27-79) applies **inconsistent date filtering** depending on which branch its own fingerprint-diffing logic takes:

```swift
if fingerprint.isEmpty || fingerprint == previous || previous.isEmpty {
    // "unchanged" branch — correctly filters to same-day, future events only
    if let event = travelEvents.first(where: { $0.date > now && calendar.isDate($0.date, inSameDayAs: now) }) { ... }
    return nil
}
if let event = travelEvents.first {
    // "changed" branch — NO date filter at all
    return TravelDisruption(..., summaryLine: "Travel update: ... at \(timeLabel) — replan around it?", ...)
}
```

**Expected behavior:** A travel-disruption prompt (severity `.high`, surface `.autoApplyPreview`, message "replan around it?") should only surface when a travel event is actually imminent/relevant to today's schedule.

**Actual behavior:** When the fingerprint of travel-related timeline events/emails changes from one non-empty value to another (i.e., *any* travel event is added, removed, or edited — including a flight weeks away, or a past flight still present in `timelineEvents`), the detector unconditionally returns `travelEvents.first` — with no `date > now` or "same day" check — and flags it as a high-severity "replan around it?" prompt. This can fire for travel that is not happening today, or that has already passed, purely because the fingerprint string differs from last time.

**Trigger:** Add/remove/edit any travel-flagged calendar event (or email matching "flight"/"departure"/"gate") on a day where a *different* travel fingerprint was already stored from a previous call (i.e., not the very first run, and not an unchanged state) — e.g., booking a flight for three weeks from now while a different trip was tracked previously.

**Impact:** Spurious high-severity "replan today" prompts unrelated to the current day's schedule; inconsistent with the detector's own same-day/future guard used in the "unchanged" branch just above it. Confirmed this does **not** escalate to silent auto-apply — `storeAutoApplyPreviewTimeouts`/`emitExpiredPreviewConfirmationIfNeeded` in `AppShellState.swift` only schedule a notification asking the user to *confirm* before applying, and `ProactiveActionRouter` requires an explicit "Preview replan" tap to call `triggerCalendarReplan()`. Severity is therefore MEDIUM (bad/irrelevant proactive nudge), not HIGH/CRITICAL (no unwanted schedule mutation without user action).

**Suggested regression test:**
```swift
// 1. Call evaluate() once with a travel event 10 days out -> primes `previous` fingerprint.
// 2. Call evaluate() again with a *different* travel event also >1 day out (or already past).
// 3. Assert result is nil (or at least date-gated) instead of an unconditional "replan around it?" prompt.
```

**Other Wave 6 verifications (no new bugs):**

- `CrossDomainFusionAnalyzer.fuse` — all boost/suppress rules are pure re-ranks of the existing `actions` array; no rule can fabricate or drop an action outside of the documented boost logic.
- `CalendarChangeDetector`, `CaptureResurrectionAnalyzer`, `ADHDProactiveRouting`, `DeferralRecoveryWeeklyAgent`, `WeekPrimerDetector`, `ExperimentFollowThroughDetector` — all pure, deterministic, correctly guard on weekday/hour/threshold and return `nil` on non-matching input; no off-by-one or inverted-condition defects found.
- `ProactiveFeedbackStore` — `score`/`shouldSuppress` windows (14-day / 7-day) are correctly computed from `recordedAt`, `maxEvents` cap (200) correctly trims oldest-first via `suffix`.
- `BadDayDetector.evaluate` — scoring/threshold/template-selection logic (`score >= 3` gate, `.recovery` vs `.minimumViable` vs `.gentlePush` bands) is internally consistent and matches `RecoveryDayTemplate`'s three cases.
- `LifeAdminBatchCurator.curate` — budget decrement and per-category `prefix(n)` caps are correct; returns `nil` when no items fit instead of an empty/degenerate batch.
- `IntegrationProactiveBridge.emailAndTravelActions` — correctly branches on `GmailOAuthService.isEnabled` and always still calls `TravelDisruptionDetector.evaluate` (with or without email subjects) so travel detection isn't accidentally skipped when Gmail is disabled.

**Coverage still open after Wave 6:** `LookAfterAI/Briefing`, `Proxy`, `Security` modules; most `LookAfterFeatures` UI/ViewModels beyond Planning; `LookAfterIntegrations` (Gmail sync/triage internals); `LookAfterHealth`; notifications/widgets scheduling internals; macOS app shell. Given six waves of investigation, further waves have shown steeply diminishing returns (Waves 4-6 combined found 1 MEDIUM bug across ~30 files) — recommend pausing broad sweeps and either remediating the 3 confirmed bugs (CRITICAL cold-launch loss, HIGH empty-userId visibility, MEDIUM anchored-task drop, MEDIUM travel-fingerprint date filter) or scoping any further hunt to a specific subsystem on request.

## Wave 7 — AI Briefing/Proxy/Security, LookAfterHealth, LookAfterIntegrations, Notification Scheduling

**Scope:** `LookAfterAI/Briefing` (`ChiefOfStaffBriefingSynthesizer`, `BriefingPromptGenerator`), `LookAfterAI/Proxy` (`AuthProxyClient`), `LookAfterAI/Security` (`KeychainStore`), `LookAfterHealth` (`SleepNightAggregator`, `HealthManager`), `LookAfterIntegrations` (`GmailOAuthService`, `GmailTokenStore`, `EmailTriageService`/`EmailTriageStore`, `IntegrationProactiveBridge`), and the full local-notification pipeline (`NotificationPolicyEngine`, `NotificationDailyBudgetStore`, `NotificationScheduler`, `NotificationCoordinator`, `NotificationRouter`, `LookAfterAppDelegate`).

**New finding — MEDIUM, confirmed:** Notification daily budget cap (`NotificationPolicy.maxProactivePerDay`) is only enforced against foreground-delivered notifications, so it silently fails to cap notifications in the common case where the app is backgrounded/not running.

**File:** `Apps/LookAfter-iOS/App/LookAfterAppDelegate.swift` (lines 50-62) and `Packages/LookAfterCore/Sources/LookAfterCore/Notifications/NotificationDailyBudgetStore.swift`

**Exact location:**
```swift
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
) {
    if let candidateID = ... , kind.countsTowardDailyCap {
        NotificationDailyBudgetStore.recordDelivered(candidateID: candidateID)
    }
    completionHandler([.banner, .sound])
}
```

**Expected behavior:** `budget.deliveredCount` should reflect every proactive notification actually delivered to the user today, so `NotificationPolicyEngine.select` can correctly cap future scheduling at `NotificationPolicy.maxProactivePerDay` (`remainingSlots = max(0, maxProactivePerDay - budget.deliveredCount)`).

**Actual behavior:** `NotificationDailyBudgetStore.recordDelivered` has exactly one call site in the entire codebase: `UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:...)`. Per Apple's documented behavior, `willPresent` is invoked **only** when a local/remote notification arrives while the app is in the foreground. When a scheduled `UNCalendarNotificationTrigger` fires while the app is backgrounded, suspended, or not running (the overwhelmingly common case for a proactive/ADHD-support app whose whole point is nudging the user when they're *not* looking at the app), no delegate callback records the delivery, so `deliveredCount` is never incremented for it. `didReceive response:` (fired when the user taps/acts on a notification) also never calls `recordDelivered`.

**Impact:** Over a normal day, `budget.deliveredCount` stays at or near 0 regardless of how many notifications actually fired in the background, so `remainingSlots` in `NotificationPolicyEngine.select` never shrinks. The entire daily proactive-notification cap (`maxProactivePerDay`) — the mechanism specifically meant to prevent notification overload for ADHD users — is effectively inert for the majority of real-world delivery, allowing far more than the intended number of proactive notifications per day. Snooze/dismiss-driven exclusions (`dismissedCandidateIDs`, `snoozedCandidateIDs`) still work since those are recorded on explicit user action via `NotificationRouter`, but the count-based cap itself does not.

**Trigger:** Normal daily use where the user is not actively foregrounding the app when each proactive notification fires (the default/expected usage pattern for scheduled reminders).

**Suggested regression test:**
```swift
// 1. Schedule N > maxProactivePerDay candidates via NotificationScheduler (simulate background delivery,
//    i.e. do NOT invoke willPresent).
// 2. Call NotificationPolicyEngine.select again for a subsequent refresh the same day.
// 3. Assert remainingSlots/selected count is NOT reduced, demonstrating the cap did not engage,
//    versus the expected behavior of it being capped at maxProactivePerDay total for the day.
```

**Other Wave 7 verifications (no new bugs):**

- `ChiefOfStaffBriefingSynthesizer` / `BriefingPromptGenerator` — degrade-on-empty-input and prompt assembly are correct; no state corruption on GLM failure (mirrors Wave 2/4 patterns).
- `AuthProxyClient` — request/response error mapping and retry logic are consistent; no leaked credentials or silently swallowed auth failures.
- `KeychainStore` / `GmailTokenStore` — `SecItemUpdate`-then-`SecItemAdd` fallback pattern is correct (handles both "item exists" and "item missing" paths without duplicate-item errors).
- `SleepNightAggregator` — night-boundary bucketing and aggregation math check out; no double-counting of overlapping sleep samples.
- `EmailTriageService` / `GmailSyncService` — `GmailSyncService.fetchUnreadThreads` currently always returns hardcoded mock threads (real Azure `/gmail` proxy route not yet implemented — labeled in-code as a known placeholder, not a functional regression). `EmailTriageStore` is a global (non-user-scoped) actor store, which *would* reintroduce a cross-user data leak pattern similar to the Wave 1 empty-`userId` finding if real per-user Gmail data were ever wired through it — flagged as a design risk to address before the real Gmail integration ships, not a currently-exploitable bug since the data is only mock content today.
- `NotificationPolicyEngine.select` itself — priority/session-local/transition-shield partitioning and `prefix(remainingSlots)` truncation logic are internally correct; the defect is entirely in the upstream `deliveredCount` bookkeeping, not the selection algorithm.
- `NotificationScheduler` — pending-request diffing (`managedIDs` vs `selectedIDs`) correctly cancels stale requests without touching unmanaged/system notifications.

**Coverage still open after Wave 7:** `LookAfterFeatures` UI/ViewModels (non-Planning), macOS app shell, widget extension code, most `Apps/LookAfter-iOS/Views/*`. Given 7 waves and a rapidly narrowing yield of new confirmed bugs (Wave 7: 1 MEDIUM across the full remaining backend-adjacent surface), further broad sweeps are not recommended; remaining areas are primarily SwiftUI view code, which is lower-risk for the kind of silent data/logic bugs this hunt has targeted.

## Wave 8 — `LookAfterFeatures` (Tasks/Planning mutation layer)

**Scope:** `ScheduleMutationService`, `TaskUndoController`, `DayReplanEngine`, `PlanMutationApplier`, and their call paths back into `TasksViewModel` (`updateTask` vs `updateTaskAndPersist`, `reconcileTodaySchedule`).
No production code was modified during this investigation.

**New finding — MEDIUM, confirmed:** `PlanMutationApplier.apply`'s `.deferTask`/`.removeFromToday` case persists via the fire-and-forget `tasksVM.updateTask(_:)` instead of the awaitable `updateTaskAndPersist(_:)`, then the same `apply()` call goes on to `await tasksVM.reconcileTodaySchedule(userId:)`, which immediately re-reads ground truth from disk. This creates a race that can silently undo the defer.

**File:** `Packages/LookAfterFeatures/Sources/LookAfterFeatures/Planning/PlanMutationApplier.swift` (lines 258-270, 385-388) and `Packages/LookAfterFeatures/Sources/LookAfterFeatures/Tasks/ViewModels/TasksViewModel.swift` (`updateTask` line 1046, `reconcileTodaySchedule` line 1970 / `pre-reconcile-local` snapshot at line 2010).

**Exact location:**
```swift
// PlanMutationApplier.apply, case .deferTask, .removeFromToday:
task.scheduledDate = tomorrow
task.scheduledTime = nil
task.scheduledEndTime = nil
tasksVM.updateTask(task)          // fire-and-forget: Task { await updateTaskAndPersist(task) }
result.appliedCount += 1
...
// later, unconditionally, in the same apply() call:
if !deferReconcile {
    tasksVM.requestForceReplan()
    await tasksVM.reconcileTodaySchedule(userId: userId)   // reads taskRepo.localSnapshot immediately
}
```
```swift
// TasksViewModel.updateTask
public func updateTask(_ task: LifeTask) {
    Task { await updateTaskAndPersist(task) }   // NOT awaited by caller
}
// TasksViewModel.reconcileTodaySchedule (first thing it does):
applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "pre-reconcile-local", authoritative: true)
```

**Expected behavior:** When the AI/planning layer applies a `deferTask`/`removeFromToday` mutation, the task's cleared schedule (moved to tomorrow, `scheduledTime = nil`) must be durably persisted *before* `reconcileTodaySchedule` re-derives today's active pool from disk, so the deferred task is correctly excluded from today's reconciliation/replan.

**Actual behavior:** `updateTask(_:)` spawns a detached `Task` and returns immediately without awaiting persistence (`taskRepo.update(...)`, which round-trips through GRDB). `apply()` does not await this detached Task at all — it proceeds through the rest of the mutation loop and then straight into `reconcileTodaySchedule`, whose very first action is `applySnapshot(taskRepo.localSnapshot(for: userId), ..., authoritative: true)`, an **authoritative** overwrite of the in-memory `tasks` array from disk. If the detached persist Task has not yet completed its `taskRepo.update` write by the time this disk read happens (no ordering guarantee between an unstructured child `Task` and a sibling top-level `await` a few statements later — both are merely MainActor jobs queued for later execution), the reconcile pass reads the **pre-defer** record: task still shows `scheduledDate` = today with its old time. `ConflictResolutionCascade`/`DayScheduleReconciler` then treats it as part of today's active pool again, potentially re-placing/re-timing it — silently reverting the user-visible "deferred to tomorrow" result the AI just reported as applied (`result.appliedCount += 1` already fired, so the UI/response claims success regardless).

**Trigger:** Any AI planning turn that includes a `deferTask`/`removeFromToday` mutation together with at least one other mutation kind that reaches the final `reconcileTodaySchedule` call in the same `apply()` invocation (the common case — plan mutations are typically batched), especially when GRDB's `update` write takes longer than the trivial synchronous work remaining in `apply()`'s loop.

**Impact:** Deferred tasks can reappear in today's schedule after a replan/reconcile pass immediately following the defer, even though the applier reported the mutation as successfully applied. This is a data-consistency/race bug rather than a deterministic one, so it will manifest intermittently (harder to reproduce, but real under load or on slower devices/disk).

**Note:** `ParkedTaskRecoveryService.swift` (line 184) has the identical `tasksVM.updateTask(existing)` fire-and-forget pattern; it wasn't traced further this wave since it doesn't visibly chain into an immediate authoritative disk re-read in the same call the way `PlanMutationApplier` does, but it's a candidate for the same class of race if such a caller exists.

**Confidence:** Medium-high — the code-level race (unawaited persist immediately followed by an authoritative disk-snapshot read in the same function) is directly evidenced; exact reproducibility depends on Swift Concurrency's MainActor job-ordering behavior on a given OS/device, which was not empirically measured this wave.

**Suggested regression test:**
```swift
// 1. Seed a task scheduled for today.
// 2. Call PlanMutationApplier.apply with a .deferTask mutation for it plus a second
//    unrelated mutation (e.g. .createTask) so the loop continues past the defer case.
// 3. Immediately inspect tasksVM.tasks / taskRepo state before any additional await yields.
// Expected: task.scheduledDate == tomorrow and it is excluded from today's active pool
//           by the time apply() returns, deterministically (not depending on scheduler timing).
// Fix direction: change `tasksVM.updateTask(task)` to `await tasksVM.updateTaskAndPersist(task)`
// in the .deferTask / .removeFromToday case (and audit ParkedTaskRecoveryService similarly).
```

**Other Wave 8 verifications (no new bugs):** `ScheduleMutationService` (`persist`, `applyDayScheduleChanges`, `removeFromTimelineToday`, `placeSuggestedSlot`, `applyTimelineOffset`) — all correctly await `viewModel.updateTaskAndPersist` before reconciling; `TaskUndoController` — timer cancellation/replacement logic is race-free (single `undoDismissTask` handle, cancelled before reassignment); `DayReplanEngine` — AI retry-then-fallback, JSON decode/variant selection, and both local-fallback code paths (`localFallback`, `localFreedSlotFallback`) are internally consistent; `PlanMutationApplier`'s other mutation kinds (`createTask`, `rescheduleTask`, `completeTask`, `markMedicationTaken`, `addShoppingItem`, `captureNote`, `createMultiDayTask`) all correctly `await` their persistence calls before the function proceeds.

**Coverage still open after Wave 8:** SwiftUI View layer proper (`Apps/LookAfter-iOS/Views/*`), macOS app shell, widget extension code, remaining `LookAfterFeatures` ViewModels outside Tasks/Planning (e.g. `LifeModulesViewModel` internals beyond what's been touched incidentally).

## Wave 9

**Scope:** Remaining `LookAfterFeatures` service/orchestration layer — `DayAuditApplier`, `ScheduleMutationIdempotencyStore`, `CalendarSyncService`, `FactoryResetManager`, `TaskFocusStretchRefiner`/`TaskFocusStretchResolver`, `StateCoalescer`, `ContextOrchestrator`, `WeekShapeAnalyzer`, `MultiDayTaskPlanner`, `TelemetrySynthesizerService`.

**Result:** No new bugs found. Notably, `DayAuditApplier` implements the same defer/skip mutation pattern as `PlanMutationApplier` (Wave 8 bug #6) but does it correctly — it awaits `updateTaskAndPersist`/`ScheduleMutationService` calls for every fix before the final `reconcileTodaySchedule`, avoiding the race. `CalendarSyncService` orphan-pruning is correctly scoped to its own "Blocked by Look After" marker so it can't delete user-created calendar events. `FactoryResetManager` ordering (store resets → bulk UserDefaults wipe → in-memory cache invalidation → widget reload) is coherent and avoids stale-cache-after-wipe issues. All other reviewed files are either pure functions or correctly-sequenced async orchestration.

No production code was modified. Coverage still open: SwiftUI View layer proper, macOS app shell, widget extension code, and remaining `LookAfterFeatures` ViewModels not yet incidentally touched.

## Wave 10

**Scope:** iOS widget/Live Activity sync layer (`WidgetSyncService`, `WidgetSyncFingerprint`, `AppGroupWidgetStore`, `WidgetDataStore`, `PinNowSnapshotBuilder`), `AppShellState` widget/timeline glue, `BrainViewModel`, and the macOS app shell (`LookAfterMacApp`, `MacContentView`, `MacProductivityTracker`).

**Result:** No functional/data-correctness bugs found in the widget sync pipeline — fingerprint-gated dedup (`WidgetSyncFingerprint.shouldWrite`), App Group disk read/write (`AppGroupWidgetStore`), and pin-now snapshot construction (`PinNowSnapshotBuilder`) are internally consistent, and the `force` bypass correctly handles the NOW-complete restamp path.

**Minor observation (not filed as a bug — dead code, no user-visible incorrect behavior):**

```swift path=Apps/LookAfter-macOS/ProductivityTracker.swift mode=EXCERPT
@Published public var todayFocusMinutes: Int = 0
...
todayFocusMinutes += 1 // approximate increment for display
```

`MacProductivityTracker.todayFocusMinutes` (and `currentWindowTitle`, `isIdle`) are updated by the 5-second polling timer but are never read by any View (`MacContentView`, `MacSettingsView`, `BrainDashboardView` all construct `macTracker` but never bind to these fields), never reset daily, and never sent to Firebase despite the type's doc comment ("Sends productivity logs to Firebase so the AI Executive Brain has full context on Mac usage") — that Firebase-send integration doesn't exist. This is incomplete/dead functionality rather than a bug with observable incorrect behavior, so it is not added to the confirmed-bug tally.

No production code was modified.

## Overall status across 10 waves

6 confirmed bugs total:
1. **CRITICAL** — cold-launch task creation wipes local storage (`TaskSQLiteStore.replaceAll`)
2. **HIGH** — empty-`userId` tasks visible across users
3. **MEDIUM** — overlapping anchored/fixed-time tasks silently dropped from schedule (`DaySchedulePlanner`)
4. **MEDIUM** — `TravelDisruptionDetector` fires irrelevant/stale replan prompts due to inconsistent date filtering
5. **MEDIUM** — notification daily budget cap does not engage for background-delivered notifications (`NotificationDailyBudgetStore.recordDelivered` only wired to foreground `willPresent`)
6. **MEDIUM** — `PlanMutationApplier` defer/remove-from-today mutations race with the subsequent authoritative `reconcileTodaySchedule` disk re-read, able to silently undo the defer

Waves 9–10 surfaced zero new confirmed bugs. Wave 9 covered the remaining `LookAfterFeatures` service/orchestration layer; Wave 10 covered the widget sync pipeline and macOS shell, finding only one minor dead-code/incomplete-feature observation (Mac productivity tracker metrics never surfaced in UI or sent to Firebase) that doesn't rise to a functional bug. This concludes the 10-wave bug hunt — recommend pivoting to remediation of the 6 confirmed bugs.
