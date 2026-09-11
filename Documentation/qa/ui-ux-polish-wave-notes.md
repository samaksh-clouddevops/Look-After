# UI/UX polish wave — 9 Sep 2026

Skill imported: `ui-ux-pro-max` → `~/.cursor/skills/ui-ux-pro-max`  
Design system draft: [design-system/look-after/MASTER.md](../design-system/look-after/MASTER.md)  
(Keep Look After’s existing lime tokens; do not adopt the skill’s teal/orange palette wholesale.)

## Fixed (user-reported)

1. **Oversized primary buttons** — Auth SSO/Sign In, `PremiumButtonMetrics`, `ImmersivePrimaryCTA`, briefing continue CTA, `TaskActionButton` now sit at ~44pt (HIG minimum) instead of 50–64pt towers.
2. **Bottom nav Capture** — icon-only lime circle (no truncated “Capture” label); no longer `.glassProminent` (looked permanently selected).
3. **Bottom nav dock** — plate uses `ignoresSafeArea(edges: .bottom)` so chrome fills the home-indicator gap.
4. **Scroll for more** — hides on first scroll (`onScrollGeometryChange` + preference) and when Continue is tapped.

## Fixed (screenshot review — 9 Sep evening)

5. **Briefing hero copy** — em-dash in task titles no longer becomes `Brush teeth. evening.`; list titles use `Brush teeth (evening)`; sleep/`Now` plan lines cleaned up.
6. **Plan With Me duplicate** — proactive seed no longer repeats the negotiation question in the chat bubble; emoji header → SF Symbol.
7. **Deferral copy** — `1 times` → `once`.
8. **Brain welcome** — skip auto-welcome during UITests; subtitle can wrap to 4 lines.
9. **Dark capture** — `-UIPreferredInterfaceStyle Dark` sets `AppAppearanceMode`; default UITests reset to system so light runs aren’t stuck dark.
10. **UX capture Auth** — UITest session seed survives Firebase nil-auth; Auth cover skipped under `-UITesting`.
11. **All Tasks title** — `lineLimit(1)` + scale so “Tasks” no longer wraps as `Task` / `s`.
12. **Capture pipeline order** — Capture before Task list so S04/S39 aren’t polluted by All Tasks.
13. **ui-ux-pro-max pass** — see [ui-ux-pro-max-audit-2026-09-09.md](ui-ux-pro-max-audit-2026-09-09.md): dark text contrast, glance truncation, scroll-hint clearance, Plan With Me density, Settings labels, Capture disabled copy, Decide/CTA contrast, schedule-check chips.

## Fixed (P0 deep inventory — 9 Sep night)

14. **Control matrix** — `LAToolbarIconButton` / `LAActionChipButton` / `LACaptureFAB` in LookAfterCore; applied on Briefing/Today/Tasks/You headers, schedule chips, bottom Capture.
15. **Bottom nav** — quieter outline Capture FAB (not permanently “selected”); dock flush; `dsTabLabel`.
16. **Today / Task headers** — equal icon toolbar (no mixed “All tasks” capsule); one primary `+` on Tasks.
17. **Brain orb** — rim / specular / glow / state color; thinking ProgressView.
18. **Scroll hint** — inline under glance (no floating pill over rows).
19. **Today assistant** — floating collapsed chip + `safeAreaInset` spacer so Top Priorities clear the chip.
20. **Glance trust** — flexible tasks no longer show `12:00 AM–10:30 PM` or crowd fixed glance; use `Flexible today · Nm`.
21. **Priority chips** — `LifeArea.shortLabel` (“Health” not “Health & Recovery”).

## Skill checklist — still open (next passes)

- Bottom nav still has 5 destinations + Capture (skill prefers ≤5 total); Review remains for tour/product.
- Larger-Text / XXXL reflow on dense rows (`@ScaledMetric` hit targets).
- Do-this-now / timeline “Start now” hierarchy audit across Today.
- macOS parity chrome.
- Persist page overrides under `design-system/look-after/pages/` when redesigning Briefing/Today/Auth.
- Task list header still dense (filter chips + dual menus) — P1 polish.
- Capture Speak/Save/chip language unification — P1.

## Wave A–D plan execution 10 Sep 2026

**Plan:** [ui-ux-fix-plan-2026-09-10.md](ui-ux-fix-plan-2026-09-10.md)  
**Path to 10 (next):** [ui-ux-path-to-10-plan-2026-09-10.md](ui-ux-path-to-10-plan-2026-09-10.md) — Waves E–H (Today Do-this-now → Briefing/nav → Brain/Capture → craft/a11y).  
**Status:** Path-to-10 Waves **E–H** implemented 10 Sep 2026. Build green. Recapture after E–H for visual proof. Prior baseline ~6.5/10.

### Path to 10 — Waves E–H (code landed)

**Plan:** [ui-ux-path-to-10-plan-2026-09-10.md](ui-ux-path-to-10-plan-2026-09-10.md)

| Wave | Landed |
|------|--------|
| **E** | `TodayCoachSlot` (overcommit → transition → micro-start → none); Do-this-now hero; Day menu for week/chips; Plan + Day + overflow header; “Up next” (2 rows); title layoutPriority |
| **F** | Briefing “Start my day” → Today; glance below fold; **4 tabs + Capture**; Review tile on You → sheet; tour retargeted |
| **G** | Brain Decide primary + Ask Brain text; Capture inbox demoted; metadata `time · Nm · priority`; Settings DEBUG already gated |
| **H** | Thicker Life State bars (12pt); Capture/Plan/Focus already Reduce Motion aware; XXXL checklist remains **manual device** pass |

### Wave A (verified in code)
1. **Today Replan** — no floating `safeAreaInset` Replan dock; header **Plan** (sparkles) → sheet; inline negotiation in scroll; micro-start ≤1 primary CTA + More.
2. **Capture FAB** — quiet outline FAB; `dsTabLabel` 11pt.
3. **Trust + Capture CTA** — micro-start duration via `TaskDurationPolicy` (no invented “2 minutes”); Top Priorities / All Tasks sort by next actionable then priority; Capture empty state is caption “Type or speak to save” (Save only when `canSave`); dismiss via toolbar `xmark`.

### Wave B (verified in code)
4. Settings “You & app” / Preferences; DEBUG-only destructive; You inset / Appearance / lime link.
5. Briefing shorter hero; glance tokens; Decide primary; orb = Decide voice; white-on-lime.
6. Tasks Add + overflow menu; stronger muted text tokens.

### Wave C–D docs
- Wave D product decisions in the fix plan (nav, serif, brain orb).
- Manual validation checklist: [ui-ux-wave-cd-checklist.md](ui-ux-wave-cd-checklist.md).

### Visual verify (recapture `screenshots/ux-agent/latest/`)
| Shot | Result |
|------|--------|
| S05 Today | **Pass** — no Replan dock; Plan sparkles in toolbar; schedule + transition use 1 primary + More; Top Priorities visible |
| S39 Capture | **Pass** — “Type or speak to save” caption (no fake Save); dismiss `xmark` |
| S04 Tab bar | **Pass** — quiet outline Capture FAB; Briefing serif name only |
| S21 Settings | **Pass** — “You & app” + Preferences |
| S19 Brain | **Pass** — Decide primary + orb = Decide path; spot-check Decide label contrast (lime vs white-on-lime) |
| S14 / S42 | Captured; no regression flagged in this pass |

**Still manual:** XXXL + Reduce Motion rows in [ui-ux-wave-cd-checklist.md](ui-ux-wave-cd-checklist.md) (H3 device sign-off). Empty/overcommit calm is enforced in `TodayCoachSlot` + empty Up next copy; archive scenario shots when available.

### Path-to-10 visual verify (recapture after E–H fixes)

| Shot | Result |
|------|--------|
| S05 | **Pass** — one Transition coach; DO THIS NOW hero; Up next; Plan/Day/…; 4-tab nav |
| S02 | **Pass** — Start my day; glance only peeks below fold |
| S04 | **Pass** — 4 tabs + quiet Capture (no Review) |
| S42 | **Pass** — Review under Life areas; thicker Life State bars |
| S19 | **Pass** — Decide primary; Ask Brain text |
| S39 | **Pass** — Type or speak caption; inbox in overflow |
| S14 | Captured with compact metadata |

**Still manual (H3):** XXXL + Reduce Motion device checklist. Empty/overcommit calm via `TodayCoachSlot` priority + empty Up next.
