# Schedule / AI architecture fix plan

**Date:** 10 Sep 2026  
**Cursor plan:** Schedule Arch Fixes (do not edit Cursor plan file for living decisions — edit **YOUR INPUT** below)

---

## YOUR INPUT (fill this in)

### Product decisions

- **P1 — AI auto-apply policy:**  
  - Default was: hold mutations when negotiation present.  
  - **Your choice:** Application should show a prompt card with what AI suggests with Reason and what changes to be done and if user approves the changes are made.
- **P2 — User-placed override:**  
  - Default was: never move `userPlacedScheduleAt` unless explicitly named.  
  - **Your choice:** User changes can be overridden but after approval only.
- **P3 — Scope for first ship:** `________________________________` (default Waves 1→2→3)
- **P4 — Undo / audit:** `________________________________` (default in-memory notices; durable log deferred)
- **P5 — Series-by-title (A5):** `________________________________` (default prefer parent/template id)
- **P6 — Firestore schedule merge (A4):** `________________________________` (default local within 60s or newer userPlaced)
- **P7 — Anything else / must-not-break:**  
  - `________________________________`  
  - `________________________________`

### Acceptance

- Device / scenario: `________________________________`
- Must still work: Plan With Me voice, multi-day “Schedule it”, drag-on-timeline — **yes**

---

## Implemented (this program)

### Wave 1 — Trust
| ID | Fix |
|----|-----|
| P1 / A2 | `PendingPlanApproval` card — reason + change list; Approve / Keep my plan; no auto-apply on Plan With Me |
| P2 / A1 | `userPlacedScheduleAt` locked unless `allowUserPlacedOverride: true` (approval / proactive chip / approved replan) |
| A3 / B6 | DayReplan allowlists task IDs; `SchedulePlacementGuard` before write; persist via `ScheduleMutationService` |

### Wave 2
| ID | Fix |
|----|-----|
| B5 | `ScheduleMutationIdempotencyStore` session fingerprints |
| A4 / P6 | `TaskMerge.prefer` schedule-aware (userPlaced + 60s skew) |
| B1 | Applier clock writes go through `scheduleMutation.persist` |

### Wave 3
| ID | Fix |
|----|-----|
| A5 | `seriesKey` prefers `parentTaskId` / template id; title fallback DEBUG log |
| B4 | Materialize `proj-*` before reschedule in applier |
| B2 | Documented single planner flag on `SchedulePlannerFlags` |
| C6 | Durable ApprovedMutation store still deferred (P4 default) |

---

## Key files

- `PlanningConversationModels.swift` — `PendingPlanApproval`
- `ExecutivePlanningViewModel.swift` — pending approve/reject; replan allowlist
- `PlanMutationApplier.swift` — locks + override + SMS persist + proj materialize
- `ScheduleMutationIdempotencyStore.swift`
- `TaskListSnapshot.swift` — `TaskMerge`
- `TaskScheduleQuery.swift` — series key
- `ExecutivePlanningConversationView.swift` — approval card UI

---

## Manual check

1. Drag a flexible task on Today timeline.  
2. Plan With Me: ask to reorganize the day.  
3. Confirm **Suggested changes** card; task clock unchanged until **Approve**.  
4. Approve → user-placed may move; Reject → unchanged.
