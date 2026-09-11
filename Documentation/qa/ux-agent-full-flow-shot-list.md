# UX agent — full functionality flow shot list

**Date:** 10 Sep 2026  
**Harness:** `UXFlowCapture.functionalityFlow` + `UXAgentCaptureUITests.testExportFullFunctionalityFlowForUXAgent`  
**Run:** `./Scripts/capture-ux-review.sh` (default mode = `flow`)  
**Output:** `screenshots/ux-agent/latest/` + stamped archive  

Pass this folder to the UI/UX agent **after** `MANIFEST.md` shows mostly `reached: yes`.

---

## Why flow (not only S## destinations)

Static tab shots miss hierarchy changes after an action (Start my day, Plan sheet, Capture Save enabled, timeline open).  
Each **F##** = one intentional step → settle → screenshot.

---

## Flow map

| ID | Step | What the agent should check |
|----|------|-----------------------------|
| F01 | Briefing first fold | Brand greeting, Start my day, Glance in fold, no dead void |
| F02 | Briefing scrolled | Chapters / health density, scroll continuity |
| F03 | Briefing customize | Filters sheet clarity vs Settings |
| F04 | Briefing after dismiss | No Auth leak; first fold restored |
| F05 | Today after Start my day | Hero = NOW; coach vs Start hierarchy |
| F06 | Today Schedule preview | 2-row preview, LATE/NOW truth |
| F07 | Full timeline | Rail density, drag affordance, dismiss |
| F08 | Today after timeline | First fold intact |
| F09 | Plan With Me | Approval card / conversation chrome |
| F10 | Today after Plan | No stuck sheet |
| F11 | All tasks | Real task list (not Today duplicate) |
| F12 | Today after tasks | Nav pop clean |
| F13 | Capture empty | Disabled Save visible (not inert hint only) |
| F14 | Capture Save ready | Enabled Save after type; chip contrast |
| F15 | Capture dismissed | Tabs usable |
| F16 | Brain | Orb + Decide for me affordance |
| F17 | You | Profile density |
| F18 | Settings | Settings stack reachable |
| F19 | Tab bar on Briefing | 4 tabs + Capture FAB flush |
| F01-dark | Briefing dark | Contrast pair |

---

## Agent prompt (copy)

> Review `Look-After/screenshots/ux-agent/latest` using the ui-ux-pro-max skill. Walk **F01→F19 in order** as one product journey. Check ADHD calm hierarchy (one primary CTA per fold), touch targets, contrast, and that MANIFEST `reached: yes` matches the PNG content. Do not score against older `20260910-092034` shots.

---

## Related

- Pipeline overview: [ux-agent-screenshot-pipeline.md](./ux-agent-screenshot-pipeline.md)  
- Screenshot UX fix plan (earlier S##): [ui-ux-screenshot-fix-plan-2026-09-10.md](./ui-ux-screenshot-fix-plan-2026-09-10.md)  
- **Flow fix plan (F01→F19 review):** [ui-ux-flow-fix-plan-2026-09-10.md](./ui-ux-flow-fix-plan-2026-09-10.md)  
- Legacy core destinations: `UXReviewCapture.coreScreens` (`LOOKAFTER_UX_CAPTURE_MODE=core`)
