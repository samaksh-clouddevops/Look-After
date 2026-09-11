# UX polish plan — open cases after ~8/10 review

**Date:** 10 Sep 2026  
**Baseline stamp:** `screenshots/ux-agent/latest/` run `20260910-155111` (post-polish)  
**Prior baseline:** `20260910-145619` (~8/10)  
**Prior:** [ui-ux-flow-fix-plan-2026-09-10.md](ui-ux-flow-fix-plan-2026-09-10.md) (journey P0 closed)  
**Goal:** ~8 → **9/10** on chrome density, rail continuity, seed truth, disabled contrast — no OccupiedDay / schedule-physics reopen.  
**Styling lens:** Token discipline (SwiftUI + DesignSystem), not a visual redesign. ui-styling review approved defaults with the tweaks below.

**Audit lens:** Touch ≥44×44 · label optically fills CTA · one primary per fold · continuous time spine · DesignSystem lime · `accentOnPrimary` on filled · Dynamic Type XXXL spot-check on exit.

---

## YOUR INPUT (defaults locked from ui-styling)

- **P1 — Primary CTA chrome:** [DEFAULT: Shared filled recipe — `dsBody(weight: .semibold)` + **exact 44pt** height (`DesignSystem.minTouchTarget`); grow via type scale only; `radiusButton` (18) / capsule — **not** `radiusFloating` on wide bars; strip stacked padding that creates empty lime]
  - Your choice: `________________________________`
- **P2 — Plan sheet density:** [DEFAULT: Fit content at `.medium` when idle; grow to `.large` only with keyboard / long thread; **top-align** stack; no `Spacer` under input]
  - Your choice: `________________________________`
- **P3 — Capture empty:** [DEFAULT: Keep Save in bottom inset; short helper under chips (“Type or speak to enable Save”); disabled Save = outline + `textSecondary` on `contentSurface` ≥4.5:1 — never grey-on-grey fill]
  - Your choice: `________________________________`
- **P4 — Time rail:** [DEFAULT: One continuous stroke **behind** dots (Glance + Full timeline); dots sit on the line]
  - Your choice: `________________________________`
- **P5 — Glance / schedule duplicates:** [DEFAULT: Dedupe by task id / title+day across Glance, Schedule preview, Full timeline, All Tasks; prefer next upcoming; never two identical “after waking” rows; fix 5:00 AM seed/timezone at source]
  - Your choice: `________________________________`
- **P6 — Health tile copy:** [DEFAULT: Prefer **shorter string** — “Connect Health for estimate” — over aggressive `minimumScaleFactor`; `lineLimit(2)` only as safety net]
  - Your choice: `________________________________`
- **P7 — Sheet Done chrome:** [DEFAULT: Keep text-only lime Done (iOS convention); do **not** fill lime — avoids competing with I’m ready / Start; optional slightly stronger weight only]
  - Your choice: `________________________________`
- **Recapture:** [DEFAULT: yes — `./Scripts/capture-ux-review.sh` after Waves 1–3]

---

## Open cases → work IDs

| ID | Shot | Issue | Sev |
|----|------|--------|-----|
| POL-T1 | F01/F02/F05 | Filled CTA taller than label; F01 vs F05 font mismatch (`dsCaption`/`dsHeadline`) | P0 |
| POL-T2 | F05 vs F09 | Hero Start vs Plan I’m ready height mismatch — lock both to 44 | P0 |
| POL-D1 | F09 | Plan sheet card ≫ content; empty bottom | P0 |
| POL-D2 | F13 | Capture empty mid void; disabled Save low contrast (white on pale grey) | P0 |
| POL-R1 | F01 Glance | Per-row rail segments; not one continuous spine | P1 |
| POL-R2 | F07 | Full timeline spine gaps at dots (verify after continuous stroke) | P1 |
| POL-S1 | F01/F06/F07/F11 | Duplicate “Brush teeth after waking” + bad 5:00 AM across Glance, Schedule, Full timeline, All Tasks | P0 (trust) |
| POL-H1 | F11 | All Tasks still shows “Brush teeth — morning” (em-dash AI tone) beside humanized twin | P0 (trust) |
| POL-C1 | F02 | Energy/Recovery subtitle truncated mid-word | P1 |
| POL-C2 | F09/F07 | Done lime-on-pale weak; keep text Done, bump weight only | P2 |
| POL-B1 | F02 | Health promo card pink/red border vs lime system | P2 |
| POL-B2 | F13 | Capture chips clip on trailing edge; Speak vs chip row alignment drift | P2 |
| POL-B3 | F06 | Schedule preview blocks oversized vs title/duration content | P2 |
| POL-B4 | F05/F17 | Serif on hero “Lunch” / You initials — lock is Briefing-name only | P2 |
| POL-B5 | F16 | Brain: large empty vertical band; “I’m here…” low contrast | P2 |

---

## Waves

| Wave | Focus | Closes | Exit |
|------|--------|--------|------|
| **0** | YOUR INPUT P1–P7 | — | Locked (ui-styling tweaks applied) |
| **1** | Shared CTA + trust seeds + Save contrast | POL-T1, POL-T2, POL-C2, POL-D2 (contrast), **POL-S1, POL-H1** | F01/F05/F09 CTAs = 44 + `dsBody` semibold; F11 no em-dash twin / no dup morning brush; F13 disabled Save readable |
| **2** | Sheet / Capture density | POL-D1, POL-D2 (void + helper) | F09 content-tight; F13 helper under chips, no dead mid gap |
| **3** | Rail + health copy + light beautify | POL-R1/R2, POL-C1, POL-B1–B3 | F01 continuous Glance spine; F07 continuous rail; F02 short health copy; optional B1–B3 |
| **4** | Recapture + score | Proof (+ optional POL-B4/B5 if time) | ≥9 only if Wave 1–2 clear on PNGs |

**Order:** CTA + **seed trust (POL-S1/H1)** before density; density before rail cosmetics. Do not style a continuous rail on duplicate broken rows.

**Padding rule (9/10):** Interactive rows / CTAs use `spacingSM` internal padding; section cards keep `cardPaddingMin` (24). Do **not** globally shrink all cards.

---

## Wave 1 — Shared CTA + seed trust + contrast

**Files (likely):** `PremiumButtons` / new `LAFilledPrimaryButton`, `LookAfterV4Components` (Start my day), `HealthStatusBanner`, hero Start, Plan I’m ready, `CaptureComposerView` disabled Save, `OnboardingTaskSeeder` / Glance query / `TaskTitleDisplay.humanized`, toolbar Done weight.

| Work | Detail |
|------|--------|
| W1-a | Introduce one filled primary: `.font(.dsBody(weight: .semibold))` + `frame(minHeight: DesignSystem.minTouchTarget)` (44) + `radiusButton` / capsule + horizontal pad only — **no** stacked vertical chrome that exceeds label |
| W1-b | Apply to Briefing Start, Health Connect, hero Start, Plan I’m ready, Capture **enabled** Save |
| W1-c | Capture disabled Save: outline + `textSecondary` on `contentSurface` (not pale fill + white label) |
| W1-d | Plan/Timeline Done: text lime only; slightly stronger weight if needed; hit ≥44pt |
| W1-e | **POL-S1:** Dedupe Glance + Schedule preview + Full timeline + list sources; fix 5:00 AM seed/timezone |
| W1-f | **POL-H1:** Humanize / retire “Brush teeth — morning” so All Tasks matches Glance language |

**Exit:** F01/F05/F09 primaries optically fill 44pt pills with same type token; F11 one morning brush (humanized); F13 disabled Save scannable.

---

## Wave 2 — Sheet / Capture density

**Files:** `TodayView` presentationDetents, `ExecutiveAssistantSheet` / `ExecutivePlanningConversationView`, `CaptureComposerView`.

| Work | Detail |
|------|--------|
| W2-a | Plan: `.medium` idle, top-aligned; no infinite spacer under input; `.large` when keyboard / long thread |
| W2-b | Capture: keep `ScrollView` + bottom `safeAreaInset` Save; helper under chips; remove dead mid gap when keyboard hidden |
| W2-c | Keyboard: interactive dismiss; Save stays above keyboard |

**Exit:** F09 and F13 first viewport feel content-led, not empty-card.

---

## Wave 3 — Rail continuity + health copy + light beautify

**Files:** `LABriefingGlanceRow` / `DailyBriefingView.glanceEvents`, `ExecutiveLiveTimelineView` rail, health snapshot tiles in `DailyBriefingCards`, optional Health banner border, Capture chip scroll, Schedule row padding.

| Work | Detail |
|------|--------|
| W3-a | Glance: single continuous ZStack line behind row dots (or one shared rail wrapping the list) |
| W3-b | Full timeline: stroke behind dots (first-dot center → last); colored segments OK if abutting |
| W3-c | Health bands: copy → “Connect Health for estimate” (or equivalent short); `lineLimit(2)` safety only |
| W3-d | Optional POL-B1: Health promo border → `contentBorder` / lime-tint, drop pink clash |
| W3-e | Optional POL-B2: Capture chip scroll padding so trailing chip isn’t clipped; align Speak with chip leading |
| W3-f | Optional POL-B3: Tighten Schedule preview block vertical padding (`spacingSM`) |

**Exit:** F01 Glance continuous + unique rows (from W1); F07 continuous spine; F02 subtitles readable end-to-end.

---

## Wave 4 — Proof (+ optional serif / Brain)

1. `./Scripts/capture-ux-review.sh`  
2. Visual: F01 CTA + Glance, F02 Health/tiles, F05 Start, F07 rail, F09 density, F11 titles, F13 Save  
3. Light + dark F01 Start  
4. Optional: POL-B4 (serif only on Briefing name), POL-B5 (Brain subtitle contrast / less empty band)  
5. Score only on new stamp; update this doc Status  

---

## Screenshot review notes (stamp `20260910-145619`)

Fresh pass over `screenshots/ux-agent/latest` (F01–F17 + dark F01):

| Surface | Still good | Still open / new |
|---------|------------|------------------|
| F01 Briefing | One Start primary; serif name; calm FOR TODAY | CTA optical fill; Glance dups + discontinuous rail |
| F02 Health | Full-width Connect pill | Truncated Energy/Recovery; tall Connect; pink card border |
| F05 Today | Quiet coach outline; hero clear | Start taller than Plan I’m ready; serif “Lunch” vs lock |
| F06 Schedule | Continuous green between blocks | Same brush dups; blocks feel padded |
| F07 Full timeline | Humanized titles; Done present | Dup 5:00 AM row; Done contrast; spine verify |
| F09 Plan | I’m ready primary + More | Sheet empty bottom; Done weak |
| F11 All Tasks | Filters clear | Em-dash “Brush teeth — morning” + humanized twin |
| F13 Capture | Save sticky bottom | Mid void; disabled Save unreadable; chip clip |
| F16 Brain | Calm orb | Large empty band; soft subtitle contrast |
| F17 You | Life State clear | Serif initials (lock drift) |

No OccupiedDay / schedule-physics work from this review.

---

## Locked

- DesignSystem lime; serif Briefing-name only  
- Journey rules from flow plan (quiet coach, I’m ready primary, hero = rail NOW)  
- No OccupiedDay / schedule-physics reopen unless pure UI  
- One filled primary per fold; sheet Done stays text (not filled lime)  

---

## Status

**Waves 1–4 implemented** (defaults + ui-styling tweaks).  
**Recapture stamp:** `20260910-155111` (`screenshots/ux-agent/latest/`).  
**Closed in code:** POL-T1/T2, POL-D1/D2, POL-R1/R2, POL-S1, POL-H1, POL-C1/C2, POL-B1–B5.  
**Verify on stamp:** CTA 44 + optical fill; Capture outline Save + helper; no em-dash brush twin; health “Connect Health for estimate”; continuous Glance spine; Plan medium→large on keyboard.
