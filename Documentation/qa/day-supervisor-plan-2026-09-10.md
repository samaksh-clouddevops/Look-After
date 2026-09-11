# Day Supervisor plan — 2026-09-10

Living implementation checklist for **AI as day supervisor** (audit sense / time / energy; ask when unsure; no task-factory gimmicks).

Aligned with canvas `ai-supervisor-psychology-plan` and Cursor plan `day_supervisor_plan`.

## North star

| Own | Owner |
|-----|--------|
| Known life + clock physics | Rules (`DaySlotAllocator`, cascade, anchors, guards) |
| Judgment under uncertainty | AI / supervisor dialogue (≤2 questions) |
| Final clock write | Guard + approve — never silent `.needsAI` accept |

## Phase 1 — shipped

- [x] `DayAuditResult` / `DayAuditService` (Core) fusing PreWindowFit, ScheduleProactive, parked/yesterday, capacity
- [x] Briefing **Today’s check** card + Start my day apply/approve (`DailyBriefingViewModel`, `DayAuditCheckCard`, `DayAuditApplier`)
- [x] Hero / chief narrative prefer audit findings when material
- [x] Skip LLM classify for known routines/meals
- [x] Reject silent `.needsAI` on slot apply / mutation / drag
- [x] Gate auto-decompose to complex tasks only
- [x] `DayAuditServiceTests`

### Acceptance

1. First open / Start my day shows faults, possible pulls, not-possible, optional questions (≤2).
2. Unanswered required questions block navigation until answered or skipped.
3. Approved shrink/skip/pulls persist via mutation + reconcile.
4. Dinner/routines do not call semantic LLM.
5. Placement `.needsAI` does not write a clock.

## Phase 2 — continuous — shipped

- [x] Today delta audit refresh on Today appear
- [x] Capture capacity fit (`DaySupervisorContinuity.captureFit` + toast hint)
- [x] Decide for me constrained to feasible set
- [x] Task create duration warning (`TasksViewModel.createDurationWarning`)

## Phase 3 — close the loop — shipped

- [x] Focus mid-session mismatch ask via `CircuitBreakerAnalyzer` + `DaySupervisorContinuity.focusMismatchQuestion`
- [x] Weekly priors → next morning audit (`DaySupervisorPriorsStore` + `DayAuditService`)
- [x] Lean morning notification body from audit (`NotificationRefreshInput.dayAuditLeanBody`)
- [x] Parked/fluid review UI (`ParkedFluidReviewView` linked from Day Audit card)

## Out of scope

- LLM replacing allocator/cascade clocks
- OccupiedDay / schedule-physics reopen
- AI chat in Settings
