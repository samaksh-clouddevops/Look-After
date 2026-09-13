# Plan — Remaining AI supervision gaps (post Issue-1 fix)

Local working plan only (not a deliverable). Consolidates the call-site audit table plus new
findings discovered while tracing every place a `.needsAI` verdict or an AI call can occur.
Principle carried over from `plan-ai-review.md`: **AI review must be compulsory, not a fallback.**

---

## Gap table

| # | Area | AI called? | Gap |
|---|---|---|---|
| 1 | `DaySlotAllocator.fits` (bulk allocation search) | No | Calls `SemanticPlacementSense.isSearchableSlot(verdict)`, which treats `.needsAI` as a valid/searchable slot instead of routing it to AI. An unresolved verdict is silently accepted as "good enough to place here." |
| 2 | `DayAuditService` (morning review) | No | Deterministic-only by design (fuses analyzers, "no GLM inside the fuse step"). No title/context AI judgment, no duplicate detection. Tracked as Issue 2 in `plan-ai-review.md`. |
| 3 | `ProactiveOrchestrator` (proactive monitoring) | No | All analyzers are fixed-threshold/rule-based; no GLM-authored context-specific question. Tracked as Issue 3 in `plan-ai-review.md`. |
| 4 | `TasksViewModel.resolveSemanticProfile` | Best-effort, race against timeout | Not compulsory: on GLM timeout/error/no-key, silently keeps the `deterministic` profile — no retry, no re-check later. A wrong profile persists for the task's lifetime. |
| 5 | `PlanMutationApplier.resolvedStart` | Yes | Correctly wired — `.needsAI` routes to `judgeWithAI`. No fix needed. |
| 6 | `PlanMutationApplier.buildSuggestedTime` (~line 453) | **Bug** | `case .makesSense, .needsAI: return suggested` — treats `.needsAI` as equivalent to `.makesSense` in the *same file* that correctly handles it elsewhere. This is the exact silent-passthrough bug already fixed in `SemanticPlacementSense.judge`, reintroduced in a second call site. |
| 7 | `AIScheduleSlotService.aiSuggestions` (~line 153-155) | No, on failure | `catch { return nil }` — any GLM error/timeout falls through to the fully deterministic local allocator with zero AI review, zero retry, and nothing surfaced to the user. |
| 8 | `DayReplanEngine.replan` | Yes, but silent fallback | `catch { return localFallback(context:) }` — same pattern: GLM failure silently degrades to deterministic-only, no compulsory re-check, no visible signal to the user that AI review was skipped. |

---

## Cross-cutting pattern

Rows 4, 7, and 8 aren't "AI is missing" — AI **is** wired in, but on timeout/error/no-key it
silently degrades to deterministic-only with:
- no retry,
- no queuing for later re-check,
- no user-visible signal that review was skipped.

This is the same "AI as fallback" anti-pattern called out in `plan-ai-review.md`'s Issue 1, just
manifesting as a runtime-failure path instead of a missing code path. Any fix for rows 4/7/8 needs
to decide: retry once, queue for background re-check, or explicitly mark the result as
"AI-unreviewed" so a downstream compulsory pass can pick it up later — silent degrade is not
acceptable per the standing rule.

---

## Fix plan (dependency order)

### Step 1 — Fix the reintroduced bug (row 6)
`PlanMutationApplier.buildSuggestedTime` must not treat `.needsAI` as `.makesSense`. Mirror the
existing correct handling in `resolvedStart` (same file): route `.needsAI` through
`judgeWithAI(task:proposedStart:durationMinutes:neighbors:)` before returning a suggested time.
Smallest, highest-confidence fix — no design decision required.

### Step 2 — Close the allocator gap (row 1)
`DaySlotAllocator.fits`/`isSearchableSlot` currently can't call AI mid-search (it's a synchronous
scan over candidate slots). Options to evaluate:
- (a) keep `.needsAI` as "searchable" during the synchronous scan (current behavior), but tag the
  resulting allocation so a caller performs a compulsory AI confirmation pass afterward before the
  slot is committed (similar to the `isAIGenerated` trust model already added to
  `DayScheduleSuggestion`), or
- (b) make the allocator async and call AI inline per ambiguous candidate (higher latency cost).
Recommend (a) first — cheaper, keeps allocator synchronous, defers the AI cost to a single
post-allocation batch pass.

### Step 3 — Compulsory-retry/queue policy for AI failures (rows 4, 7, 8)
Define one shared policy instead of three separate silent catches:
- On GLM error/timeout: retry once with backoff before falling back.
- If still failing: mark the result explicitly as AI-unreviewed (new flag, following the
  `isAIGenerated` pattern) instead of silently presenting it as fully reviewed.
- Surface AI-unreviewed items to the compulsory morning review (Issue 2) so they get judged once
  GLM is available again, rather than being permanently stuck on the deterministic guess.

### Step 4 — Issues 2 and 3 (unchanged scope)
Proceed per `plan-ai-review.md` once Steps 1-3 land, so the compulsory AI review pass being built
for the morning audit has correct, non-buggy inputs to work from.

---

## Verification checklist

- [ ] Unit test: `PlanMutationApplier.buildSuggestedTime` with a verdict of `.needsAI` must call
      `judgeWithAI` (or reject), never silently return the suggested time unchanged.
- [ ] Unit test: an ambiguous allocator candidate (`.needsAI`) is tagged as AI-unreviewed if
      Step 2(a) is chosen, and is not committed to a task's final schedule without a follow-up AI
      confirmation.
- [ ] Unit/integration test: simulate GLM timeout in `resolveSemanticProfile`,
      `AIScheduleSlotService.aiSuggestions`, and `DayReplanEngine.replan` — assert each surfaces an
      AI-unreviewed marker rather than silently presenting a fully-reviewed result.
