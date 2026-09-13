# Plan — AI review gaps in scheduling & proactive monitoring

Local working plan only (not a deliverable). Covers the four issues reported:
1. Tasks scheduled without time context (e.g. Gym at 1:30 AM)
2. Morning open should AI-review + schedule tasks (title context, duration, feasibility, duplicates)
3. AI should monitor throughout the day and ask proactive questions
4. Review/document all AI prompts

---

## Issue 1 — Tasks scheduled without time context (e.g. "Gym" at 1:30 AM) — **NOT gym-specific, systemic gap**

**Revised root cause (broader than first pass):**
`TaskEphemeralityDefaults.boundingBox(for:)` (`TaskEphemerality.swift:132-166`) only hard-codes a fence for `.selfCare`, meal-subtype `.errand`, and `.medication`, plus a title-keyword fallback (lunch/breakfast/dinner/snack). **Every other semantic type — `.physicalActivity`, `.deepWork`, `.administrative`, `.communication`, `.creative`, `.learning`, `.generic`, non-meal `.errand` — has no case and falls through to `nil`.** Gym was just the symptom that surfaced this; the same gap applies to any task whose semantic type isn't in that small allowlist and whose title doesn't happen to match a meal keyword.

Downstream, `SemanticPlacementSense.hourBounds(for:)` falls back to the profile's `preferredTimeWindows`, which defaults to `[.anytime]` (`TaskSemanticProfile.init`) unless something upstream explicitly narrows it. When it's `[.anytime]`, `hourBounds` returns `nil` (no fence) **and** `SemanticPlacementSense.judge`'s `inPreferred` check is trivially true — so neither the deterministic bounding box nor the semantic judge catches an out-of-context placement for the majority of task types. This is a **deterministic-coverage gap**, not a one-off bug: a fixed allowlist of "known" types can never cover every task title/context combination a user creates.

**Revised fix path — AI review is a mandatory step, not a fallback:**
Deterministic checks (`TaskEphemeralityDefaults.boundingBox`, `SemanticPlacementSense.judge`'s rule branches) stay as a **fast pre-filter** — they can still reject obviously-wrong placements (forbidden windows, hard bounding boxes) cheaply without a network call. But they must no longer be the terminal answer when they *don't* reject: today, if no rule fires, the verdict defaults to `.makesSense` and the task is placed with **zero context review**. That silent pass-through is the actual bug.

- Every task placement/review (scheduling, morning audit, and any reschedule) must pass through an AI judgment step — it is not conditional on the deterministic system having "no opinion." Deterministic rules narrow/pre-validate; AI is the compulsory final check on **title, estimated duration, life area, semantic type, and current day state** (already-scheduled tasks/times, energy/capacity) before a placement is accepted.
- Concretely: change `SemanticPlacementSense.judge`'s final `return .makesSense` (`SemanticPlacementSense.swift:165`) so it is never reached silently — route it to the AI judgment step instead. `.needsAI` stops being one branch among several and becomes the default outcome whenever no deterministic rule has already rejected/accepted with high confidence (e.g. inside a known-safe bounding box).
- Cost/latency implication (must be addressed in implementation, not deferred): calling GLM on every placement is expensive relative to the current mostly-synchronous deterministic path. Needs caching/batching (e.g. one AI review per full-day replan pass rather than per single-task placement call) — this is a design decision to make during implementation, not a reason to keep it a fallback.

**Verification:**
- Unit test: a "Gym"/`.physicalActivity` task proposed at 01:30 must not return `.makesSense`.
- Broader test: construct tasks across several semantic types with no deterministic fence (e.g. `.creative`, `.learning`, generic titles) proposed at implausible hours (3 AM) — assert each one either gets a deterministic reject or routes to `.needsAI` rather than silently passing through as `.makesSense`.

---

## Issue 2 — Morning review lacks AI-driven scheduling (title context, duration, feasibility, duplicates)

**Root cause (confirmed by trace):**
`DayAuditService.run` (`DayAuditService.swift:52-181`) is explicitly documented as "Deterministic day supervisor — fuses existing analyzers; **no GLM inside the fuse step**." Its checks are: overlap detection, `PreWindowFitAnalyzer` (shrink/skip by time budget only), `ScheduleProactiveAnalyzer`, capacity vs. flex, and parked/yesterday pull candidates. None of these:
- read task **titles** for semantic/contextual sense (that's `SemanticPlacementSense`, invoked only during placement, not during the morning audit),
- call any AI/GLM service to judge feasibility, or
- check for **duplicate** tasks (no dedupe-by-title/semantic-similarity logic anywhere in `DayAuditService` or `DayAuditApplier`).

The only place `SemanticPlacementSense.judge` (which does read title-derived semantic type) runs is inline during placement/allocation (`DaySlotAllocator.fits`, `PlanMutationApplier.resolvedStart`) — not as a standalone morning-open review pass. `DailyBriefingViewModel.refreshDayAudit`/`applyDayAudit` (~lines 1392-1411) is the morning-open entry point and only surfaces `DayAuditService`'s deterministic faults/fixes for user approval; it never calls GLM.

**Fix path — mandatory, not optional:** the morning-open flow must always run an AI review pass; it is not gated behind a deterministic pre-check finding a problem first (matches Issue 1's stance: AI is compulsory, never a fallback). Add a required step to the morning audit flow (inside `DayAuditService.run`, or as a new step `DailyBriefingViewModel` always invokes alongside `refreshDayAudit`) that:
- (a) runs the compulsory AI judgment (see Issue 1) across all of today's tasks — not just ones a deterministic rule flagged — and surfaces `.needsAI`/`.doesNotMakeSense` verdicts as audit faults;
- (b) adds a duplicate-detection step (title/semantic-similarity match within the same day) emitting a new `DayAuditFault.sourceKind` (e.g. `.duplicate`), also run every time, not conditionally.

**Use full stored user context, not just today's task list, so the AI can judge best fit — not isolated rules.**
`DayAuditService.Input` (`DayAuditService.swift:6-50`) already aggregates most of what's needed for a rich AI prompt without new plumbing:
- `profile: UserLifeProfile` (`UserLifeProfileStore.load()`) — routines, preferences, work hours.
- `lifeModel: LifeModel?` (`LifeModelStore.load()`) — learned anchors/patterns.
- `energyPercent`, `capacityBandLabel` — today's capacity state.
- `yesterdayIncomplete`, `parkedCandidates` — carryover context.
- `weeklyPriors: DaySupervisorPriorsStore.Priors?` — "prefer lighter mornings" style learned notes.

Missing from today's deterministic audit but available elsewhere and worth including in the AI prompt payload: `BehaviorMemory`/deferral records (used by `ProactiveActionsBuilder`/`CircuitBreakerAnalyzer`), and the full `tasks` array's semantic profiles (title + duration + life area + semantic type), not just IDs. Compose these into one sanitized payload (following the existing `BriefingPIISanitizer`/`BriefingRouterPayload` pattern used by `BriefingPromptGenerator` — categories/counts over raw text where the pattern already avoids PII) and pass it to GLM so it can reason about "does this task, at this title/duration, make sense today given this user's routine and current state" instead of running isolated context-free checks.

---

## Issue 3 — AI should monitor throughout the day and ask proactive questions

**Root cause (partially exists, but narrow):**
`ProactiveOrchestrator.analyze` (`ProactiveOrchestrator.swift`) already fuses several analyzers (`ScheduleProactiveAnalyzer`, `WaitingModeAnalyzer`, `TransitionShieldBuilder`, `EndOfDayAgent`, `PatternCoachAnalyzer`, `CircuitBreakerAnalyzer`, `StallAgent`, `PostCompletionAgent`, relationship-drift, etc.) and does surface proactive prompts/questions with options — but this is deterministic/rule-based, not AI-judged:
- All analyzers use fixed thresholds (elapsed time, counts, energy bands) — none call GLM to reason about the specific situation or phrase a context-aware question.
- `DayAuditService.questions` (the only place a free-form `DayAuditQuestion` is generated) is capped at `maxQuestions` (default 2) and only fires for the capacity-overload case (`DayAuditService.swift:142-148`) — one hardcoded question, not general-purpose.
- No recurring/periodic trigger re-evaluates "what's happening now" mid-day beyond app-foreground/notification-budget-gated proactive checks (`ProactiveDailyBudget`, `NotificationDailyBudgetStore`).

**Fix path (scope gap, not a bug):** decide whether to
- (a) extend `ProactiveOrchestrator` with a GLM-backed analyzer that takes current task/timeline state and generates a context-specific question, and
- (b) wire a periodic/background trigger if "throughout the day" implies checks beyond app-open moments.

---

## Issue 4 — Review and document all AI prompts

**Root cause:** no audit exists yet. Confirmed prompt sources found so far:
- `LookAfterPrompts.swift` — `structuredOutputSystem`, `taskFocusStretchSystem`, `briefingModuleInsightsSystem`, `executiveBrainSystem`, `chiefOfStaffBriefingSystem`, `taskAutoFillPrompt`, quick-capture intent prompt, life-profile-to-commitments prompt.
- `BriefingPromptGenerator.compile` — sanitized schedule-data prompt.
- `ChiefOfStaffBriefingSynthesizer.buildUserPrompt`.

Not yet enumerated: `TaskSemanticAnalyzer`'s extraction prompt, `ExecutiveBrain`'s per-call system prompt assembly (coach + personalization + calibration blocks), and any prompts in `EmailTriageClassifier`, `TravelDisruptionDetector`, or other AI-classifier call sites.

**Fix path:** grep all `GLMService`/`glm.complete`/`glm.sendMessage`/`glmComplete(` call sites repo-wide, list each prompt's purpose, model tier, and output contract. Only produce a doc file if explicitly requested (per scope rules).

---

## Suggested execution order

1. **Issue 1** — narrowest, highest-severity, concrete code fix. Do first.
2. **Issue 2** — larger scope; builds on Issue 1's fence fix being correct first (otherwise AI review would just re-surface the same gap).
3. **Issue 3** — depends on deciding scope (foreground-only vs. background trigger) before implementation.
4. **Issue 4** — no code risk, can run in parallel; only create the documentation file if explicitly requested.
