# UX flow fix plan (post F01→F19 ui-ux-pro-max review)

**Date:** 10 Sep 2026 · **Revised:** same day (plan meta-review)  
**Cursor plan (executable):** [`~/.cursor/plans/ux_flow_fix_plan_2026_09_10.plan.md`](file:///Users/samaksh/.cursor/plans/ux_flow_fix_plan_2026_09_10.plan.md) — fill YOUR INPUT there or reply “accept defaults”  
**Source shots:** `screenshots/ux-agent/latest/` (run `20260910-133343` — full functionality flow)  
**Shot list:** [ux-agent-full-flow-shot-list.md](./ux-agent-full-flow-shot-list.md)  
**Prior plan (destination shots):** [ui-ux-screenshot-fix-plan-2026-09-10.md](./ui-ux-screenshot-fix-plan-2026-09-10.md)  
**Baseline from review:** ~7.5/10  

**Audit lens (ui-ux-pro-max):** Touch ≥44×44pt iOS + ≥8pt gap · no clipped/wrapped button labels · one primary CTA per fold · card vertical rhythm · SwiftUI `.accessibilityLabel` · no emoji-as-icon · Dynamic Type / Reduce Motion on exit  

**ID convention:** `FLOW-*` = product/journey trust · `LAY-*` = chrome. When both tag the same bug, **track the first token** in the P0/P1 index row.

---

## Plan amendments (ui-ux-pro-max meta-review)

| Change | Why |
|--------|-----|
| **V3 default primary = “I’m ready”** | Unblocks Wave 2; closes transition; Open plan stays secondary |
| **LAY-S2 → P0** (ships in Wave 1) | Touch is CRITICAL; coach ~32–36pt fails 44pt |
| **LAY-S1 stays P0 but deferred to Wave 3** | Today trust (F05) beats Health chrome for ≥8 path; do not drop |
| **Wave 4 + Dynamic Type XXXL + light/dark filled-CTA check** | Pre-delivery checklist |
| **Wave 1 exit: harness ≠ UX pass** | Assert is necessary; PNG visual still required |

---

## Context

Waves 1–3 of the earlier screenshot plan shipped in code. Fresh **flow** capture (F01–F19) proved Capture, Brain, All Tasks, and Briefing first fold — and exposed remaining **Today / Plan / clock-truth** gaps plus **button size, in-button text, card placement, and CTA placement** defects.

**Rule:** Score only against a new `latest/` after this plan’s waves. Do not reopen OccupiedDay / Plan-approval architecture unless a fix is pure UI hierarchy or copy.  
**Order:** Do not start Wave 3 before Waves 1–2. ~7.5→8+ depends on F05/F09 first.

---

## Control & layout audit (F01→F19)

Focused pass on **button size**, **text inside buttons**, **normal text / card placement**, and **button placement**. Visual estimates from simulator PNGs.

### A. Button size

| ID | Shot | What’s wrong | Target | Sev |
|----|------|----------------|--------|-----|
| **LAY-S1** | F02 | Connect Health **circle** too small | Full-width pill ≥44pt | **P0 → W3** |
| **LAY-S2** | F05, F09, F10 | Open plan / More ~32–36pt | `minHeight` 44 | **P0 → W1** |
| **LAY-S3** | F02 | Minus ≪44pt | 44pt hit | P1 |
| **LAY-S4** | F06, F07 | Chevrons ~20–24pt | 44pt hit | P1 |
| **LAY-S5** | F09 | Three CTAs cramped row | One primary + More | P0 |
| **LAY-S6** | F11 | Filter chips short; category pills tiny | ≥44pt or decorative | P2 |
| **LAY-S7** | F13 | Speak/chips short vs Save | Verify minTouchTarget | P2 |
| **LAY-S8** | F11 | + oversized vs title | Toolbar ~44–48 | P2 |

### B. Text inside buttons / compact labels

| ID | Shot | What’s wrong | Target | Sev |
|----|------|----------------|--------|-----|
| **LAY-T1** | F02 | Mid-word wrap in circle | Single-line + scale | **P0 → W3** |
| **LAY-T2** | F07 | Lunch vertical letters | lineLimit + minWidth 0 | P1 |
| **LAY-T3** | F09 | Three equal lime labels | **I’m ready** only filled | P0 |
| **LAY-T4** | F05 vs F01 | Pale-lime+black vs lime+white | `accentOnPrimary` on filled | P1 |
| **LAY-T5** | F16 | Decide dark-on-lime | `accentOnPrimary` | P1 |
| **LAY-T6** | F06–F08 | Cyan vs lime links | One link token | P1 |

### C. Card placement / normal text layout

| ID | Shot | What’s wrong | Target | Sev |
|----|------|----------------|--------|-----|
| **LAY-C1** | F05 | Missing DO THIS NOW | Scroll-to-top hero | P0 |
| **LAY-C2** | F06, F08 | EOD mid-afternoon | Gate / collapse | P1 |
| **LAY-C3** | F02 | Clock under Overdue | Fix stats | P1 |
| **LAY-C4** | F02 | Nested Health cramped | Stack title → pill → links | P0 (w/ S1) |
| **LAY-C5** | F05 | Coach empty right void | Full-width button row | P1 |
| **LAY-C6** | F07 | LATE card broken height | Same template as Passed | P1 |
| **LAY-C7** | F13 | Dead gap chips→Save | Tighten | P1 |
| **LAY-C8** | F06 | Moon emoji | SF Symbol | P2 |

### D. Button placement / CTA hierarchy

| ID | Shot | What’s wrong | Target | Sev |
|----|------|----------------|--------|-----|
| **LAY-P1** | F05 | Loud Open plan without hero | Quiet coach; hero only filled | P0 |
| **LAY-P2** | F09 | Duplicate Open plan sheet+bg | Sheet owns CTAs | P1 |
| **LAY-P3** | F09 | Three primaries horizontal | I’m ready + outline/More | P0 |
| **LAY-P4** | F02 | Text links vs broken circle | Health = pill family | P1 |
| **LAY-P5** | F16 | Ask Brain tight under Decide | ≥8pt gap | P1 |
| **LAY-P6** | F01 | Dual header icons similar | Keep distinct a11y labels | P2 |

### Severity (revised)

| Severity | IDs |
|----------|-----|
| **P0 Wave 1–2** | LAY-C1, LAY-P1, LAY-S2, LAY-P3, LAY-T3, LAY-S5 + FLOW-T* / FLOW-P1 |
| **P0 deferred Wave 3** | LAY-S1, LAY-T1, LAY-C4 |
| **P1** | LAY-S3–S4, LAY-T2/T4–T6, LAY-C2–C3/C5–C7, LAY-P2/P4/P5 |
| **P2** | LAY-S6–S8, LAY-C8, LAY-P6 |

### What looks correct (do not regress)

| Area | Shots | Notes |
|------|-------|--------|
| Primary pill CTAs | F01, F10, F12, F14, F16, F01-dark | Start my day / Start focus / Save / Decide — wide, ≥~44–50pt |
| Disabled Save | F13 | Clearly non-interactive — keep |
| Tab bar + Capture FAB | F01, F19 | ≤5 destinations; FAB not “selected” |
| All Tasks list cards | F11 | Clear title > metadata |
| Glance rows | F01 | Nested rows + chevron |
| Customize toggles | F03 | Standard row height |

---

## YOUR INPUT (defaults in brackets — reply “accept defaults” or edit)

### Product decisions

- **V1 — Today after Start my day (F05):**  
  [DEFAULT: Land on first fold with **DO THIS NOW** hero; scroll reset after Start / sheet dismiss; coach never louder than Start focus.]  
  - Your choice: `________________________________`

- **V2 — Coach vs hero when both visible:**  
  [DEFAULT: Critical coach above hero with **quiet** outline Open plan; micro below; scroll-hid hero = bug not excuse to fill Open plan.]  
  - Your choice: `________________________________`

- **V3 — Plan With Me sheet CTAs (F09):**  
  [DEFAULT: **One lime primary = “I’m ready”**; **Open plan** + **Snooze 5m** → outline or More menu; never three equal lime pills.]  
  - Your choice: `________________________________`  
  - Preferred primary label: [DEFAULT: **I’m ready**] `________________________________`

- **V4 — Clock / NOW truth (F05–F08):**  
  [DEFAULT: Hero = rail `nowTaskId`; LATE/Overdue/Passed agree with wall clock.]  
  - Your choice: `________________________________`

- **V5 — End of day on Today (F06/F08):**  
  [DEFAULT: Gate until evening or user expands; no mid-afternoon **Save & teach my brain** vs NOW.]  
  - Your choice: `________________________________`

- **V6 — Secondary link color:**  
  [DEFAULT: All text links DesignSystem lime (or textSecondary); kill cyan Full timeline.]  
  - Your choice: `________________________________`

- **V7 — Must-not-break:**  
  [DEFAULT: 4 tabs + Capture, Plan approval, Schedule 2-row preview, hero = rail NOW, lime, serif Briefing-only — **yes**]  
  - Your choice: `________________________________`

- **V8 — Button chrome rule:**  
  [DEFAULT: Multi-word CTAs = pills not circles; filled = lime + `accentOnPrimary`; secondary outline ≥44pt; icon-only ≥44pt hit.]  
  - Your choice: `________________________________`

### Acceptance

- Device / seed: `________________________________`  
- Recapture: [DEFAULT: yes — `./Scripts/capture-ux-review.sh`; F05≈F10 PNG, F09 I’m ready only filled, F02 Health pill, F07 Lunch readable, F06 no mid-day EOD, coach ≥44pt, Dynamic Type XXXL, light+dark filled CTA]

---

## Review summary (run 20260910-133343)

| Band | Steps | Verdict |
|------|-------|---------|
| Strong | F01, F03, F04, F10–F16, F19, F01-dark | Keep |
| Mixed | F02, F06–F08, F11, F13, F17–F18 | Polish |
| Fail vs intent | **F05**, **F09**, **F02 Health CTA** | P0 |

### P0 — Wave 1–2

| Canonical | Also | Shot | Issue |
|-----------|------|------|--------|
| FLOW-T1 | LAY-C1, LAY-P1 | F05 | Missing hero; Open plan loud |
| FLOW-T2 | — | F05 vs F10 | Coach hierarchy inconsistent |
| FLOW-T3 | — | F05–F08 | NOW/Passed/LATE vs clock |
| FLOW-P1 | LAY-P3, LAY-S5, LAY-T3 | F09 | Three equal lime CTAs |
| LAY-S2 | — | F05/F10 | Coach buttons &lt;44pt |

### P0 — Wave 3 deferred (must not drop)

| Canonical | Also | Shot | Issue |
|-----------|------|------|--------|
| LAY-S1 | LAY-T1, LAY-C4 | F02 | Health circle + wrap + placement |

### P1

| Canonical | Shot | Issue |
|-----------|------|--------|
| FLOW-B1 / LAY-C3 | F02 | Stats clock under Overdue |
| FLOW-E1 / LAY-C2 | F06/F08 | EOD mid-afternoon |
| FLOW-L1 / LAY-T6 | F06–F08 | Cyan Full timeline |
| FLOW-L2 / LAY-T2 | F07 | Lunch title stack |
| LAY-S3 / LAY-S4 | F02/F07 | Minus / chevron hits |
| LAY-T4 / LAY-T5 | F05/F16 | On-primary inconsistent |
| LAY-P2 | F09 | Duplicate Open plan |
| LAY-C5 / LAY-C7 | F05/F13 | Whitespace |
| FLOW-I1 / LAY-C8 | F06 | Emoji → symbol |

### Keep (do not regress)

- Briefing Glance + Start my day · Capture Save enable · Brain orb · All Tasks · F10/F12 quiet coach · 4 tabs + Capture FAB  

---

## Waves

| Wave | Focus | Closes | Exit |
|------|--------|--------|------|
| **0** | YOUR INPUT V1–V8 | — | Locked |
| **1** | Today scroll + quiet coach **44pt** + NOW=hero | FLOW-T*, LAY-C1, LAY-P1, LAY-S2 | F05 ≈ F10 **on PNG** |
| **2** | Plan **I’m ready** primary | FLOW-P1, LAY-P2/P3, LAY-S5, LAY-T3 | F09 one filled = I’m ready |
| **3** | **Deferred P0** Health pill + P1 polish | LAY-S1/T1/C4 + … | F02/F07/F16 clean |
| **4** | Recapture + DT XXXL + light/dark CTA | Proof | ≥8 only if W1–2 P0 clear |

---

## Wave 1 — Today trust (P0)

| Work | Detail |
|------|--------|
| W1-a | Scroll Today to top after Start / Plan dismiss / timeline Done / tasks dismiss |
| W1-b | `emphasizesPrimary: false` whenever hero present |
| W1-c | Hero + `nowTaskId` + LATE shared SoT |
| W1-d | Coach Open plan / More: **minHeight 44**; outline only (**LAY-S2 P0**) |
| W1-e | Harness assert `today-do-this-now` — **necessary, not sufficient** |

**Exit:** “What do I do now?” from F05 **PNG**; coach ≥44pt. Harness alone does not close FLOW-T1.

---

## Wave 2 — Plan sheet (P0)

| Work | Detail |
|------|--------|
| W2-a | **Filled primary = “I’m ready”** only; Open plan + Snooze → outline or More |
| W2-b | Override only if YOUR INPUT changes V3 |
| W2-c | Demote/hide background Open plan while sheet up |
| W2-d | Vertical stack on narrow if two secondaries remain |

**Exit:** F09 one filled CTA **I’m ready**; Done works.

---

## Wave 3 — Deferred P0 Health + layout polish

**Note:** LAY-S1/T1/C4 are **P0 deferred** — ship after Today/Plan; do not skip before claiming score.

| Work | Detail |
|------|--------|
| W3-a | Connect Apple Health → **full-width pill**; no mid-word wrap |
| W3-b | Stats: clock not under Overdue |
| W3-c | Unify secondary links to lime token |
| W3-d | LATE row title + same card template as Passed |
| W3-e | End-of-day gate; SF Symbol not emoji |
| W3-f | Minus / chevron → 44pt hits |
| W3-g | All filled lime CTAs use `accentOnPrimary` |
| W3-h | Capture chips→Save spacing; Speak/chip 44pt |
| W3-i | Optional P2: All Tasks + size; filter chips |

**Exit:** F02 Health pill; F07 Lunch readable; F16 Decide contrast OK.

---

## Wave 4 — Proof

1. `./Scripts/capture-ux-review.sh`  
2. MANIFEST `reached: yes` + **visual** F05 ≈ F10  
3. Re-check: F02 Health, F09 I’m ready, coach 44pt  
4. **Dynamic Type XXXL:** hero Start, coach, Plan I’m ready — no wrap regression  
5. **Light + dark:** filled CTAs `accentOnPrimary` (F01, F10, F16, F01-dark)  
6. ui-ux-pro-max walk F01→F19  
7. Score only on new stamp  

**Claim ≥8/10 only if Wave 1–2 P0 clear on PNGs** (Health P0 should be clear too before marketing the score).

---

## Locked

- DesignSystem lime; serif name Briefing-only  
- No OccupiedDay / schedule-physics reopen unless UI-only  
- 4 tabs + Capture FAB  
- U1–U6 remain unless V* overrides  
- V8 applies once accepted  
- V3 default **I’m ready** unless YOUR INPUT overrides  

---

## Working order

1. Fill **YOUR INPUT** (or “accept defaults”).  
2. Wave 1 → Today + coach 44pt.  
3. Wave 2 → Plan I’m ready.  
4. Wave 3 → Health pill + polish.  
5. Wave 4 → recapture + DT/dark + score.

---

## Status

- **Implemented** — Waves 0–4 complete 10 Sep 2026 (defaults V1–V8).  
- **Proof run:** `20260910-142729` → `screenshots/ux-agent/latest/` (all F01–F19 + F01-dark `reached: yes`).  
- **Visual checks on proof PNGs:**
  - F05 / F08: quiet outline **Open plan** + **DO THIS NOW** Lunch (rail NOW / LATE)
  - F09: Plan With Me sheet — filled **I'm ready** + outline **More** only
  - F02: Connect Apple Health **full-width pill**, single-line label
  - F01-dark present for filled-CTA contrast spot-check
- **Score:** Claim **≥8/10** only after ui-ux-pro-max walk of this stamp; prior baseline `20260910-133343` was ~7.5.  
- Dynamic Type XXXL: not automated in harness — spot-check Start / Open plan / I'm ready manually if shipping.
