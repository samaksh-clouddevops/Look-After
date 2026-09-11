# Fake-glass cleanup wave

Aligned with [ios26-chrome.md](../design/ios26-chrome.md): content stays opaque; chrome may use real Liquid Glass.

## Shipped

Replaced translucent / frosted **content** fills and decorative blur plates with `contentSurface*` / `border`:

| Area | Before | After |
|---|---|---|
| Insights chips / context block | `Color.white` / `black.opacity` fills | `contentSurfaceSubtle` / `contentSurfaceElevated` |
| Plan With Me chips / modality | `backgroundPrimary.opacity(0.5–0.7)` | opaque content surfaces |
| Voice capture transcript + waveform idle | white opacity | `contentSurfaceElevated` / `border` |
| Progress bar track | `white.opacity(0.1)` | `contentSurfaceElevated` |
| Immersive primary CTA | accent blur glow plate | solid accent button only |
| Life context / remember cards | `FallbackGradient.opacity` + white hairlines | opaque surfaces + `DesignSystem.border` / `divider` |
| Briefing / V4 section “highlight” stroke | white gradient hairline (fake glass rim) | `DesignSystem.border` |
| Premium sheet/alert overlays | white.opacity stroke | `border` |
| Daily Plan immersive timer | blur orb + white ring stroke | removed blur orb; `border` track |
| Energy / cycle ring tracks | white.opacity stroke | `border` |

## Intentionally kept

- **Real glass chrome** (tab bar, Capture, docks, `.glassEffect` / `.glassProminent`)
- **ADHD focus / reset breathe glows** (ambient motion, not content cards)
- **Privacy blur** on life-context photo previews
- **Sleep atmosphere** gradient (dark immersive mood, not frosted UI chrome)
- Deprecated `surfaceGlass` / `borderGlass` aliases (already map to opaque; no remaining call sites)

## Verify

- Briefing cards, Insights, Plan With Me, Capture voice sheet — no milky translucency over content
- Reduce Transparency still falls back to opaque chrome where already wired
- Focus session breathe glow still animates

## Out of scope

- macOS shell parity
- Full string catalog migration / further Dynamic Type layout reflow
