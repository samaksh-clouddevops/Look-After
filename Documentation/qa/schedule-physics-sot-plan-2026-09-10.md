# Schedule physics + calendar peer + clock SoT plan

**Date:** 10 Sep 2026  
**Cursor plan:** `~/.cursor/plans/schedule_physics_sot_2026_09_10.plan.md`  
**Resolves:** (1) allocation/fences/overlap · (2) calendar as occupied peer · (3) multi-clock SoT  

---

## YOUR INPUT (defaults accepted)

- **C1:** Calendar occupies; movable task shifts. Anchored immovable → Conflict (cascade keeps fixed).  
- **C2:** Busy all-day soft-occupies; free/transparent ignored.  
- **C3:** W0→W3 shipped this program.  
- **C4:** Bypass writers funnel through SMS + guard.  
- **C5:** Suggested Add uses `placeSuggestedSlot` + OccupiedDay guard.  
- **C6:** Keep 60s + userPlaced; added 5s in-flight local dirty.  
- **C7:** Approval, drag, complete NOW, gym, dinner fence preserved.

---

## Implemented

| Wave | Status | Notes |
|------|--------|--------|
| **W0** | Done | `OccupiedDay` + `OccupiedDayTests` |
| **W1** | Done | Cascade/allocator/planner/guard/drag/SMS/AI suggest/suggested Add use OccupiedDay |
| **W2** | Done | SMS persist → reconcile + `onScheduleWriteCommitted` → rebuild + `projectNow` + widgets |
| **W3** | Done | Tomorrow calendar day filter; TaskMerge 5s dirty; this doc |

### Key additions

- `OccupiedDay.swift` — tasks + EventKit (`cal.*`) + protected  
- `BriefingCalendarEvent.isAllDay` / `isBusy`  
- `ConflictResolutionCascade.calendarEvents` seeds fixed blocked  
- `DayScheduleReconciler.hasOverlap` / `reconcile` take calendar  
- `ScheduleMutationService.placeSuggestedSlot` + guarded `applyDayScheduleChanges` / `applyTimelineOffset`  
- Shell wires `calendarEventsProvider` + `onScheduleWriteCommitted`

---

## Manual check

1. Add a 12:00 calendar meeting; place flex work at 12:00 → snaps/shifts off meeting.  
2. Dinner stays 17–21; gym never_schedule still blocks.  
3. Drag onto calendar → reject/snap; no illegal `userPlaced`.  
4. Complete NOW → Today / widgets same NOW after restamp.  
5. Plan With Me still requires Approve before AI clocks move.
