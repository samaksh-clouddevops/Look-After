# Look After — Path to 10 UI/UX plan

**Date:** 10 Sep 2026  
**Baseline score:** ~6.5 / 10 (post Waves A–D chrome + trust)  
**Target:** 10 / 10 for an ADHD “decide → start” product  
**Foundation:** [ui-ux-fix-plan-2026-09-10.md](./ui-ux-fix-plan-2026-09-10.md) (A–D mostly landed)  
**Audits:** [ui-ux-full-screenshot-audit-2026-09-10.md](./ui-ux-full-screenshot-audit-2026-09-10.md), [ui-ux-deep-issue-inventory.md](./ui-ux-deep-issue-inventory.md)  
**Constraints:** Keep DesignSystem lime (no skill teal/orange). Structure before polish. Prove every wave with `./Scripts/capture-ux-review.sh` + named shots in `screenshots/ux-agent/latest/`.

---

## What “10” means here

Open Look After → know the **one** next move → start it in **&lt;3 seconds**, with:

1. **Decide** — one primary above the fold  
2. **Start** — one tap into Focus / Decide; everything else deferred  
3. **Trust** — times, durations, order never contradict (live data, not only UITest seed)  
4. **Nav** — ≤5 bottom chrome slots; Capture never a peer “selected” destination  
5. **Calm** — first viewport = one job + brand, not a dashboard  
6. **Craft + a11y** — no truncation bugs; XXXL + Reduce Motion pass

A 10 is **decision architecture**, not denser cards or prettier padding.

---

## Score path

| Stage | Target | Must ship |
|-------|--------|-----------|
| Now (A–D) | **6.5** | Replan dock gone; quiet Capture; trust/sort/CTA; control matrix |
| **Wave E** | **8.0** | Today = Do-this-now + single coach slot |
| **Wave F** | **9.0** | Briefing gate + nav cut (4 tabs + Capture) |
| **Wave G** | **9.5** | Brain one path; Capture finish; metadata/trust polish |
| **Wave H** | **10** | Craft motion; You Life State; XXXL/Reduce Motion proof; empty/crisis-day calm |

Do not claim a stage score without new `latest/` proof for that wave’s exit shots.

---

## Principles (path-to-10)

1. **One coach card max** — never stack Schedule check + Transition + Micro-start.  
2. **Hero = next action** — priorities support the hero; they don’t compete with it.  
3. **Progressive disclosure by default** — week strip, context chips, glance, Ask Brain, Review are secondary.  
4. **Product courage on nav** — Wave D “keep 5 tabs” is **reopened** for a 10.  
5. **Reuse before invent** — mount existing `TodayRecommendedHeroCard` / `TodayWhyAffordance`; demote unused chrome.  
6. **Real-day scenarios** — empty day, overcommitted day, crisis/low-energy day must feel as calm as UITest happy path.

---

## Delivery shape

| Wave | Focus | Est. | Exit gate (shots) | Score |
|------|--------|------|-------------------|-------|
| **E** | Today Do-this-now rebuild | 3–5 days | S05: one lime CTA + next task; no dual banners; title not “T…” | → 8.0 |
| **F** | Briefing gate + nav fold | 3–4 days | S02 first fold = greeting + ≤2 lines + CTA; S04 = 4 tabs + quiet FAB | → 9.0 |
| **G** | Brain / Capture / trust polish | 2–3 days | S19 one start path; S39 Save competition gone; S14 metadata unified | → 9.5 |
| **H** | Craft + a11y + scenario proof | 2–3 days | XXXL/RM checklist green; empty + overcommit captures; motion intentional | → 10 |

After each wave: update [ui-ux-polish-wave-notes.md](./ui-ux-polish-wave-notes.md) with **verified** (shot IDs), not “in progress.”

---

## Wave E — Today = Do this now (→ 8.0)

**Closes residual:** S05-02, S05-03, S05-07, S05-08, ADHD-01; partial S05-09  
**Unblocks:** everything else (Briefing/nav only matter after Today stops overwhelming)

### E1. Single coach slot (`TodayCoachSlot`)

**Decision:** Exactly **one** proactive surface above the task list, chosen by priority:

1. Overcommit / pre-window fit (`PreWindowFitBanner`)  
2. Else transition / time-critical moment  
3. Else micro-start / initiation bridge  
4. Else **nothing** (hero alone)

Never render `TodayPreWindowFitSection` and `TodayProactiveSuggestionSection` as siblings. Collapse into one owner that picks the winner.

**Files:**  
- `Apps/LookAfter-iOS/Views/Briefing/TodayView.swift` (`TodayPreWindowFitSection`, `TodayProactiveSuggestionSection`, `TodayInlineNegotiationSection`)  
- `Packages/LookAfterCore/.../PreWindowFitAnalyzer.swift`  
- Proactive selection in Today / `ProactiveActionRouter`

**Acceptance:** S05 shows ≤1 white coach card above tasks.

---

### E2. Do-this-now hero

**Decision:** First content after (optional) coach = **next actionable task** as hero:

- Title, when, duration (trust-aligned via `TaskDurationPolicy`)  
- **One** primary CTA: Start N-min focus (or Open if not startable)  
- Optional “Why this?” via existing `TodayWhyAffordance`  
- Mount / wire `TodayRecommendedHeroCard` (exists, currently unused in stack)

**Files:**  
- `TodayView.swift` — `TodayRecommendedHeroCard`, `TodayWhyAffordance`  
- Sort: `TaskListSorter.sortByNextActionableThenPriority`  
- Start path: `ProactiveActionRouter` / `ADHDViewModel.startFocusSession`

**Acceptance:** S05 first fold answers “what do I do?” without reading two banners.

---

### E3. Demote week strip + context chips

**Decision:**  
- Default: **hide** week strip and “I just woke up” / “Going out” from first fold.  
- Reveal via single control: **“Day”** disclosure / menu in header, **or** inside Plan sheet.  
- Context chips must not share toolbar glass language when shown.

**Files:**  
- `TodayView.swift` — `TodayContextQuickActions`, `LAWeekDateStrip` placement  
- Plan sheet: `ExecutiveAssistantSheet.swift` (optional home for chips)

**Acceptance:** S05 first fold has no dual context pills + full week strip before the hero.

---

### E4. Toolbar + title fix

**Decision:**  
- Visible: **Plan** (sparkles) + **overflow** (`…`) containing All tasks / Refresh / Settings.  
- Fix truncated title **“T…”** — title must read “Today” at default Dynamic Type (layout: don’t crush title with 4 peer icon buttons).

**Files:**  
- `TodayHeaderBar` in `TodayView.swift`  
- Tour: `.todayAssistant` stays on Plan

**Acceptance:** S05 header shows full “Today”; ≤2 chrome controls visible.

---

### E5. Priorities as support, not rival

**Decision:**  
- Rename section affordance to **“Up next”** (or keep “Top Priorities” but visually secondary to hero).  
- Show **2** items max in first fold; rest via “View full timeline” / All tasks.  
- Row metadata: compact `7:30 · 5m · Medium` — not four competing pills if it crowds the hero.

**Files:**  
- `TodayPrioritiesSection` in `TodayView.swift`  
- `TaskCardView` / metadata helpers if shared

**Acceptance:** Hero CTA optically dominates priorities; priorities still scannable.

---

### Wave E exit checklist

- [ ] S05: one coach card **or** none  
- [ ] S05: Do-this-now hero + one primary lime CTA  
- [ ] S05: no context chips + week strip in first fold (default)  
- [ ] S05: title “Today” not truncated  
- [ ] Build green; tour Plan still findable  
- [ ] Score claim **8.0** only after side-by-side vs prior S05

---

## Wave F — Briefing gate + nav cut (→ 9.0)

**Reopens Wave D nav decision.** Tour must be updated when Review leaves the tab bar.

### F1. Briefing first viewport = gate

**Decision:** First viewport contains **only**:

1. Greeting (serif name stays — brand)  
2. ≤2 hero lines (morning-relevant, from `BriefingDayHeroSummaryGenerator`)  
3. One CTA: **“Start my day”** → Today (or Focus if a session is the right next step)

**Move below fold or disclose:** “Today at a Glance”, Customize density, chapter previews.

**Files:**  
- `DailyBriefingView.swift` — `firstViewport(onContinue:)`  
- `DailyBriefingCards.swift` / `LAExecutiveBriefingCard`  
- `BriefingDayHeroSummaryGenerator`

**Acceptance:** S02 first fold has no glance card competing with Continue; hero ≤2 lines.

---

### F2. Nav: 4 labeled tabs + Capture

**Product decision (path-to-10):**

| Keep | Fold |
|------|------|
| Briefing, Today, Brain, You | **Review** → section under **You** (preferred) or Briefing chapter |

- Capture remains center **quiet** `LACaptureFAB` (not a tab).  
- Bottom chrome = 4 labels + FAB = skill-aligned pressure relief.  
- Deep links / tour `.reviewHero` retarget to You → Review section.  
- UITests / capture pipeline update tab indices.

**Files:**  
- `LookAfterBottomNav.swift` — `LookAfterTab`  
- `LookAfterRootCanvas.swift` / tab routing  
- You hub: Review entry row  
- `AppFeatureTourModels.swift` / coordinator  
- `Scripts/capture-ux-review.sh` / snapshot tests if tab-order dependent

**Acceptance:** S04 shows 4 tabs + quiet Capture; Review reachable from You in ≤2 taps.

**Fallback (if product blocks F2):** Capture leaves the bar entirely (header / keyboard only) so labeled tabs stay ≤5 — document as F2-alt; score caps at ~8.5 until real fold ships.

---

### Wave F exit checklist

- [ ] S02: greeting + ≤2 lines + one CTA  
- [ ] S04: 4 tabs + quiet FAB (or documented F2-alt)  
- [ ] Tour + UITests green for new IA  
- [ ] Score claim **9.0**

---

## Wave G — Brain, Capture, trust polish (→ 9.5)

### G1. Brain = one start path

**Decision:**  
- Primary: **Decide for me** (`accentOnPrimary` on lime).  
- Orb tap = **same** action (already intended).  
- **Ask Brain** → secondary text / overflow — not a second large peer CTA.  
- Remove redundant under-button caption; put listening/thinking **in orb state**.

**Files:**  
- `BrainDashboardView.swift`

**Acceptance:** S19 has one dominant CTA; orb does not invent a third product path.

---

### G2. Capture finish

**Decision:**  
- Empty: caption “Type or speak to save” (done).  
- After first character: sticky **Save** primary.  
- Speak secondary; Auto chip quieter / outline.  
- **View inbox** only post-save or in overflow — not competing with Save on empty sheet.

**Files:**  
- `CaptureComposerView.swift`

**Acceptance:** S39 empty = caption; with text = Save only as primary exit (besides dismiss).

---

### G3. Metadata + list trust

**Decision:** One metadata pattern app-wide: `time · duration · priority` (e.g. `7:30 AM · 5m · Medium`). Retire repeated “Estimated time N min” prose on dense lists. Confirm All Tasks / Top Priorities sort on **non-UITest** fixtures.

**Files:**  
- `TaskCardView.swift`, `TagChipView.swift`  
- `TaskFocusStretchResolver` / `TaskFocusStretchRefiner`  
- `TaskListSorter` + tests

**Acceptance:** S14 rows scannable; no conflicting duration languages.

---

### G4. Settings / production hygiene

**Decision:** Developer + Factory Reset **DEBUG-only** (verify Release). Stats rows not looking like dead nav. Lime links (not blue) for in-brand actions.

**Files:** Settings / You settings stack

**Acceptance:** S21 production-like build has no Factory Reset.

---

### Wave G exit checklist

- [ ] S19 / S39 / S14 / S21 match above  
- [ ] Score claim **9.5**

---

## Wave H — Craft, a11y, scenario proof (→ 10)

### H1. Intentional motion (2–3 moments)

- Plan sheet present/dismiss  
- Capture morph from FAB  
- Focus session enter  

All respect **Reduce Motion** (fade/static alternatives). No decorative bounce that implies wrong selected state on tabs.

**Files:** sheet/FAB/Focus presentation sites; motion tokens if any

---

### H2. You Life State craft

- Thicker energy/focus/wellbeing bars; clearer hierarchy vs “You” title  
- “See all insights” uses **lime** brand link (not system blue)  
- Routines clear tab bar inset (already partly addressed — re-verify)

**Files:** You hub views

---

### H3. Accessibility sign-off

Run and tick every row in [ui-ux-wave-cd-checklist.md](./ui-ux-wave-cd-checklist.md):

- Dynamic Type **XXXL** on Briefing, Today, Capture, Tasks, You, Brain, chrome  
- **Reduce Motion** On for the same  

Archive proof shots or note device + date in polish notes.

---

### H4. Scenario captures (product truth)

Add / run capture variants (or manual shots) for:

| Scenario | Calm criteria |
|----------|----------------|
| **Empty day** | Hero copy honest; one Capture or Plan CTA; no fake urgency banners |
| **Overcommitted** | Single coach slot only; Start path still visible or explicitly deferred with one reason |
| **Low energy / post-wake** | Copy shorter; Decide/Start not buried |

Without these, UITest happy path can look like a 10 while real days stay a 7.

---

### Wave H exit checklist

- [ ] XXXL + Reduce Motion checklist all Pass  
- [ ] Motion moments present + RM-safe  
- [ ] Empty + overcommit (+ optional low-energy) shots calm  
- [ ] Side-by-side S02/S05/S04/S19 vs 6.5 baseline — structure obviously different  
- [ ] Score claim **10** only if Decide→Start &lt;3s holds on a real device with real tasks

---

## Explicit product decisions (path-to-10)

| Topic | Decision | Notes |
|-------|----------|--------|
| **Today first fold** | Do-this-now hero + ≤1 coach slot; week/chips demoted | Replaces soft A3 “reduce padding” |
| **Nav** | **4 tabs + Capture**; Review under You | **Reopens** Wave D “keep 5” |
| **Serif** | Keep greeting name only | Unchanged |
| **Brain orb** | Keep hero; Decide = only primary | Ask Brain demoted further |
| **Glance on Briefing** | Below fold / disclose | Not first viewport |
| **F2-alt** | Only if Review cannot move | Capture off bar; score may stall ~8.5 |

Won’t-fix for a 10: stacking multiple coach banners “because both are useful”; keeping Review in the tab bar without another chrome cut.

---

## Traceability (path-to-10 → residual / themes)

| Theme / ID | Wave |
|------------|------|
| Today cognitive load (S05-02/03/07/08, ADHD-01) | E |
| Title truncation / toolbar density (S05-09) | E4 |
| Briefing first-fold load (S02-01, ADHD-03) | F1 |
| Nav ≤5 / destination pressure (S04-01, Wave D reopen) | F2 |
| Brain three start paths (S19-01/04/05) | G1 |
| Capture competition (S39-05/07 residual) | G2 |
| List metadata / trust (S14-05, ADHD-04 residual) | G3 |
| Settings destructive (ADHD-05) | G4 |
| You craft / blue link (S42-02/06) | H2 |
| XXXL / Reduce Motion | H3 |
| Empty / crisis day calm | H4 |

Audit IDs already closed in A–D stay closed; this plan does not re-litigate Replan dock or quiet FAB unless regression appears.

---

## Working agreements

1. One PR per wave (or E1–E5 slices if review needs smaller diffs).  
2. No “fixed” / score claims without named `latest/` files.  
3. Update polish notes after each wave with Pass/Fail table.  
4. Tour + UITest anchors updated when IA moves (Review, Today chrome, Briefing glance).  
5. Prefer mounting existing hero/why affordances over new card systems.  
6. Keep Firebase OAuth sync idempotent so captures don’t flake.

---

## Suggested first implementation slice

When you say go: **Wave E only**, order **E1 → E2 → E4 → E3 → E5**, then recapture S05 and stop for review before Wave F (nav is the product call that needs explicit “yes”).

---

## Related docs

| Doc | Role |
|-----|------|
| [ui-ux-fix-plan-2026-09-10.md](./ui-ux-fix-plan-2026-09-10.md) | Waves A–D foundation |
| [ui-ux-polish-wave-notes.md](./ui-ux-polish-wave-notes.md) | Verified changelog |
| [ui-ux-wave-cd-checklist.md](./ui-ux-wave-cd-checklist.md) | XXXL / Reduce Motion (H3) |
| [ui-ux-full-screenshot-audit-2026-09-10.md](./ui-ux-full-screenshot-audit-2026-09-10.md) | Original findings |

---

*End of path-to-10 plan.*
