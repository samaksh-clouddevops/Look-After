# UX Excellence Roadmap — Top-Notch User Experience

**Document ID:** UX-EXCELLENCE-001  
**Date:** 2026-08-10  
**Goal:** Make Look After feel calm, fast, and trustworthy every day — *before* award packaging.  
**North star:** *The next right 10 minutes, without friction or shame.*  
**Related:** [APPLE-DESIGN-AWARD-ROADMAP.md](./APPLE-DESIGN-AWARD-ROADMAP.md) · [qa/10-accessibility-checklist.md](../qa/10-accessibility-checklist.md) · [qa/focus-timer-ui-lag.md](../qa/focus-timer-ui-lag.md)

---

## Principle stack (non-negotiable)

| # | Principle | User feels… |
|---|-----------|-------------|
| 1 | **One decision** | Only one obvious next action on the hero |
| 2 | **Instant honesty** | Timer/UI never lie; poor sleep never sells Peak deep work |
| 3 | **Faster than doubt** | Start is felt in the same breath as the tap |
| 4 | **Forgiving** | Defer / miss / offline never shame or lose data |
| 5 | **Quiet power** | Depth exists; it never crowds the first screen |
| 6 | **Accessible by default** | VoiceOver, large text, Reduce Motion are first-class |
| 7 | **Human copy** | Short, concrete, warm — no system jargon |

---

## What “top notch” means (acceptance)

A stranger with ADHD can, unassisted:

1. Finish onboarding **or** skip to value in ≤ **3 minutes**  
2. See **one** clear next action in ≤ **10 seconds** after home loads  
3. Start focus and believe the clock within **1 second**  
4. Capture a thought in ≤ **2 taps**  
5. Defer without guilt and get a tiny recovery option  
6. Use Briefing → Focus with **VoiceOver** and **XXXL text**  
7. Lose network mid-capture and **not** lose the item  

Until all seven are true, we are not “UX complete.”

---

## Core journey map

```text
Install → Auth → Onboarding (minimal) → Home hero
    → Start now → Focus session → Complete / Defer
    → Capture anytime → Optional plan / health
```

**Excellence = polish every arrow, not every module.**

---

## Program phases (12 weeks to “excellent daily driver”)

### UX-0 · Baseline (Week 1)

| # | Work | Exit | Status |
|---|------|------|--------|
| 0.1 | Film first-run + morning open (silent, real device) | Baseline tape | **Protocol ready** — [baseline-films/](./baseline-films/README.md) |
| 0.2 | Heuristic pass on Briefing, Focus, Capture, Onboarding | Bug/UX list ranked P0–P2 | **Done** — [UX-0-BASELINE.md](./UX-0-BASELINE.md) |
| 0.3 | Copy inventory: every primary button label | Jargon killed | **Done** (CTA vocabulary §0.4) |
| 0.4 | Latency finger-feel: open, start, complete | Numbers noted | **Needs device film B** |

### UX-1 · Hero & home (Weeks 2–4) — *highest leverage*

| # | Work | Exit |
|---|------|------|
| 1.1 | Single primary CTA always (“Start · 25m”) | No competing equal buttons |
| 1.2 | Supporting line ≤ 3 lines; Dynamic Type safe | No truncate at XXXL |
| 1.3 | Empty / loading / error hero states designed | Never blank white anxiety |
| 1.4 | Post-complete hero refresh same session | No stale task |
| 1.5 | Poor-sleep / recovery visual + copy treatment | Distinct calm state |
| 1.6 | Secondary actions only under “Why this?” | Progressive disclosure held |
| 1.7 | Reduce briefing chrome above the fold | Fold = greeting + hero + CTA |

### UX-2 · Focus signature (Weeks 4–6)

| # | Work | Exit |
|---|------|------|
| 2.1 | Device fix Focus open lag (BUG-007) | QA-09 budgets green on device |
| 2.2 | Start Pulse (countdown → session) | Designed RM path |
| 2.3 | Pause / end / break copy + haptics pass | Consistent, calm |
| 2.4 | Live Activity = in-app truth | Spot-check 10 sessions |
| 2.5 | Interruption resume honest | No fake full restart |

### UX-3 · Capture & trust (Weeks 6–8)

| # | Work | Exit |
|---|------|------|
| 3.1 | Capture ≤ 2 taps from home | Timer measured |
| 3.2 | Offline banner + “saved on device” | User can see queue |
| 3.3 | Planning changes always confirm | Regression test green |
| 3.4 | Failure toasts with next step | Never dead-end error |

### UX-4 · First-run lightness (Weeks 7–9)

| # | Work | Exit |
|---|------|------|
| 4.1 | Onboarding trim: name + essential only; rest optional | ≤ 3 minutes happy path |
| 4.2 | Health/notifications as **boosts**, not walls | Skip always available |
| 4.3 | Feature tour ≤ 3 steps or kill | Anchored to Start |
| 4.4 | Post-onboarding lands on hero with a real task | Not empty settings |

### UX-5 · Inclusivity & calm polish (Weeks 9–11)

| # | Work | Exit |
|---|------|------|
| 5.1 | VoiceOver core path | Full start→complete |
| 5.2 | Dynamic Type XXXL | Hero + focus + capture |
| 5.3 | Reduce Motion audit | No info-only-in-motion |
| 5.4 | Contrast AA on primary surfaces | Spot-check |
| 5.5 | ADHD-informed tone review (external) | Notes acted on |

### UX-6 · Harden & measure (Weeks 11–12)

| # | Work | Exit |
|---|------|------|
| 6.1 | 8 moderated user tests | ≥ 7 complete first start |
| 6.2 | Crash-free + perf board | 14-day green |
| 6.3 | UX scorecard ≥ 32/40 (§ scorecard) | Ship “excellent” |

---

## UX scorecard (score 0–2 each, max 40)

| # | Criterion | Score |
|---|-----------|------:|
| 1 | Time-to-hero understanding | |
| 2 | CTA clarity | |
| 3 | Start speed feel | |
| 4 | Clock/UI honesty | |
| 5 | Empty states | |
| 6 | Error recovery | |
| 7 | Offline dignity | |
| 8 | Defer kindness | |
| 9 | Capture speed | |
| 10 | Motion calm | |
| 11 | VoiceOver core | |
| 12 | Large text core | |
| 13 | Copy warmth | |
| 14 | Visual hierarchy | |
| 15 | Notification usefulness | |
| 16 | Widget/LA coherence | |
| 17 | Onboarding lightness | |
| 18 | Settings findability | |
| 19 | Trust after AI suggestion | |
| 20 | Would use tomorrow morning | |
| | **Total** | **/40** |

- **Good daily app:** ≥ 28  
- **Top-notch:** ≥ 34  
- **Award-grade craft:** ≥ 36 (then see ADA roadmap)

---

## Eng ticket order (when building)

1. **P0** Focus device lag · stale hero · a11y blockers on hero/focus  
2. **P0** Capture offline visibility  
3. **P1** Hero CTA/copy/hierarchy (partially started: CalmHero + Start label)  
4. **P1** Onboarding trim  
5. **P1** Empty/loading/error system on briefing  
6. **P2** Tour reduction · notification copy · settings IA  

Architecture flags (session/outbox/etc.) support reliability; **do not block** UX-1/UX-2 unless user-visible.

---

## Already started (code)

| Change | Why |
|--------|-----|
| `CalmHeroSurface` — 3-line support, type scale, a11y | Readable hero under real conditions |
| Integrated hero CTA → **Start · {duration}** | Action language beats “Continue” |

---

## Weekly ritual

| When | What |
|------|------|
| Mon | Scorecard + film one cold open |
| Wed | Fix top 3 friction clips |
| Fri | One stranger test (15 min) |

---

## Definition of done (UX excellence)

- [ ] Seven acceptance bullets above all true  
- [ ] Scorecard ≥ 34  
- [ ] No open P0 UX/trust bugs on core loop  
- [ ] Device focus budgets green  
- [ ] External tone or a11y note addressed  

Then layer [APPLE-DESIGN-AWARD-ROADMAP.md](./APPLE-DESIGN-AWARD-ROADMAP.md) packaging — not before.

---

## Change log

| Date | Change |
|------|--------|
| 2026-08-10 | Initial UX excellence roadmap + first hero CTA/a11y pass |
