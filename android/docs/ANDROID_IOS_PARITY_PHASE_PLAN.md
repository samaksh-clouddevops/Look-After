# Android ↔ iOS Parity — Next Phase Plan

**Baseline:** `feature/android-implementation` @ `4b74361`  
**Goal:** Close the remaining gap so Android is a true peer of the iOS product shell (not feature-identical overnight, but same jobs-to-be-done).

## Current state (short)

| Layer | ~Parity |
|-------|--------|
| LifeEngine / shell IA / DS V4 | High |
| Daily path (Today, capture/edit, meds, focus) | Medium |
| AI / planning / coach | Medium-Low |
| ADHD companion / WebRTC | Low–Medium |
| Health / insights depth | Low–Medium |
| Secondary modules (Travel, Cycle, Learning…) | Near zero |

**Honest overall:** ~40–55% of iOS surface.

---

## Strategy

1. **Depth before breadth** for the daily loop (Brain, Timeline, Health).  
2. **Port modules in user-value order**, not alphabetical.  
3. Every slice: **core pure logic → ViewModel → Compose → unit tests → CI green**.  
4. Keep **local-first**; cloud remains optional.

---

## Phase A — Daily loop excellence (2–3 weeks)

**Outcome:** Android daily use feels as intentional as iOS Today + Brain + Briefing.

| # | Workstream | Deliverables | Exit criteria |
|---|------------|--------------|---------------|
| A1 | Timeline / Tasks depth | Areas/tags filters, smart sections (Anchored / Flexible / Fluid), richer recurrence UI, swipe complete/park | Parity checklist vs iOS Timeline |
| A2 | Briefing narrative | Morning script from WorldState + health + meds + calendar; “start focus” CTA | Golden briefing snapshot tests |
| A3 | ExecutiveCapacity v1 | Energy budget model in core; Brain + Briefing consume it | Unit tests for capacity bands |
| A4 | Notifications policy UX | Settings screen for meds/anchored/briefing toggles + quiet hours | Policy tests + toggle persistence |
| A5 | Empty/error/haptics pass | Shared empty states on Inbox/Meds/Health; light haptics on complete | Visual QA checklist |

**Gate:** Internal dogfood for 1 week without iOS for core day.

---

## Phase B — AI & Planning peer (2–3 weeks)

**Outcome:** Planning conversation quality approaches iOS Planning module.

| # | Workstream | Deliverables | Exit criteria |
|---|------------|--------------|---------------|
| B1 | Planning VM parity | Multi-turn goals, day horizon picker, mutation diff UI before accept | Compose tests for accept/reject |
| B2 | WorldState expansion | Calendar density, travel flags hooks, capacity, med risk | Cross-platform field map doc |
| B3 | Streaming plan JSON | Stream tokens → partial parse → final PlanProposal | Fail-soft to offline plan |
| B4 | Coach surfaces | Dedicated Coach history, pinned decisions, “why this hero” | Coach transcript persisted |
| B5 | Context pack | Prompt builders shared shape with iOS LookAfterAI | Snapshot golden prompts |

**Gate:** Same 5 scripted planning prompts produce usable plans on both platforms.

---

## Phase C — ADHD Companion product (2 weeks)

**Outcome:** Body double is a real session product, not a demo.

| # | Workstream | Deliverables | Exit criteria |
|---|------------|--------------|---------------|
| C1 | Native WebRTC AAR | Integrate Stream/Google WebRTC; real PeerConnection | 2-device call on Wi‑Fi |
| C2 | Signaling | Firebase RTDB/Firestore rooms or self-hosted signal | Join by code works cross-device |
| C3 | Session UX | Lobby, reconnect, mute cam/mic, end summary | Matches iOS Companion happy path |
| DND + focus link | Auto focus session when room connects | Engine tests |

**Gate:** Two Android devices (or Android↔iOS later) hold a 10‑min body-double session.

---

## Phase D — Health + Insights depth (1.5–2 weeks)

| # | Workstream | Deliverables | Exit criteria |
|---|------------|--------------|---------------|
| D1 | Health history | Multi-day sleep/readiness series | Charts on Health screen |
| D2 | Insights/Performance | Streaks, weekly review depth, tag heat | Align metrics with iOS names |
| D3 | Med ↔ briefing | Due meds in Briefing hero path | Integration test |

**Gate:** Health + Insights usable without opening iOS.

---

## Phase E — Secondary iOS modules (3–5 weeks, parallelizable)

Port in this order (value × dependency):

1. **Home / Modules grid** — launcher for features (unblocks discovery)  
2. **Companion** polish (feeds C)  
3. **Travel** — trips, timezone day packing  
4. **Cycle** — cycle-aware capacity (feeds ExecutiveCapacity)  
5. **Learning** — light spaced practice loops  
6. **Creativity** — capture boards  
7. **Behavior** — habit loops tied to LifeEngine  
8. **Life** hub — goals / areas overview  
9. **Tour** — post-onboarding coach marks  

Each module: `lookafter-core` models → intents → UI under `ui/<module>` → You/Modules entry.

**Gate:** Modules grid lists all shipped modules; each has empty state + primary action.

---

## Phase F — Account, sync, ship (ongoing / 2 weeks concentrated)

| # | Workstream | Deliverables |
|---|------------|--------------|
| F1 | Auth UX | Email + anonymous + sign-out clarity; account screen |
| F2 | Sync product | Conflict policy (LWW or field merge), last-sync UI, retry |
| F3 | Brand | 512 icon, feature PNG, 6–8 screenshots |
| F4 | Pages | Enable GitHub Pages Actions on `main` |
| F5 | Play | Internal track AAB, content rating, data safety live |
| F6 | QA | Device matrix, accessibility pass, battery/DND OEM notes |

**Gate:** Internal testing track installable by non-dev testers.

---

## Suggested calendar (aggressive)

| Weeks | Phase |
|------|--------|
| 1–3 | **A** Daily loop |
| 3–5 | **B** AI/Planning (overlap late A) |
| 5–7 | **C** Companion WebRTC |
| 6–8 | **D** Health/Insights |
| 8–12 | **E** Modules (Home first, then Travel/Cycle) |
| 10–12 | **F** Ship concentration |

---

## Working agreements

- Branch: keep `feature/android-implementation` until Phase A gate, then cut `release/android-0.2`.  
- CI must stay green (unit + emulator smoke + release AAB).  
- No new module without: core tests + at least one UI entry + Design System V4 tokens.  
- Prefer pure Kotlin in `lookafter-core`; Android APIs only in `app`.  
- Document cross-platform field maps when adding LifeState keys.

---

## Immediate next slice (start Phase A)

**A1 + A3 kickoff (recommended first PR):**

1. Task sections on Today (Anchored / Flexible / Fluid / Done)  
2. Filter chips (priority / tag)  
3. `ExecutiveCapacity` pure model + wire into Briefing/Brain  
4. Unit tests + CI  

---

## What we will not chase in Phase A–B

- Mac companion  
- Pixel-perfect iOS animation clones  
- Full LLM feature parity without offline fallback  
- Every iOS module before daily loop is excellent
