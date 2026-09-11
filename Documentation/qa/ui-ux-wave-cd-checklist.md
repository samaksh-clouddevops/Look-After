# Wave C–D — Dynamic Type XXXL & Reduce Motion checklist

**Date:** 10 Sep 2026  
**Plan:** [ui-ux-fix-plan-2026-09-10.md](ui-ux-fix-plan-2026-09-10.md)  
**Related:** [10-accessibility-checklist.md](10-accessibility-checklist.md), [ui-ux-polish-wave-notes.md](ui-ux-polish-wave-notes.md)  
**Mode:** Manual (device or Simulator). No code changes required to run this list.

**Wave D decisions (do not contradict while verifying):**
- Nav: 5 labeled tabs + quiet Capture FAB
- Serif: Briefing greeting name only
- Brain orb: hero; primary = Decide for me (orb tap = same)

---

## How to run

1. Build Look After Debug to a phone or Simulator (iOS 26 target).
2. **Dynamic Type:** Settings → Accessibility → Display & Text Size → Larger Text → drag to **XXXL** (or Accessibility sizes → XXXL). Relaunch app if needed.
3. **Reduce Motion:** Settings → Accessibility → Motion → **Reduce Motion** On. Retest the same screens.
4. Optional: also spot-check **Increase Contrast** if a finding looks contrast-related.
5. After Waves A–B land, recapture with `./Scripts/capture-ux-review.sh` and archive shots that prove XXXL / reduced-motion behavior.

Mark each row **Pass** when criteria hold; note failures with screen ID + one-line symptom.

---

## Dynamic Type — XXXL

| Screen | Focus | Pass criteria | Pass |
|--------|--------|---------------|------|
| **Briefing** | Greeting + hero | Greeting name (serif) readable; hero bullets wrap without clipping; Customize / Settings targets ≥44pt; scroll cue not covering rows | ☐ |
| **Briefing** | Glance / Continue | Glance labels wrap; Continue / primary CTA not truncated; content clears bottom nav | ☐ |
| **Today** | Header + first fold | Title/toolbar icons usable; Top Priorities titles wrap; chips/menus not overlapping; no covered CTAs under tab bar | ☐ |
| **Today** | Rows / banners | Micro-start / schedule banner text wraps; priority rows readable; secondary actions remain tappable | ☐ |
| **Capture** | Composer | Placeholder + Speak / Auto / Save labels readable; chips scroll/peek without clipping; dismiss control reachable | ☐ |
| **Tasks** | Header + list | “Tasks” title single-line or scales; filters/menus usable; row title + metadata no overlap with checkbox/actions | ☐ |
| **You** | Hub | Section headers visible; progress/metrics readable; Routines (and last content) clear tab bar inset | ☐ |
| **Brain** | Orb + CTAs | Under-orb copy wraps (≤4 lines ok); **Decide for me** primary readable; Ask Brain / More still findable; orb not clipping chrome | ☐ |
| **Chrome** | Bottom nav | All 5 tab labels readable (may truncate gracefully); Capture FAB still ≥44pt hit target and not looking “selected” | ☐ |

---

## Reduce Motion

With **Reduce Motion** On, confirm no essential information is motion-only and decorative motion is off or replaced with fades/static states.

| Screen | Focus | Pass criteria | Pass |
|--------|--------|---------------|------|
| **Briefing** | Enter / scroll | No reliance on bounce or parallax to notice content below fold; scroll cue still understandable if shown | ☐ |
| **Today** | Transitions | Sheet/toolbar Plan open-close without jarring bounce; list updates readable without animation | ☐ |
| **Capture** | Morph / present | Capture open/close and any morph use reduced or static transition; composer usable immediately | ☐ |
| **Tasks** | List chrome | Filter/header changes don’t depend on motion; rows remain clear | ☐ |
| **You** | Hub | Progress / appearance controls understandable without animated flourish | ☐ |
| **Brain** | Orb | Orb idle/thinking does not require continuous motion to convey state (ProgressView / static state ok); Decide for me still obvious | ☐ |
| **Chrome** | Tab bar | Tab selection / Capture FAB without bounce or spring that implies wrong selected state | ☐ |

---

## Sign-off

| Check | Done |
|-------|------|
| XXXL pass on Briefing, Today, Capture, Tasks, You, Brain | ☐ |
| Reduce Motion pass on same six + chrome | ☐ |
| Failures filed or linked to audit IDs (S02 / S05 / S14 / S19 / S39 / S42 / S04) | ☐ |
| Notes updated in [ui-ux-polish-wave-notes.md](ui-ux-polish-wave-notes.md) after verification | ☐ |
| Recapture archived (if feature waves complete) | ☐ |

**Verifier:** _________________ **Date:** _________________
