# AI Opportunity & Implementation Plan

_Status: Approved plan — source of truth for the R1/R2/R3 AI initiative. Supersedes `ai-opportunity-discovery-2026-09.md` (removed) and `ai-opportunity-implementation-plan-2026-09.md` (retained, marked superseded)._

**Related documentation (not duplicated here):**
- [`ATTENTION_OS_SPEC.md`](ATTENTION_OS_SPEC.md) — canonical product spec; defines the "AI explains, deterministic engine decides" boundary (Flow Director/ExecutiveBrain own scheduling decisions, LLM generates copy only) and the **max-2-proactive-notifications-per-day** product constraint referenced in Section 7.
- [`architecture/dependencies.md`](architecture/dependencies.md) — canonical package dependency graph (`LookAfterCore`, `LookAfterAI`, `LookAfterData`, `ExecutiveBrain`, `LookAfterFeatures`).
- [`qa/README.md`](qa/README.md) and [`qa/07-ai-validation.md`](qa/07-ai-validation.md) — canonical QA/validation framework for all AI surfaces, including GLM prompt evaluation rubrics; this document defines what to test, that framework defines how it is executed and gated for release.
- [`architecture-audit-2026-09.md`](architecture-audit-2026-09.md) — unrelated general architecture/bug audit; not part of this AI initiative.

## 1. Objective

Finish already-scaffolded personalization and prediction hooks that the app already collects data for but does not yet use: behavioral history for scheduling, deferral-prone task detection, and natural-language task capture. The goal is incremental, measurable, reversible AI augmentation of existing deterministic workflows — not new AI infrastructure or a chatbot/general-assistant expansion.

## 2. Current State

- `BehaviorMemoryStore` (actor, append-only) already records every task completion, deferral, and flow session with duration and environment context.
- `BehaviorMemorySnapshot` already exposes `patterns: [BehaviorPattern]`, `preferredFlowDurationMinutes: Int?`, `typicalDeepWorkHour: Int?` — currently hard-coded to `nil`/`[]` in `BehaviorMemorySnapshotBuilder`/`DefaultBehaviorAnalysisEngine`.
- `NotificationCandidateKind.patternInsight` exists in the enum with a reserved priority (9) but has no candidate-builder path producing it.
- `AIScheduleSlotService` / `DailyPlannerViewModel.proposeReschedule` already call GLM for daily scheduling, but prompt context (`DayContext`) does not include behavioral history.
- `TasksViewModel.createFromInbox` already performs AI-assisted structured extraction (`resolveSemanticProfile`) using `LookAfterPrompts.structuredOutputSystem`; this pattern is proven and reusable.
- `ExecutiveBrainEngine`'s deterministic decision pipeline explicitly excludes the LLM ("The LLM is NOT in this pipeline") — this is an intentional architecture boundary, not a gap, and must not be replaced.

## 3. Guiding Principles

- AI augments existing workflows; it does not replace deterministic decision-making where deterministic logic is already better.
- AI must not invent user information (dates, priorities, durations) that is not explicitly stated or derivable via an existing deterministic default policy.
- AI cannot override hard constraints (calendar conflicts, deadlines) — a deterministic validator is always the final authority.
- Consequential changes (schedule changes, task creation) require human-in-the-loop review before commit.
- New AI behavior must ship with objective, measurable success criteria (cohort/baseline/window/threshold), not just a metric name.
- MVPs are incremental, additive (`nil`-safe defaults), reversible via feature flag, and deterministic-first where a deterministic solution suffices.

## 4. Opportunity Summary

| ID | Opportunity | Current Gap | AI Role | MVP | Priority |
| -- | ----------- | ----------- | ------- | --- | -------- |
| R1 | Behavior-Driven Scheduling Personalization | Behavioral history recorded but never fed into scheduling | Ranks/reasons over deterministic pattern data already in prompt | Deterministic pattern extraction + advisory prompt context | 1 |
| R3 | Natural-Language Task Capture | Manual task creation requires explicit fields despite proven free-text extraction elsewhere | Structured JSON extraction (known/inferred/ambiguous/unknown) | Extraction → validation → review → existing create flow | 2 |
| R2 | Deferral-Risk Early Warning | Deferral counts recorded but never matched against new/recurring tasks | None in MVP — deterministic similarity matching only | Rule-based matcher → `.patternInsight` notification | 3 |

---

# 5. R1 — Behavior-Driven Scheduling Personalization

### Current Flow
`BehaviorMemoryStore.fetchEvents()` → `DefaultBehaviorAnalysisEngine.buildSnapshot(from:)` → `BehaviorMemorySnapshot` (mostly empty today) → not consumed by scheduling. Separately, `AIScheduleSlotService.aiSuggestions` / `DailyPlannerViewModel.proposeReschedule` call `GLMService.complete` with `LookAfterPrompts.dailySchedulerSystem`, with no behavioral input.

### Problem
Every user receives the same scheduling logic regardless of their own completion-time patterns and deferral-prone task types.

### Existing Data
`BehaviorEvent` (`kind`, `taskID`, `lifeAreaRawValue`, `recordedAt`, `durationMinutes`, `context` incl. `hourOfDay`), `TaskDeferralRecord` (`deferralCount`, `lastDeferredAt`).

### Deterministic Behavior Analysis

**File:** `Packages/LookAfterCore/Sources/LookAfterCore/Models/Flow/BehaviorMemorySnapshotBuilder.swift`

`BehaviorMemorySnapshot`'s existing flat fields are preserved unchanged; only new optional companion fields are added:

```text
BehaviorMemorySnapshot   (existing fields unchanged)
 ├── typicalDeepWorkHour: Int?                          (existing)
 ├── typicalDeepWorkHourSampleCount: Int?               (new)
 ├── typicalDeepWorkHourConfidence: PatternConfidence?  (new)
 ├── preferredFlowDurationMinutes: Int?                 (existing)
 ├── preferredFlowDurationSampleCount: Int?             (new)
 ├── preferredFlowDurationConfidence: PatternConfidence? (new)
 ├── patterns: [BehaviorPattern]                        (existing, unrelated struct — untouched)
 ├── deferralRecords: [TaskDeferralRecord]               (existing, untouched)
 └── recordedEventCount / completionEventCount / deferralEventCount / flowSessionEventCount (existing)
```

`BehaviorPattern` (`id, category, summary, confidence: Double, lastObservedAt`) is a separate, unrelated existing type used for narrative summaries — do not conflate it with the numeric hour/duration fields above. `BehaviorMemorySnapshot` is public API consumed by `ProactiveActionsBuilder.loadBehaviorMemory()`, `DefaultBehaviorAnalysisEngine`, and `BehaviorMemoryStoreTests`; the field names must not be renamed or restructured into a nested object.

- **`typicalDeepWorkHour`** — mode of `hourOfDay` across `taskCompletion` events where `durationMinutes >= 30`. Semantics: "typical hour long-focus tasks were historically completed" — this reflects when long tasks happened to finish (which may be a calendar/work-schedule artifact), not a proven user preference. Do not claim it proves a true preference; surface it neutrally to the AI and let it reason about actionability.
- **`preferredFlowDurationMinutes`** — median `durationMinutes` across `flowSessionEnded` events.
- **Historical duration bias is out of scope.** `BehaviorEvent` only stores actual `durationMinutes` at record time; there is no `estimatedMinutes` field, and reconstructing it by joining against current `LifeTask` state is unreliable (task may have been edited/deleted since — survivorship bias). This is deferred until a reliable historical-estimate source exists (e.g. snapshotting `estimatedMinutes` into the event itself, a separate data-model change).
- **Timezone:** `hourOfDay` is computed from `Calendar.current` at event-recording time and fixed permanently into the event. Historical events from different timezones (e.g. travel) mix in aggregation with no stored UTC offset to correct after the fact. This is an accepted, documented limitation — no normalization is attempted unless later metrics show a measured problem for frequent travelers.
- **Sample-size guard:** only emit a value when sample count ≥ 5; otherwise `nil`.
- **Mode-tie handling:** if two or more hours tie for the top count, do not fabricate a preference — emit `nil` (and omit sample count/confidence) rather than depending on iteration/dictionary order. A tie is itself evidence against a single typical hour.
- **Confidence is concentration-based, not sample-count alone** — a flat distribution with many samples still implies no real preference:

```text
PatternConfidence: .low | .medium | .high

sampleCount < 5              → nil (omit)
sampleCount 5–14             → .low
sampleCount >= 15:
  concentration < 0.4        → .low
  concentration 0.4–0.6      → .medium
  concentration > 0.6        → .high
```
(`concentration = modeCount / totalCount`; thresholds are starting points, tunable during implementation.)

### Scheduling Integration

**Files:** `AIScheduleSlotService.swift`, `DailyPlannerViewModel.swift` (`schedulingPrompt`).

- Extend the prompt-building input (`DayContext` or equivalent) with an optional `behaviorSnapshot: BehaviorMemorySnapshot?`.
- Append a behavioral-context block to the prompt **only** when the relevant confidence field is `.medium`/`.high` — never surface `.low`/`nil` signals. Phrase neutrally: "User has historically completed long-focus tasks around {hour}:00 ({sampleCount} occurrences)" — not "user prefers deep work at {hour}:00."
- Default parameter is `nil` — fully additive, no existing call site breaks. Roll out behind a feature flag (e.g. `TaskManagementPreferences.highQualitySchedulingEnabled` or a new flag).

### Constraint Contract

```text
Hard constraints (fixed commitments, deadlines)
> Explicit user request for this session
> Calendar commitments
> Behavioral signal (typicalDeepWorkHour, preferredFlowDuration) — advisory only
> General AI optimization
```

This is an architectural requirement enforced by the deterministic validator, not just prompt guidance:

- **Candidate-space construction** (existing hard-constraint/calendar logic) defines which slots are eligible at all — unchanged, existing logic.
- **The AI ranks/selects only within that already-constrained space**; it never re-derives or re-validates hard constraints itself, and is never trusted to self-enforce priority ordering.
- **`DayScheduleSuggestionValidator`** (or equivalent) is the single, final, authoritative enforcement point — it rejects/repairs any suggestion violating hard constraints, deadlines, or calendar conflicts, regardless of prompt/model output. No second independent constraint-checking pass is added.

### Explainability

When a suggestion is influenced by a `.medium`/`.high`-confidence pattern, it must carry a short human-readable reason (via `aiReasoningNote` on `LifeTask` or an equivalent suggestion field), e.g. "Scheduled at 9:00 AM because you've historically completed longer tasks around this time" — so a bad inference is visible and correctable, not silently applied.

### Testing

- `BehaviorMemorySnapshotBuilderTests`: empty history → nil; below-threshold count → nil; high count + low concentration → `.low`; high count + high concentration → `.high`; tied mode counts → `nil`, deterministic across repeated runs; correct mode/median values.
- Prompt-string tests: behavioral block appears only at medium/high confidence, omitted otherwise; existing scheduler tests pass unchanged with `behaviorSnapshot == nil`.
- Required regression test: a calendar conflict is never overridden by a behavioral-preference suggestion (validator-level).
- Reasoning-note test: present when a medium/high-confidence pattern influenced the suggestion, absent otherwise.
- Golden cases (`AISchedulingGoldenCaseTests`, using `debugCompleteHandler` test doubles, no live model calls):

| Input | Expected outcome |
| --- | --- |
| Meeting 9–11 AM; pattern says 9 AM, high confidence | AI must not schedule at 9 AM — validator rejects/repairs regardless of prompt |
| No conflict; pattern says 9 AM, high confidence | AI may prefer 9 AM; suggestion carries a reasoning note |
| Pattern confidence `.low`/tied/omitted | Behavioral block absent from prompt; suggestion looks non-personalized |

### Evaluation

- **Cohort:** flag-on vs. flag-off, same eligibility (e.g. ≥15 recorded behavior events).
- **Baseline:** 2 weeks flag-off per user, or a concurrent flag-off control cohort (pick one, apply consistently across R1/R2/R3).
- **Minimum sample size:** ≥30 scheduling proposals per user before including in aggregate reporting.
- **Window:** 7-day rolling window per proposal.
- **Metrics:** schedule acceptance rate (accepted without edits / shown); AI suggestion abandonment rate (accepted then substantially rewritten shortly after — counts against acceptance); re-deferral rate (same task/pattern deferred again within 7 days); manual override rate after a personalized suggestion; completion rate, personalized vs. non-personalized.
- **Success threshold:** defined pre-launch, e.g. "personalized-cohort acceptance rate ≥ flag-off rate, re-deferral rate not worse by more than X pts."

### Rollout

Flag off by default → enable for eligible cohort → measure against the gate above → expand only if the gate is met.

---

# 6. R3 — Natural-Language Task Capture

### Current Flow
`TasksViewModel.createFromInbox(_ draft: InboxTaskDraft, ...)` already performs AI-assisted capture via `resolveSemanticProfile`, using the proven `LookAfterPrompts.structuredOutputSystem` JSON-extraction pattern.

### Problem
Manual/scheduled task creation still requires explicit `estimatedMinutes`, `priority`, `difficulty`, `scheduledAt` even though free-text extraction already works elsewhere in this codebase.

### Extraction Schema

**File:** `Packages/LookAfterAI/Sources/LookAfterAI/Prompts/LookAfterPrompts.swift`

New prompt template (e.g. `naturalLanguageTaskCaptureSystem`) mirroring `structuredOutputSystem`. Fields: `title`, `estimatedMinutes`, `deadline`, `scheduledAt` (optional), `priority`, `lifeArea`, `timeConstraint`.

### Known / Inferred / Ambiguous / Unknown

**AI extraction is not AI invention.** Each extractable field (`scheduledAt`, `deadline`, `estimatedMinutes`, etc.) carries:

```text
status: known | inferred | ambiguous | unknown
source: explicit_user_text | deterministic_policy | model_inference   (present only when status != unknown)
```

- `explicit_user_text` — value taken directly from input.
- `deterministic_policy` — filled from an existing codebase default (e.g. `TaskDurationPolicy.defaultMinutes`), not model judgment.
- `model_inference` — model derived the value from context without explicit statement or policy.

A field is `known`/`inferred` only when explicitly stated or derivable via an existing deterministic default policy — never from general model judgment alone. `model_inference`-sourced `priority`/`estimatedMinutes` are downgraded to `unknown` rather than surfaced as confident inferences. The system prompt must instruct the model to prefer `unknown`/`ambiguous` over guessing.

### Validation

**File:** New/extended service near `TasksViewModel` (e.g. `NaturalLanguageTaskCaptureService`) + `InboxTaskDraftValidator` (or equivalent).

- Per-field: clamp/repair genuinely **invalid** values (negative minutes, invalid enum strings) — mirror the `DayScheduleSuggestionValidator` pattern.
- Do not repair `ambiguous`/`unknown` fields by inventing a value — pass status through to the review UI so it prompts the user only for specific missing high-value fields.
- Cross-field validation: `scheduledAt` after `deadline` → reject/flag; `scheduledAt` in the past → flag for review; deadline text implies "tomorrow" but `scheduledAt` is weeks out → flag inconsistent; `priority = urgent` extracted while text implies low urgency (e.g. "whenever," "no rush") → flag for review.

### Review and Commit

New entry point (e.g. `createFromNaturalLanguage(_ text: String, userId: String) async throws -> InboxTaskDraft`) returns a draft for **review**, never a direct commit. On confirm, route through the existing `createFromInbox`/`createScheduledFromCapture` path — no new commit path is introduced.

### Testing

- Unit tests on JSON decode/validation/clamping using canned GLM responses (valid, malformed, partially missing fields) via `GLMService`'s `debugCompleteHandler` test-double hook — no network calls in tests.
- Cases for `ambiguous`/`unknown` fields alongside valid/malformed cases, asserting the draft surfaces status rather than a fabricated value.
- Cross-field validator tests for each inconsistency rule above.
- Golden cases (`NaturalLanguageCaptureGoldenCaseTests`):

| Input | Expected outcome |
| --- | --- |
| "Prepare presentation Friday 2 PM" | `scheduledAt: known, source: explicit_user_text`; nothing else fabricated |
| "Prepare presentation sometime next week" | `scheduledAt: ambiguous` — not resolved to a fabricated timestamp |
| "Prepare presentation whenever" | `priority`/`deadline` remain `unknown` — not defaulted or presented as a confident guess |

### Evaluation

Field extraction accuracy (spot-check sample), edit-before-confirm rate, confirmation rate, task-creation completion rate, time-to-create vs. manual entry.

---

# 7. R2 — Deferral-Risk Early Warning

> **Deterministic MVP — not an AI feature.** No LLM calls in the MVP.

### Current Data
`TaskDeferralRecord` (`deferralCount`, `lastDeferredAt`) aggregated in `BehaviorMemorySnapshotBuilder`; `LifeTask.lifeArea`, `requiredEnergy`, `title`; `NotificationCandidateKind.patternInsight` already declared (priority 9, unused).

### Matching Algorithm

**File:** New helper, e.g. `Packages/LookAfterCore/Sources/LookAfterCore/Notifications/DeferralRiskMatcher.swift`.

Input: newly scheduled `LifeTask` + historical `[TaskDeferralRecord]` + originating task metadata. Recurring occurrences get new IDs daily, so matching generalizes beyond exact `taskID`: same `lifeArea` + similar title tokens (case-insensitive substring/word-overlap) + `deferralCount >= threshold` (e.g. 3).

### Confidence
Output a confidence/overlap score; surface only above a fixed cutoff to control false positives.

### Match Reason
Log the match reason alongside each flagged candidate (`same-life-area`, `title-overlap`, `deferral-count`, or a combination) so any future Phase-3B evaluation has evidence for which failure modes the deterministic matcher is weak on. Telemetry is feature-based and privacy-safe: log only structured features/reasons (`matchReasons`, `overlapScore`, `deferralCount`), never raw task titles/content. This restriction applies to the evaluation telemetry path specifically; it does not require deleting titles from on-device storage where they already exist.

### Notification Integration

**File:** `Packages/LookAfterCore/Sources/LookAfterCore/Notifications/NotificationCandidateBuilder.swift`

New candidate-building function (e.g. `patternInsightCandidates(tasks:deferralRecords:now:)`) called from `build(from:calendar:)` alongside other candidate builders, emitting `NotificationCandidate(kind: .patternInsight, ...)`. No changes needed to `NotificationPolicyEngine` — priority and cap logic already exist for this kind, and it must compete for a slot within the product-wide **max-2-proactive-notifications-per-day** cap (see `ATTENTION_OS_SPEC.md`) rather than being treated as an exception to it.

### Prediction Window
A flag is a **true positive** if the flagged task is deferred again **within 7 days** of the flag being generated.

### Outcome Taxonomy

Mutually exclusive, tracked separately:

```text
deferred-again           → true positive
completed                → true negative (risk didn't materialize)
deleted                  → inconclusive, excluded from precision
manually-rescheduled     → inconclusive, excluded/tracked separately
no-action-window-expired → false positive only if task remained pending/unchanged the full window
```

### Evaluation

Precision (per above taxonomy), dismissal rate, false-positive rate, user action rate (did the nudge change behavior?), repeat-deferral rate — all split by match-reason to determine whether, and for which failure mode, semantic enhancement is justified.

### Testing
Unit tests on `DeferralRiskMatcher` (matches above/below threshold; no match on different `lifeArea`) and on the candidate builder (correct `NotificationCandidate` shape; dedup with existing `taskDue` candidates for the same task).

---

# 8. R2 Phase 3B — Optional Semantic/AI Enhancement

> **Not scheduled by default.** Only pursue if Phase 3A's measured precision/recall (Section 7 evaluation) shows a material semantic gap the deterministic matcher cannot close (e.g. clearly-related titles sharing no tokens, such as "pay rent" vs. "landlord transfer").

Preferred evolution if justified by data:

```text
Deterministic matching → measure → embeddings if required → LLM classification only if still required
```

Do not build this speculatively.

---

# 9. Evaluation Framework

| Feature | Metric | Definition | Cohort/Baseline | Window | Success Threshold |
| --- | --- | --- | --- | --- | --- |
| R1 | Schedule acceptance rate | Proposals accepted without edits / proposals shown | Flag-on vs. flag-off, ≥15 behavior events | 7-day rolling, ≥30 proposals/user | Personalized ≥ flag-off rate |
| R1 | Abandonment rate | Accepted then substantially rewritten/rescheduled shortly after | Same as above | 7-day | Not worse than flag-off |
| R1 | Re-deferral rate | Same task/pattern deferred again | Same as above | 7-day | Not worse by more than agreed X pts |
| R1 | Override rate | Manual reschedule after personalized suggestion | Same as above | 7-day | Not worse than flag-off |
| R1 | Completion rate | Personalized vs. non-personalized | Same as above | 7-day | ≥ flag-off |
| R3 | Extraction accuracy | Spot-checked field-level correctness | Sample of captures | Per release | Defined pre-launch |
| R3 | Edit-before-confirm rate | Drafts edited before commit / drafts shown | All NL captures | Rolling | Lower is better, trend-tracked |
| R3 | Confirmation rate | Drafts confirmed / drafts shown | All NL captures | Rolling | Defined pre-launch |
| R3 | Completion rate | Tasks created via NL capture later completed | All NL captures | 30-day | Comparable to manual entry |
| R3 | Time-to-create | NL capture vs. manual entry | All NL captures | Rolling | Lower than manual |
| R2 | Precision | True positives (`deferred-again` within window) / (true positives + false positives), excluding inconclusive outcomes | All flagged candidates | 7-day | Defined pre-3B decision |
| R2 | Dismissal rate | Notifications dismissed without action / shown | All flagged candidates | 7-day | Trend-tracked |
| R2 | User action rate | Behavior changed after nudge | All flagged candidates | 7-day | Trend-tracked |
| R2 | Repeat-deferral rate, by match-reason | Precision split by `matchReasons` | All flagged candidates | 7-day | Used to gate Phase 3B |

---

# 10. Testing Strategy

### Deterministic Tests
Behavior pattern calculations (`BehaviorMemorySnapshotBuilderTests`), `DayScheduleSuggestionValidator` constraint enforcement, `DeferralRiskMatcher` matching, notification candidate state transitions.

### AI Tests
Golden prompt cases (R1, R3 — see Sections 5 and 6), structured-output decode tests, ambiguous-intent cases, malformed-response handling, regression cases re-run whenever prompt/model changes. All AI tests use `GLMService.debugCompleteHandler` test doubles — no network calls.

### Safety Tests

```text
Calendar conflict + behavioral preference
→ behavioral preference must not override calendar (validator-enforced)

Ambiguous task request
→ AI must not invent missing values; field remains ambiguous/unknown

Stale/older scheduling result
→ must not overwrite valid newer state
```

---

# 11. Cross-Cutting Concerns

- **Privacy:** R1/R2 operate entirely on data already stored locally (`BehaviorMemoryStore`, `TaskDeferralRecord`) — no new data collection. R3 sends free-text task descriptions to GLM, same trust boundary as existing `createFromInbox`. R2 evaluation telemetry records match features/reasons only, never raw task titles/content.
- **Cost/latency:** R1 adds a short text block to an existing GLM call (no new call). R3 adds one new GLM call per capture (user-initiated, low frequency). R2 MVP is fully deterministic — zero new GLM calls.
- **Reliability/Rollback:** All three are additive with `nil`-safe defaults; each is independently disableable via feature flag or by not invoking the new entry point, without touching existing deterministic paths.
- **Feature flags:** Each of R1/R2/R3 ships behind its own flag; flags are enabled sequentially per the rollout gate in Section 13, not all at once.

---

# 12. PR / Implementation Plan

```text
PR1 — Behavior snapshot infrastructure (Step: deterministic pattern builder + confidence/sample size + tests only; no user-visible change)
PR2 — R1 scheduler personalization (prompt wiring, priority contract, feature flag, evaluation metrics)
PR3 — R3 natural-language task capture (self-contained entry point, existing review UI, fully user-initiated)
PR4 — R2 deterministic deferral-risk MVP (depends on PR1's aggregation helpers; metrics shipped alongside, not after)
PR5 — Optional R2 semantic enhancement — CONDITIONAL, only scheduled if PR4's metrics demonstrate a precision/recall gap the deterministic matcher can't close
```

---

# 13. Rollout Strategy

```text
PR1 (no user-visible change)
 ↓
PR2 (flag-gated)
 ↓
measure R1 (Section 9 gate met)
 ↓
PR3
 ↓
measure R3 (Section 9 gate met)
 ↓
PR4
 ↓
measure R2 (Section 9 gate met, by match-reason)
 ↓
PR5 only if evidence justifies it
```

Each stage's flag stays off for the next cohort until its own measurement gate is met — flags are not enabled in parallel before individual gates are validated.

---

# 14. Final Architecture / Data Flows

### R1
```text
Behavior events → deterministic analysis → BehaviorMemorySnapshot
 → AI scheduler (advisory context) → deterministic validator (authoritative)
 → user review → outcome → behavior history
```

### R3
```text
Natural language → AI extraction (known/inferred/ambiguous/unknown)
 → validation (per-field + cross-field) → user review → existing task creation
```

### R2
```text
Task → deterministic deferral matcher → notification
 → outcome (taxonomy) → measurement → optional semantic enhancement (3B, conditional)
```

---

# 15. Final Decision Table

| Decision | Final State |
| --- | --- |
| Historical duration bias (R1) | Deferred — no `estimatedMinutes` reconstruction from `LifeTask` |
| Behavior confidence | Sample size (≥5/≥15) + concentration ratio, not count alone |
| R1 constraint enforcement | Deterministic validator (`DayScheduleSuggestionValidator`) is authoritative; LLM never self-enforces |
| `typicalDeepWorkHour` interpretation | Neutral — "hour long tasks were historically completed," not a proven preference |
| Mode ties (R1) | Emit `nil`, never a fabricated/order-dependent hour |
| R2 MVP | Deterministic, no LLM |
| R2 AI enhancement (3B) | Conditional on measured precision/recall gap |
| R3 AI task creation | Draft only — review required before commit via existing create flow |
| R3 field invention | Not allowed — `unknown`/`ambiguous` preferred over guessing |
| Existing `BehaviorMemorySnapshot` API | Preserved — new fields additive, no renames/nesting |
| Timezone handling (R1) | Accepted limitation, no normalization unless proven necessary by metrics |

---

## Consolidation Summary

**Documents reviewed:** `ai-opportunity-discovery-2026-09.md` (initial discovery/recommendations), `ai-opportunity-implementation-plan-2026-09.md` (post-engineering-review revision, the latest validated decision set).

**Major duplication removed:** Confidence/sample-size, feature-flag, validation, privacy, metrics, and rollout rules were each previously described in both the discovery doc and the review-notes preamble of the implementation plan; each now has one authoritative definition (Sections 5–9). The 23-item numbered "review notes" changelog was converted into final-state statements rather than preserved as a historical log.

**Contradictions resolved:** An earlier proposed nested `typicalDeepWorkWindow{...}` structure (mentioned only as a rejected prior revision) was discarded in favor of the verified existing flat-field API, which this document preserves as final.

**Final decisions preserved:** All R1/R2/R3 design decisions from the implementation plan (Section 0 review notes) are carried forward as the current approved plan — see Section 15 for the decision table.

## Remaining Unresolved Repository Facts

- Exact minimum-sample-size and concentration thresholds (5/15 events, 0.4/0.6 concentration) are stated as illustrative starting points pending tuning during implementation — not yet finalized against real data.
- The specific feature-flag name for R1 (`TaskManagementPreferences.highQualitySchedulingEnabled` vs. a new flag) is not yet decided.
- Baseline methodology (2-week flag-off vs. concurrent control cohort) is not yet chosen — must be picked once and applied consistently across R1/R2/R3 before measurement begins.
