# UX screenshot fix plan (post ui-ux-pro-max review)

**Date:** 10 Sep 2026  
**Cursor plan:** `~/.cursor/plans/ux_screenshot_fix_plan_2026_09_10.plan.md`  
**Source shots:** `screenshots/ux-agent/latest/` (run `20260910-092034` — captured **before** Timeline UI / schedule physics)  
**Baseline from review:** ~6.5–7/10  

---

## YOUR INPUT — accepted defaults (2026-09-10)

### Product decisions

- **U1 — Coach vs Do-this-now:** Coach above hero only when critical (overcommit/transition); micro-start below; quiet Open plan (not glassProminent).
- **U2 — Stale/overdue hero:** Overdue rail NOW → LATE + honest overdue supporting line; transition prep no duplicate “in 8m”.
- **U3 — Briefing empty middle:** “Today at a Glance” pulled into first fold.
- **U4 — Dual header icons:** Keep both — “Briefing layout and life filters” vs “App settings”.
- **U5 — Capture footer:** Always-visible Save; disabled until content; chip scroll peek + stronger chip contrast.
- **U6 — Must-not-break:** 4 tabs + Capture, Plan approval, Schedule preview, hero = rail NOW — **yes**.

### Acceptance

- Recapture `latest/`: **required** before any new score claim (S02, S05 scrolled Schedule, S14 real task list, S19, S39, S02-dark).

---

## Waves

| Wave | Focus | Closes | Status |
|------|--------|--------|--------|
| **1** | Today trust: NOW/LATE truth, coach hierarchy, transition copy once, quiet hero chrome | S05 P0 | **Done in code** |
| **2** | Briefing grammar + void; Capture save + chips + contrast | S02 / S39 | **Done in code** |
| **3** | Dual settings labels, Brain orb affordance, 44pt/DT, fix S14 capture | S19 / harness | **Done in code** |
| **4** | Recapture + score only on new shots | Proof | **Pending device recapture** |

---

## Locked

- DesignSystem lime; serif name Briefing-only.  
- Do not reopen OccupiedDay / Plan approval unless UI-only.  
- Path-to-10 nav (4 tabs + Capture) stays.

---

## Implementation notes (defaults)

| ID | Change |
|----|--------|
| UX-T2 | `TransitionShieldBuilder` `.eight` prep = `"Wrap up."` |
| UX-T3 | `TodayCoachSlot` placements `.aboveHero` / `.belowHero`; `emphasizesPrimary: false` on coach |
| UX-T4 | Removed dead `TodayHeroIllustration` heart/pulse |
| UX-B1 | `BriefingDayHeroSummaryGenerator.underwayLine` grammar |
| UX-B2 | Glance in `firstViewport`; scroll hint → sleep/tasks/health |
| UX-C1–C3 | Capture always shows Save; chip fade peek; primary chip text |
| UX-N1 | Distinct Briefing header a11y labels |
| UX-BR1 | Brain copy + orb a11y “Voice orb ready. Tap to speak.” |
| UX-CAP | `SnapshotEngine.openTaskList` opens `nav-today-overflow` → “All tasks” |

---

## Status

- **Waves 1–3 implemented in code** (build verify).  
- **Wave 4 superseded for scoring:** use full-flow recapture + [ui-ux-flow-fix-plan-2026-09-10.md](./ui-ux-flow-fix-plan-2026-09-10.md) (run `20260910-133343`, ~7.5/10). Do not claim score uplift from the old `20260910-092034` set alone.
