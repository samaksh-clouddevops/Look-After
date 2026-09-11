# Timeline fix plan (UI/UX + architecture)

**Date:** 10 Sep 2026  
**Cursor plan:** `~/.cursor/plans/timeline_fix_plan_2026_09_10.plan.md`  
**Source:** Timeline audit TL-A1–A11, TL-U1–U13

---

## YOUR INPUT (filled — defaults accepted)

### Product decisions

- **T1 — First-fold Schedule:** Compact 2-row Schedule preview under Up next + Full timeline opens sheet; keep Do-this-now hero.
- **T2 — Single NOW source:** Hero uses rail NOW id (`TimelineService.nowTaskId` / `TimelineNowResolver`).
- **T3 — Plan sheet timeline:** “After you approve” delta strip (not a full live rail).
- **T4 — LATE visual:** `DesignSystem.late` amber chip + rail (not lime).
- **T5 — Clock-proportional rail dead code:** Removed unused `ContinuousTimelineTrack` / `progressLineEndY` / `pendingPatches`.
- **T6 — Scope:** Waves 1→2→3 shipped together.
- **T7 — Must-not-break:** Plan approval, drag, complete/uncomplete, multi-day preserved.

### Acceptance

- Recapture scrolled Schedule + Full sheet: pending (manual / UX agent)

---

## Implemented

### Wave 1
| ID | Fix |
|----|-----|
| T2 / TL-A2 | `TodayDoThisNowSection` + Up next skip hero via `planningVM.nowTaskId` |
| T1 / TL-U1 | Today Schedule preview = 2 incomplete rows + Full timeline link |
| TL-U2 | Start remains behind expand on rail; hero keeps primary Start |
| TL-A5 / TL-A3 | Dropped dead `pendingPatches`; patch mutates snapshot then `projectRows` |

### Wave 2
| ID | Fix |
|----|-----|
| T4 / TL-U4 | LATE uses `DesignSystem.late` |
| TL-U5 | Conflict fill + thicker warning border |
| TL-U7 | Full sheet: `showsFullTimelineButton: false`; only Done dismisses |
| TL-A6 | Today resolve/materialize via `resolveTimelineTask` / `materializeTimelineTask` |
| TL-A7 | Suggested label + **Add to day** |
| T3 / TL-U9 | Plan approval “After you approve” strip |

### Wave 3
| ID | Fix |
|----|-----|
| TL-U3 | Rail/chips/metadata → `.dsCaption` / `.dsBody` |
| T5 / TL-U6 | Removed unused clock-track helpers |
| TL-U8 | VO hint + `AccessibilityNotification.Announcement` on drag commit |
| TL-U11 | Drag hint only when movable rows exist |
| Docs | This file updated |

---

## Key files

- `TodayView.swift` — hero NOW, Schedule preview, proj resolve
- `ExecutiveLiveTimelineView.swift` — LATE, compact, suggested Add, a11y fonts
- `LookAfterRootCanvas.swift` — Full sheet chrome + suggested + materialize persist
- `TimelineService.swift` — `nowTaskId`, no pendingPatches
- `LifeBlockView.swift` — announce on drop
- `ExecutivePlanningConversationView.swift` — approval preview
- `DesignSystem.swift` — `late` token
- `TimelineServiceTests.swift` — NOW id + complete patch tests

---

## Manual check

1. Today — Do-this-now title matches rail NOW/LATE.  
2. Schedule shows ≤2 rows without scrolling; Full timeline opens sheet.  
3. Complete NOW — next NOW updates cleanly.  
4. Full sheet Done-only dismiss; LATE not lime.  
5. Suggested → Add to day persists clock.  
6. Plan With Me approval still required before AI moves clocks.
