# Adaptive Guided Tour V2

Layout-aware first-launch / feature tour. The explanation card is never placed with hardcoded coordinates; a pure placement engine chooses a collision-free position on every layout pass.

## Architecture

```
Anchors (views)
    │ preference: global frame + cornerRadius
    ▼
AppFeatureTourCoordinator  ──► TourPlacementEngine (LookAfterCore)
    │ layout metrics: safe area, keyboard, tab bar, card size
    ▼
AppFeatureTourOverlay
    ├── Spotlight cutout (matches target corner radius)
    ├── Explanation card (measured, Dynamic Type aware)
    └── Arrow (points at closest edge of highlight)
```

### Core (`Packages/LookAfterCore/.../Tour/`)

| Type | Role |
|------|------|
| `TourLayoutMetrics` | Screen, safe area, keyboard, nav/tab/sheet obstacles, card size |
| `TourPlacementEngine` | Candidate generation (above/below/left/right/center/floating), collision scoring, scroll suggestions |
| `TourLayoutProposal` | Final card frame, side, arrow edge/tip, `needsScroll` |

### App layer (`Apps/LookAfter-iOS/Views/Tour/`)

| Type | Role |
|------|------|
| `AppFeatureTourAnchor` | View modifier + preference key registry |
| `AppFeatureTourCoordinator` | Steps, persistence/restore, keyboard, scroll requests, layout recompute |
| `AppFeatureTourOverlay` | Spotlight, adaptive card position, a11y focus, Reduce Motion |
| `AppFeatureTourModels` | Steps (short copy), preferred sides (soft), store keys |

Anchors include `todayAssistant` on the collapsed **Plan With Me** bar (`ExecutiveAssistantSheet`), separate from `todayTimeline`.

## Positioning rules

1. Expand highlight by padding; never let card intersect that rect (+ gap).
2. Prefer sides from the step’s `preferredSides`, then the remaining sides.
3. Clamp into **usable bounds** = screen − safe area − keyboard − tab bar − bottom sheet.
4. If no collision-free fit → floating fallback + optional auto-scroll request.
5. Orientation / Dynamic Type / keyboard changes → recompute (no cached coords).

## Auto-scroll

Coordinator posts `.tourScrollToAnchor` with anchor id. Screens that own a `ScrollViewReader` (Briefing, Today) scroll the matching `.id` to center, then layout remeasures.

## Persistence

- `lookafter.hasCompletedFeatureTour` — completed
- `lookafter.featureTour.wasActive` + `stepIndex` — mid-tour restore after kill

## UITest

```
-UITesting -ShowFeatureTour -SkipLiveActivity
```

Accessibility ids: `screen-feature-tour`, `tour-next`, `tour-back`, `tour-skip`, `tour-finish`.

## Unit tests

`TourPlacementEngineTests` in LookAfterCore — below/above placement, no-overlap suite, keyboard, SE, landscape, scroll request.

## Validation matrix (manual / CI)

- iPhone SE, standard, Pro Max — portrait + landscape
- Dynamic Type: large → accessibility XXXL
- Keyboard shown during a step
- VoiceOver: focus lands on tour card each step
- Reduce Motion: opacity-only transitions
