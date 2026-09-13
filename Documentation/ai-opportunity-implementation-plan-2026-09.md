# AI Opportunity Implementation Plan

> **Status: Superseded.**
> Canonical document: [`Documentation/ai-opportunity-plan.md`](ai-opportunity-plan.md). This file is retained as a historical decision record (engineering-review revision notes in §0) but is no longer updated. Do not implement against this file — use the canonical document.

_Date: 2026-09-12_
_Source: Documentation/ai-opportunity-discovery-2026-09.md (removed — superseded, content merged into canonical doc)_
_Revision: incorporates engineering review — see §0 Review Notes_

This plan breaks the three recommended AI opportunities into concrete, incrementally shippable engineering steps, in the sequencing **R1 (infra) → R3 (user-facing MVP) → R2 (deterministic MVP first, AI only if needed)**.

## 0. Review Notes Incorporated Into This Revision

1. **R1 duration-bias removed from scope.** Verified in `BehaviorEvents.swift`: `BehaviorEvent` only captures `durationMinutes` (actual/session duration) at record time — there is no `estimatedMinutes` field. Reconstructing it by joining against current `LifeTask` state would be unreliable (the task may have been edited or deleted since completion → survivorship bias). Duration-bias-by-lifeArea is **deferred** until a reliable historical-estimate source exists (e.g. snapshotting `estimatedMinutes` into the event at record time — a separate, explicit data-model change, not an implicit join).
2. **Confidence/sample-size now travels with every pattern**, not just gates emission.
3. **R2 reclassified as a deterministic-first MVP**, not an AI feature, per the discovery doc's own "AI OPTIONAL" language for the matching step. AI/embeddings are a follow-up phase gated on measured precision/recall.
4. **Evaluation metrics added** for R1, R2, R3 — personalization without measurement is a regression risk, not an improvement by default.
5. **Priority/guard rule added** for R1: hard constraints > explicit user request > calendar > behavioral preference > AI optimization — encoded in the scheduler contract, not left implicit in the prompt.
6. **R3 distinguishes invalid output from ambiguous intent** — the extraction schema must represent "unknown/inferred/ambiguous" fields, not force a guess.
7. **PR breakdown expanded to 5 PRs**, splitting R2 into a deterministic MVP (PR4) and an optional AI-enhancement follow-up (PR5) gated on PR4's measured results.
8. **`typicalDeepWorkHour` relabeled conceptually** (not the field name — see §0.9) — the metric only proves "long tasks were completed around this hour," not that the user prefers deep work then; it may just reflect their calendar/work schedule. Docs and the AI-facing prompt now describe it accordingly.
9. **API compatibility verified before implementation, per review.** Checked `BehaviorPattern` and `BehaviorMemorySnapshot` in `BehaviorMemorySnapshot.swift`: `BehaviorPattern` is an existing public struct (`id, category, summary, confidence: Double, lastObservedAt`) used for narrative pattern summaries, unrelated in shape to numeric hour/duration data. `BehaviorMemorySnapshot.typicalDeepWorkHour: Int?` and `.preferredFlowDurationMinutes: Int?` already exist as **flat top-level optional fields**, not nested inside `patterns`. `BehaviorMemorySnapshot` is public API consumed by `ProactiveActionsBuilder.loadBehaviorMemory()` (LookAfterFeatures), `DefaultBehaviorAnalysisEngine`, and `BehaviorMemoryStoreTests`. **The previous revision's proposed nested `typicalDeepWorkWindow { hour, sampleCount, confidence }` structure is corrected below (§1.1) to preserve the existing flat fields and add sample-count/confidence as new companion fields instead of restructuring the type.**
10. **Confidence model strengthened** — sample count alone doesn't imply a strong preference; added a concentration/dominance check.
11. **Priority hierarchy is now an architectural requirement enforced by the deterministic validator**, not only prompt guidance.
12. **R3: "AI extraction ≠ AI invention" rule added** — a field may only be extracted when explicitly stated or inferable via an existing deterministic default policy; not inferred purely by LLM guess.
13. **R3: cross-field validation added** (e.g. `scheduledAt` after `deadline`, `scheduledAt` in the past, priority/urgency mismatched with stated tone).
14. **R2: prediction window and outcome taxonomy defined** for precision measurement; deferral/completion/deletion/manual-reschedule are tracked as distinct outcomes, not lumped into "not a false positive."
15. **R2: match-reason telemetry added** (`same-life-area` / `title-overlap` / `deferral-count`) so a future 3B decision is evidence-based.
16. **Metrics section now requires baseline/cohort/window/threshold definitions**, not just metric names.
17. **R1 explainability added** — personalized suggestions should carry a short human-readable reason, so bad inferences are visible and correctable rather than silent.
18. **R1 timezone behavior defined** — verified `hourOfDay` is computed from `Calendar.current` at event-recording time and permanently fixed into the stored event; documented as an accepted limitation for cross-timezone travel rather than silently ignored (§1.1).
19. **R1 mode-tie handling defined** — a tie between top hours yields `nil` (no fabricated preference) instead of depending on iteration/dictionary order (§1.1).
20. **R1 validator responsibility clarified** — candidate-space construction (existing hard-constraint logic) vs. the validator's final authoritative enforcement are explicitly separated, preventing the implementing agent from duplicating constraint logic or over-filtering before the AI ever sees candidates (§1.2).
21. **R3 provenance added alongside status** — `known`/`inferred` fields now carry a `source` (`explicit_user_text | deterministic_policy | model_inference`), with `model_inference`-sourced `priority`/`estimatedMinutes` downgraded to `unknown` unless explicitly allowed (§2.1).
22. **R2 telemetry explicitly restricted to features/scores/counts** — raw task titles/content must not be logged in evaluation telemetry (§3.1).
23. **Golden evaluation cases added** for R1 and R3 (§4) as a repeatable AI regression suite, distinct from unit tests, for use whenever the prompt/model changes.

---

## Phase 1 — Behavior-Driven Scheduling Personalization (Recommendation 1)

### Step 1.1 — Populate `BehaviorMemorySnapshot`'s existing fields deterministically (no LLM)

**File:** `Packages/LookAfterCore/Sources/LookAfterCore/Models/Flow/BehaviorMemorySnapshotBuilder.swift`

**API-compatibility constraint (verified against `BehaviorMemorySnapshot.swift`):** `typicalDeepWorkHour: Int?` and `preferredFlowDurationMinutes: Int?` already exist as flat top-level optional fields on the public, cross-package-consumed `BehaviorMemorySnapshot` type (consumed by `ProactiveActionsBuilder.loadBehaviorMemory()`, `DefaultBehaviorAnalysisEngine`, `BehaviorMemoryStoreTests`). `BehaviorPattern` is a separate, unrelated existing type (`id, category, summary, confidence: Double, lastObservedAt`) used for narrative pattern summaries, not numeric hour/duration data. **Do not restructure these into a nested object** — add new optional companion fields for sample size/confidence instead, keeping the existing fields' names and types unchanged:

```text
BehaviorMemorySnapshot   (existing fields unchanged)
 ├── typicalDeepWorkHour: Int?                     (existing)
 ├── typicalDeepWorkHourSampleCount: Int?          (new)
 ├── typicalDeepWorkHourConfidence: PatternConfidence?  (new, see below)
 ├── preferredFlowDurationMinutes: Int?            (existing)
 ├── preferredFlowDurationSampleCount: Int?        (new)
 ├── preferredFlowDurationConfidence: PatternConfidence?  (new)
 ├── patterns: [BehaviorPattern]                   (existing, unrelated — untouched by this step)
 ├── deferralRecords: [TaskDeferralRecord]         (existing, untouched)
 └── recordedEventCount / completionEventCount / deferralEventCount / flowSessionEventCount (existing)
```

- **Naming/semantics correction:** `typicalDeepWorkHour` (the field name stays, since it's existing public API and a rename is a breaking migration out of scope here) is documented and surfaced to the AI prompt as **"typical hour long-focus tasks are completed"**, not "preferred deep-work time." The metric only proves _when long tasks were completed_, which may reflect calendar/work-schedule constraints rather than a genuine preference — let the AI (Step 1.2) reason about whether it's actionable, don't bake the "deep work" interpretation into the metric itself. In code, name the internal computed value accordingly (e.g. a private `longTaskCompletionHourMode` before it's assigned to the public `typicalDeepWorkHour` field) so the codebase itself doesn't reinforce the overclaim.
- Compute `typicalDeepWorkHour`: mode of `hourOfDay` (from `BehaviorContextMetadata`) across `taskCompletion` events where `durationMinutes >= 30`.
- Compute `preferredFlowDurationMinutes`: median `durationMinutes` across `flowSessionEnded` events.
- **Duration-bias-by-lifeArea is out of scope for this step** (see §0.1) — do not attempt to reconstruct `estimatedMinutes` from current `LifeTask` state.
- **Timezone behavior (verified against `BehaviorContextMetadata.from(context:at:calendar:)`):** `hourOfDay` is computed as `calendar.component(.hour, from: date)` with `calendar: Calendar = .current` **at event-recording time** — i.e. it reflects the device's local hour at the moment the event was recorded, permanently fixed into the stored event. This is correct for the common case (user stays in one timezone) but has a known limitation: a user who travels will have historical events whose `hourOfDay` values are in different timezones, mixed together in the same aggregation, with no way to normalize after the fact since the original UTC offset isn't stored. **Decision for this step: accept this as a documented limitation, do not attempt timezone normalization** (no reliable UTC-offset field exists on `BehaviorContextMetadata` to correct it). If this becomes a measured problem (e.g. via Step 1.4 metrics showing degraded suggestion quality for frequent travelers), a follow-up would add a stored UTC-offset field to `BehaviorContextMetadata` at record time — that is out of scope here, not implied by this plan.
- Guard: only emit a value when sample count ≥ a minimum threshold (e.g. 5 events) to avoid overfitting on sparse history — leave `nil` otherwise.
- **Confidence is not sample count alone.** Sample count can be high while the underlying hour distribution is flat (e.g. 5 events each at 09/12/15h — no real preference). Compute a **concentration ratio** (`modeCount / totalCount`) alongside sample count, and require both to be sufficient before assigning `.medium`/`.high`:

```text
PatternConfidence: .low | .medium | .high

sampleCount < 5              → nil (omit)
sampleCount 5–14             → .low  (regardless of concentration — insufficient evidence either way)
sampleCount >= 15:
  concentration < 0.4        → .low  (weak signal despite volume)
  concentration 0.4–0.6      → .medium
  concentration > 0.6        → .high
```

  (Thresholds are illustrative starting points, tune during implementation/testing — the requirement is that concentration, not just count, gates `.medium`/`.high`.)

- **Deterministic mode-tie handling (required, do not leave to dictionary/array iteration order):** when two or more hours have the same top count, **do not fabricate a preference** — treat it as no strong typical-hour signal: emit `typicalDeepWorkHour = nil` (and omit sample count/confidence) rather than arbitrarily picking the earliest or a dictionary-order-dependent hour. A tie is itself evidence the data doesn't support a single typical hour.

**Testing:** New unit tests in `BehaviorMemorySnapshotBuilderTests` (or equivalent) covering: empty history → nil; below-threshold count → nil; high count + low concentration (flat distribution) → `.low`, not `.high`; high count + high concentration → `.high`; **tied mode counts → `nil`, verified deterministic across repeated runs** (guards against relying on hash-order); correct mode/median values in each case.

### Step 1.2 — Wire snapshot into scheduling prompt context, with an explicit priority contract

**Files:** `Packages/LookAfterFeatures/Sources/LookAfterFeatures/Planning/AIScheduleSlotService.swift`, `DailyPlannerViewModel.swift` (`schedulingPrompt`).

- Extend `DayContext` (or the prompt-building input struct) with an optional `behaviorSnapshot: BehaviorMemorySnapshot?` field.
- In `schedulingPrompt(for:calendar:)`, append a short behavioral-context block to the prompt text only when the relevant confidence field is `.medium` or `.high` (never surface `.low`/`nil` signals to the model — avoid noise on sparse-history users). Phrase the signal neutrally, e.g. "User has historically completed long-focus tasks around {hour}:00 ({sampleCount} occurrences)" — not "user prefers deep work at {hour}:00."
- Update `LookAfterPrompts.dailySchedulerSystem` (or the per-call prompt) with an **explicit priority ordering** the model must follow, matching the product's non-negotiables:

```text
1. Hard constraints (fixed commitments, deadlines)
2. Explicit user request for this session
3. Calendar commitments
4. Behavioral preference (typicalDeepWorkHour, preferredFlowDuration) — advisory only
5. General AI optimization
```

- **Architectural requirement (not just a prompt instruction):** behavioral context may influence ranking/ordering of candidate slots only; it must never alter or bypass deterministic constraint validation. **Clarification on responsibilities, to avoid the implementing agent duplicating scheduling logic in two places:**
  - **Candidate-space construction** (hard constraints, deadlines, calendar busy blocks) defines which slots are _eligible_ to be proposed at all. This is existing logic — it is not a new "pre-check" gate added by this plan, just the existing constraint-driven slot generation the AI already selects from.
  - **The AI ranks/selects within that already-constrained space** — it should not be handed slots that are already known-invalid, but it is also not re-deriving or re-validating hard constraints itself.
  - **The existing `DayScheduleSuggestionValidator` (or equivalent) is the single authoritative, final enforcement point**, running after the AI proposes a slot, rejecting/repairing any suggestion that violates hard constraints, deadlines, or calendar conflicts — regardless of what the LLM output contains or what the candidate space looked like. Do not add a second independent constraint-checking pass; the validator is authoritative, not a second copy of candidate-space filtering.
  - Flow: `Hard constraints define candidate slot space → AI ranks/selects within that space (behavioral preference as tiebreaker/ranking signal) → validator performs final, authoritative enforcement → only valid suggestions reach UI`. The LLM is never trusted to self-enforce priority ordering, and no scheduling-constraint logic should be duplicated between candidate-space construction and the validator.
- **Explainability:** when a suggestion is influenced by a behavioral pattern at `.medium`/`.high` confidence, the returned suggestion should carry a short human-readable reason (e.g. surfaced via the existing `aiReasoningNote` field on `LifeTask` or an equivalent field on the suggestion type) such as "Scheduled at 9:00 AM because you've historically completed longer tasks around this time" — so a bad inference is visible and correctable, not silently applied.

**Testing:** Snapshot-based prompt-string tests confirming: the behavioral block appears only at medium/high confidence; is omitted at low/no confidence; existing `AIScheduleSlotService`/`DailyPlannerViewModel` tests still pass unchanged when `behaviorSnapshot` is `nil` (backward compatible default). Add a regression test asserting a calendar conflict is never overridden by a behavioral-preference suggestion in the validator (`DayScheduleSuggestionValidator`) — this is a required test, not optional, since it enforces the architectural guarantee above. Add a test confirming the reasoning note is present when a medium/high-confidence pattern influenced the suggestion, absent otherwise.

### Step 1.3 — Threading the snapshot through call sites

- Identify where `AIScheduleSlotService`/`DailyPlannerViewModel` are invoked (likely `TasksViewModel`/`FlowDirector`) and pass the already-computed `BehaviorMemorySnapshot` from `BehaviorAnalysisEngineProtocol.buildSnapshot` down to the scheduling call.
- No new stores needed — `BehaviorMemoryStore.fetchEvents()` → `DefaultBehaviorAnalysisEngine.buildSnapshot(from:)` is already the existing pipeline; only the consumer at the scheduling layer needs the new parameter.

**Risk control:** Keep this fully additive — default parameter `nil`, so no existing call site breaks; roll out behind `TaskManagementPreferences.highQualitySchedulingEnabled` or a new feature flag if desired for staged rollout.

### Step 1.4 — Evaluation metrics (required before wide rollout)

**Definitions required before implementation** (a metric name alone is not measurable):

- **Cohort:** flag-on vs. flag-off, same eligibility criteria (e.g. users with ≥15 recorded behavior events, so both cohorts could theoretically have received a personalized suggestion).
- **Baseline period:** 2 weeks of flag-off data per user before enrollment, or a concurrent flag-off control cohort — pick one and document it consistently across R1/R2/R3.
- **Minimum sample size:** define per-metric (e.g. ≥30 scheduling proposals per user before including that user's rate in aggregate reporting) to avoid single-user noise skewing cohort averages.
- **Measurement window:** 7-day rolling window per proposal, matching the re-deferral definition below.
- **Success threshold:** define what "better" means numerically before shipping (e.g. "personalized-cohort acceptance rate ≥ flag-off cohort rate, with re-deferral rate not worse by more than X pts") — not left to post-hoc interpretation.

Metrics tracked, per cohort:

- **Schedule acceptance rate** = proposals accepted without edits / proposals shown.
- **AI suggestion abandonment rate** — a proposal accepted but then substantially rewritten/rescheduled shortly after should count against acceptance, not as a success; track separately from a clean accept.
- Re-deferral rate (same task/pattern deferred again within 7 days, matching the R2 window for consistency).
- Manual reschedule / override rate after an AI-personalized suggestion.
- Task completion rate for personalized vs. non-personalized suggestions.

Without these, personalization changes ship un-validated — sounding smarter is not the same as being better.

---

## Phase 2 — Natural-Language Task Capture Enrichment (Recommendation 3)

### Step 2.1 — Define the extraction schema

**File:** `Packages/LookAfterAI/Sources/LookAfterAI/Prompts/LookAfterPrompts.swift`

- Add a new prompt template (e.g. `naturalLanguageTaskCaptureSystem`) mirroring the existing `structuredOutputSystem` JSON-only contract.
- Schema: `title`, `estimatedMinutes`, `deadline` (ISO8601 or relative), `scheduledAt` (optional), `priority`, `lifeArea`, `timeConstraint`.

- Distinguish **invalid output** from **ambiguous user intent** in the schema itself: each extractable field (`scheduledAt`, `deadline`, `estimatedMinutes`) carries a status of `known | inferred | ambiguous | unknown`, not just a raw value. E.g. "sometime next week" → `scheduledAt: { status: "ambiguous" }`, not a fabricated timestamp.
- The system prompt must instruct the model to prefer `unknown`/`ambiguous` over guessing when the input doesn't specify a field.
- **"AI extraction ≠ AI invention" rule:** a field may only be marked `known`/`inferred` when it is either explicitly stated in the text or derivable via an existing deterministic default policy already in the codebase (e.g. `TaskDurationPolicy.defaultMinutes` for a missing `estimatedMinutes`, not a model-guessed number). Example: "Call John tomorrow afternoon" → `deadline: inferred (tomorrow, from "tomorrow afternoon")` is fine; `estimatedMinutes` or `priority` must be `unknown` unless a documented default policy applies — the model should not invent them from general judgment.
- **Require provenance alongside status**, not status alone. Each `known`/`inferred` field carries a `source` in addition to `status`:

```text
status: known | inferred | ambiguous | unknown
source: explicit_user_text | deterministic_policy | model_inference   (present only when status != unknown)
```

- `explicit_user_text` — value taken directly from the input (e.g. "Friday 2 PM" → `scheduledAt`).
- `deterministic_policy` — value filled from an existing codebase default/policy (e.g. `TaskDurationPolicy.defaultMinutes`), not the model's judgment.
- `model_inference` — the model derived the value from context without an explicit statement or policy (e.g. inferring `lifeArea` from task phrasing).
- **Product decision required before implementation:** `model_inference` should not qualify as `inferred` for fields like `priority`/`estimatedMinutes` unless explicitly allowed — for those fields, `model_inference`-sourced values should be downgraded to `unknown` rather than surfaced as a confident inference. This distinction also makes debugging extraction-quality regressions far easier (e.g. "did quality drop because `model_inference` sources are less accurate?" is answerable from telemetry once source is recorded).

### Step 2.2 — Extraction call + validation

**File:** New or existing service near `TasksViewModel` (e.g. a `NaturalLanguageTaskCaptureService`).

- Call `GLMService.complete(prompt:systemPrompt:tier:)` with the free-text input and new system prompt.
- Decode JSON into an `InboxTaskDraft`-compatible structure; reuse existing decode/validation utilities (mirror `DayScheduleSuggestionValidator` pattern) to clamp/repair **invalid** values (e.g. negative minutes, invalid enum strings) before constructing a draft.
- Do **not** repair `ambiguous`/`unknown` fields by inventing a value — pass the status through to the review UI so it can prompt the user only for the specific missing high-value fields, instead of silently guessing.
- **Add cross-field (semantic consistency) validation**, not just per-field validity, via a new/extended `InboxTaskDraftValidator` (or equivalent):
  - `scheduledAt` after `deadline` → reject/flag for review.
  - `scheduledAt` in the past → flag for review/repair, don't silently accept.
  - `deadline` text implies "tomorrow" but extracted `scheduledAt` is weeks out → flag as inconsistent.
  - `priority = urgent` extracted while the text implies low urgency (e.g. "whenever," "no rush") → flag for review rather than trusting the enum in isolation.

**Testing:** Add cases for `ambiguous`/`unknown` status fields alongside the existing valid/malformed/missing-field cases, asserting the draft surfaces the status rather than a fabricated value. Add cross-field validator tests for each inconsistency rule above (conflicting dates, mismatched urgency).

### Step 2.3 — Wire into existing capture UI/flow

**File:** `Packages/LookAfterFeatures/.../Tasks/ViewModels/TasksViewModel.swift`

- Add a new entry point (e.g. `createFromNaturalLanguage(_ text: String, userId: String) async throws -> InboxTaskDraft`) that returns a draft for **review**, not direct commit — reuse the existing inbox-draft review UI so the trust model matches `createFromInbox`.
- On confirm, route to existing `createFromInbox`/`createScheduledFromCapture`.

**Testing:** Unit tests around the JSON decode/validation/clamping logic using canned GLM responses (valid, malformed, partially missing fields); no test should hit the network — use the existing `debugCompleteHandler` hook on `GLMService` for deterministic test doubles.

### Step 2.4 — Evaluation metrics

Track: field extraction accuracy (spot-check sample), edit-before-confirm rate, confirmation rate, task-creation completion rate, time-to-create-task vs. manual entry.

---

## Phase 3 — Deferral-Risk Early Warning (Recommendation 2)

_Depends on Phase 1's pattern extraction utilities being in place. Reclassified per review: this is a **deterministic heuristic MVP**, not an AI feature — AI/embeddings are an optional follow-up (Phase 3B) gated on measured precision from the MVP._

### Phase 3A — Deferral-Risk Heuristic MVP (deterministic, no LLM)

#### Step 3.1 — Similarity matching

**File:** New helper, e.g. `Packages/LookAfterCore/Sources/LookAfterCore/Notifications/DeferralRiskMatcher.swift`.

- Input: a newly scheduled `LifeTask` + historical `[TaskDeferralRecord]` + originating task metadata (`lifeAreaRawValue`, `title`, `requiredEnergy`) needed to generalize beyond exact `taskID` (recurring occurrences get new ids daily).
- Matching heuristic (deterministic): same `lifeArea` + similar title tokens (case-insensitive substring/word-overlap) + `deferralCount >= threshold` (e.g. 3).
- Output: a confidence score; only surface above a fixed cutoff to control false positives.
- **Log the match reason** alongside each flagged candidate (e.g. `same-life-area`, `title-overlap`, `deferral-count`, or a combination) so that if Phase 3B is later evaluated, there's evidence for _which_ matches the heuristic is weak on (e.g. same-life-area-but-no-token-overlap cases like "pay rent" vs. "landlord transfer" — the exact failure mode token overlap can't catch), rather than a single opaque precision number.
- **Telemetry must be feature-based and privacy-safe — explicit requirement, not left to implementer discretion.** Log only structured features/reasons, never raw task titles or free-text content:

```text
// Correct — features only:
matchReasons = [.sameLifeArea, .titleTokenOverlap]
overlapScore = 0.67
deferralCount = 4

// Incorrect — do not log:
"Prepare quarterly financial presentation" matched "Prepare Q4 financial presentation"
```

  Task titles/content may exist in local on-device storage already (`BehaviorMemoryStore`), but the **evaluation telemetry** used to decide Phase 3B (Step 3.3 metrics) must not persist/export raw titles — only the enum-based match reasons, numeric scores, and counts. Apply the same rule to any future logging/export path (e.g. if evaluation data is ever aggregated off-device).

#### Step 3.2 — Notification candidate wiring

**File:** `Packages/LookAfterCore/Sources/LookAfterCore/Notifications/NotificationCandidateBuilder.swift`

- Add a new candidate-building function (e.g. `patternInsightCandidates(tasks:deferralRecords:now:)`) using `DeferralRiskMatcher`, emitting `NotificationCandidate(kind: .patternInsight, ...)`.
- Call it from `build(from:calendar:)` alongside the other candidate builders.
- No changes needed to `NotificationPolicyEngine` — `.patternInsight` priority (9) and cap logic already exist.

**Testing:** Unit tests on `DeferralRiskMatcher` (matches above/below threshold, no match on different `lifeArea`) and on the new candidate builder (correct `NotificationCandidate` shape, dedup with existing `taskDue` candidates for the same task).

#### Step 3.3 — Evaluation metrics (required before considering Phase 3B)

- **Prediction window defined:** a flag is scored as a **true positive** if the flagged task is deferred again **within 7 days** of the flag being generated. A flag with no deferral within 7 days is scored based on outcome taxonomy below — not automatically a false positive.
- **Outcome taxonomy** (mutually exclusive, tracked separately — do not collapse into "not deferred = false positive"):
  - `deferred-again` (true positive)
  - `completed` (arguably a true negative — risk didn't materialize)
  - `deleted` (inconclusive — exclude from precision calculation)
  - `manually-rescheduled` (inconclusive — user acted before a natural deferral could occur; exclude or track separately)
  - `no-action-window-expired` (ambiguous; count as false positive only if the task remained pending and unchanged for the full window)
- Additional metrics: dismissal rate, user action rate (did the nudge change behavior?), repeat-deferral rate.
- These numbers, split by match-reason (from Step 3.1's logging), determine whether Phase 3B is justified and _for which failure mode_.

### Phase 3B — Semantic/AI Enhancement (optional, only if 3A's precision is insufficient)

- Only pursue if Step 3.3's metrics show the deterministic token-overlap matcher has unacceptable precision/recall (e.g. missing clearly-related titles that don't share tokens, such as "pay rent" vs "landlord transfer").
- If pursued: replace/augment the title-similarity step with embedding-based semantic similarity; reserve full LLM classification for cases embeddings still can't resolve confidently.
- Do not build this speculatively — it is explicitly gated on 3A's measured gap, not scheduled by default.

---

## Phase 4 — Golden Evaluation Cases (R1 and R3)

Unit tests validate implementation correctness; golden cases validate **AI behavior against known-good/known-bad outcomes**, and must be re-run whenever the prompt or model changes (unlike unit tests, which validate deterministic Swift code paths that don't change with the model).

### R1 golden cases (scheduler personalization)

| Input | Expected outcome |
| --- | --- |
| Calendar has a 9–11 AM meeting; behavioral pattern says typical long-task-completion hour = 9 AM (high confidence) | AI must **not** schedule the task at 9 AM — validator rejects/repairs any suggestion overlapping the meeting regardless of prompt content |
| No calendar conflict; behavioral pattern says 9 AM (high confidence) | AI **may** prefer 9 AM, and the suggestion should carry an explainability reason referencing the pattern |
| Behavioral pattern confidence is `.low` (or tied/omitted per §1.1) | The behavioral block must not appear in the prompt at all — suggestion should look identical to a non-personalized one |

### R3 golden cases (natural-language capture)

| Input | Expected outcome |
| --- | --- |
| "Prepare presentation Friday 2 PM" | `scheduledAt: known, source: explicit_user_text` — no fabricated fields for anything not stated |
| "Prepare presentation sometime next week" | `scheduledAt: ambiguous` — not resolved to a specific fabricated timestamp |
| "Prepare presentation whenever" | `priority` and `deadline` remain `unknown` — not defaulted to `medium`/a fabricated date; no `model_inference`-sourced guess presented as confident |

These cases should live as a small, explicitly-named regression suite (e.g. `AISchedulingGoldenCaseTests`, `NaturalLanguageCaptureGoldenCaseTests`) using the existing `debugCompleteHandler`/deterministic test-double pattern already used elsewhere in the plan, so they run in CI without live model calls.

---

## Cross-Cutting Concerns

- **Privacy:** All new logic operates on data already stored locally (`BehaviorMemoryStore`, `TaskDeferralRecord`) — no new data collection required for R1/R2. R3 sends free-text task descriptions to GLM, same trust boundary as existing `createFromInbox`.
- **Cost/latency:** R1 adds a short text block to an already-existing GLM call (no new call). R3 adds one new GLM call per natural-language capture (user-initiated, low frequency). R2 is deterministic — zero new GLM calls.
- **Rollback safety:** All three are additive with `nil`-safe defaults; can be disabled independently (feature flags or simply not calling the new entry points) without touching existing deterministic paths.

## Suggested PR Breakdown

1. **PR 1** — Step 1.1 (behavior telemetry → deterministic pattern builder, with confidence/sample size) + tests only. No user-visible behavior change.
2. **PR 2** — Steps 1.2–1.4 (R1 scheduler personalization: prompt wiring, priority contract, feature flag, evaluation metrics).
3. **PR 3** — Phase 2 (R3 natural-language capture) — self-contained new entry point, existing review UI, fully user-initiated.
4. **PR 4** — Phase 3A (R2 deterministic deferral-risk MVP) — depends on PR 1's aggregation helpers; metrics (Step 3.3) shipped alongside, not after.
5. **PR 5** — Phase 3B (R2 semantic/AI enhancement) — only scheduled if PR 4's metrics demonstrate a precision/recall gap the deterministic matcher can't close.

## Recommended User-Facing Rollout Order

The 5-PR code-shipping order above is unchanged. The actual **feature-flag enablement / measurement** order is sequential, with a measurement gate between each stage:

```text
PR1 — Behavior snapshot infrastructure (no user-visible change)
        ↓
PR2 — Behavior-aware scheduler (flag-gated)
        ↓
     Measure (Step 1.4 metrics, minimum window/sample size met)
        ↓
PR3 — Natural-language task capture
        ↓
     Measure (Step 2.4 metrics)
        ↓
PR4 — Deferral-risk deterministic MVP
        ↓
     Measure precision (Step 3.3 outcome taxonomy, by match-reason)
        ↓
PR5 — Semantic/AI enhancement — ONLY if data proves it's needed
```

Each stage's flag stays off for the next cohort until its own measurement gate is met — features are not enabled in parallel before their individual metrics are validated.
