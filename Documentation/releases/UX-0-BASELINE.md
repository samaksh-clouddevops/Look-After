# UX-0 Baseline Pack

**Document ID:** UX-0-BASELINE  
**Date:** 2026-08-10  
**Branch:** `feature/arch-infra-implementation`  
**Parent plan:** [UX-EXCELLENCE-ROADMAP.md](./UX-EXCELLENCE-ROADMAP.md)  
**Method:** Static product/heuristic pass on code + flows (device film still required — see §6)

---

## 0.1 North-star (locked for UX program)

> **The next right 10 minutes, without friction or shame.**

If a screen does not get the user closer to a calm start, it is secondary.

---

## 0.2 First-run map (as built today)

### Onboarding — `OnboardingView` / `StartStep`

| # | Step | Title (UI) | Friction note |
|---|------|------------|---------------|
| 0 | welcome | Welcome to Look After | Good entry; checklist promises ~3 min — **11 steps after welcome** stretches that |
| 1 | name | What should we call you? | Essential |
| 2 | gender | How do you identify? | Can be later; blocks flow |
| 3 | schedule | Your typical work day | Valuable but heavy |
| 4 | commitments | Fixed commitments | Valuable; optional pass OK |
| 5 | profile | Teach your brain your rhythms | **Jargon + cognitive load** |
| 6 | health | Connect Apple Health | Optional — keep skip (exists) |
| 7 | cycle | Your cycle | Conditional; keep skip |
| 8 | notifications | Gentle reminders | Optional — keep skip (exists) |
| 9 | ready | You're all set | Then still builds tasks |
| 10 | taskReview | Review your day | Extra wall before hero |

**Count:** 11 cases after welcome → **high** for ADHD first session.  
**UX-1/4 target:** essential path = welcome → name → (optional schedule) → ready → **hero** (≤3–4 steps).

### Post-onboarding

- Feature tour (`AppFeatureTourCoordinator`) can still fire (~700ms delay) — risk of **second tutorial** after long onboarding.
- Health may start background connect — good if non-blocking; bad if it steals focus with sheets.

### Home / hero

- Canvas: `LookAfterRootCanvas` + `CalmHeroSurface` / briefing hero.
- CTA path improved: vague **Continue** → **Start now** (code already landing).
- Briefing tab also loads **many chapters** (tasks & numbers, health, schedule, recommendations) — scroll tax before trust.

---

## 0.3 Heuristic friction inventory (P0–P2)

### P0 — Breaks “top notch” feeling

| ID | Surface | Issue | Evidence / files | Fix phase |
|----|---------|--------|------------------|-----------|
| **F-001** | Focus | Start may feel laggy vs timer truth | `focus-timer-ui-lag.md`, ADHD VM, Live Activity | UX-2 |
| **F-002** | Hero | Stale / wrong next task after complete | Historical R-001; FlowDirector serialization fixed — **device regression still required** | UX-1 |
| **F-003** | Hero/Trust | Peak / deep work when capacity poor | Capacity gates + BrainFacade recovery — **verify UI treatment** | UX-1 |
| **F-004** | Onboarding | Too many steps before value | 11 `StartStep`s | UX-4 |
| **F-005** | A11y | Core path VO / XXXL / RM not certified | Checklist exists; needs pass | UX-5 |
| **F-006** | Capture | Offline success may be invisible | Queue fixed eng-side; need “Saved on device” UI | UX-3 |

### P1 — Daily friction

| ID | Surface | Issue | Fix phase |
|----|---------|--------|-----------|
| **F-010** | Briefing | Heavy multi-chapter scroll competes with hero | UX-1 |
| **F-011** | Tour | Second teach layer after onboarding | UX-4 |
| **F-012** | Copy | System words in user chrome (“teach your brain”, AI-heavy subtitles) | UX-1 |
| **F-013** | Hero loading | Bootstrapping / decide-for-me overlays — ensure skeleton not blank | UX-1 |
| **F-014** | Primary buttons | Mixed Continue/Next/Start vocabulary | UX-1 (partially fixed) |
| **F-015** | Notifications | Risk of non-actionable pings | UX-3 |
| **F-016** | Settings IA | Power-user density | Later |

### P2 — Polish

| ID | Issue | Fix phase |
|----|--------|-----------|
| **F-020** | Brand dual IDs invisible but feel unfinished if leaks to UI | Polish |
| **F-021** | Weather stub if over-weighted in copy | Trust |
| **F-022** | Feature tour anchors / scroll await complexity | UX-4 |
| **F-023** | Analytics/trends cards early | Bury week 1 |

---

## 0.4 Primary button / CTA vocabulary (inventory)

| Current (examples) | Verdict | Prefer |
|--------------------|---------|--------|
| Continue | Weak | Start now / Save / Connect / Skip for now |
| Next | Weak | Specific verb |
| Get started | OK on welcome | Keep |
| Skip for now | Good | Keep |
| Start planning | OK if true | Or “See my day” |
| Looks good | OK on review | Keep |
| Start · {duration} | Good | Keep / standardize |
| Start now | Good | Default primary |

**Rule:** Primary label = **verb + object/outcome**. Never “Continue” unless continuing a named draft.

---

## 0.5 Week-1 information architecture (cut list)

### Always visible (week 1)

- Home hero (Now)  
- Start / Focus  
- Capture  
- Today (simple list)  
- Settings (profile, health, notifications only up top)

### Bury under More / later

- Full life modules at equal weight (travel, creative, dense analytics)  
- Long feature tour  
- Weekly trends / advanced brain  
- Multi-chapter briefing fold (collapse below hero)

### Explicit non-goals for UX excellence bar

- macOS parity  
- Every module perfect  
- Award trailer (until scorecard ≥ 34)  
- New architecture flags on by default  

---

## 0.6 Baseline film protocol (you must shoot — device)

**Cannot automate on this agent.** Do on a physical iPhone:

| Shot | Script | Max length |
|------|--------|------------|
| A | Fresh install → end of onboarding → first hero | 3 min |
| B | Cold open (returning) → tap primary → focus chrome | 30 s |
| C | Complete task → confirm hero changes | 30 s |
| D | Airplane mode capture → back online | 45 s |
| E | Settings → Large Text + VO swipe hero | 60 s |

**Store:** `Documentation/releases/baseline-films/` (git-ignore large binaries; keep a checklist note).

### Latency finger-feel (note during film B)

| Action | Feel target | Note (fill) |
|--------|-------------|-------------|
| Tap Start → UI commits | Instant | |
| Focus chrome visible | &lt; 100ms feel | |
| First tick trustworthy | Immediate | |

---

## 0.7 UX scorecard baseline (static estimate)

Score 0–2. **Pre-device estimates** — replace after film day.

| # | Criterion | Est. | Why |
|---|-----------|-----:|-----|
| 1 | Time-to-hero understanding | 1 | Hero exists; onboarding long |
| 2 | CTA clarity | 1→2 | Start-now fix helps |
| 3 | Start speed feel | 0–1 | Device lag open |
| 4 | Clock honesty | 1 | Needs device |
| 5 | Empty states | 1 | Partial |
| 6 | Error recovery | 1 | Mixed |
| 7 | Offline dignity | 1 | Eng OK, UI weak |
| 8 | Defer kindness | 1 | Logic exists |
| 9 | Capture speed | 1 | Path OK |
| 10 | Motion calm | 1 | RM partial |
| 11 | VoiceOver core | 0–1 | Unverified |
| 12 | Large text core | 1 | Hero improved |
| 13 | Copy warmth | 1 | Some jargon |
| 14 | Visual hierarchy | 1 | Briefing heavy |
| 15 | Notifications | 1 | Unknown quality |
| 16 | Widget/LA | 1 | Verify |
| 17 | Onboarding lightness | 0 | Too many steps |
| 18 | Settings findability | 1 | Dense |
| 19 | AI trust | 1 | Confirm paths |
| 20 | Use tomorrow | 1 | Potential high |
| | **Total est.** | **~18–22 / 40** | **Below “good daily” (28)** |

---

## 0.8 UX-0 exit checklist

- [x] North star written  
- [x] Onboarding step map  
- [x] Friction inventory P0–P2  
- [x] CTA vocabulary rules  
- [x] Week-1 cut list  
- [x] Baseline scorecard (static)  
- [ ] **Device films A–E** (owner: you / QA)  
- [ ] Scorecard updated from film  
- [ ] P0 tickets filed in tracker (optional; list above is source of truth)  

**UX-0 status:** *Static baseline complete → device film day closes UX-0.*

---

## 0.9 Immediate next (start UX-1)

Ordered build work:

1. **Hero fold** — reduce Briefing chrome; keep one CTA  
2. **Loading/empty/error** hero states  
3. **Onboarding slim** design (implement in UX-4; design now)  
4. **Focus lag** device proof (UX-2 parallel)  
5. **Capture offline** banner  

---

## Change log

| Date | Change |
|------|--------|
| 2026-08-10 | UX-0 static baseline pack |
