# Apple Design Award Roadmap — Look After

**Document ID:** ADA-ROADMAP-001  
**Date:** 2026-08-10  
**Honest premise:** Awards are not guaranteed. This plan maximizes *worthiness* and Apple visibility.  
**Primary bet:** **Inclusivity** (ADHD executive support) · secondary **Interaction** · tertiary **Social Impact**  
**North-star sentence:** *The app that starts your next right 10 minutes.*

**Related:** [architecture/MASTER-IMPLEMENTATION-PLAN.md](../architecture/MASTER-IMPLEMENTATION-PLAN.md) · [qa/10-accessibility-checklist.md](../qa/10-accessibility-checklist.md) · [qa/14-production-readiness.md](../qa/14-production-readiness.md) · [qa/focus-timer-ui-lag.md](../qa/focus-timer-ui-lag.md)

---

## 0. Reality check (keep this visible)

| Outcome | Strategy |
|---------|----------|
| **Win ADA** | Exceptional craft + clear story + months of public proof + luck |
| **This roadmap optimizes for** | Product Apple *could* feature; category leadership; nomination-grade polish |
| **Do not** | Delay ship for an award lottery; expand modules to look "complete" |

**Hard rule:** If a feature does not make the *first 10 minutes* clearer, calmer, or more successful, it is **cut, buried, or post-award**.

---

## 1. Award thesis

### 1.1 One product story

> Look After is an executive companion for ADHD brains: it reads capacity, protects deep work when sleep is thin, and turns overwhelm into **one trustworthy next action**—with a focus start that feels instant.

### 1.2 Category strategy

| Priority | Category | Why you can win *only if*… |
|----------|----------|----------------------------|
| **1** | **Inclusivity** | Dynamic Type, VoiceOver, Reduce Motion, plain language, no shame UX, recovery over grind |
| **2** | **Interaction** | Briefing → Focus → Done is fluid; LA/widget/App Intent feel designed, not bolted |
| **3** | **Social Impact** | Independent stories + metrics of "days I started" |
| Avoid as primary | Visuals / Delight / pure Innovation | Need signature art direction or a one-line invention story first |

### 1.3 Five proof surfaces (reviewer must feel all five)

1. **Cold open** — clear next action in &lt; 90 seconds  
2. **Poor-sleep day** — never heroes 90m deep work (Brain #12)  
3. **Focus start** — UI lag of zero emotional weight (device-proven)  
4. **Wrong plan** — user confirms; no silent schedule mutate  
5. **Accessibility** — core path usable VoiceOver + Reduce Motion + large text  

---

## 2. Product cut — "ADA build"

### 2.1 Core loop (keep and perfect)

```text
Open → Trust hero ("do this") → Start (countdown/focus) → Work →
Complete / Defer (with recovery) → Quiet celebration → Smarter tomorrow
```

**Surfaces in the loop:** Home/Briefing hero · Focus session · Capture (voice/text) · Pin/Live Activity · Notifications that only help  

### 2.2 First-week packaging (bury, don't delete)

| Visible week 1 | Behind "More" / later |
|----------------|----------------------|
| Briefing / Now | Travel, Creative deep modules |
| Focus + ADHD tools that serve start | Full analytics labyrinth |
| Capture + Inbox | Dense settings forests |
| Today plan (simple) | Every life module at equal weight |
| Health connect (guided) | Advanced brain debug |

### 2.3 Signature moment (design this like a hero trailer beat)

**Name:** *Start Pulse*  
**Moment:** User taps primary CTA → 3-2-1 (or skip) → focus chrome appears in same breath as timer truth → Lock Screen pin is correct.  
**Metric:** Focus open p95 &lt; 100ms feel; hard fail 500ms (existing budgets).
**Never:** Spinner after they already decided to start.

---

## 3. Program structure (24 weeks)

```text
W1–4   ADA-0  Narrative freeze + cut list + baseline film
W5–10  ADA-1  Core loop craft (UX + motion + trust)
W11–14 ADA-2  Inclusivity hard bar (a11y + tone + health ethics)
W15–18 ADA-3  Performance + reliability ship bar
W19–20 ADA-4  Visual identity + App Store packaging
W21–22 ADA-5  External proof (users, press, featuring push)
W23–24 ADA-6  Freeze, App Store, sustained excellence
Ongoing        Live with dignity — no award-season hacks
```

Run **parallel** to [MASTER-IMPLEMENTATION-PLAN.md](../architecture/MASTER-IMPLEMENTATION-PLAN.md):
architecture flags stay **off by default** in the ADA build unless they remove user-visible pain.

---

## 4. Phase ADA-0 — Narrative freeze (Weeks 1–4)

**Owner:** Design + PM + Eng lead
**Exit:** Written bible + cut list signed; no new module work without exception.

| # | Work package | Exact deliverable |
|---|--------------|-------------------|
| 0.1 | **One-liner + 3-beat story** | One-pager: problem → moment of calm → outcome |
| 0.2 | **IA cut** | Week-1 nav map; list of buried modules |
| 0.3 | **Hero copy system** | Max lengths; reading level; no jargon ("orchestrate", "facade") in UI |
| 0.4 | **Emotion rules** | No shame on defer; recovery celebrated; Peak/deep work gated copy |
| 0.5 | **Competitor film study** | 10 apps: screenshot strip of first 30s |
| 0.6 | **Baseline App Preview v0** | 30s capture of *current* app (ugly truth tape) |
| 0.7 | **ADA scorecard v0** | Fill §8 with Red/Yellow/Green |
| 0.8 | **Non-goals list** | Explicit "not for award cut" (macOS parity, every module equal, etc.) |

**Exit criteria**

- [ ] "Next right 10 minutes" is the only north star in design reviews
- [ ] Cut list PR merged (feature flags or nav hide — not code delete required)
- [ ] Trailer script draft approved

---

## 5. Phase ADA-1 — Core loop craft (Weeks 5–10)

**Owner:** iOS design + Features eng
**Exit:** 10/10 strangers complete first start without help.

### 5.1 First-run (must feel like care, not onboarding homework)

| # | Task | Done when |
|---|------|-----------|
| 1.1 | Reduce sign-in friction for try path (guest OK if safe) | Hero usable before deep settings |
| 1.2 | Guided Health connect as optional *boost*, not wall | Decline still gets honest low-confidence UI |
| 1.3 | Tour: **3 steps max** tied to hero action | No 12-page swagger tour |
| 1.4 | Empty states design, not placeholders | Capture / add one task / breathe |
| 1.5 | Failure copy audit | Network/AI/health fail = human, next step |

### 5.2 Briefing / Now (trust surface)

| # | Task | Done when |
|---|------|-----------|
| 1.6 | One primary CTA always | Secondary actions visually quieter |
| 1.7 | Explainability one line | "Why this" without essay |
| 1.8 | Stale hero impossible | Complete → hero updates same session (R-001 class) |
| 1.9 | Poor sleep state design | Recovery hero + soft palette/motion |
| 1.10 | Planning mutations always confirm | Already fixed — regression UI test |

### 5.3 Focus = signature interaction

| # | Task | Done when |
|---|------|-----------|
| 1.11 | Device Instruments: Focus open | Meet QA-09 budgets on physical device |
| 1.12 | Start Pulse motion | Designed under Reduce Motion too |
| 1.13 | Live Activity matches in-app | No orphan/stale pin (prior fixes + verify) |
| 1.14 | Pause/end haptics + copy | Calm, not gameified spam |
| 1.15 | Interruption resume | Honest recovery, not fake restart |

### 5.4 Capture

| # | Task | Done when |
|---|------|-----------|
| 1.16 | Voice/text capture &lt; 2 taps from home | Offline queue never silent-drop (fixed path — verify UX) |
| 1.17 | Success toast → optional "add to today" | No modal maze |

**Exit criteria**

- [ ] Moderated tests n=8 ADHD / executive-dysfunction users; ≥7 succeed first start
- [ ] Zero P0 trust bugs open
- [ ] Focus lag closed or waived with data in [focus-timer-ui-lag.md](../qa/focus-timer-ui-lag.md)

---

## 6. Phase ADA-2 — Inclusivity hard bar (Weeks 11–14)

**Owner:** A11y lead + design
**Map every item to** [qa/10-accessibility-checklist.md](../qa/10-accessibility-checklist.md).

| # | Task | Standard |
|---|------|----------|
| 2.1 | VoiceOver: Briefing, Focus, Capture, Plan confirm | Full task complete without sight |
| 2.2 | Dynamic Type XXXL | No truncated primary CTA; reflow not clip |
| 2.3 | Reduce Motion | No essential info only in motion; Start Pulse alternative |
| 2.4 | Color contrast | WCAG AA on hero, buttons, charts that matter |
| 2.5 | Voice Control / Switch | Primary actions named and hittable |
| 2.6 | Cognitive load pass | One decision per screen in core loop |
| 2.7 | Tone audit | External ADHD-informed reviewer (paid) |
| 2.8 | Medical boundary | Not a diagnostic/treatment; copy legal-safe |
| 2.9 | RTL / locale smoke | At least one second language layout smoke |
| 2.10 | Accessibility Nutrition Labels honesty | App Store a11y features match reality |

**Exit criteria**

- [ ] External a11y audit: no Critical
- [ ] Inclusivity one-pager for Apple story (PDF)
- [ ] Screen recordings of VO session published internally

---

## 7. Phase ADA-3 — Performance & reliability (Weeks 15–18)

**Owner:** Eng
**Use:** [PERFORMANCE-DEEP-ANALYSIS.md](../qa/PERFORMANCE-DEEP-ANALYSIS.md), [09-performance-benchmarks.md](../qa/09-performance-benchmarks.md).

| # | Task | Gate |
|---|------|------|
| 3.1 | Device farm: cold launch → hero tappable | Target in QA-09 |
| 3.2 | Focus open device CI manual lane | Documented pass |
| 3.3 | 300-task stress | Mutate &lt; 50ms local (upsert path) |
| 3.4 | Crash-free | ≥ 99.5% sessions 14-day window |
| 3.5 | AI offline | Deterministic brain usable without network |
| 3.6 | Proxy-only prod AI | No key exfil path |
| 3.7 | Outbox | Airplane → online never loses capture/task |
| 3.8 | Factory reset | Privacy complete (prior privacy bugs verified) |
| 3.9 | Battery / thermal | 25m focus + LA acceptable |
| 3.10 | Privacy nutrition | Accurate; Health/Microphone usage strings excellent |

**Exit criteria**

- [ ] Production-readiness [14](../qa/14-production-readiness.md) Checklist green for ADA surfaces
- [ ] No open Critical brain bugs ([brain-bugs.md](../qa/brain-bugs.md))

---

## 8. Phase ADA-4 — Visual identity & packaging (Weeks 19–20)

**Owner:** Brand / motion design

| # | Task | Done when |
|---|------|-----------|
| 4.1 | Signature palette + type lockup | Not "generic premium dark" only |
| 4.2 | Custom icon | Reads at 29pt; storyboards with Start Pulse |
| 4.3 | Empty/hero illustrations | 5–7 consistent marks |
| 4.4 | Motion language sheet | Spring constants, durations, RM equivalents |
| 4.5 | App Preview 30s | Follows 3-beat story; no feature tour |
| 4.6 | Screenshots 6.7" | 5–6 frames, caption literacy |
| 4.7 | Subtitle + promo text | Inclusivity keywords truthful |
| 4.8 | Privacy / Support URLs | Working, human |
| 4.9 | Remove mixed brand residue in user-visible UI | Look After everywhere |

**Exit criteria**

- [ ] Design review with external product designer
- [ ] Trailer + screenshots AA-ready

---

## 9. Phase ADA-5 — External proof (Weeks 21–22)

Awards follow **evidence**, not decks.

| # | Task | Artifact |
|---|------|----------|
| 5.1 | Closed beta 50+ ADHD / friends users | Feedback synthesis |
| 5.2 | 5 written case stories (permissioned) | PDF quotes |
| 5.3 | Independent review outreach | 3 published pieces target |
| 5.4 | Accessibility community demo | Public writeup |
| 5.5 | App Store featuring pitch | Editorial notes + preview |
| 5.6 | Metrics board | D1/D7 start rate, focus completes, defer→recover |
| 5.7 | Trust incidents log | Zero unaddressed P0 |

**Exit criteria**

- [ ] Public App Store version live ≥ 30 days before any "push"
- [ ] NPS or qualitative warmth from target users documented

---

## 10. Phase ADA-6 — Freeze & sustain (Weeks 23–24+)

| # | Task |
|---|------|
| 6.1 | Feature freeze on core loop |
| 6.2 | Only trust/a11y/crash fixes |
| 6.3 | Weekly "stranger test" (1 person, filmed) |
| 6.4 | Maintain featuring hygiene (ratings response, crashes) |
| 6.5 | Archive award submission materials (story, VO film, before/after) |

Apple does not publish a public entry form for ADA like a hackathon; **presence is earned via the public product + editorial**. Your job is to be unignorable.

---

## 11. ADA readiness scorecard (track weekly)

Score each 0–2 (0 = fail, 1 = partial, 2 = award-grade). **Max 40. Ship bar ≥ 28. Campaign bar ≥ 34.**

| # | Criterion | Score |
|---|-----------|------:|
| 1 | One-sentence clarity to a stranger | |
| 2 | First 90s → meaningful start | |
| 3 | Hero trust (no stale/wrong Peak) | |
| 4 | Focus Start Pulse feel | |
| 5 | Defer without shame | |
| 6 | Capture delight + offline loss | |
| 7 | Live Activity / widget coherence | |
| 8 | Motion + Reduce Motion pair | |
| 9 | VoiceOver core path | |
| 10 | Dynamic Type core path | |
| 11 | Visual uniqueness (icon + 3 screens) | |
| 12 | App Preview emotional hit | |
| 13 | Copy humanity | |
| 14 | Offline / failure dignity | |
| 15 | Privacy & reset integrity | |
| 16 | Crash/perf bar | |
| 17 | Inclusivity evidence (audit/users) | |
| 18 | Real-user stories | |
| 19 | App Store packaging | |
| 20 | Differentiation vs todo/AI wrappers | |
| | **Total** | **/40** |

---

## 12. Engineering backlog mapped to award (priority order)

Do **in this order** when eng capacity is limited:

| P | Work | Award lever |
|---|------|-------------|
| P0 | Device-verify focus UI lag; close BUG-007 | Interaction |
| P0 | Trust gates: capacity Peak, planning confirm, stale hero regressions | Inclusivity / Trust |
| P0 | A11y critical path VO + RM + XXXL | Inclusivity |
| P1 | First-run IA cut + single CTA briefing | Story |
| P1 | Signature motion + icon | Visuals support |
| P1 | Offline capture/task dignity already engineered — **expose polish** | Reliability |
| P2 | Proxy-only + privacy nutrition | Trust |
| P2 | Entitlements brand cleanup (user-visible only) | Polish |
| P3 | Architecture Session/outbox (flags) | Stability underpinning — not user-facing story |

Architecture plan Phases 6–8 platform tasks **do not block** ADA-1 craft unless they fix a user-visible scar.

---

## 13. RACI (lightweight)

| Area | Accountable | Responsible |
|------|-------------|-------------|
| Narrative / cut | PM | Design |
| Core loop UX | Design | iOS eng |
| A11y | Design | Eng + external auditor |
| Perf device bar | Eng lead | iOS eng |
| Brand / trailer | Design | Motion / editor |
| User proof | PM | Community / research |
| Store featuring | PM | Marketing |

---

## 14. Risk register (award-specific)

| Risk | Mitigation |
|------|------------|
| Scope creep ("also macros…") | ADA-0 non-goals; weekly cut review |
| AI embarrassment | Confirm-only plans; deterministic fallback; sleep gates |
| Looks like every dark productivity app | Phase ADA-4 art direction budget non-negotiable |
| A11y theater | External audit paid |
| Chasing award instead of users | Ship public; stories over trophies |
| Team burnout | 24w intensity then sustain mode |

---

## 15. Milestone calendar (example)

| Week | Milestone |
|-----:|-----------|
| 4 | Narrative + cut signed; scorecard baseline |
| 10 | Core loop stranger-test pass |
| 14 | A11y audit clear |
| 18 | Perf/reliability bar green |
| 20 | Packaging + trailer locked |
| 22 | Public proof pack |
| 24 | Freeze; live excellence |

Adjust start date when you begin ADA-0; keep duration.

---

## 16. Definition of "ready to be seen by Apple"

All must be true:

1. Public App Store app, stable ≥ 30 days
2. Scorecard ≥ 34/40
3. External a11y + ADHD-informed tone review
4. Focus + hero trust verified on **device**
5. App Preview that makes a non-user feel the relief
6. Real stories with permission
7. Zero open Critical trust/brain bugs
8. Privacy & medical positioning clean

Even then: **winning remains uncertain**. You will have built something that deserves featuring and lasting users—which is the actual prize.

---

## 17. First 7 days (start Monday)

| Day | Action |
|-----|--------|
| 1 | Write one-liner + 3-beat story; team read-aloud |
| 2 | Film baseline 30s of current first run |
| 3 | Draft week-1 IA cut list in Figma/notes |
| 4 | Score §11 scorecard honestly (expect low) |
| 5 | File eng tickets for P0 only (focus lag, a11y smoke, hero trust) |
| 6 | Book external ADHD reviewer + a11y auditor dates |
| 7 | Approve trailer script v1; freeze new feature requests |

---

## 18. Change log

| Date | Change |
|------|--------|
| 2026-08-10 | Initial ADA roadmap — Inclusivity-first, 24-week craft program |

---

*"Win the day for one overwhelmed human, repeatedly. Let Apple notice if they will."*
