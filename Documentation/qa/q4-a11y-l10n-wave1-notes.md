# Q4 a11y / L10n wave 1 — Dynamic Type root + String Catalog

Architecture Q3 wave 1 left as-is; this epic starts platform honesty for Larger Text + localization.

## Shipped

1. **Dynamic Type at typography root** — `Font.ds*` now uses `relativeTo:` system text styles (`LookAfterTypography.TextRole`). Default point sizes unchanged at standard size; scales with Larger Text / XXXL.
2. **String Catalog** — `LookAfterCore/Resources/Localizable.xcstrings` (`defaultLocalization: en` + SPM resources).
3. **`LookAfterL10n`** — typed accessors for root tabs, Capture, and widget chrome.
4. **Call sites** — `LookAfterBottomNav` + `LookAfterWidgetBundle` use L10n (not raw English literals).

## Not in this wave

- Full app string migration (Briefing / Today / Settings / onboarding copy)
- Additional locales (catalog is English-ready; add `hi`, etc. in Xcode)
- `@ScaledMetric` for icon/spacing/hit targets on every screen
- Accessibility-size layout reflow (stack vs hstack) on dense rows
- Fake-glass cleanup / macOS parity (separate epics)

## How to verify

- Settings → Accessibility → Display & Text Size → Larger Text → XXXL on Briefing / Today / Capture / tab bar
- Widget + tab labels still English; change catalog values to smoke-test wiring
- `swift test --filter 'LookAfterTypography|LookAfterL10n'` in LookAfterCore

## Next slices

- Migrate Briefing hero + Capture composer strings into the catalog
- `@ScaledMetric` for tab icon size / Capture control height
- Second locale (optional product decision)
