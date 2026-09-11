# UX agent screenshot pipeline

**Goal:** Run UI tests → save PNGs at each product step → Cursor + `ui-ux-pro-max` review without manual grabs.

## Quick start (full functionality flow — default)

```bash
cd Look-After
./Scripts/capture-ux-review.sh
```

This walks **F01–F19** (Briefing → Today → Plan → Tasks → Capture → Brain → You → Settings) and writes one PNG per step.

Outputs:

| Path | Purpose |
|------|---------|
| `screenshots/ux-agent/latest/*.png` | Newest set (agent default) |
| `screenshots/ux-agent/latest/MANIFEST.md` | Step ID, file, reached?, notes |
| `screenshots/ux-agent/<timestamp>/` | Archived run |

Shot list + agent prompt: [ux-agent-full-flow-shot-list.md](./ux-agent-full-flow-shot-list.md)

**Harness note (2026-09-10):** Flow steps must not call `dismissBlockingOverlays` inside a generic `wait` after opening Capture — that closed the sheet before F13. Reached detection uses accessibility ids **or** visible labels.

Then in Cursor:

> Review `Look-After/screenshots/ux-agent/latest` with ui-ux-pro-max. Walk F01→F19 in order as one journey.

## Modes

| Env | Test |
|-----|------|
| `LOOKAFTER_UX_CAPTURE_MODE=flow` (default) | `testExportFullFunctionalityFlowForUXAgent` |
| `LOOKAFTER_UX_CAPTURE_MODE=core` | Legacy destination set S02/S05/S19/… |

```bash
LOOKAFTER_UX_CAPTURE_MODE=core ./Scripts/capture-ux-review.sh
```

## What exists

- `UXFlowCapture` — sequential F## journey steps  
- `UXReviewCapture` — PNG + MANIFEST writer; also lists legacy `coreScreens`  
- `ScreenNavigator` — S01–S47 navigation catalog  
- `UXAgentCaptureUITests` — flow + core exporters  
- `FlowTestBase.captureScreenshot` — ad-hoc evidence under `Documentation/qa/.engine/screenshots/`

## Full static catalog export (optional)

```bash
LOOKAFTER_EXPORT_UX_REVIEW=1 xcodebuild \
  -scheme LookAfter-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:LookAfterSnapshotTests/ScreenSnapshotTests/testAllDocumentedScreens \
  test
```

## Agent workflow

1. `./Scripts/capture-ux-review.sh`  
2. Confirm `MANIFEST.md` — prefer `reached: yes` for F01, F05, F11, F13–F14, F16, F19  
3. Ask the agent to read PNGs in **flow order** + apply ui-ux-pro-max  
4. Fix → re-run → compare `latest/` vs previous timestamp folder  

## Limits

- Simulator glass ≠ App Store truth (see [ios26-screenshot-shot-list.md](../releases/ios26-screenshot-shot-list.md))  
- Soft-fail still saves a screenshot when a deep step is missing  
- Do not commit PII; UITest seed uses `uitest@lookafter.test`  
- Do not claim UX score uplift on pre-fix timestamp folders  
