# UI Dead Code / Unwired Feature Findings — 2026-09

**Scope:** Cross-referenced from the repository-wide UI functional bug hunt
(`Documentation/ui-bug-hunt-findings-2026-09.md`, Waves 1–23). This file tracks
code that is either entirely unreachable (dead code) or reachable-but-inert
(dead closures / no-op handlers), as distinct from functional bugs where wired
code behaves incorrectly.

## Resolution status (2026-09, follow-up session)

All four items below have been resolved:

1. `timelineDayPicker` — **discarded** (deleted from `TodayView.swift`; was fully inert).
2. `MorningBriefingView` — **discarded** (deleted `MorningBriefingView.swift`; confirmed zero production call sites, superseded by the live `LAExecutiveBriefingCard` hero + `todayAtAGlanceSection` design in `DailyBriefingView.swift`).
3. `HealthStatusActionHandler.onOpenSettings` — **integrated** (wired to open Settings, matching sibling call sites).
4. `organizeProfileWithAI()` — **integrated** (wired to an "Organize with AI" button in `OnboardingView.profileStep`, with `isOrganizing`/`organizeError` now surfaced).

## Summary (original findings, kept for history)

| # | Item | File | Category | Importance |
|---|---|---|---|---|
| 1 | `timelineDayPicker` — unused `Picker` property, never referenced in `body` | `Apps/LookAfter-iOS/Views/Briefing/TodayView.swift` (Wave 3) | Dead code (inert property) | Low — safe cleanup, no behavioral impact |
| 2 | `MorningBriefingView` — entire view compiled into app target, never instantiated from any production call site (only its own `#Preview`) | `Apps/LookAfter-iOS/Views/Briefing/MorningBriefingView.swift` (Wave 7) | Dead code (unreachable view) | Low-Medium — no user impact today, but maintenance hazard / possible abandoned integration with `ChiefOfStaffBriefingHeader` or `DailyBriefingView` hero narrative |
| 3 | `HealthStatusActionHandler.perform(..., onOpenSettings: { })` — literal no-op closure for the `.trackingOff` status's primary action | `Apps/LookAfter-iOS/Views/Settings/SettingsView.swift` (Wave 15) | Dead closure (reachable control, inert action) | Medium — sibling call sites (`HealthDetailView`, `DailyBriefingView`) wire this correctly; reachability of this exact status/section pairing in `SettingsView` is unconfirmed |
| 4 | `organizeProfileWithAI()` — fully implemented AI-polish flow for the structured life profile via `GLMService`; `isOrganizing`/`organizeError` state never read by any UI | `Apps/LookAfter-iOS/Views/Onboarding/OnboardingView.swift` (Wave 23) | Dead code (unwired feature) | **Medium-High** — a complete, working feature with no button/control ever calling it; users only get raw uncleaned `LifeProfileComposer.compile` text during onboarding |

---

## Details

### 1. `TodayView.timelineDayPicker`
Genuinely inert leftover `Picker` bound to `selectedDay`, never referenced anywhere in `body` or elsewhere in the file. Likely a leftover from before the week-strip day controls were added. No behavioral impact — safe to delete during cleanup.

### 2. `MorningBriefingView`
A full narrative + snapshot-chips card, entirely unreachable in production (no call site instantiates `MorningBriefingView(`, only its own SwiftUI previews do). Cannot misbehave for real users since it's never shown, but represents dead weight in the shipped binary and a maintenance hazard — any latent bugs in this file would never be caught by manual QA. Worth confirming with the feature owner whether it should be deleted or wired up (it may have been intended to feed into `ChiefOfStaffBriefingHeader` or the `DailyBriefingView` hero narrative).

### 3. `HealthStatusBanner` / `HealthStatusActionHandler.onOpenSettings`
In `SettingsView`'s health-verification sheet, the `onOpenSettings` closure passed to `HealthStatusActionHandler.perform` is a literal no-op (`{ }`), so a status whose primary action is "Open Settings" (the `.trackingOff` case) does nothing when tapped. Sibling call sites elsewhere in the app (`HealthDetailView`, `DailyBriefingView`) correctly wire this closure to open Settings. Reachability caveat: under the current toggle wiring, this exact status/section pairing may not currently be reachable from `SettingsView`, but the dead closure is a latent bug if that path is ever exercised.

### 4. `OnboardingView.organizeProfileWithAI()`
A complete, working "AI-polish the structured life profile" feature (calls `GLMService.shared.complete`, falls back to `LifeProfileComposer.organizeLocally` on empty/error) with its own `isOrganizing` / `organizeError` `@State`. No button or control anywhere in `profileStep` (or elsewhere in the 997-line file) invokes it, and its state is never read/displayed. This is the most significant of the four findings — a real, functioning capability that's simply disconnected from the UI, not stale leftover code.

---

## Recommendation (for future remediation, not part of this investigation)

Prioritize in this order if remediation is undertaken:
1. **`organizeProfileWithAI()`** — wire a button in `profileStep` to call it and surface `isOrganizing`/`organizeError`. Real missing capability.
2. **`HealthStatusBanner.onOpenSettings`** — wire to open Settings like the sibling call sites, once reachability is confirmed.
3. **`MorningBriefingView`** — decide with feature owner: delete, or integrate into the live briefing flow.
4. **`timelineDayPicker`** — safe to delete during any pass through `TodayView.swift`.
