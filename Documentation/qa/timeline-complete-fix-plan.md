# Timeline complete fix plan

**Document ID:** QA-TIMELINE-PLAN-01  
**Date:** 9 September 2026  
**Status:** Implemented 9 September 2026 — T-01–T-37 across Phases 1–9. Verify on device using §6.  
**Related:** [timeline-feature-audit.md](timeline-feature-audit.md)

This is the full work plan. Nothing from the audit is deferred. Former “out of scope” items are in Phases 7–9 with a precise meaning so we do not accidentally paint the UI from a lagging cloud copy.

---

## 0. What “complete” means

Fix every user-visible and data-integrity fault in the **Today / Briefing live timeline** and every system that writes the clocks it reads:

| Surface | Included |
|---|---|
| Today rail, NOW chip, lime progress, drag | Yes |
| Briefing hero “now”, widgets, lock-screen pin, Live Activity | Yes |
| Planner, cascade, AI mutations, life-model assemble | Yes |
| Calendar, shopping, finance, bills, meds, sleep/wind-down | Yes |
| SQLite ↔ memory ↔ Firestore consistency for task times | Yes |
| Health copy on Briefing | Yes (alignment with NOW, not HealthKit metric math) |

**Not a rewrite of the whole app.** Recurrence engine, onboarding, and HealthKit sync algorithms stay except where they feed wrong times into the timeline.

---

## 1. Locked product decisions

| Topic | Decision |
|---|---|
| Timeline shape | Stay a **sorted event list**, but the **green rail is a real clock** (interpolated Y + wall-clock caption). Rows may gain **time-gap spacing** so a 3-hour hole is visibly longer than a 15-minute hole. Not a Google Calendar grid. |
| Paint source of truth | **SQLite + in-memory `TasksViewModel`**. Firestore is a **replica**. Never paint the rail from a cloud snapshot. Never let older cloud/cache overwrite newer local `updatedAt`. |
| Overdue incomplete work | Stays **NOW** with a **Late** state. Do not jump to Wind down. |
| Wind down as NOW | Only after **17:00 local**, and only if no incomplete non-sleep tasks remain. Hide the row before 17:00 (display). AI may still use an all-day sleep fence internally. |
| Meals | **Fence**, not hard lock. Dinner may slide 17:00–21:00. Never morning. Gym stays `never_schedule`. |
| Calendar vs task same minute | Calendar **occupies**. Task **shifts**. Two timed cards must not share a start minute. |
| Shopping / grouped finance | **Untimed** grouping rows (no NOW, no fake clock). Real dated child tasks keep clocks. |
| Drag Dinner to 10:00 | **Refuse / snap back**. Do not `markUserPlaced`. Evening drag inside the fence: allow + mark placed. |
| Completing NOW | Immediately reassign NOW on the rail **and** restamp widgets / pin / briefing from the same snapshot. |
| Briefing vs Today | One NOW event id. Briefing pull restamps timeline NOW; it does not skip the clock. |

---

## 2. Shared architecture (do once, use everywhere)

### 2.1 `SchedulePlacementGuard`

New type in LookAfterCore. Single allow/deny for start times:

```
allows(start, task, occupied, now, calendar) -> Placement
  .accepted(start)
  .snapped(start)      // nearest legal inside box / past occupancy
  .rejected(reason)
```

Rules:

- Bounding box from `TaskEphemeralityDefaults` (meals, gym-like semantics).
- Occupied intervals: tasks + **calendar** + protected gym windows.
- `scheduledDate` is always `startOfDay`; clock lives in `scheduledTime` / `scheduledEndTime` **combined onto that day**.

Call sites: `DaySlotAllocator.fits`, `PlanMutationApplier`, `TimelineConstraintViewModel` drag, `correctRoutineScheduleDrift`.

### 2.2 One clock for dual date fields

Helper (extend existing `calendar.combine(date:timeFrom:)`):

- Readers of “when does this task start today?” **must** combine `scheduledDate` + time-of-day from `scheduledTime`.
- Never compare a raw `scheduledTime` whose calendar day may be yesterday.

Apply to: sleep wake anchor, TaskReaper, DayScheduleReconciler midnight sweep, finance grouping, DayAssembler existence check.

### 2.3 NOW restamp vs full rebuild

| Operation | What it does |
|---|---|
| `projectNow(now:)` | Restamps `isNow` / `isPast` / Late on existing events. 30s tick. Cheap. |
| `rebuild(...)` | Recalculates events from tasks. After persist, assemble, calendar fetch. |
| `applyPatch` | Optimistic UI, then **must** `projectNow` **and** write `snapshot.today` (or rebuild) so widgets match. |

`ExecutiveLiveTimelineView` owns a 30s `Timeline` tick. **Does not** wait on `refreshContext`. Focus session may skip brain refresh; it must **not** skip NOW.

---

## 3. Bug catalog (complete)

### Reported (T-01–T-04)

| ID | Sev | Issue | Phase |
|---|---|---|---|
| T-01 | P0 | Dinner / meals land in the morning (allocator uses office hours; boxes ignored) | 2 |
| T-02 | P0 | Multiple tasks at the same clock | 3 |
| T-03 | P0 | NOW on Wind down while important work unfinished | 1 |
| T-04 | P0 | Green marker 11:45 vs wall 12:51 (row label + frozen rebuild + sleep math) | 1 + 7 |

### First audit pass (T-05–T-20)

| ID | Sev | Issue | Phase |
|---|---|---|---|
| T-05 | P0 | Drag: no box / overlap / gym check | 3 |
| T-06 | P1 | Drag offset mutates `scheduledDate` by minute delta | 3 |
| T-07 | P0 | `markUserPlaced` after illegal drag kills restore | 3 |
| T-08 | P1 | Tomorrow wake uses raw `scheduledTime` without combine onto tomorrow | 1 |
| T-09 | P1 | Wind-down injected from 00:00 (`showFromHour: 0`) | 1 |
| T-10 | P1 | Shopping cursor (now+15) can steal NOW | 4 |
| T-11 | P1 | Grouped finance from raw `scheduledTime` / next hour | 4 |
| T-12 | P1 | Calendar never in overlap cascade | 4 *(see T-25)* |
| T-13 | P2 | Projector `DateFormatter` missing timeZone/calendar | 6 |
| T-14 | P1 | Unslotted `when = startOfDay` (midnight) | 4 |
| T-15 | P2 | `isPast` vs `resolvedEndDate` vs `scheduledEndTime` | 6 |
| T-16 | P1 | Patch reschedule uses a new `Date()` vs frozen snapshot | 1 |
| T-17 | P2 | Suggested-slot rows display-only; complete/drag no-op | 6 |
| T-18 | P1 | `warmLocalCache(force:)` can race concurrent save | 5 |
| T-19 | P2 | Briefing hero vs timeline different NOW | 5 |
| T-20 | P1 | `refreshBriefingSurface` skips timeline restamp | 5 |

### Second hunt pass (T-21–T-34) — 9 Sep 2026

| ID | Sev | Issue | Where |
|---|---|---|---|
| T-21 | P0 | Complete/uncomplete patch clears NOW and never reassigns | `TimelineRowProjector.applyPatch` — complete path skips `resortRows` |
| T-22 | P0 | Patches update `todayRows` only; `snapshot.today` stale → widgets / pin / briefing wrong | `TimelineService.applyPatch`; `completeTimelineTask` uses `rebuildTimeline: false` |
| T-23 | P0 | `scheduledEndTime` at 00:00 treated as placeholder → evening block becomes Flexible today | `TaskScheduleInterval.isPlaceholderMidnightSchedule` ORs midnight **end** |
| T-24 | P1 | `scheduledTime` without `scheduledDate` never reaches the day timeline | `TaskRecurrenceEngine.isActionableOnDayStart` requires `scheduledDate` |
| T-25 | P1 | Production rebuild **never passes** `calendarEvents` — T-12 assumed they paint; they **don’t** | `AppShellState.performTimelineRebuild` |
| T-26 | P1 | Today filter `date >= dayAnchor` admits tomorrow’s events onto today’s rail | `LifeTimelinePresenter.build` |
| T-27 | P1 | Finance “next hour” overflows hour 24 → next-day midnight, still shown today via T-26 | `groupedFinanceSession` |
| T-28 | P1 | After-hours shopping cursor falls back to **this morning’s** work start | `PlanningSchedulePolicy.schedulingCursor` |
| T-29 | P1 | DayAssembler skips today’s Gym if any series match has `scheduledDate == nil` | `DayAssembler.assemble` `onDay = date.map { } ?? true` |
| T-30 | P1 | Commitment end times past midnight clamped to hour 23 | `DayAssembler.makeTask` |
| T-31 | P1 | TaskReaper / midnight reconcile expire on absolute `scheduledTime`, ignore `scheduledDate` | `TaskReaper.verdict`, `DayScheduleReconciler` |
| T-32 | P1 | Suggested-slot rows can become NOW | `suggestedSlotRows` not treated as unslotted |
| T-33 | P0 | Med daily reset + UserDefaults write bypasses `MedicationStore` cache | `MedicationViewModel` vs `MedicationStore.load` on rebuild |
| T-34 | P1 | Bills / birthdays are 30-min windows from midnight due/birthday → steal early-morning NOW | `LifeTimelinePresenter.build` |

### Former out of scope (now in plan)

| ID | Sev | Issue | Phase |
|---|---|---|---|
| T-35 | P0 | Rail is event-attached, not clock-proportional — user reads 11:45 as “app time” | 7 |
| T-36 | P1 | Cloud/local divergence: remote merge / cache can show wrong times until relaunch | 8 |
| T-37 | P1 | Health/Briefing “how you’re doing” / hero NOW can disagree with the rail after Sync / pull | 9 |

---

## 4. Implementation phases

Each phase is a PR. Tests from the phase table land **in the same PR**. Do not mix Phase 7 UI spacing into Phase 1 logic.

### Phase 1 — NOW + sleep (T-03, T-04 B/C, T-08, T-09, T-16, T-21, T-22, T-32)

**Files:** `TimelineNowResolver.swift`, `TimelineDisplaySort.swift`, `TimelineService.swift`, `DayBoundaryPlanner.swift`, `IdealSleepPlanner.swift`, `ExecutiveLiveTimelineView.swift`, `AppShellState.swift`, `LookAfterRootCanvas.swift`

Work:

1. NOW priority: in-window → **overdue incomplete slotted** (Late) → gap flexible → future slotted **excluding** `sleep-boundary` → sleep only after 17:00 with no remaining work.
2. Suggested slots never NOW (`isUnslottedFlexible` or dedicated skip).
3. `showFromHour: 17` for the **display** wind-down row; keep internal fence if AI needs it.
4. Combine tomorrow + time-of-day for wake.
5. `applyPatch` complete/uncomplete/reschedule: `resortRows` / `projectNow`, then **sync `snapshot.today`**. Completing NOW must immediately pick the next event.
6. 30s tick: `projectNow(now: Date())` independent of `refreshContext`.
7. `completeTimelineTask` must restamp widgets from the patched snapshot (`rebuildTimeline: true` or `projectNow` + `syncWidgetDataOnly`).

**Tests:** overdue work at 12:51 ≠ wind-down; complete NOW reassigns; suggested row never NOW; wake combine; patch uses snapshot `now`.

### Phase 2 — Meal / gym physics (T-01)

**Files:** `SchedulePlacementGuard.swift` (new), `DaySlotAllocator.swift`, `DaySchedulePlanner.swift`, `PlanMutationApplier.swift`, `TasksViewModel.swift` (drift)

Work: allocate meals inside bounding box, not office 9–18. Gym occupied. AI rejects outside box (snap). Drift restore **shifts inside box** instead of bailing when 19:00 overlaps gym.

**Tests:** Dinner 19:00 + office 9–18 + Gym 18:00 → dinner stays 17–21, `hasOverlap == false`. Allocator `fits` Dinner 10:00 → false.

### Phase 3 — Overlap + drag (T-02, T-05, T-06, T-07)

**Files:** `DaySchedulePlanner.swift`, `ConflictResolutionCascade.swift`, `TimelineConstraintViewModel.swift`, `ScheduleMutationService.swift`

Work: no `allowOverlap` leftovers without persist. After planner+cascade `hasOverlap == false`. Drag uses guard; illegal drop no `markUserPlaced`. Offset does **not** add minutes to `scheduledDate`.

**Tests:** drag Dinner 10:00 rejected; offset +90 keeps start-of-day `scheduledDate`; two cards never share start minute.

### Phase 4 — Presenter clocks (T-10–T-12, T-14, T-23–T-28, T-34)

**Files:** `LifeTimelinePresenter.swift`, `TaskScheduleInterval.swift`, `AppShellState.swift`, `PlanningSchedulePolicy.swift`, `TaskRecurrenceEngine.swift` / `TaskSeriesResolver.swift`

Work:

- Midnight **end** is not a placeholder (T-23). Midnight **start** still is, unless duration spans evening→midnight and start is not 00:00.
- Filter today with **same calendar day only** (T-26).
- Pass EventKit/briefing calendar into `rebuild` (T-25). Occupied in guard (T-12).
- Shopping/finance grouping untimed; after-hours cursor ≠ this morning (T-10, T-11, T-27, T-28).
- Bills/birthdays: untimed / due-day badges, not 00:00–00:30 NOW windows (T-34).
- Unslotted events do not use midnight as `date` for NOW (T-14).
- Time-only tasks combine onto today or get a `scheduledDate` (T-24).

**Tests:** end-at-midnight still slotted; tomorrow event absent from today; calendar events appear and occupy; bill at midnight ≠ NOW at 00:10.

### Phase 5 — Assemble, reaper, meds, shell (T-18, T-19, T-20, T-29, T-30, T-31, T-33)

**Files:** `DayAssembler.swift`, `TaskReaper.swift`, `DayScheduleReconciler.swift`, `MedicationViewModel.swift`, `MedicationStore.swift`, `AppShellState.swift`, `Repositories.swift`

Work:

- `alreadyExists` requires **same day** (nil date ≠ today) (T-29).
- Overnight commitments keep real end across midnight or a documented next-day split — do not clamp hour to 23 silently (T-30).
- Reaper/reconcile combine onto `scheduledDate` (T-31).
- Med reset on timeline rebuild; VM writes go through `MedicationStore.save` (T-33).
- `warmLocalCache(force:)` merge by `updatedAt`, never clobber newer memory (T-18).
- `refreshBriefingSurface` calls `projectNow`; hero uses `TimelineNowResolver.currentNowEvent` from the same snapshot (T-19, T-20).

### Phase 6 — Display leftovers (T-13, T-15, T-17)

Formatter timezone; `isPast` prefers `scheduledEndTime`; suggested rows cannot complete/drag until materialized.

### Phase 7 — Clock-proportional rail (T-35, remainder of T-04 A)

Former out of scope.

**Files:** `ExecutiveLiveTimelineView.swift`, `TimelineDragTimeMeter.swift`

Work:

1. Wall-clock caption on the NOW chip (device time, updating with the 30s tick).
2. Interpolate lime rail Y inside the current block: `(now - start) / duration`.
3. **Time-gap spacing:** extra padding between rows proportional to `max(0, nextStart - thisEnd)` capped (e.g. 8–48 pt) so empty hours read as empty hours.
4. Optional compact “now needle” on the rail independent of row dots.

Still not a full-day calendar canvas. If we later want hour gutters (9 AM / 12 / 3 / 6 labels), add them as a thin overlay — same PR or a follow-up if layout fights drag.

**Verify:** 11:45–13:00 block at 12:51 → label 11:45, caption 12:51, fill ~70% through the block, not parked on the 11:45 dot.

### Phase 8 — Local / cloud consistency (T-36)

Former out of scope (“Firestore as source of truth”).

**Decision:** Firestore is **not** the paint source. It is a replica.

Work:

1. Document and enforce: UI reads `TasksViewModel` ← SQLite. Cloud pull **merges** by `id` + `updatedAt` (newer wins). Equal timestamps: local wins if `userPlacedScheduleAt` or dirty flag set.
2. After merge, `rebuildTimelineFromTasks(immediate: true)`.
3. Never apply a remote task whose `updatedAt` is older than cached.
4. `cachedAll` generation / dirty set: skip `warmLocalCache` replace while saves in flight (T-18).
5. Timeline widgets always from post-merge in-memory snapshot.

**Tests:** local newer dinner 19:00 vs cloud 10:00 → UI stays 19:00; then rebuild still 19:00.

### Phase 9 — Health / Briefing alignment (T-37)

Former out of scope.

Work:

1. Briefing hero NOW = `timelineService` current NOW event (same id as rail).
2. After Health Sync, restamp timeline NOW (health does not move clocks; it must not freeze them either).
3. “How you’re doing” missing-metrics must not block or skip `projectNow`.
4. Pull-to-refresh Briefing: health refresh **and** `projectNow` (T-20).

HealthKit sample math stays in the health package; this phase only **connects** that refresh to the same clock the rail uses.

---

## 5. Test matrix (must exist before calling a phase done)

| Case | Phase |
|---|---|
| 12:51, incomplete 10:00 work → NOW ≠ Wind down | 1 |
| 12:51, incomplete 11:45–13:00 → NOW that row, Late if ended, rail interpolated | 1 + 7 |
| Complete NOW → next real task gets NOW; widget snapshot matches | 1 |
| Dinner 19:00 survives plan with office 9–18 and Gym 18:00 | 2 |
| Dinner drag to 10:00 rejected; `userPlacedScheduleAt` nil | 3 |
| `hasOverlap == false` including a 12:00 calendar block | 3 + 4 |
| Calendar events visible on Today | 4 |
| End 00:00 not flexible-day | 4 |
| Nil `scheduledDate` gym does not block today’s assemble | 5 |
| Med taken then timeline rebuild shows Taken | 5 |
| Local newer vs older Firestore keeps local time | 8 |
| Briefing pull: hero event id == rail `isNow` id | 9 |

---

## 6. Device verification (after Phases 1–3 + 7)

1. Dinner 7:00 PM, Gym 6:00 PM, 45-min work 11:45 AM, leave incomplete. At ~12:51: NOW is that work (Late if ended). Caption ~12:51. Not Wind down.
2. Plan / replan: Dinner evening. No shared start minute.
3. Drag Dinner toward 10:00 AM: refuse.
4. Wait 10 minutes: NOW advances without relaunch.
5. Complete NOW: chip moves immediately; lock-screen pin matches.
6. Briefing pull + Health Sync: hero and rail agree.

---

## 7. Suggested PR slices

| PR | Contents |
|---|---|
| **A** | Phase 1 NOW + sleep + complete/patch snapshot |
| **B** | Phase 2 meal fence |
| **C** | Phase 3 overlap + drag |
| **D** | Phase 4 presenter + calendar wiring + midnight end |
| **E** | Phase 5 assemble / reaper / meds / cache / briefing restamp |
| **F** | Phase 6 polish |
| **G** | Phase 7 clock-proportional rail |
| **H** | Phase 8 cloud merge rules |
| **I** | Phase 9 health/briefing NOW |

---

## 8. Bug-finding session log

**Pass 1 (audit):** storage path, NOW resolver, allocator office hours, drag, sleep planner, dual dates. → T-01–T-20.

**Pass 2 (this plan):** complete/patch vs snapshot, midnight end sentinel, calendar omitted from rebuild, presenter day filter, shopping/finance overflow, DayAssembler nil-date skip, reaper absolute dates, meds cache, bills as NOW. → T-21–T-34.

**Pass 3 (during implementation):** for each PR, grep remaining `scheduledTime` readers and add bugs to this catalog if they move clocks without `combine`. Explicit leftover hunt after PR E:

- Recurrence materialization writing `scheduledTime` on the wrong calendar day
- DST / travel (formatter + combine)
- Focus session + pin-to-lock still frozen
- Tomorrow page using today `now` for `isNow`

New IDs continue T-38+.

---

## 9. Execution order

Start **PR A (Phase 1)** next. It fixes the live 12:51 / Wind down / frozen NOW reports without waiting on meal physics. Then B → C so dinner and overlaps stop. G (clock rail) can follow A immediately if we want the 11:45 label vs 12:51 caption in the same user-visible drop; otherwise keep G after C so drag geometry is stable.

**Recommendation:** A, then G (user-visible clock), then B, C, D, E, F, H, I.
