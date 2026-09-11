# Look After — Plan to fix full UI/UX screenshot audit

**Source audit:** [ui-ux-full-screenshot-audit-2026-09-10.md](./ui-ux-full-screenshot-audit-2026-09-10.md)  
**Date:** 10 Sep 2026  
**Goal:** Close every P0 → P1 → P2 item with **visible** screenshot proof after each wave.  
**Constraints:** Keep DesignSystem lime (no skill teal/orange). Prefer UX structure changes over padding-only chrome. Recapture with `./Scripts/capture-ux-review.sh` after each wave.

---

## Principles

1. **Structure before polish** — If content is covered or CTAs compete, fix interaction model first.  
2. **One primary action per region** — ADHD-safe.  
3. **Trust is UX** — Duration/order/copy mismatches are P0 even if “pretty.”  
4. **Prove with pixels** — A fix isn’t done until `latest/` shows it vs the prior run.  
5. **Map every audit ID** — No orphan findings.

---

## Delivery shape

| Wave | Focus | Est. effort | Exit gate |
|------|--------|-------------|-----------|
| **A** | P0 UX structure + trust | 2–4 days | S05/S02/S04/S39 clearly different; Replan not a second dock |
| **B** | P1 consistency + a11y | 3–5 days | Contrast + control matrix + Settings/Capture/Brain/You |
| **C** | P2 polish + validation | 1–2 days | Type rule, Dynamic Type, reduced-motion shots |
| **D** | Hardening / leftovers | 1 day | Any deferred IDs closed or explicitly won’t-fix |

After each wave: update polish notes + tick IDs in this plan’s checklist.

---

## Wave A — P0 UX structure & trust

### A1. Kill Replan-as-second-dock
**IDs:** S05-01, S05-10 (partial), ADHD-01, ADHD-02  

**Decision (recommended):** Remove full-width floating `ExecutiveAssistantSheet` collapsed bar from Today overlay/inset.  
- Collapsed: **toolbar sparkles** (or “Plan” icon) on Today header → expands planning sheet / conversation.  
- Expanded: present as **sheet** (detents) or full-height cover — not a second dock above the tab bar.  
- Keep negotiation chips **inline** in content when active (already partly true).

**Primary files:**  
- `Apps/LookAfter-iOS/Views/Briefing/TodayView.swift`  
- `Apps/LookAfter-iOS/Views/Briefing/ExecutiveAssistantSheet.swift`  
- `Apps/LookAfter-iOS/Views/Briefing/TodayHeaderBar` (in TodayView)  
- Tour anchors for `.todayAssistant` — retarget to toolbar button  

**Acceptance:** S05 shows Top Priorities fully; no “Replan or adjust my day” bar above tab bar.

---

### A2. Capture selected-language + destination pressure
**IDs:** S02-02, S02D-03, S04-01, S04-02, S04-04, S05-10, S19-05 (partial)  

**Decision:**  
1. **Visual:** `LACaptureFAB` = quiet surface + outline + accent glyph only; never filled lime equal to selected tab.  
2. **Optional product:** Collapse to **4 labeled tabs + Capture** (e.g. fold Review into You/Briefing) — **product call**; if deferred, still fix (1) and document Review as known ≤5 violation.  

**Primary files:**  
- `Packages/LookAfterCore/.../LookAfterChromeControls.swift` (`LACaptureFAB`)  
- `Apps/LookAfter-iOS/Views/Navigation/LookAfterBottomNav.swift`  
- Tab label token: bump `dsTabLabel` readability (ties S04-03 into A if quick)

**Acceptance:** Side-by-side S04 — Capture does not look “selected” when Briefing/Today/Brain is active.

---

### A3. Today first-viewport load
**IDs:** S05-02, S05-03, S05-06, S05-07, S05-08, ADHD-01  

**Decision:**  
- **One banner max** above priorities (Micro-start **or** schedule check — not stacked with equal weight).  
- Micro-start: **1 primary CTA** + secondary menu (“More…”) for Pick another / Not now.  
- Context chips: demote to **text buttons / quieter style**, or collapse under “Context” disclosure.  
- Week strip: keep, but reduce vertical padding; consider sticky only after scroll.

**Primary files:**  
- `TodayView.swift` + proactive/micro-start sections  
- `TodayContextQuickActions`  
- `LAActionChipButton` usage (3-up → 1+menu)

**Acceptance:** S05 first fold: title/toolbar → (optional one banner) → Top Priorities readable; ≤2 competing CTAs.

---

### A4. Trust copy & ordering
**IDs:** S05-04, S05-05, S02-05, S14-04, S14-05, ADHD-04  

| Fix | Approach |
|-----|----------|
| Micro-start 2m vs task 5m | Drive micro-start duration from `task.estimatedMinutes` (or show “up to Nm”); never invent 2m if estimate is 5m |
| Priority order | Sort Top Priorities by next actionable time, then priority |
| Briefing “main ones” | Filter to morning-relevant / next-window tasks in hero generator |
| All Tasks order | Default sort: time-of-day then flexible; Morning review not after Dinner |
| Dinner metadata | Unify to `Estimated time Xm` (+ optional note secondary) |

**Primary files:**  
- Micro-start / proactive copy builders  
- `BriefingDayHeroSummaryGenerator`  
- `TodayPrioritiesSection` sort  
- `TaskListSorter` / list presentation  

**Acceptance:** No contradictory durations; priorities chronological; hero mains make sense in morning.

---

### A5. Capture disabled CTA clarity
**IDs:** S39-01 (P0)  

**Decision:** Disabled state = **caption text**, not a fake button; when ready, one `.glassProminent` Save.  

**Files:** `CaptureComposerView.swift`  

**Acceptance:** S39 — empty state doesn’t look like a tappable primary.

---

### Wave A exit checklist

- [ ] A1–A5 landed  
- [ ] `./Scripts/capture-ux-review.sh`  
- [ ] Spot-check S05, S02, S04, S39, S14  
- [ ] Tick all Wave A IDs in audit / this plan  

---

## Wave B — P1 consistency, a11y, screen polish

### B1. Control matrix (global)
**IDs:** S05-09, S14-01, S14-02, S04-03, S04-05, cross-cutting  

- Enforce: `LAToolbarIconButton` / `LAActionChipButton` / `LACaptureFAB` / Primary CTA / Tab item  
- Ban raw ad-hoc sizes in chrome  
- Tab labels: slightly larger token or Dynamic Type–friendly  
- Task header: equal optical size for primary `+` (tint, not bigger frame); move Import into Menu  

**Files:** Chrome components + TaskListView + BottomNav + headers  

---

### B2. Contrast pass
**IDs:** S02-09, S02D-01, S14-03, S19-02, S19-03, S39-02, S42-03  

- Raise `textMuted` / `textSecondary` on light & dark  
- Decide CTA: white on lime if dark-on-lime fails  
- Capture placeholder + disabled copy ≥4.5:1 or restructure  

**Files:** `DesignSystem` color tokens; Brain/Capture/You copy styles  

---

### B3. Briefing load & chrome clarity
**IDs:** S02-01, S02-03, S02-04, S02-06, S02-07, S02-08, ADHD-03  

- Shorten hero bullets (max 2 lines each / fewer bullets)  
- Customize → label “Customize briefing” in AX + distinct icon; Settings remains gear  
- Glance dots: use life-area tokens consistently with hero  
- Inline scroll cue only if content below fold; ensure bottom inset clears tab bar  
- Serif: document as **brand greeting only** (Wave C formalizes)

---

### B4. Task list UX
**IDs:** S14-02–S14-08  

- Chrome: Add + overflow menu (Import, Adjust schedule, Plan tomorrow, Stack)  
- Filters: stronger inactive contrast  
- Rows: reduce to checkbox + title block; category as text/chip not third competing icon if dense  
- Sort + metadata unify (from A4)  

---

### B5. Brain single start path
**IDs:** S19-01, S19-04, S19-05, S19-06, S19-07  

- Primary: **Decide for me**; secondary: Ask Brain  
- Orb tap = same as primary (or listening only) — one mental model  
- Shorten under-orb copy; caption contrast  
- Menu: visible “More” or AX-only with clear label  

---

### B6. Settings hygiene
**IDs:** S21-01–S21-06, ADHD-05  

- Rename sheet / row: e.g. sheet “You & app” or row “Preferences” (avoid Settings→App settings)  
- Today stats: non-row style (metrics strip) so not fake nav  
- Debug + Factory Reset behind `#if DEBUG` or Developer unlock  
- Unify footer placement (always below or always inside)  
- Done uses shared chrome  

---

### B7. Capture composer
**IDs:** S39-02–S39-07  

- Unify Speak / Auto / Save languages (outline secondary, filled primary when enabled)  
- Dismiss: top trailing `xmark` toolbar, not bottom center FAB  
- Reduce empty vertical gap; chip carousel fade/peek  
- Demote “View inbox” to secondary  

---

### B8. You hub
**IDs:** S42-01–S42-06  

- Bottom content inset so Routines clear tab bar  
- Thicker progress / clearer hierarchy  
- Sun → “Appearance” label or menu  
- Link accent → brand lime (not system blue)  
- Optional: one more Life area shortcut (P2 can wait)

---

### Wave B exit checklist

- [ ] B1–B8 landed  
- [ ] Recapture full set + dark  
- [ ] Manual contrast spot-check light/dark  

---

## Wave C — P2 polish & validation

| ID(s) | Work |
|-------|------|
| S02-06 (formalize) | Written type rule: serif = greeting name only |
| S04-05 | FAB optical flush |
| S14-07, S14-08 | Import label/tooltip; tighten header spacing |
| S19-06, S19-07 | Spacing + menu affordance |
| S21-05, S21-06 | Empty state / Done chrome |
| S39-07 | Inbox competition |
| S42-05 | Hub richness (if product wants) |
| Dynamic Type | XXXL on Briefing, Today, Capture, Tasks, You |
| Reduced motion | Capture morph / orb / tab bounce off; recapture |
| S02D-02 | Glance color meaning on dark |

**Exit:** Manual checklist [ui-ux-wave-cd-checklist.md](ui-ux-wave-cd-checklist.md) (XXXL + Reduce Motion); also see `10-accessibility-checklist.md`; screenshots archived.

---

## Wave D — Decisions / won’t-fix

Document explicitly if deferred:

| Topic | Options |
|-------|---------|
| Nav ≤5 | Keep 5+Capture with quiet FAB **or** drop/merge Review |
| Serif greeting | Keep as brand **or** all-sans |
| Brain orb as hero | Keep with single CTA binding **or** shrink orb |

### Wave D decisions

Explicit product calls (10 Sep 2026). Do not reopen in Wave A–C PRs unless product revisits.

| Topic | Decision | Notes |
|-------|----------|--------|
| **Nav** | **KEEP** 5 labeled tabs + quiet Capture FAB for now | Tour/product need all five destinations. Known tension with skill ≤5 total destinations; **revisit merging Review** later (into You/Briefing). Quiet FAB still required (A2). |
| **Serif** | **KEEP** for Briefing greeting name only | Brand moment; elsewhere stays sans. Formalizes S02-06 / Wave C type rule. |
| **Brain orb** | **KEEP** as hero | Primary CTA binding is **Decide for me**; orb tap = same primary. Ask Brain remains secondary. |

Won’t-fix unless product reopens: shrinking the orb, all-sans greeting, or collapsing to 4 tabs in this audit cycle.

**Wave C–D manual validation:** [ui-ux-wave-cd-checklist.md](ui-ux-wave-cd-checklist.md).

---


## Traceability matrix (audit ID → wave)

| ID | Wave |
|----|------|
| S02-01 | B3 |
| S02-02 | A2 |
| S02-03 | B3 |
| S02-04 | B3 |
| S02-05 | A4 |
| S02-06 | B3 / C |
| S02-07 | B3 |
| S02-08 | B3 |
| S02-09 | B2 |
| S02D-01 | B2 |
| S02D-02 | C |
| S02D-03 | A2 |
| S04-01 | A2 (+ D if product) |
| S04-02 | A2 |
| S04-03 | B1 |
| S04-04 | A2 |
| S04-05 | C |
| S05-01 | A1 |
| S05-02 | A3 |
| S05-03 | A3 |
| S05-04 | A4 |
| S05-05 | A4 |
| S05-06 | A3 |
| S05-07 | A3 |
| S05-08 | A3 |
| S05-09 | B1 |
| S05-10 | A2 |
| S14-01 | B1 |
| S14-02 | B4 |
| S14-03 | B2 / B4 |
| S14-04 | A4 |
| S14-05 | A4 |
| S14-06 | B4 |
| S14-07 | C |
| S14-08 | C |
| S19-01 | B5 |
| S19-02 | B2 |
| S19-03 | B2 |
| S19-04 | B5 |
| S19-05 | A2 / B5 |
| S19-06 | C |
| S19-07 | C |
| S21-01 | B6 |
| S21-02 | B6 |
| S21-03 | B6 |
| S21-04 | B6 |
| S21-05 | C |
| S21-06 | C |
| S39-01 | A5 |
| S39-02 | B2 / B7 |
| S39-03 | B7 |
| S39-04 | B7 |
| S39-05 | B7 |
| S39-06 | B7 |
| S39-07 | C |
| S42-01 | B8 |
| S42-02 | B8 |
| S42-03 | B2 / B8 |
| S42-04 | B8 |
| S42-05 | C / D |
| S42-06 | B8 |
| ADHD-01 | A1 + A3 |
| ADHD-02 | A1 |
| ADHD-03 | B3 |
| ADHD-04 | A4 |
| ADHD-05 | B6 |

---

## Working agreements while implementing

1. One wave PR (or one PR per A1–A5 if preferred) — keep reviewable.  
2. No “fixed” claims without new `latest/` shot named in the PR.  
3. Update [ui-ux-polish-wave-notes.md](./ui-ux-polish-wave-notes.md) after each wave.  
4. Tour / UITest anchors updated when chrome moves (Today assistant, Capture).  
5. Firebase OAuth sync script must stay idempotent (already rewritten) so captures don’t flake.

---

## Suggested first implementation slice (when you say go)

Start **Wave A only**, in order: **A1 → A2 → A5 → A4 → A3** (Replan + Capture + Capture CTA + trust + Today load), then recapture and stop for review before Wave B.

---

---

## Successor plan (path to 10)

A–D closes the audit’s chrome/trust floor (~6.5/10). For decision-architecture work to reach **10/10**, see:

**[ui-ux-path-to-10-plan-2026-09-10.md](./ui-ux-path-to-10-plan-2026-09-10.md)** — Waves **E–H** (Today Do-this-now, Briefing gate + 4-tab nav, Brain/Capture polish, craft + a11y + scenario proof). Reopens the Wave D “keep 5 tabs” decision.

---

*End of plan.*
