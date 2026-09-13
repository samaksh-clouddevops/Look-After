# Plan: Fix all AI prompt definitions

## Implementation status

**Step 1 + 1a + 1b: DONE.** `placementSensePrompt` now includes day-of-week, `now`, life-context
block, medication safety rules, precomputed neighbor end/`confidence` schema field, full-day
schedule (`allDayTasks`), full task detail (lifeArea/priority/tags/difficulty), current/previous-day
health+energy blocks, calendar events, deadline pressure, user-initiated-vs-guessed flag,
recurrence-consistency hint, calibration notes, cycle context, weather, and negative-constraint
guardrails (items 20a–20c). `PlacementJudgment` gained `confidence` (default `1.0`, back-compat
safe). `PlanMutationApplier.judgeWithAI` passes `allDayTasks` and logs low-confidence (`< 0.5`)
verdicts without changing accept/reject semantics. Remaining optional params (`calendarEvents`,
health/energy, `weatherSummary`, `previousAcceptedSameSlot`) default to empty/nil since
`PlanMutationApplier` does not yet have plumbing to those data sources — wiring them is a follow-up,
not a blocker (prompt safely omits the corresponding blocks when unset).

**Step 3 (`captureRoutingPrompt` duplicates): DONE.**

**Step 5 (regression sweep): DONE (static/manual — CLI test run blocked by environment).**
`swift test` cannot execute on this Windows dev machine: `LookAfterCore` fails to compile
(`no such module 'SwiftUI'` — Apple-only framework, plus separate pre-existing Firebase SPM
symlink/permission errors on the app target). Both are environment limitations unrelated to these
changes, so verification here was done via `diagnostics` (zero issues across all edited files) and
manual trace of each consumption chain instead of a live test run:
- `PlacementSensePromptTests` (already written, covers prompt-block rendering + `confidence`
  parsing incl. legacy-response default) — code inspected, matches `judgePlacement`'s
  `(json["confidence"] as? Double) ?? ... ?? 1.0` parsing exactly.
- `SemanticPlacementSenseTests` — confirmed untouched by Step 1/3 changes (deterministic
  `SemanticPlacementSense.judge` path, no AI/confidence involvement).
- `AIScheduleSlotServiceTests`, `ContextualDayReplanTests` — confirmed they stub
  `debugSendMessageHandler`/`applySuggestions` directly and never touch `judgePlacement`,
  `PlacementJudgment`, or `captureRoutingPrompt`; unaffected by prompt content or the new
  `confidence`/`possibleDuplicateOfTitle` fields.
- `CaptureIntentClassifierTests` — new `testParseDecisionAcceptsMatchingDuplicateTitle` /
  `testParseDecisionRejectsFabricatedDuplicateTitle` added and inspected against
  `parseDecision`'s exact-match guard; existing tests use default params, unaffected.
- Fixed unrelated stray syntax error (`l` on line 1) in `CaptureModels.swift` found during this
  sweep — would have failed compilation on any environment.

Recommend running the full `swift test` suite on macOS CI to get an actual pass/fail signal before
merging, since this environment cannot compile SwiftUI-dependent targets at all.

Step 3 implementation: `captureRoutingPrompt` takes `existingTaskTitles: [String] = []`, renders a
"RECENT/OPEN TASKS" block (capped at 15, most recent first) when non-empty, and the response schema
gained `possibleDuplicateOfTitle`. `CaptureRoutingDecision` gained the matching field.
`CaptureIntentClassifier.classify`/`classifyWithAI`/`parseDecision` thread `existingTaskTitles`
through, and `parseDecision` only trusts `possibleDuplicateOfTitle` when it exactly matches a title
from the list given to the AI (never fabricated). `CaptureRouter` gained
`existingTaskTitlesProvider` (wired in `AppShellState.configureCaptureRouter` to
`tasksVM.activeTasks`, most-recent-first) and `routeTask` now routes to `fallbackReview` instead of
silently creating a duplicate when the AI flags one. Unit tests added in
`CaptureIntentClassifierTests` for accept/reject of the duplicate-title guard.

Scope: every prompt in `LookAfterPrompts.swift`, `AIScheduleSlotService.schedulingPrompt`,
`DayReplanEngine.buildPrompt`/`systemPrompt`, and their parsers. Ordered by severity/risk.

## Step 1 (highest priority): `placementSensePrompt` + `judgePlacement`

File: `Packages/LookAfterAI/Sources/LookAfterAI/Prompts/LookAfterPrompts.swift`
File: `Packages/LookAfterAI/Sources/LookAfterAI/Utilities/TaskSemanticAnalyzer.swift`

This is the compulsory `.needsAI` resolution path (last line of defense before committing an
ambiguous placement). Currently missing data it needs to actually judge correctly.

Fixes:
1. Add date + day-of-week to the prompt (`formatter.dateFormat = "EEEE, yyyy-MM-dd HH:mm"` or a
   separate line), not just `HH:mm`. Needed for "rest day" / day-of-week-dependent reasoning.
2. Add `now` (current real time) as a separate line, distinct from `proposedStart`, so the AI can
   tell whether the slot is already in the past.
3. Inject `PlanningPromptContextBuilder.combinedLifeContextBlock(profile:)` so the AI has the same
   life-context (work hours, gym windows, commitments) every other scheduling prompt gets.
4. Inject `MedicationStore.medicalSafetyRulesBlock()` — rule 1 already tells the AI to enforce med
   timing rules; it must be shown the actual rules, matching `taskSemanticPrompt`'s pattern.
5. Precompute neighbor end times (`start`–`end`) instead of making the AI do `start + minutes`
   arithmetic itself, reducing placement-judgment errors.
6. Add `"confidence": <0.0-1.0>` to the JSON response schema (mirrors `taskSemanticPrompt`).
7. Thread `confidence` through `PlacementJudgment` (new field, default `1.0` for back-compat) and
   through `judgePlacement`'s JSON parsing.
8. Downstream: wherever `PlacementJudgment` is consumed (`PlanMutationApplier.judgeWithAI`), treat
   low confidence (e.g. `< 0.5`) as an additional signal — likely still respect `allowed` but log/
   flag it rather than silently trusting it the same as a high-confidence verdict. (Decide exact
   consumption during implementation — do not change accept/reject semantics without checking
   `PlanMutationApplier` call site first.)
9. Add a "HOW TODAY LOOKS" block: the full day's schedule, not just the 12 nearest neighbor tasks
   — reuse/extend the existing `neighborTasks` filter to include ALL of the day's active tasks
   (fixed + flexible) with their time ranges, so the AI can see gaps, density, and whether the day
   is already packed or empty. Keep the 12-item cap only as a display truncation with a
   "...and N more" suffix (matching the pattern in `nextActionPrompt`), not a hard data loss.
10. Add full task detail for the task being judged, not just title/description/semantic fields
    already present — also include `task.lifeArea`, `task.priority.label`, `task.tags`, and
    `task.difficulty.rawValue` (all already on `LifeTask`, currently omitted from this prompt only;
    every other task-facing prompt in the file includes these).
11. Add a "USER STATE" block with:
    - Current day: today's energy/mood/sleep-so-far if available (reuse `HealthSummary`,
      `EnergyReport` — same fields `nextActionPrompt` and `dailySummaryPrompt` already format:
      total sleep hours, HRV, resting HR, steps, energy level).
    - Previous day: yesterday's equivalent metrics (sleep hours, HRV, energy) for trend context —
      this is new; no existing prompt passes prior-day comparison data. Needs a new parameter
      (e.g. `previousDayHealthSummary: HealthSummary?`, `previousDayEnergy: EnergyReport?`) plumbed
      into `judgePlacement` → `SemanticPlacementSense`/`PlanMutationApplier.judgeWithAI` call site.
    - Only include the block when data exists (mirror the `if let health = ...` guard pattern used
      in `nextActionPrompt`/`dailySummaryPrompt`) — never fabricate placeholder health data.

Verification: unit test `placementSensePrompt` contains day-of-week, medication rules block
(when task is medication-adjacent), life-context block, full-day schedule block, task
lifeArea/priority/tags/difficulty, and current+previous-day health/energy blocks (present when
supplied, absent when nil). Unit test `judgePlacement` parses `confidence` correctly and defaults
sanely when the field is absent from a legacy-shaped response.

### Step 1a: signature/plumbing impact of items 9–11

`SemanticPlacementSense.judge` (deterministic, synchronous, `LookAfterCore`) has no health/energy
inputs today and should NOT gain them — it must stay deterministic and fast. Items 9–11 only apply
to the AI-only path:

- `TaskSemanticAnalyzer.judgePlacement(task:proposedStart:durationMinutes:neighborTasks:calendar:)`
  gains new optional parameters: `allDayTasks: [LifeTask]` (for item 9, defaults to
  `neighborTasks` if not supplied to avoid a breaking change), `todayHealthSummary: HealthSummary?`,
  `todayEnergy: EnergyReport?`, `previousDayHealthSummary: HealthSummary?`,
  `previousDayEnergy: EnergyReport?` (all default `nil`).
- Call site `PlanMutationApplier.judgeWithAI` must be updated to fetch and pass these — check what
  health/energy stores it already has access to (likely the same `HealthKitService`/
  `EnergyReportStore` used by `nextActionPrompt`'s caller) before adding new plumbing.
- Keep all new parameters optional with `nil` defaults so existing call sites/tests compile
  unchanged; only `PlanMutationApplier.judgeWithAI` needs the follow-up wiring change.

### Step 1b: additional decision-quality context (items 12–19)

Further gaps found beyond items 9–11 that also affect `placementSensePrompt` judgment quality:

12. **Calendar events, not just tasks.** `neighborTasks` only covers `LifeTask`s — real calendar
    meetings (`CalendarSyncService`/EventKit) are invisible to this prompt. Add a "CALENDAR EVENTS"
    block (reuse the same event-summary shape `BriefingCalendarEvent`/`DayReplanEngine` already
    uses) so a slot that looks free in the task list but is actually double-booked gets rejected.
13. **Deadline pressure.** Include `task.deadline` (if set) and how much runway remains vs. now —
    the AI should tolerate a stranger placement when it's the last slot before a deadline, and be
    stricter when there's plenty of runway. No new store needed — `LifeTask.deadline` already
    exists.
14. **User-initiated vs AI-guessed placement.** Add a boolean/label input (e.g.
    `isUserPlaced: Bool`, derived from `task.userPlacedScheduleAt != nil` at the call site) so the
    prompt can explicitly raise its bar for rejecting a placement the user chose themselves vs. one
    the local allocator guessed.
15. **Recurrence/history consistency.** Include whether this exact task (by id or recurrence
    group) was previously placed at this same time and accepted — avoids the AI flip-flopping a
    different verdict on an identical daily-recurring placement. Needs a small lookup (e.g. last
    accepted `PlacementJudgment` cached per task id/time, new light-weight store) — scope precisely
    during implementation; do not over-build this into a full history engine.
16. **User calibration notes.** Include `UserCalibrationStore.promptBlock(maxEntries: 5)` — already
    used by `nextActionPrompt`/`journalFeedbackAnalysisPrompt` — so calibrations like "gym always
    slips to evening" inform the judgment instead of being invisible to this one prompt.
17. **Cycle context when active.** Include `PlanningPromptContextBuilder.cycleBlock(...)` only when
    `CyclePreferencesStore.isActive`, matching the guarded pattern used elsewhere. Most relevant for
    `physicalActivity`/`selfCare` semantic types.
18. **Weather**, for outdoor-dependent tasks (errands, physical activity). `DayReplanEngine` already
    threads `weatherSummary` through; add the same optional parameter here, included only when
    present and only when the task's semantic type plausibly benefits from it (avoid noise for
    indoor/admin tasks — decide the exact filter during implementation).
19. **Explicit reject-safe default instruction.** Add a line to the prompt rules: "If uncertain,
    prefer `allowed: false` with a `suggestedStartHour`/`suggestedStartMinute` alternative rather
    than guessing `true`." Pairs with the `confidence` field (item 6) so low-confidence output
    defaults to the safe direction instead of a coin-flip accept.

Priority within this sub-step: items 12, 13, 14, and 19 first (directly prevent double-booking,
ignore deadlines, override explicit user intent, or produce unsafe guesses). Items 15–18 are
context-completeness parity with what other prompts in the app already receive — lower urgency,
implement after 12/13/14/19 land and are verified.

All new blocks/parameters in this sub-step follow the same rule as Step 1a: optional with safe
defaults (`nil`/`false`/empty), included in the rendered prompt only when data exists, never
fabricated as placeholder values.

### Item 20: negative-constraint guardrails

Beyond telling the AI what to check, `placementSensePrompt` should explicitly tell it what NOT to
do — mirrors negative constraints already present elsewhere (`schedulingPrompt`'s "Never assign
the same startHour/startMinute to two tasks", `DayReplanEngine`'s "Never invent medication times" /
"use actual ids — never copy placeholders literally"), which this prompt currently lacks:

20a. **Do not assume unstated constraints.** Add: "Do not reject a slot merely because it seems
     unusual — only reject based on conflicts actually present in the provided context (life
     context, medication rules, calendar events, deadlines)." Prevents over-conservative rejection
     driven by generic priors instead of the given data.
20b. **An empty slot is not sufficient justification for `allowed: true`.** Add: "A free/empty slot
     alone does not make a placement valid — it must also not conflict with life-context,
     medication, or calendar rules." Directly complements item 19's safe-default-when-uncertain
     instruction (empty ≠ safe).
20c. **Do not fabricate or guess field values you were not given.** Add: "Never invent times, task
     ids, or titles not present in the provided context." Matches the no-fabrication guard already
     used in `DayReplanEngine`'s prompt but currently absent from `placementSensePrompt`.

Scope note: 20a–20c apply only to `placementSensePrompt` for now — no evidence of the AI going
wrong in the positive-instruction direction on `captureRoutingPrompt` or the Step 4 reviewed-fine
prompts, so do not add blanket negative constraints there without a concrete observed failure mode.

## Step 2: `judgePlacement` / `analyze` shared parsing hardening

File: `Packages/LookAfterAI/Sources/LookAfterAI/Utilities/TaskSemanticAnalyzer.swift`

- No behavior change planned here beyond the `confidence` field above — parsing already defaults
  safely (`allowed ?? false`). Re-verify after Step 1 that new fields don't break existing decode
  paths (`data(using:.utf8)` → `JSONSerialization` is lenient to extra/missing keys already).

## Step 3: `captureRoutingPrompt` — add duplicate-detection context

File: `Packages/LookAfterAI/Sources/LookAfterAI/Prompts/LookAfterPrompts.swift`

Currently the capture router classifies intent with zero visibility into existing tasks, so it
cannot flag "this looks like a duplicate of an existing task." This overlaps with the still-open
Issue 2 (morning review duplicate-checking) from `plan-ai-review.md` — treat as a prerequisite:

1. Add an optional `existingTaskTitles: [String]` parameter to `captureRoutingPrompt`.
2. Include a short "RECENT/OPEN TASKS" block (cap ~15 titles, most recent first) in the prompt.
3. Add `"possibleDuplicateOfTitle": "<title or null>"` to the response JSON schema.
4. Caller (find call site during implementation) decides whether to surface a duplicate warning
   instead of auto-creating a new task when this field is non-null.

Verification: unit test with a synthetic existing-task list confirms the block renders and the
schema field round-trips through the parser.

## Step 4: Re-audit prompts confirmed fine in this pass (no action, listed for completeness)

- `dailySchedulerSystem` / `schedulingPrompt` — has life context, medications, temporal block. OK.
- `DayReplanEngine.buildPrompt` / `systemPrompt` — has life context, medications, duplicate-reuse
  rules block. OK.
- `taskSemanticPrompt` — has medical safety block, enums match `TaskSemanticProfile` exactly. OK.
- All remaining briefing/coach/cycle/import/journal prompts — reviewed, no correctness gaps found.

## Step 5: Regression test sweep

After Steps 1–3, re-run (or request macOS CI run of):
- `SemanticPlacementSenseTests` (unaffected by prompt text, but co-located logic)
- Any `TaskSemanticAnalyzer`/`PlacementJudgment` tests (add if none exist — check first, do not
  create new test files if equivalent coverage already exists per repo instructions)
- `AIScheduleSlotServiceTests`, `ContextualDayReplanTests` — confirm unaffected by prompt content
  changes (they stub `debugCompleteHandler`/`debugSendMessageHandler`, so prompt text changes are
  transparent to them; only response-shape changes like adding `confidence` need their stubs
  checked for shape compatibility).

## Order of execution

1. Step 1 (placementSensePrompt) — highest safety impact, standalone.
2. Step 3 (captureRoutingPrompt duplicates) — feeds into future Issue 2 work.
3. Step 5 (verification) — after both.

Step 2 and Step 4 are verification/no-op notes, not separate execution work.
