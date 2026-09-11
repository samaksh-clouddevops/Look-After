# iOS 26 chrome (Look After V5)

**Related:** [QA-IOS26-01](../qa/ios26-revamp-plan.md) Phase D · `DesignSystem.swift` · `LookAfterChrome`

## Two materials only

| Layer | Use | Tokens / APIs |
|---|---|---|
| **Chrome** | Tab bar, toolbars, Capture, floating docks, toasts, transient controls | `GlassEffectContainer`, `.glassEffect()`, `.buttonStyle(.glass)` / `.glassProminent`, tint via `LookAfterChrome.accentTint` |
| **Content** | Cards, lists, timeline rows, briefing sections, auth success card | Opaque `DesignSystem.contentSurface` / `contentSurfaceSubtle` / `contentSurfaceElevated` |

There is **no third material**. Do not invent translucent card fills (`backgroundSecondary.opacity(0.6)`, `surfaceGlass`, stacked `.ultraThinMaterial` under content).

Deprecated aliases (still compile, warn):

- `DesignSystem.surfaceGlass` → use `contentSurface`
- `DesignSystem.borderGlass` → use `border`

## Glass kind

| Kind | When |
|---|---|
| **`.regular`** | Default for tab bar plate, floating docks, assistant panel, toasts, toolbar clusters. |
| **`.clear`** | Media / photo overlays only. Always put `lookAfterClearGlassDimming()` (or an equivalent dim plate) underneath. |
| **No glass** | All content cards and ADHD emergency surfaces that need maximum contrast (prefer opaque elevated fills). |

## Accent

Green `5A9E3F` (`LookAfterChrome.accentTint` / `DesignSystem.accentPrimary`) is a **tint on glass-prominent buttons**, not a flood fill behind content.

```swift
Button("Capture") { … }
    .buttonStyle(.glassProminent)
    .tint(LookAfterChrome.accentTint)
```

## ADHD / Reduce Transparency

- One `GlassEffectContainer` per chrome cluster (tab bar, dock, toolbar group).
- When `accessibilityReduceTransparency` is on, fall back to opaque `contentSurface` / `contentSurfaceElevated` (see `LookAfterBottomNav`, assistant chrome, ADHD dock).
- Reduce Motion is handled in Phase F; chrome glass still must remain legible without morphing.

## Shapes

| Surface | Shape |
|---|---|
| Tab bar plate | `.rect` (edge-to-edge under home indicator) |
| Floating dock / toolbar cluster | Capsule |
| Assistant panel / toasts | Continuous rounded rect (`radiusLG` / 16) |
| Capture FAB | System glass-prominent circle via button style |

## Do not

- Apply `.glassEffect()` to timeline rows, task titles, or briefing narrative cards.
- Stack multiple nested `GlassEffectContainer`s for the same cluster.
- Use `Color.black.opacity(0.4+)` scrims that fight system sheet glass — use `LookAfterChrome.overlayScrim` (~0.22) for custom tap-to-dismiss overlays.
