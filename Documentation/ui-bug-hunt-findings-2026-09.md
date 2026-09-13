# UI Functional Bug Hunt Findings â€” Wave 1

**Scope:** Root canvas navigation/presentation (`LookAfterRootCanvas.swift`) and contextual replan sheet
presentation (`ContextualReplanSheetsModifier.swift`).
This is an **investigation-only** task. No production code was modified.

## Summary

| Severity | Bug | Status |
|---|---|---|
| MEDIUM | Contextual replan sheet fails to reopen when re-triggered with identical summary text | CONFIRMED (mechanism), reachability not fully proven |
| LOW | Duplicate/redundant `onChange` watching the same value in two places | Noted, not counted as a bug (dead logic only) |
| HIGH | Stale sticky `TasksViewModel.error` causes false "save failed" UI after an unrelated earlier failure (Wave 2) | CONFIRMED |
| MEDIUM | `ReschedulePreviewSheet` "Apply" always dismisses even when apply fails â€” silent failure | CONFIRMED |
| MEDIUM | `TodayView` fails to re-scroll to hero task when returning to "Today" from a mid-week day (Wave 3) | CONFIRMED |
| LOW | `TodayView.timelineDayPicker` is dead code, never referenced in `body` | Noted, not counted as a bug |
| LOW-MEDIUM | `TodayEndOfDayGate` evening gate doesn't auto-reveal at 5pm without an unrelated re-render (Wave 4) | CONFIRMED (mechanism) |
| MEDIUM | `DailyBriefingView` "Start my day" silently no-ops with zero feedback when day-audit questions are unresolved (Wave 5) | CONFIRMED |
| HIGH | Day-audit clarifying questions get non-deterministic random IDs each run, so "Start my day" can never unblock via answering questions once `hasBlockingQuestions` is true (Wave 6) | CONFIRMED |
| LOW | `MorningBriefingView` is dead code â€” compiled into the app target but never instantiated from any production call site (Wave 7) | CONFIRMED |

---

## [MEDIUM] â€” Sheet fails to reopen when re-triggered with identical content

**Category:** Presentation / Async
**Feature:** Contextual Replan (post-wake / going-out / calendar-change / freed-slot)
**File:** `Apps/LookAfter-iOS/Views/Planning/ContextualReplanSheetsModifier.swift`
**Line / View:** lines 44-46 (`onChange(of: planningVM.contextualReplanResult?.summary)`); related pattern also present in `Apps/LookAfter-iOS/Views/LookAfterRootCanvas.swift` lines 393-395, 405-409

**Expected behavior:** Triggering a contextual replan should always present the preview sheet with the new result, regardless of whether its content happens to match a previous result.

**Actual behavior:** Sheet presentation (`showContextualReplanPreview`) is driven entirely by:

```swift
.onChange(of: planningVM.contextualReplanResult?.summary) { _, summary in
    showContextualReplanPreview = summary != nil
}
```

`onChange` only fires when the **watched value actually changes**. Dismissing the sheet (e.g. swipe-down) only flips `showContextualReplanPreview` to `false` â€” it does **not** clear `planningVM.contextualReplanResult`. If the user then triggers another replan whose generated `summary` string is byte-identical to the previous one (plausible for deterministic/templated summaries, or re-triggering the same trigger type with unchanged inputs), the old and new values are equal, `onChange` never fires, and `showContextualReplanPreview` stays `false`. The sheet silently never reopens.

**Trigger:** Dismiss the contextual-replan sheet without acting on it, then trigger the same replan again (e.g. "Post-Wake" or "Around Your Outing") with inputs that produce identical output text.

**Preconditions:** `contextualReplanResult` is not reset to `nil` on manual dismiss; the replan generator returns identical `summary` text on a subsequent call.

**Reproduction:**
```text
1. Trigger a contextual replan (e.g. tap "Post-Wake" from the briefing card).
2. Preview sheet appears with a summary.
3. Swipe down to dismiss without approving/rejecting.
4. Trigger the same replan again with the same underlying inputs.
5. Observe whether the preview sheet reappears.
```

**UI State Before:** `showContextualReplanPreview == false`, `contextualReplanResult.summary == "<text A>"`.

**UI State After (expected):** Sheet visible with new result.
**UI State After (actual, when summary text repeats):** `showContextualReplanPreview` remains `false`; no sheet shown despite a completed replan generation.

**Execution Path:**
```text
User dismisses sheet (swipe)
â†’ showContextualReplanPreview = false (contextualReplanResult NOT cleared)
User re-triggers replan
â†’ planningVM.contextualReplanResult set to new value with identical .summary string
â†’ onChange(of: ...summary) sees old == new â†’ does not fire
â†’ showContextualReplanPreview stays false
â†’ sheet never presents
```

**Root Cause:** Presentation state is derived from equality-diffing a `String?` content field instead of being driven by an explicit "new result" event (e.g., an incrementing generation counter or fresh identifier attached to each replan result, independent of its text content).

**User Impact:** User re-taps a replan action expecting to see the preview and nothing visibly happens â€” appears as a broken/unresponsive button.

**Evidence:** `Apps/LookAfter-iOS/Views/Planning/ContextualReplanSheetsModifier.swift` lines 44-46.

**Confidence:** Medium â€” the presentation-suppression mechanism is confirmed directly in code; whether the replan generator actually produces identical summary strings across separate invocations in practice was not verified (would require inspecting the summary-generation code, out of scope for this file-level pass).

**Related/same-pattern (not separately confirmed):** `LookAfterRootCanvas.swift` lines 330-339 / 393-395 uses `onChange(of: tomorrowPlannerVM.rescheduleProposal?.id)` to drive `showTomorrowPlanPreview`. This is more robust (keys off an `id` rather than display text) but would exhibit the same class of bug if `id` is ever not a fresh value per proposal â€” not confirmed without inspecting the proposal model.

---

## [LOW] â€” Duplicate onChange watching the same value (dead logic, not a bug)

**Category:** State (informational only)
**File:** `LookAfterRootCanvas.swift` lines 405-409 vs `ContextualReplanSheetsModifier.swift` lines 44-46

Both watch `planningVM.contextualReplanResult?.summary`. The modifier's handler unconditionally sets `showContextualReplanPreview = summary != nil`; `RootCanvas`'s handler (gated on `.calendarChange` trigger) sets the same value redundantly. No observable incorrect behavior â€” not counted toward the bug tally.

---

## Coverage so far

| File | Views | Reviewed | Bugs |
|---|---|---|---|
| `Apps/LookAfter-iOS/Views/LookAfterRootCanvas.swift` | Root canvas, tab switch, sheets/full-screen covers, capture flow, brain/planning triggers | Partial (~1150/1308 lines) | 1 (shared w/ modifier) |
| `Apps/LookAfter-iOS/Views/Planning/ContextualReplanSheetsModifier.swift` | Post-wake / going-out / contextual replan preview sheets | Full | 1 |
| `Apps/LookAfter-iOS/Views/Tasks/QuickTaskEditSheet.swift` | Quick task edit sheet (title/duration/scheduling) | Full | 1 (shared) |
| `Apps/LookAfter-iOS/Views/Tasks/TaskListView.swift` | Task list, filters, create/edit sheet, swipe actions | Partial (create/edit save path) | 1 (shared) |
| `Apps/LookAfter-iOS/Views/Tasks/ReschedulePreviewSheet.swift` | AI reschedule proposal preview / apply / reject | Full | 1 |

Remaining unreviewed surface: Briefing/Today, Brain, Settings, Onboarding, Auth, Shared components, Modules, ADHD, Health, Insights, Review, Tour, macOS shell, Widget, UIKit bridges â€” to be covered in subsequent waves.

---

## Wave 2 â€” Tasks UI (Sheets & List)

**Reviewed:** `QuickTaskEditSheet.swift` (full), `ReschedulePreviewSheet.swift` (full), `TaskListView.swift`
(create/edit save path), and the underlying `TasksViewModel`/`ScheduleMutationService` persistence methods
they call into (read-only inspection â€” these are `LookAfterFeatures` view-model files, not touched).

## [HIGH] â€” Stale, sticky `TasksViewModel.error` causes false "save failed" UI after an unrelated earlier failure

**Category:** State / Error handling
**Feature:** Quick task edit, full task edit (create/edit sheet in `TaskListView`)
**Files:**
- `Apps/LookAfter-iOS/Views/Tasks/QuickTaskEditSheet.swift`, lines 160-173 (`save()`)
- `Apps/LookAfter-iOS/Views/Tasks/TaskListView.swift`, lines 738-752 (`.edit` branch of the save action)
- Root cause lives in `Packages/LookAfterFeatures/.../TasksViewModel.swift` (`@Published public var error: String?`, line 14) and `ScheduleMutationService.persist(...)` (lines 14-37) â€” neither resets `error` to `nil` at the start of an operation, only sets it in `catch` blocks on failure.

**Expected behavior:** After calling `tasksVM.scheduleMutation.persist(...)` for the current save, the sheet should reflect whether *this* save succeeded or failed.

**Actual behavior:** Both sheets infer success/failure purely by reading the *global* `tasksVM.error` immediately after the awaited persist call:

```swift
await tasksVM.scheduleMutation.persist(updated, userId: userId, userPlaced: ...)
isSaving = false
if tasksVM.error == nil {
    dismiss()               // QuickTaskEditSheet / TaskListView
} else {
    saveError = tasksVM.error  // QuickTaskEditSheet only
}
```

`tasksVM.error` is a single shared `@Published` property mutated by dozens of unrelated code paths across the
view model (reconcile, recurrence sync, semantic refresh, onboarding cleanup, dedupe, etc. â€” 15+ call sites),
and it is **never cleared back to `nil` on success** anywhere in `TasksViewModel` or `ScheduleMutationService`.
Once *any* background operation fails and sets `tasksVM.error`, it stays set indefinitely. The very next time
the user opens either edit sheet and successfully saves a change, the sheet reads the leftover non-nil
`error` from the earlier, unrelated failure and incorrectly treats the current, successful save as failed:
- `QuickTaskEditSheet`: shows a wrong/stale error message under the form fields, sheet stays open.
- `TaskListView` edit sheet: no error is displayed at all (no `saveError` binding read there) â€” the sheet
  simply fails to dismiss and skips the success haptic, with **no explanation given to the user**, even
  though the task was actually saved correctly.

**Trigger:** Any prior failure anywhere in the app that sets `tasksVM.error` (e.g. a transient network/repo
error during background reconcile, recurrence sync, or semantic-profile refresh) followed by a normal,
successful task edit via either sheet.

**Reproduction:**
```text
1. Cause any TasksViewModel operation to fail so tasksVM.error becomes non-nil
   (e.g. a repo write failure during background reconcile/sync).
2. Without restarting the app, open a task via QuickTaskEditSheet or the full edit sheet in TaskListView.
3. Make a valid edit and tap Save.
4. Observe: even though the update actually persists successfully, the sheet reports/behaves as if the
   save failed (stale error text shown, or sheet fails to dismiss / no success haptic).
```

**Root Cause:** Success/failure of a specific async operation is inferred from a long-lived, globally shared
`error` flag instead of using the awaited call's own throw/result. `error` is set-only on the failure path and
never reset on the success path, so it accumulates state across unrelated operations.

**User Impact:** Users can see an incorrect "something went wrong" message (or an edit sheet that silently
refuses to close) for a save that actually succeeded, with no way to tell the change was saved except by
reopening the task list.

**Confidence:** High â€” verified directly: (a) both sheets' post-persist logic reads `tasksVM.error` with no
per-call scoping, (b) `persist()`/`updateTaskAndPersist()` never reset `error = nil` before doing work, and
(c) `error` is set from many unrelated failure sites throughout `TasksViewModel`.

---

## [MEDIUM] â€” `ReschedulePreviewSheet` "Apply" always dismisses even when the apply fails

**Category:** Error handling / Silent failure
**Feature:** AI-generated day reschedule â€” "Apply" action
**File:** `Apps/LookAfter-iOS/Views/Tasks/ReschedulePreviewSheet.swift`, lines 68-81

**Expected behavior:** If applying the reschedule proposal fails, the user should see an error and the sheet
should stay open (or clearly indicate failure) so they don't lose track of the pending proposal.

**Actual behavior:**
```swift
Button("Apply") {
    Task {
        await plannerVM.applyRescheduleProposal(userId: userId, tasksViewModel: tasksViewModel)
        dismiss()
    }
}
```
`dismiss()` is called unconditionally after `applyRescheduleProposal` returns, with no check of
`plannerVM.error` (which `applyRescheduleProposal` sets on failure â€” confirmed in
`DailyPlannerViewModel.swift` lines 183-188, `error = nil` at start / set in catch on failure). If the apply
throws internally, the sheet closes exactly as if the apply had succeeded, with zero visible indication to
the user that their reschedule was not actually applied.

**Trigger:** Any failure inside `applyRescheduleProposal` (e.g. repo write failure, constraint conflict)
while tapping "Apply" on the reschedule preview sheet.

**Reproduction:**
```text
1. Trigger a day reschedule proposal and open the preview sheet.
2. Cause the underlying persist to fail (e.g. simulate a repo error).
3. Tap "Apply".
4. Observe: the sheet dismisses as if successful; plannerVM.error is set but never surfaced anywhere.
```

**Root Cause:** No error check/guard between the awaited `applyRescheduleProposal` call and `dismiss()`.

**User Impact:** User believes their schedule was rearranged as previewed, but some or all of the proposed
changes were not actually persisted â€” silent data-loss-adjacent failure with no recovery path from the UI.

**Confidence:** High for the missing-check mechanism; the underlying error is confirmed to be set in
`DailyPlannerViewModel.applyRescheduleProposal`'s catch path, so this is a directly reachable UI failure
mode whenever that call throws.

---

## Wave 2 summary

**Reviewed:** Task edit sheets (`QuickTaskEditSheet`, `TaskListView` create/edit path) and
`ReschedulePreviewSheet`, cross-referencing their view-model call targets in `TasksViewModel` /
`ScheduleMutationService` / `DailyPlannerViewModel` (read-only).

**Result:** 2 new confirmed bugs â€” both are "silent/incorrect failure feedback" issues rooted in checking a
shared, long-lived `error` property instead of the awaited call's own outcome. No production code modified.

---

## Wave 3 â€” Briefing / Today

**Reviewed:** `TodayView.swift` (full, 1661 lines) â€” week-strip day selection, hero/timeline scroll behavior,
coach banners, schedule preview. (`DailyBriefingView.swift`, `MorningBriefingView.swift`, and the other
`Briefing/` files not yet covered â€” deferred to a later wave.)

## [MEDIUM] â€” Returning to "Today" from a mid-week day fails to re-scroll to the hero task

**Category:** State / Scroll behavior
**Feature:** Today screen â€” week date strip (`showDayControls` â†’ `LAWeekDateStrip`)
**File:** `Apps/LookAfter-iOS/Views/Briefing/TodayView.swift`, lines 55, 371-422, 300-318

**Expected behavior:** Whenever the effectively-displayed day changes (governed by `selectedCalendarDate`),
the timeline scroll position should reset to the hero section, and the cached pre-window-fit / proactive
action state should be recomputed for the newly selected day.

**Actual behavior:** The view has two pieces of day-selection state:
- `selectedCalendarDate: Date` â€” the actual source of truth; drives `isSelectedToday` / `isSelectedTomorrow`
  and therefore which content branch renders (lines 408-414, 193/266/283).
- `selectedDay: TimelineDaySelection` (`.today` / `.tomorrow` only) â€” a legacy enum that all the *side-effect*
  `onChange` handlers key off instead (lines 111-114 refresh, 310-312 scroll-to-hero).

`syncSelectedDay(from:)` (lines 416-422) only updates `selectedDay` when the newly picked date is today or
tomorrow; for any other day in the week strip it leaves `selectedDay` untouched:
```swift
private func syncSelectedDay(from date: Date) {
    if Calendar.current.isDateInToday(date) {
        selectedDay = .today
    } else if Calendar.current.isDateInTomorrow(date) {
        selectedDay = .tomorrow
    }
}
```

**Trigger / Reproduction:**
```text
1. Open Today, tap "Day controls" to reveal the week strip.
2. Tap a day 2+ days from today (neither today nor tomorrow) â€” content correctly shows
   "No plan for this day yet." selectedDay stays at its last value (.today, from initial state).
3. Tap back on "Today" in the week strip. selectedCalendarDate changes back to today's date.
4. syncSelectedDay(from: today) sets selectedDay = .today â€” but it was ALREADY .today (never changed
   in step 2), so this is a no-op assignment: onChange(of: selectedDay) does NOT fire.
5. Observe: isSelectedToday flips back to true and the full hero/timeline content re-renders, but the
   ScrollView does not scroll back to the hero card (scrollTodayToHero is only invoked from the
   onChange(of: selectedDay) handler at line 310) â€” the scroll position is left wherever it was for the
   "No plan for this day yet" placeholder content.
```

**Root Cause:** Two independent, non-synchronized day-selection state variables where the one driving content
(`selectedCalendarDate`) doesn't always cause the one driving side effects (`selectedDay`) to actually change
value, since `selectedDay` only distinguishes "today" vs "tomorrow" vs (implicitly) "neither" but never gets
set to a distinct value for "neither."

**User Impact:** After browsing to a non-today/non-tomorrow day and returning to Today, the user lands on a
freshly re-rendered Today screen scrolled to an arbitrary/incorrect position instead of the hero task â€”
appears as a broken/janky scroll position on a screen the user visits constantly.

**Confidence:** High â€” the state-shape mismatch and the exact `onChange` gating are directly confirmed in
code; the only assumption is that the ScrollView's contentless placeholder branch doesn't happen to already
be scrolled to a position that visually coincides with the hero (plausible but not pixel-verified without a
simulator).

---

## [LOW] â€” `timelineDayPicker` is dead code

**File:** `TodayView.swift`, lines 429-436

`private var timelineDayPicker` builds a segmented `Picker` bound to `selectedDay`, but it is never referenced
anywhere in `body` or any other view in the file. Harmless dead code, not a functional bug â€” likely a leftover
from a previous UI iteration before the week-strip day controls were added. Not counted toward the bug tally.

---

## Wave 3 summary

**Reviewed:** `TodayView.swift` in full.

**Result:** 1 new confirmed MEDIUM bug (stale `selectedDay` breaking scroll-to-hero on day-strip navigation
back to Today), plus 1 dead-code observation. No production code modified. Remaining `Briefing/` files
(`DailyBriefingView`, `MorningBriefingView`, `ExecutiveLiveTimelineView`, `TodayEndOfDayGate`, etc.) still
need coverage in a future wave.

---

## Wave 4 â€” Briefing (End-of-Day Gate)

**Reviewed:** `TodayEndOfDayGate.swift` (full, 53 lines) plus surrounding call site in `TodayView.swift`
(lines 255-266) and its state-refresh triggers (`TodayView.onAppear`/`onChange` handlers, lines 64-77,
745-753).

## [LOW-MEDIUM] â€” Evening gate does not auto-reveal at 5pm without an unrelated re-render

**Category:** State / Time-based UI
**Feature:** Today screen â€” end-of-day journal reveal gate
**File:** `Apps/LookAfter-iOS/Views/Briefing/TodayEndOfDayGate.swift`, lines 13-18

**Expected behavior:** Per the file's own doc comment ("V5: Hide the full end-of-day journal until evening
â€¦ or explicit expand"), the journal card should become visible once the wall-clock time crosses 5pm (17:00),
even if the user is already sitting on the Today screen with it open.

**Actual behavior:**
```swift
private var isEvening: Bool {
    Calendar.current.component(.hour, from: Date()) >= 17
}
```
`isEvening` is a plain computed property with no `@State`/timer backing it â€” it is only re-evaluated when
SwiftUI re-renders `TodayEndOfDayGate`, which only happens when one of its `@ObservedObject`s
(`modulesVM`, `tasksVM`, `speechManager`) publishes a change, or when its parent (`TodayView`) re-renders
for an unrelated reason (task list change, proactive actions change, `nowTaskId` change, etc.). There is no
periodic timer driving this view or its ancestors purely for a per-minute/per-hour clock tick.

**Trigger / Reproduction:**
```text
1. Open the Today screen at 4:59pm with the collapsed "End of day reflection" pill showing (isExpanded
   remains false since the user hasn't tapped it, isEvening is false).
2. Leave the app open and idle on this screen, watching the clock cross 5:00pm, without performing any
   task action, tab switch, or other state-changing interaction.
3. Observe: the pill remains collapsed past 5pm; the journal does not auto-appear on its own the moment
   the hour ticks over, contrary to the "auto-reveal in evening" design intent.
4. The gate only flips to expanded the next time some unrelated event forces a re-render of TodayView/
   TodayEndOfDayGate (e.g. planningVM.nowTaskId changes on the next scheduled task boundary, or the user
   backgrounds/foregrounds the app) â€” at which point isEvening is finally re-read and (if now >= 17:00)
   the card appears.
```

**Root Cause:** `isEvening` is derived from `Date()` with no observed time source (no `Timer.publish`,
no `TimelineView`, no scenePhase-driven refresh) to force SwiftUI to reconsider it as time passes while
the view is already on screen.

**User Impact:** A user who has the Today screen open and idle in the late afternoon may not see the
end-of-day journal appear automatically right at 5pm as designed; it only shows up whenever the next
incidental re-render happens to occur (which in practice is fairly frequent due to `nowTaskId`/task-list
churn, so this is a UX/timing gap rather than a full-lockout failure â€” hence LOW-MEDIUM rather than HIGH).

**Confidence:** High on the mechanism (confirmed no timer/TimelineView exists anywhere upstream that would
force this specific re-evaluation); the practical user-visible frequency depends on how often incidental
re-renders happen to occur near 5pm, which is not independently verified.

---

## Wave 4 summary

**Reviewed:** `TodayEndOfDayGate.swift` in full, cross-referenced against `TodayView`'s re-render triggers.

**Result:** 1 new confirmed LOW-MEDIUM bug (evening auto-reveal relies on incidental re-renders rather than
an actual clock-driven update). No production code modified. Remaining `Briefing/` files (`DailyBriefingView`,
`MorningBriefingView`, `ExecutiveLiveTimelineView`, etc.) and other directories (Brain, Settings, Shared,
macOS shell, UIKit bridges) still need coverage in future waves.

---

## Wave 5 â€” Briefing (Daily Briefing hero / "Start my day")

**Reviewed:** `DailyBriefingView.swift` (full, 712 lines) and `DailyBriefingViewModel.startMyDay` /
`refreshDayAudit` / `dayAuditQuestionsResolved` in `DailyBriefingViewModel.swift`.

## [MEDIUM] â€” "Start my day" silently no-ops when day-audit questions are unresolved

**Category:** Feedback / Silent failure
**Feature:** Briefing hero â€” `LAExecutiveBriefingCard` "Start my day" button
**File:** `Apps/LookAfter-iOS/Views/Briefing/DailyBriefingView.swift`, lines 59-69;
`Packages/LookAfterFeatures/Sources/LookAfterFeatures/Briefing/ViewModels/DailyBriefingViewModel.swift`,
lines 1379-1411

**Expected behavior:** Tapping "Start my day" should either navigate to Today (success) or clearly show
the user why it didn't (e.g. scroll to / highlight the unresolved day-audit questions in `DayAuditCheckCard`
just below the hero card).

**Actual behavior:** The button's action is:
```swift
onContinue: {
    Task { @MainActor in
        let ok = await briefingVM.startMyDay(tasksVM: tasksVM, userId: userId)
        guard ok else { return }
        hasUserScrolled = true
        onOpenToday()
    }
}
```
`startMyDay` returns `false` whenever `dayAuditQuestionsResolved` is `false` (line 1394,
`guard dayAuditQuestionsResolved else { return false }`) â€” i.e. whenever the day-audit surfaced fix/pull
questions that the user hasn't yet accepted/rejected in `DayAuditCheckCard`. When that happens, the `guard
ok else { return }` on the view side is a bare early return: no alert, no haptic, no scroll-to-card, no
visual state change of any kind.

**Trigger / Reproduction:**
```text
1. Open the Briefing screen on a day where DayAuditService.run() produces proposedFixes/possiblePulls
   (e.g. an incomplete task carried over from yesterday, or an overcommitted schedule) â€” DayAuditCheckCard
   renders below the hero with unanswered questions.
2. Without scrolling down to interact with DayAuditCheckCard, tap "Start my day" on the hero card.
3. isLoading briefly flips true ("Checkingâ€¦"), then false again â€” button returns to "Start my day".
   No navigation to Today occurs, no message explains why, no scroll/highlight draws attention to the
   card that needs interaction directly beneath it.
4. A user unaware of the day-audit feature (or who doesn't immediately scroll down) perceives the button
   as broken/unresponsive with no way to tell what to do next.
```

**Root Cause:** `startMyDay`'s `Bool` return conflates "should navigate" with "input needed" â€” the caller
only handles the true/false result as pass/fail with no branch for the "needs user input elsewhere on
screen" case, and provides no feedback for the false path.

**User Impact:** The primary CTA on the Briefing screen appears to silently fail with no error, explanation,
or navigational cue â€” a real "broken button" experience for any user who hasn't already scrolled past the
hero to resolve the audit prompts first.

**Confidence:** High â€” both sides of the flow (the `guard ok else { return }` in the view and the `guard
dayAuditQuestionsResolved else { return false }` in the view model) are directly confirmed in code.

---

## Wave 5 summary

**Reviewed:** `DailyBriefingView.swift` in full, cross-referenced against `DailyBriefingViewModel.startMyDay`.

**Result:** 1 new confirmed MEDIUM bug (silent no-op on "Start my day" when day-audit questions are
unresolved). No production code modified. Remaining `Briefing/` files (`MorningBriefingView`,
`ExecutiveLiveTimelineView`, `DayAuditCheckCard`, etc.) and other directories (Brain, Settings, Shared,
macOS shell, UIKit bridges) still need coverage in future waves.

---

## Wave 6 â€” Briefing (Day Audit questions â€” root cause of Wave 5)

**Reviewed:** `DayAuditCheckCard.swift` (full, 200 lines), `DayAuditService.swift` (question construction,
lines 52-181), `DayAuditModels.swift` (`DayAuditQuestion`, `DayAuditResult`), and
`DailyBriefingViewModel.refreshDayAudit` / `dayAuditQuestionsResolved` / `answerDayAuditQuestion`.

## [HIGH] â€” Day-audit clarifying questions get a fresh random ID on every audit run, so answering them can never satisfy `dayAuditQuestionsResolved` when "Start my day" re-audits first

**Category:** State identity / Data flow
**Feature:** Day-audit clarifying questions gating "Start my day" (`DayAuditCheckCard` + `startMyDay`)
**File:** `Packages/LookAfterCore/Sources/LookAfterCore/Planning/DayAudit/DayAuditService.swift`, lines
124-129, 142-148; `Packages/LookAfterCore/Sources/LookAfterCore/Planning/DayAudit/DayAuditModels.swift`,
lines 114-133 (`DayAuditQuestion.id` defaults to `UUID().uuidString`);
`Packages/LookAfterFeatures/Sources/LookAfterFeatures/Briefing/ViewModels/DailyBriefingViewModel.swift`,
lines 1347-1394 (`dayAuditQuestionsResolved`, `startMyDay`)

**Expected behavior:** A user who answers every clarifying question shown in `DayAuditCheckCard` should be
able to tap "Start my day" and proceed, since `dayAuditQuestionsResolved` should read those same answers
back as satisfied.

**Actual behavior:** `DayAuditService.run()` constructs every `DayAuditQuestion` without passing an
explicit `id`:
```swift
questions.append(DayAuditQuestion(
    prompt: "Today looks heavy for your energy. What should we protect?",
    options: ["Keep deep work", "Cut flex work", "Keep as planned"],
    relatedTaskIDs: []
))
```
and `DayAuditQuestion.id` defaults to `UUID().uuidString` â€” a brand-new random value generated on *every*
call to `DayAuditService.run()`, not a stable ID derived from the question's content/source. Meanwhile,
`answerDayAuditQuestion(id:option:)` stores the answer keyed by that transient ID in
`dayAuditQuestionAnswers: [String: String]`, and `dayAuditQuestionsResolved` checks
`audit.clarifyingQuestions.allSatisfy { dayAuditQuestionAnswers[$0.id] != nil }` against **the current**
`dayAudit`'s (freshly regenerated) question IDs.

Critically, `startMyDay` itself re-runs the audit immediately before checking resolution:
```swift
await refreshDayAudit(tasksVM: tasksVM, now: now, calendar: calendar)   // regenerates dayAudit with NEW random question IDs
guard dayAuditQuestionsResolved else { return false }                   // checks answers keyed by the OLD IDs
```
Since `refreshDayAudit` only resets `dayAuditQuestionAnswers` once per calendar day (line 1328,
`if lastKey != dayKey`), the stored answer survives, but it's keyed by an ID that no longer matches any
question in the just-regenerated `dayAudit.clarifyingQuestions` â€” the new questions have new random IDs.

**Trigger / Reproduction:**
```text
1. Reach a day state where DayAuditService produces a blocking clarifying question (e.g. capacity
   overloaded) â€” DayAuditCheckCard shows "Today looks heavy for your energy..." with 3 option chips.
2. Tap one of the option chips (e.g. "Keep deep work") â€” answerDayAuditQuestion stores
   dayAuditQuestionAnswers[question.id] = "Keep deep work" using THIS render's random question.id.
3. Tap "Start my day" on the hero card.
4. Inside startMyDay, refreshDayAudit() re-runs DayAuditService.run(), producing a new DayAuditResult whose
   clarifyingQuestions contains a DayAuditQuestion with a DIFFERENT random id (same prompt/options text,
   different UUID).
5. dayAuditQuestionsResolved evaluates allSatisfy against the NEW question's id, which was never answered
   â†’ returns false â†’ startMyDay returns false â†’ "Start my day" no-ops (see Wave 5 finding).
6. The chip the user tapped in step 2 also no longer shows as selected after the re-render, since
   FlowQuestionChips' `selected` binding is `dayAuditQuestionAnswers[question.id]` looked up by the NEW id
   â€” the previously-tapped chip visually reverts to unselected.
```

**Root Cause:** `DayAuditQuestion` uses a random UUID as its identity instead of a stable ID derived from
its semantic source (e.g. `sourceKind` + day key, or the related fault's ID), so re-running the otherwise
deterministic `DayAuditService.run()` produces content-identical but ID-different questions each time.

**User Impact:** Once a day trips a blocking clarifying question, the user is functionally stuck: tapping
an answer chip appears to work (visually selects) but is silently invalidated by the very next audit
refresh, and "Start my day" keeps re-triggering that refresh right before checking resolution â€” so the
*only* path forward the UI actually offers is "Skip questions" (which doesn't depend on question IDs).
This directly explains and deepens the Wave 5 finding: it isn't merely a missing-feedback issue, it's a
structural bug that can make the answer-based path permanently non-functional for that day's audit.

**Confidence:** High â€” `DayAuditQuestion`'s default `id: String = UUID().uuidString`, the two question
construction sites omitting `id`, and `startMyDay`'s call to `refreshDayAudit` immediately before checking
`dayAuditQuestionsResolved` are all directly confirmed in code. The only unconfirmed detail is whether
`DayAuditService.run()`'s other inputs (task list, capacity, etc.) are byte-identical between the two calls
in a given `startMyDay` invocation â€” if they are (the common case, since nothing mutates tasks between the
two calls when no fixes/pulls are selected), the ID mismatch is guaranteed on every attempt.

---

## Wave 6 summary

**Reviewed:** `DayAuditCheckCard.swift`, `DayAuditService.swift`'s question-construction paths, and
`DailyBriefingViewModel`'s day-audit question/resolution plumbing.

**Result:** 1 new confirmed HIGH bug â€” day-audit question IDs are non-deterministic (random per audit run),
which (combined with `startMyDay` re-auditing right before checking resolution) can make the "answer the
question" path permanently unable to unblock "Start my day," leaving "Skip questions" as the only working
exit. This is the concrete root cause underlying the Wave 5 silent-no-op finding. No production code
modified. Remaining `Briefing/` files (`MorningBriefingView`, `ExecutiveLiveTimelineView`, etc.) and other
directories (Brain, Settings, Shared, macOS shell, UIKit bridges) still need coverage in future waves.

---

## Wave 7 â€” Briefing (Morning Briefing narrative card)

**Reviewed:** `MorningBriefingView.swift` (full, 193 lines), plus a repository-wide search for production
call sites instantiating `MorningBriefingView(`.

## [LOW] â€” `MorningBriefingView` is dead code: compiled into the app target but never instantiated anywhere

**Category:** Dead code / Unreachable UI
**Feature:** "Morning Briefing" narrative + snapshot chips card
**File:** `Apps/LookAfter-iOS/Views/Briefing/MorningBriefingView.swift` (whole file)

**Expected behavior:** If a SwiftUI view is compiled into the shipped app target (it's registered in
`LookAfter.xcodeproj/project.pbxproj` under both `PBXFileReference` and the `Sources` build phase), it
should be reachable from some real screen a user can navigate to.

**Actual behavior:** A repository-wide search (`Get-ChildItem -Recurse *.swift | Select-String
'MorningBriefingView\('`) across `Apps/` finds exactly two matches, both inside
`MorningBriefingView.swift` itself, inside `#if DEBUG` / `#Preview` blocks (lines 171, 183). There is no
call site in `LookAfterRootCanvas.swift`, `TodayView.swift`, `DailyBriefingView.swift`, or any other
production view that constructs `MorningBriefingView(...)`. The type, its `BriefingTypeScale` enum, and the
`present(_:)` reveal-animation logic are fully implemented and exercised only by Xcode previews.

**Trigger / Reproduction:**
```text
1. Search the app-target source tree for `MorningBriefingView(`.
2. Only matches are the two #Preview blocks inside MorningBriefingView.swift.
3. No production screen (Today, Daily Briefing, onboarding, etc.) presents this view.
```

**User Impact:** None directly (the view is unreachable, so it cannot misbehave for a real user) â€” but this
represents dead weight in the shipped binary and, more importantly, a *maintenance hazard*: any of the
Wave-1-style bugs that could exist in this file (e.g. `onChange(of: narrative)` combined with
`guard text != displayedNarrative` silently swallowing a re-presentation of identical narrative text after a
manual state reset) would never be caught by manual QA of the live app, only by directly opening the Xcode
preview. It's also possible this was intended to replace/feed into `ChiefOfStaffBriefingHeader` or the
`DailyBriefingView` hero narrative but the integration was never wired up â€” worth confirming with the
feature owner whether this should be deleted or hooked up.

**Confidence:** High on "no production call site exists" (confirmed via full-repo grep and targeted
`codebase-retrieval`). Medium on *why* â€” could be an abandoned redesign, an in-progress feature, or
intentionally kept for future use.

---

## Wave 7 summary

**Reviewed:** `MorningBriefingView.swift` in full, plus a repository-wide search for its usage.

**Result:** 1 new confirmed LOW finding â€” `MorningBriefingView` is entirely dead/unreachable production
code (only referenced from its own `#Preview`s). No functional bug for real users since it's never shown,
but flagged as a maintenance/dead-code risk. No production code modified. Coverage table updated.

Remaining unreviewed: `ExecutiveLiveTimelineView`, `ExecutiveAssistantSheet`, `ExecutivePlanningConversationView`,
`ExecutiveCapacityCard`, `LifeBlockView`, `LifeGapsCard`, `BriefingModuleInsightsCard`,
`ChiefOfStaffBriefingHeader`, `TimelineDragCoordinator`/`TimelineDragTimeMeter`, `TodayCompactMetricsStrip`,
`TodayEndOfDayJournalCard`, Brain, Settings, Shared components, macOS shell, UIKit bridges.

Ready for Wave 8 whenever you say "wave 8."

---

## Wave 8 â€” Briefing (Executive Live Timeline â€” reschedule/remove/complete action buttons)

**Reviewed:** `ExecutiveLiveTimelineView.swift` (full, 1146 lines) â€” `gitRailRow`, `EventTimelineCard`,
action-button disabled/spinner state management.

## [MEDIUM] â€” Reschedule / Remove-from-timeline / Complete button loading states are reset by a fixed timer, not by actual completion, allowing duplicate taps during slow operations

**Category:** Race condition / Double-submission
**Feature:** Timeline row action buttons (Start now, Reschedule, Remove from timeline, double-tap complete/uncomplete)
**File:** `Apps/LookAfter-iOS/Views/Briefing/ExecutiveLiveTimelineView.swift`, lines 315-363 (complete/uncomplete),
341-363 (reschedule/remove)

**Expected behavior:** Tapping "Reschedule" (or "Remove from timeline", or double-tapping to complete)
should show a spinner and disable that action until the underlying operation actually finishes, preventing
duplicate submissions if the user taps again.

**Actual behavior:** All the callback props (`onRescheduleTask`, `onRemoveFromTimelineTask`,
`onCompleteTask`, `onUncompleteTask`) are synchronous `(String) -> Void` closures â€” fire-and-forget calls
into the parent, with no completion signal. The "loading" UI state is faked with a hardcoded timer instead:
```swift
onReschedule: row.canReschedule ? row.taskId.flatMap { taskId in
    guard let onRescheduleTask else { return nil }
    return {
        reschedulingTaskIds.insert(taskId)
        onRescheduleTask(taskId)
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            reschedulingTaskIds.remove(taskId)
        }
    }
} : nil,
```
Same pattern for `onRemoveFromTimeline` (800ms) and `onDoubleTapComplete`/uncomplete (600ms). The
`.disabled(isRescheduling)` / `.disabled(isRemoving)` guard on the button is driven purely by whether that
fixed-duration `Task.sleep` has elapsed â€” it has no relationship to whether `onRescheduleTask`/
`onRemoveFromTimelineTask` actually finished persisting the change upstream (e.g. `PlanMutationApplier`,
which the backend bug hunt already found has fire-and-forget persistence races of its own).

**Trigger / Reproduction:**
```text
1. Expand a timeline row's actions and tap "Reschedule" on a task while the device/persistence layer is
   momentarily slow (e.g. under load, or if the upstream mutation involves an await chain longer than
   800ms).
2. The button re-enables and the spinner disappears after 800ms regardless of whether the reschedule has
   actually been applied yet.
3. The user, seeing the button active again with no visible in-flight indicator, taps "Reschedule" again
   (or taps "Remove from timeline" on the same row) before the first mutation has committed.
4. Two overlapping mutation calls race on the same taskId with no de-duplication â€” best case a harmless
   duplicate; worst case (consistent with the backend-confirmed `PlanMutationApplier` race on
   `.deferTask`/`.removeFromToday`) a lost update or inconsistent final state depending on which async
   completion lands last.
```

**Root Cause:** The view has no way to observe true async completion since the action callbacks are typed
as synchronous `Void`-returning closures; the fixed-duration `Task.sleep` is a purely cosmetic proxy for
"probably done by now," not a real completion signal.

**User Impact:** Under normal-speed conditions this is invisible (800ms/600ms is usually enough). Under any
slowdown (large task lists, cold cache, background contention), a user can double-tap the same action,
compounding with the already-confirmed backend race in `PlanMutationApplier` fire-and-forget persistence.

**Confidence:** High on the mechanism (directly read from source â€” the callbacks are non-async, and the
reset is a bare `Task.sleep` with no result-checking). Medium on real-world frequency, since it requires the
backend operation to exceed the hardcoded delay window to actually manifest as a double-submission.

---

## Wave 8 summary

**Reviewed:** `ExecutiveLiveTimelineView.swift` in full â€” timeline row rendering, action button state
management, drag-to-reschedule integration points.

**Result:** 1 new confirmed MEDIUM bug â€” reschedule/remove/complete action loading states are driven by a
fixed timer rather than real async completion, permitting duplicate taps under slow-operation conditions.
This compounds the previously-confirmed backend `PlanMutationApplier` fire-and-forget race. No production
code modified. Coverage table updated.

Remaining unreviewed: `ExecutiveAssistantSheet`, `ExecutivePlanningConversationView`, `ExecutiveCapacityCard`,
`LifeBlockView`, `LifeGapsCard`, `BriefingModuleInsightsCard`, `ChiefOfStaffBriefingHeader`,
`TimelineDragCoordinator`/`TimelineDragTimeMeter`, `TodayCompactMetricsStrip`, `TodayEndOfDayJournalCard`,
Brain, Settings, Shared components, macOS shell, UIKit bridges.

Ready for Wave 9 whenever you say "wave 9."

---

## Wave 9 â€” Briefing (Timeline drag-to-reschedule lift/cancel lifecycle)

**Reviewed:** `LifeBlockView.swift` (full, 318 lines), `TimelineDragCoordinator.swift` (full, 39 lines),
cross-referenced with `ExecutiveLiveTimelineView`'s `effectiveScrollDisabled` binding (Wave 8 file).

## [MEDIUM-HIGH] â€” If a lifted timeline block's gesture is interrupted (view removed mid-drag) instead of ending normally, scroll stays permanently disabled and the drag coordinator state is never cleared

**Category:** Lifecycle interruption / Stuck UI state
**Feature:** Timeline drag-to-reschedule (long-press-then-drag on a timeline block)
**File:** `Apps/LookAfter-iOS/Views/Briefing/LifeBlockView.swift`, lines 142-165 (`beginLiftSession` /
`cancelLift`), 197-227 (`finishDrag`) â€” no `.onDisappear` cleanup exists anywhere in the file.

**Expected behavior:** If a user starts lifting/dragging a timeline row and the row is removed from the
view hierarchy mid-gesture (e.g. the underlying task is completed/removed by another part of the app,
a data refresh reorders/removes rows, or the parent sheet is dismissed), the drag session should be torn
down: `scrollDisabled` reset to `false`, and `TimelineDragCoordinator.end()` called so no other row/overlay
is left believing a drag is in progress.

**Actual behavior:** `beginLiftSession()` sets `isLifted = true`, `scrollDisabled = true` (a `@Binding` that
maps into `ExecutiveLiveTimelineView.effectiveScrollDisabled`, shared across the *entire* timeline's
`ScrollView`), and calls `dragCoordinator.begin(taskID:...)`. The only two places that ever undo this are
`cancelLift()` (called from the gesture's `.onEnded` default branch) and `finishDrag()` (called from
`.onEnded` on a successful drag) â€” both are gesture-callback-driven. There is **no `.onDisappear` modifier**
anywhere in `LifeBlockView` to force-reset `scrollDisabled`/`isLifted`/`dragCoordinator` if the view is torn
down while `isLifted == true` without SwiftUI ever delivering `.onEnded` for that gesture (which is a known
SwiftUI behavior when a view is removed from the hierarchy mid-gesture, e.g. due to a `ForEach` id change,
list reordering after a background data refresh, or the row's task completing via a different code path
while it's being dragged).

**Trigger / Reproduction:**
```text
1. Long-press a flexible/fluid timeline row to lift it (isLifted = true, scrollDisabled = true on the whole
   timeline's ScrollView, TimelineDragCoordinator.begin(taskID:) called).
2. While still holding (mid-drag, before lifting your finger), trigger something that removes/reorders this
   row out from under the gesture â€” e.g. a background refresh completes and the task is marked as
   auction-resurrected/removed elsewhere, or `DailyBriefingViewModel.refreshDayAudit` causes the parent to
   re-render `displayRows` without this row's id.
3. SwiftUI tears down the row's view (and its attached gesture) without delivering `.onEnded` because the
   underlying view identity is gone.
4. `scrollDisabled` binding is left at `true` forever (nothing else in the timeline resets it), so the
   entire timeline `ScrollView` becomes permanently unscrollable until the user navigates away and back
   (which reconstructs `blockScrollDisabled` fresh at `false` in `ExecutiveLiveTimelineView`'s `@State`).
5. Separately, `TimelineDragCoordinator`'s `activeTaskID`/`proposedStart`/`anchorY` remain stuck at their
   last values, so `TimelineDragTimeMeter`'s overlay could keep rendering a stale "proposed time" pill tied
   to a task that's no longer part of the visible timeline.
```

**Root Cause:** Drag-session teardown is entirely gesture-driven (`.onEnded` only) with no `.onDisappear`
safety net, so any lifecycle interruption that removes the view without completing the gesture leaves
shared, binding-based UI state (`scrollDisabled`) and object state (`TimelineDragCoordinator`) permanently
stuck.

**User Impact:** The user experiences a frozen/unscrollable timeline with no visible error, and no obvious
way to recover other than navigating away from the screen and back (if that state even resets â€” depends on
whether `ExecutiveLiveTimelineView` itself is recreated or merely re-rendered, since `@State private var
blockScrollDisabled` and `@State private var dragCoordinator = TimelineDragCoordinator()` persist across
re-renders of the same view identity).

**Confidence:** Medium-High. The missing `.onDisappear` reset and shared/binding nature of `scrollDisabled`
are directly confirmed in code. The exact trigger conditions for SwiftUI tearing down a view mid-gesture
without `.onEnded` firing are a well-documented SwiftUI edge case (view identity change / `ForEach` removal
during an active gesture), not independently reproduced in a live run here.

---

## Wave 9 summary

**Reviewed:** `LifeBlockView.swift` and `TimelineDragCoordinator.swift` in full â€” the timeline's
long-press-then-drag-to-reschedule lift session lifecycle.

**Result:** 1 new confirmed MEDIUM-HIGH bug â€” drag-session cleanup (shared `scrollDisabled` binding +
`TimelineDragCoordinator` state) relies entirely on gesture `.onEnded` callbacks with no `.onDisappear`
safety net, so a mid-gesture view teardown (row removed/reordered by an unrelated data refresh while being
dragged) can permanently freeze the entire timeline's scrolling. No production code modified. Coverage
table updated.

Remaining unreviewed: `ExecutiveAssistantSheet`, `ExecutivePlanningConversationView`, `ExecutiveCapacityCard`,
`LifeGapsCard`, `BriefingModuleInsightsCard`, `ChiefOfStaffBriefingHeader`, `TimelineDragTimeMeter`,
`TodayCompactMetricsStrip`, `TodayEndOfDayJournalCard`, Brain, Settings, Shared components, macOS shell,
UIKit bridges.

Ready for Wave 10 whenever you say "wave 10."

---

## Wave 10 â€” Briefing (Executive Capacity/Life Gaps cards + Assistant sheet voice keepalive)

**Reviewed:** `ExecutiveCapacityCard.swift` (full, 251 lines), `LifeGapsCard.swift` (full, 84 lines) â€”
no functional defects found in either (both are presentation-only, driven entirely by immutable input
models with no independent state-sync hazards). `ExecutiveAssistantSheet.swift` (full, 77 lines) â€” one
confirmed defect below.

## [MEDIUM] â€” Dismissing the assistant sheet while a voice-mode request is still processing leaves the voice session keepalive stuck active forever

**Category:** Lifecycle interruption / Stuck resource
**Feature:** Executive Assistant sheet ("Ask" conversation), voice input mode
**File:** `Apps/LookAfter-iOS/Views/Briefing/ExecutiveAssistantSheet.swift`, lines 46-64

**Expected behavior:** `VoiceSessionKeepAlive.begin("planning-voice-processing")` /
`.end("planning-voice-processing")` should be perfectly paired â€” any voice-mode processing session that
begins a keepalive token must eventually end it, even if the sheet is dismissed mid-processing.

**Actual behavior:** The keepalive pairing is driven solely by
`.onChange(of: planningVM.isProcessing)` (lines 58-64): `begin` fires when processing starts in voice mode,
`end` fires when processing stops. The toolbar's "Done" button (lines 46-55) calls
`speechManager.stopListening()` and `dismiss()` â€” it does **not** call
`VoiceSessionKeepAlive.end("planning-voice-processing")`, and there is no `.onDisappear` modifier anywhere
in the view to catch this case either. If the user taps "Done" while `planningVM.isProcessing` is still
`true` (voice request in flight), the sheet is torn down before `isProcessing` ever flips back to `false`,
so the `.onChange` that would call `.end(...)` never fires.

**Trigger / Reproduction:**
```text
1. Open the Executive Assistant sheet, switch to voice input mode, and submit a request
   (planningVM.isProcessing becomes true, VoiceSessionKeepAlive.begin("planning-voice-processing") fires).
2. Before the response finishes processing, tap "Done" in the toolbar.
3. speechManager.stopListening() and dismiss() run; the view disappears.
4. planningVM.isProcessing later flips to false in the background (or never does, if the in-flight
   request is abandoned), but the sheet's .onChange(of: planningVM.isProcessing) can no longer fire since
   the view no longer exists.
5. VoiceSessionKeepAlive's "planning-voice-processing" token is never ended â€” the keepalive leaks for the
   remainder of the app session (or until some unrelated code path happens to call .end with that same key).
```

**Root Cause:** Keepalive begin/end pairing is entirely `.onChange`-driven with no `.onDisappear`/dismiss-time
cleanup, so any dismissal that races ahead of the `isProcessing` transition leaks the keepalive token.

**User Impact:** Silent resource leak â€” depending on what `VoiceSessionKeepAlive` controls (e.g. keeping
the audio session / microphone-adjacent hardware active, preventing device sleep, or holding a
`AVAudioSession` category), this can manifest as unexpected battery drain, the screen not auto-locking, or
audio session conflicts with other app features until the process is restarted.

**Confidence:** Medium. The missing cleanup path is directly confirmed in code; the exact downstream effect
depends on `VoiceSessionKeepAlive`'s implementation (not inspected in this wave), which could not be
verified as being idempotent/self-expiring.

---

## Wave 10 summary

**Reviewed:** `ExecutiveCapacityCard.swift`, `LifeGapsCard.swift` (no defects â€” pure presentation), and
`ExecutiveAssistantSheet.swift` (1 new confirmed MEDIUM bug).

**[MEDIUM]** â€” `ExecutiveAssistantSheet`'s "Done" button can dismiss the sheet while a voice-mode request
is still processing, without ever calling `VoiceSessionKeepAlive.end("planning-voice-processing")` â€” the
pairing relies solely on an `.onChange(of: isProcessing)` that can't fire once the view is gone, leaking the
keepalive token for the rest of the app session.

No production code modified. Coverage table updated.

Remaining unreviewed: `ExecutivePlanningConversationView`, `BriefingModuleInsightsCard`,
`ChiefOfStaffBriefingHeader`, `TimelineDragTimeMeter`, `TodayCompactMetricsStrip`,
`TodayEndOfDayJournalCard`, Brain, Settings, Shared components, macOS shell, UIKit bridges.

Ready for Wave 11 whenever you say "wave 11."

---

## Wave 11 â€” Briefing (Planning conversation voice/text input area)

**Reviewed:** `ExecutivePlanningConversationView.swift` (full, 680 lines) â€” quick actions, conversation
turns, negotiation strip, and all three input-area variants (`voicePrimaryInput`, `textPrimaryInput`,
`neutralInput`). `TodayCompactMetricsStrip.swift` and `TodayEndOfDayJournalCard.swift` (both full) reviewed
with no functional defects found.

## [MEDIUM] â€” `neutralInput`'s mic button fires the "start voice" callback even when the tap is actually stopping an in-progress recording

**Category:** Callback misuse / Inconsistent state signaling
**Feature:** Planning conversation input area, neutral (no locked modality) state
**File:** `Apps/LookAfter-iOS/Views/Briefing/ExecutivePlanningConversationView.swift`, lines 569-602
(`neutralInput`), contrasted with lines 489-549 (`voicePrimaryInput`)

**Expected behavior:** `onStartVoice()` is a callback meant to signal "voice input is starting" (per its
name, and confirmed by its only other call site in `voicePrimaryInput` at line 524, which calls it solely
in the `else` branch â€” i.e., only when the mic is *not* currently listening and is about to start).

**Actual behavior:** In `neutralInput`'s mic button action (lines 571-586), `onStartVoice()` is called
**unconditionally**, before the `if speechManager.isListening { ... } else { ... }` branch even executes:
```swift
PremiumIconButton(speechManager.isListening ? "stop.circle.fill" : "mic.fill") {
    HapticManager.impact(.medium)
    onStartVoice()
    Task {
        if speechManager.isListening {
            speechManager.stopListening()
            ...
        } else {
            planningVM.setInputMode(.voice)
            await speechManager.startListening()
        }
    }
}
```
So tapping this button while `speechManager.isListening == true` (i.e., the user is stopping their
recording) still fires `onStartVoice()` â€” the exact same callback that should only fire when starting.

**Trigger / Reproduction:**
```text
1. From the neutral (unlocked-modality) input state, tap the mic button to start voice capture
   (isListening becomes true; onStartVoice() correctly fires once).
2. Tap the same mic button again to stop recording and submit the transcript.
3. onStartVoice() fires again â€” even though this tap is a stop/submit action, not a start action.
```

**Root Cause:** The call to `onStartVoice()` was hoisted outside the `if/else` that distinguishes
start-vs-stop, unlike the otherwise-parallel logic in `voicePrimaryInput` where the same callback is
correctly scoped to only the "start" branch.

**User Impact:** Depends on what the call site wires `onStartVoice` to (not inspected in this wave â€” likely
UI-state or analytics/telemetry side effects in the parent `TodayView`/`ExecutiveAssistantSheet`). At
minimum this double-fires a "voice started" signal on every stop action from the neutral input state,
which could cause incorrect analytics, spurious UI transitions, or redundant state resets depending on the
callback's implementation.

**Confidence:** Medium-High. The asymmetry between `neutralInput` and `voicePrimaryInput`'s handling of the
same callback is directly confirmed in code; the exact downstream user-visible effect depends on the
callback's wiring at the call site, which wasn't traced in this wave.

---

## Wave 11 summary

**Reviewed:** `ExecutivePlanningConversationView.swift` (full â€” 1 new confirmed MEDIUM bug),
`TodayCompactMetricsStrip.swift`, `TodayEndOfDayJournalCard.swift` (both full â€” no defects found).

**[MEDIUM]** â€” `neutralInput`'s mic button calls `onStartVoice()` unconditionally on every tap, including
taps that stop an in-progress recording â€” inconsistent with the otherwise-parallel `voicePrimaryInput`,
which correctly scopes the same callback to only the "start" branch.

No production code modified. Coverage table updated.

Remaining unreviewed: `BriefingModuleInsightsCard`, `ChiefOfStaffBriefingHeader`, `TimelineDragTimeMeter`,
`DailyBriefingCards`, `DailyBriefingCustomizationView`, `BriefingCardContainer`, Brain, Settings, Shared
components, macOS shell, UIKit bridges.

Ready for Wave 12 whenever you say "wave 12."

---

## Wave 12 â€” Briefing (Module insights card, Chief-of-Staff header, timeline drag time meter)

**Reviewed:** `BriefingModuleInsightsCard.swift` (full, 71 lines), `ChiefOfStaffBriefingHeader.swift` (full,
112 lines), `TimelineDragTimeMeter.swift` (full, 72 lines) â€” plus a cross-check of `TimelineDragHint`'s
`dismissedKey` wiring in `TodayView.swift` (`showsDragHint` / `onScheduleDragCommitted` at lines 1078-1125).

**Result:** No functional defects found in any of the three files. All are presentation-only components
driven by immutable/observed inputs with no independent state-sync hazards: `BriefingModuleInsightsCard`
has a straightforward loading/empty/populated branch with no state; `ChiefOfStaffBriefingHeader`'s
reveal-animation guard (`animateReveal`) correctly no-ops on repeated identical narrative text and handles
`reduceMotion`; `TimelineDragTimeMeter` is a pure derived-label renderer with proper `nil`-guarding. The
`TimelineDragHint.dismissedKey` `@AppStorage` flag is correctly set in exactly one place
(`onScheduleDragCommitted` in `TodayView`) after a real drag commit, and correctly gates `showsDragHint`.

No production code modified. Coverage table updated.

Remaining unreviewed: `DailyBriefingCards`, `DailyBriefingCustomizationView`, `BriefingCardContainer`,
Brain, Settings, Shared components, macOS shell, UIKit bridges.

Ready for Wave 13 whenever you say "wave 13."

---

## Wave 13 â€” Briefing (Card container primitives, customization view, DailyBriefingCards.swift full pass)

**Reviewed:** `BriefingCardContainer.swift` (full, 88 lines â€” no defects, pure presentation),
`DailyBriefingCustomizationView.swift` (full, 98 lines â€” no defects, pin/hide/reorder bindings all correctly
wired to `DailyBriefingViewModel`), `DailyBriefingCards.swift` (full, 1021 lines â€” every card type), cross-
referenced with `DailyBriefingViewModel.buildMission` (lines 773-825) and the `BriefingMissionData` /
`BriefingMissionTask` model (`DailyBriefingModels.swift` lines 286-322).

**[MEDIUM]** â€” `BriefingMissionCard` (in `DailyBriefingCards.swift`) silently drops pending (incomplete)
tasks past the 6th with no indicator, while completed tasks past the 5th correctly show a
"+N more completed" label.

**Root cause in `DailyBriefingViewModel.buildMission`:**
```swift
let visibleCompleted = Array(dedupedCompleted.prefix(completedCap))   // cap = 5
let hiddenCompleted = max(0, dedupedCompleted.count - visibleCompleted.count)

var items: [BriefingMissionTask] = visibleCompleted.map { missionTask(from: $0, isCompleted: true) }
items += pending.prefix(6).map { missionTask(from: $0, isCompleted: false) }   // no cap tracking at all
```
`hiddenCompletedCount` is only ever derived from the completed-task truncation. If `pending.count > 6`,
those extra incomplete tasks are cut from `items` with **zero** count tracked or surfaced anywhere in the
model or view.

**Downstream effect in the view (`BriefingMissionCard.body`):** `completionPercent` (shown via the
progress bar and "`X`% of today's list done" text) is computed in the view model from the *full*
`totalScheduled` set (all dedup'd completed + active tasks, not just the visible slice), so the percentage
is accurate â€” but the task *list* underneath silently shows only 6 of e.g. 10 pending tasks with no
"+4 more" affordance, while the completed-side truncation right above it does show such an affordance.
This inconsistency makes it look like the list is complete/exhaustive when it isn't, and a user with more
than 6 open tasks for the day has no way to see the rest from this card (no "view all" style overflow
notice â€” the `onAddTask`/"All tasks" button exists, but doesn't communicate that items are hidden).

**Trigger / Reproduction:**
```text
1. Have 7+ active (non-completed) tasks scheduled/reconciled for today.
2. Open the Daily Briefing / Today mission card.
3. Observe: only 6 pending tasks render; the 7th+ are simply absent, no "+N more" label,
   even though the completion percentage above still factors in the total (e.g. shows 30% correctly
   while only showing 6 of 10 possible task rows).
```

No production code modified. Coverage table updated.

**Wave 13 also closes out the Briefing module.** Remaining unreviewed areas across the whole repo:
Brain, Settings, Shared components, macOS shell, UIKit bridges.

Ready for Wave 14 whenever you say "wave 14."

---

## Wave 14 â€” Brain (voice orb dashboard)

**Reviewed:** `BrainDashboardView.swift` in full (425 lines) â€” voice orb state machine, proactive welcome
scheduling, and the `startListening`/`sendVoiceMessage`/`handleOrbTap` turn-taking flow.

**Result:** The voice turn-taking state machine itself is solid â€” `sendVoiceMessage` correctly pairs
`VoiceSessionKeepAlive.begin`/`.end` via `defer` (unlike the Wave 10 `ExecutiveAssistantSheet` leak), and
mid-flight cancellation via `cancelInFlightVoiceTurn` is properly guarded by the `orbState == .thinking`
re-check after `await` resumes.

**[LOW-MEDIUM]** â€” The proactive voice welcome (an unprompted spoken greeting fired ~3.5s after the Brain
tab appears idle) can replay on every single visit to the tab within a session, not just once.
`scheduleProactiveWelcome()` unconditionally resets `didDeliverProactiveWelcome = false` on every
`.onAppear`, and `.onDisappear` only cancels the pending `Task` â€” it never marks the welcome as delivered
or otherwise remembers that a welcome already fired earlier in the session. So a user who taps into Brain,
switches to another tab, and taps back into Brain (repeated within the same app session) will hear the
proactive greeting again each time they idle on the tab for 3.5s, which reads as the app "restarting" the
conversation instead of a one-time icebreaker â€” especially awkward since `hasPriorVoiceConversation` is
passed in from the parent specifically to vary this message's copy for returning users, implying the
intent was a once-per-session (or once-per-cold-launch) greeting, not a once-per-tab-visit one.

No production code modified. Coverage table updated.

Remaining unreviewed: Settings, Shared components, macOS shell, UIKit bridges, ADHD, Auth, Capture, Coach,
Health, Inbox, Insights, Modules, Navigation, Onboarding, Review, Tour.

Ready for Wave 15 whenever you say "wave 15."

---

## Wave 15 â€” Settings (SettingsView.swift full pass)

**Reviewed:** `SettingsView.swift` in full (1077 lines) â€” account/appearance/notifications/accountability/
help/profile/AI-config/voice/preferences/features/health-sync/cycle-tracking/widgets/life-profile/energy/
about sections, plus the `showHealthVerification` sheet and all `@AppStorage`/`@State` bindings.

**[MEDIUM]** â€” In the `showHealthVerification` sheet's `HealthStatusBanner` primary-action handler, the
`onOpenSettings` callback is a literal no-op:

```swift
HealthStatusActionHandler.perform(
    status.primaryAction,
    onConnect: { showHealthVerification = false },
    onSync: { Task { ... } },
    onOpenSettings: { }   // <-- does nothing
)
```

`HealthStatusActionHandler.perform` dispatches `.openAppSettings` straight to this closure
(`HealthStatusBanner.swift` lines 201-202). `HealthConnectionStatusResolver.resolve` returns
`primaryAction: .openAppSettings` with label "Open Settings" specifically for the `.trackingOff` case
("Health tracking is turned off... Open Settings in Look After, turn on Health Tracking under Features").
Since this sheet is *itself* reached from within Settings (`showHealthVerification = true`, triggered by
tapping "What's wrong?" under Health Data Sync), and Health Tracking is a toggle a few sections above in
the very same `SettingsView`, tapping "Open Settings" here does nothing â€” no dismiss, no scroll, no
navigation back to the Features toggle. The user is told to flip a setting and given a button captioned
"Open Settings" that is inert.

For comparison, sibling call sites correctly wire this same case: `HealthDetailView` uses
`onOpenSettings: { dismiss() }` and `DailyBriefingView` forwards a real `onOpenSettings` closure from its
parent.

**Trigger / Reproduction:**
```text
1. Turn off "Health Tracking" under Settings â†’ Features.
2. (Health section collapses since `enableHealth` gates it â€” see Wave 15 note below on reachability.)
3. If reached via a state where `connectionStatus.kind == .trackingOff` and "What's wrong?" is visible,
   tap it, then tap "Open Settings" in the sheet: nothing happens.
```
**Reachability caveat:** `Section` content for Health Data Sync (including "What's wrong?") is only shown
when `if enableHealth` (line 571) is true, but `.trackingOff` is only returned when `!input.isHealthEnabled`
(i.e. `enableHealth == false`). So under the *current* toggle wiring this specific status/button pairing
may not be reachable from `SettingsView` today â€” the dead `onOpenSettings` closure is nonetheless a latent
bug (matches the pattern of stale copy-pasted handler wiring) and would surface immediately if
`connectionStatus` is ever computed from a different enable source, or if `enableHealth` becomes non-@State
so the section stays visible transiently during the toggle-off animation frame.

No production code modified. Coverage table updated.

Remaining unreviewed: Shared components, macOS shell, UIKit bridges, ADHD, Auth, Capture, Coach, Health,
Inbox, Insights, Modules, Navigation, Onboarding, Review, Tour.

Ready for Wave 16 whenever you say "wave 16."

---

## Wave 16 â€” Shared components (ADHDFloatingDockView, GeneratedTasksReviewView, HealthSyncProgressView, TaskActionButton, TaskCardView header, ToastView, VoiceCaptureView)

**Reviewed:** `ADHDFloatingDockView.swift`, `TaskActionButton.swift`, `ToastView.swift` (incl. `UndoToastModifier`),
`VoiceCaptureView.swift`, `HealthSyncProgressView.swift` (incl. `HealthConnectSheet`, `HealthVerificationReportView`)
â€” all full, no defects found (pure presentation / correctly-scoped state). `TaskCardView.swift` header/init
reviewed (full body deferred). `GeneratedTasksReviewView.swift` full â€” 1 new confirmed bug.

**[MEDIUM]** â€” `GeneratedTasksReviewView.syncKeptIDsWithReviewableTasks()` cannot distinguish "user
intentionally unchecked every task" from "selection not seeded yet," and silently re-checks everything in
the former case:

```swift
private func syncKeptIDsWithReviewableTasks() {
    let valid = Set(reviewableTasks.map(\.id))
    keptTaskIDs = keptTaskIDs.intersection(valid)
    if keptTaskIDs.isEmpty, !valid.isEmpty {
        keptTaskIDs = valid   // re-selects everything, discarding an intentional "keep none"
    }
}
```

This runs on every `.onChange(of: tasksVM.tasks.map(\.id))` â€” i.e. whenever the reviewable task ID set
changes for *any* reason (task added/removed/regenerated elsewhere while this review sheet is open). If a
user has already unchecked all the generated tasks (a deliberate "discard everything" choice,
`keptTaskIDs == []`) and then anything shifts the underlying task ID list before they tap "Looks good" â€”
e.g. a background AI regeneration, or editing one task via `editingTask` sheet which itself can add/remove
tasks â€” every task silently flips back to checked with no visual undo cue, re-adding tasks the user just
explicitly rejected.

No production code modified. Coverage table updated.

Remaining unreviewed: `TaskCardView.swift` full body, `ActivityView`, `LifeProfileImportView`,
`StructuredLifeProfileEditor`, `Legacy/EnergyRingView`, macOS shell, UIKit bridges, ADHD, Auth, Capture,
Coach, Health, Inbox, Insights, Modules, Navigation, Onboarding, Review, Tour.

Ready for Wave 17 whenever you say "wave 17."

---

## Wave 17 â€” Shared components (TaskCardView full body, ActivityView, LifeProfileImportView, StructuredLifeProfileEditor, Legacy/EnergyRingView)

**Reviewed:** `TaskCardView.swift` full body (list/focus-stack cards, checkbox/expand controls, action button
grid), `ActivityView.swift` (UIKit share-sheet bridge), `LifeProfileImportView.swift` (incl.
`LifeModelSummaryView`), `StructuredLifeProfileEditor.swift` (incl. `KeyboardDismissToolbarModifier`),
`Legacy/EnergyRingView.swift` â€” all full.

**Result:** No new functional defects found. All five are correctly-scoped presentation components with
appropriately-wired bindings, no independent state-sync hazards, and no dead/no-op action closures.

No production code modified. Coverage table updated. **This closes out the Shared components module** (see
Wave 16 for the one confirmed bug, `GeneratedTasksReviewView`).

Remaining unreviewed: macOS shell, UIKit bridges, ADHD, Auth, Capture, Coach, Health, Inbox, Insights,
Modules, Navigation, Onboarding, Review, Tour.

Ready for Wave 18 whenever you say "wave 18."

---

## Wave 18 â€” ADHD emergency & decider components (ADHDViews.swift, DecideForMeView, PhysiologicalResetView)

**Reviewed:** `EmergencyModeView`, `FocusSessionView`, `BodyDoublingView`, `TaskInitiationView` (all in
`ADHDViews.swift`), `DecideForMeView.swift`, `PhysiologicalResetView.swift` â€” all full.

**[MEDIUM]** â€” `PhysiologicalResetView.phaseText` is initialized once to `"Inhale Deeply..."` and never
updated for the full 60-second session, even though the breathing circle visibly animates through
repeating 4-second inhale/exhale cycles (`scale` oscillates 0.6 â†” 1.1 via `.repeatForever(autoreverses:
true)`). A user following the on-screen instruction during the "exhale" half of every cycle is told to
"Inhale Deeply" instead, which directly undermines the breathing-pacing purpose of this nervous-system
regulation exercise. There is no timer-driven or animation-driven logic anywhere in the view that ever
mutates `phaseText`.

**[LOW]** â€” Same view: when `secondsRemaining` reaches 0, the `onReceive(timer)` handler calls
`HapticManager.notification(.success)` and `dismiss()` on every subsequent tick until the dismissal actually
takes effect. If SwiftUI's dismissal is delayed by even one more 1-second timer tick (e.g. during a
transition/animation), the success haptic fires more than once for a single session completion.

No production code modified. Coverage table updated.

Remaining unreviewed: macOS shell, UIKit bridges, Auth, Capture, Coach, Health, Inbox, Insights, Modules, Navigation, Onboarding, Review, Tour.

Ready for Wave 19 whenever you say "wave 19."

---

## Wave 19 â€” Auth & Capture (AuthView, CaptureComposerView)

**Reviewed:** `AuthView.swift` (SSO, email/password, guest sign-in, license-prompt handoff), `CaptureComposerView.swift` (incl. `ExecutiveCaptureSheet`, `CaptureSaveChrome`) â€” both full.

**[HIGH]** â€” `AuthView.performGuestSignIn()` calls `try? await firebase.signInAnonymously()` and unconditionally proceeds to show the "Welcome back!" success overlay and invoke `onGuestContinue?()` / `dismiss()` regardless of whether anonymous sign-in actually succeeded. Unlike every other auth path in this file (`performAppleSignIn`, `performGoogleSignIn`, `performAuth`), which all route failures through `failAuth(error)` to surface an error message, guest sign-in has no `catch` branch at all â€” a failed anonymous auth (e.g. disabled in Firebase console, network error) is silently swallowed and the user is told they're signed in as "Guest" and taken to the app, potentially in an unauthenticated state.

**[LOW]** â€” `CaptureComposerView`'s `.onChange(of: speechManager.transcript)` unconditionally overwrites `text` with the latest transcript whenever it's non-empty. If the user manually edits the text field while still listening (e.g. correcting a misheard word), the next transcript update silently stomps their edit with the raw speech-to-text output.

No production code modified. Coverage table updated.

Remaining unreviewed: macOS shell, UIKit bridges, Coach, Health, Inbox, Insights, Modules, Navigation, Onboarding, Review, Tour.

Ready for Wave 20 whenever you say "wave 20."

---

## Wave 20 â€” Coach & Health (AICoachView, CycleDashboardView, CycleQuickLogSheet, ManualSleepSheet)

**Reviewed:** `AICoachView.swift` (chat scroll, suggestion chips, input bar), `CycleDashboardView.swift` (incl. `FlowLayout` sizing math), `CycleQuickLogSheet.swift`, `ManualSleepSheet.swift` â€” all full.

**Result:** No functional defects found. All four are correctly-wired presentation/interaction components â€” chat auto-scroll, chip toggles, sliders, and disabled-state gating all behave as expected with no stale state or dead closures.

No production code modified. Coverage table updated.

Remaining unreviewed: macOS shell, UIKit bridges, Inbox, Insights, Modules, Navigation, Onboarding, Review, Tour.

Ready for Wave 21 whenever you say "wave 21."

---

## Wave 21 â€” Inbox & Insights (InboxView, InsightsDashboardView)

**Reviewed:** `InboxView.swift` (incl. `InboxItemCard`), `InsightsDashboardView.swift` (incl. `AnalyticsTrendChart`) â€” both full. Cross-checked `InsightsViewModel.selectedTimeframe` (confirmed `didSet` triggers reload â€” no missing-refresh bug on timeframe switch).

**[LOW]** â€” Same pattern as Wave 19's `CaptureComposerView`: `InboxView`'s `.onChange(of: speechManager.transcript)` unconditionally overwrites `captureText`, silently discarding manual edits made while still listening. Not re-logged as a separate root cause, noting for completeness since it's the same shared-pattern bug reproduced in a second location.

**Result:** No new distinct functional defects found in either file â€” `InboxView`'s review/routed filtering, delete/process actions, and `InsightsDashboardView`'s timeframe switching, cache banners, and personalization sync are all correctly wired.

No production code modified. Coverage table updated.

Remaining unreviewed: macOS shell, UIKit bridges, Modules, Navigation, Onboarding, Review, Tour.

Ready for Wave 22 whenever you say "wave 22."

---

## Wave 22 â€” Modules & Navigation (AllModulesGridView, ModuleViews, LookAfterBottomNav)

**Reviewed:** `AllModulesGridView.swift` (full), `ModuleViews.swift` (full, 1265 lines â€” `AIMemoryView`, `FinanceBillsView`/`AddBillSheet`, `HydrationNutritionView`, `ShoppingInventoryView`/`AddShoppingItemSheet`, `RelationshipsView`/`ContactPickerViewController`, `ReflectionJournalView`), `LookAfterBottomNav.swift` (full, incl. tab bounce/zoom-morph modifiers).

**Result:** No new functional defects found. `ReflectionJournalView` uses `VoiceCaptureView` in a way that binds directly to `entryText` (not via a separate transcript `.onChange`), so it does not reproduce the Wave 19/21 transcript-overwrite pattern. Async AI calibration, bill/shopping/contact CRUD flows, and tab selection/haptics are all correctly wired with proper `try?` fallback messaging where AI calls can fail.

No production code modified. Coverage table updated.

Remaining unreviewed: macOS shell, UIKit bridges, Onboarding, Review, Tour.

Ready for Wave 23 whenever you say "wave 23."

---

## Wave 23 â€” Onboarding & Review (OnboardingView, WeeklyReviewView)

**Reviewed:** `OnboardingView.swift` (full, 997 lines â€” all 11 `StartStep` cases, forward/back navigation, health/cycle gating, task generation handoff), `WeeklyReviewView.swift` (full, incl. `MetricTile`) â€” both full.

**[MEDIUM]** â€” `OnboardingView.organizeProfileWithAI()` (AI-polish the structured life profile via `GLMService`) is dead code: no button or control in `profileStep` (or anywhere else in the view) calls it, and its `isOrganizing`/`organizeError` state is never read by the UI. The "organize with AI" capability is fully implemented but unreachable â€” users only get the raw `LifeProfileComposer.compile` text with no AI-cleanup path during onboarding.

**Result:** No other defects found. Step progression math (`goForward`/`goBack`/`canContinue`), health/cycle conditional gating, and `WeeklyReviewView`'s empty-state vs. populated-state branching are all correctly wired.

No production code modified. Coverage table updated.

Remaining unreviewed: macOS shell, UIKit bridges, Tour.

Ready for Wave 24 whenever you say "wave 24."

---

## Wave 24 â€” Feature Tour (AppFeatureTourCoordinator, AppFeatureTourOverlay, AppFeatureTourAnchor, AppFeatureTourModels)

**Reviewed:** `AppFeatureTourCoordinator.swift`, `AppFeatureTourOverlay.swift`, `AppFeatureTourAnchor.swift`, `AppFeatureTourModels.swift` â€” all full.

**[MEDIUM]** â€” Every step in `AppFeatureTourStep.all` sets `allowsTargetInteraction: false`, and `AppFeatureTourOverlay`'s full-screen scrim only becomes hit-test-transparent when `allowsTargetInteraction` is true (`.allowsHitTesting(!coordinator.currentStep.allowsTargetInteraction)`). Since no step ever sets it `true`, the scrim always intercepts touches everywhere on screen, including over the spotlighted target â€” tapping it only fires `coordinator.advance()` via the scrim's tap gesture, never the real control underneath. Several step messages explicitly instruct the user to interact with the highlighted element (e.g. `"assistant"`: *"Tap Plan in the Today header to replan your day. Talk or type â€” it reshapes your schedule with you."*; `"capture"`: implies tapping the Capture tab), but doing so during the tour just advances/dismisses the tour step instead of performing the described action. The spotlight cutout in `SpotlightCutoutShape` is purely a visual mask on the dimming layer, not a hit-test hole, so this isn't recoverable by the cutout alone â€” `allowsTargetInteraction` needs to actually be `true` on at least the steps whose copy tells the user to tap something.

**Result:** No other defects â€” anchor registry sizing/pruning, keyboard-frame tracking, stuck-step auto-skip persistence (`AppFeatureTourStore`), and layout placement math are all correctly wired.

No production code modified. Coverage table updated. **This closes out the Tour module** (macOS shell and UIKit bridges directories were not found to exist as separate targets in this repository layout â€” the app is iOS-only per `Apps/LookAfter-iOS`).

Ready for Wave 25 whenever you say "wave 25."
