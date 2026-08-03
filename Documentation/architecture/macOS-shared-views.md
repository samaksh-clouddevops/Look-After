# macOS Shared Views

The **LookAfter-macOS** target intentionally compiles a subset of files from `Apps/LookAfter-iOS/Views/`.

## Why

macOS and iOS share the same design system (`LookAfterCore/DesignSystem/`) and many feature ViewModels (`LookAfterFeatures/`). Duplicating every view would create drift. Instead, `project.yml` lists specific iOS view files in the macOS target's `sources` section.

## What this means

- **Not accidental duplication** — the shared list in `project.yml` is the source of truth
- macOS gets a read-focused subset (timeline, tasks, brain inspector, settings)
- iOS-only views (camera, Live Activity, widget deep links) stay iOS-only

## Adding a shared view

1. Implement the view in `Apps/LookAfter-iOS/Views/`
2. Add its path to the macOS target in `project.yml`
3. Run `xcodegen generate`
4. Verify macOS build

## Platform checks

Use `#if os(iOS)` / `#if os(macOS)` inside shared views when platform APIs differ. Prefer keeping platform-specific code in `Apps/LookAfter-iOS/Services/` or `Apps/LookAfter-macOS/`.
