# Q3 architecture wave 1 — Composition + de-godding

StoreKit/licensing ignored per product direction.

## Shipped

1. **`AppComposition`** (`LookAfterFeatures/Composition/`) — injectable factory for Tasks / Inbox / Briefing / ADHD / Modules / ContextOrchestrator; `AppShellState` constructs through it.
2. **`InboxViewModel`** moved out of `TasksViewModel.swift` into `Inbox/ViewModels/` (~170 lines off the god file).
3. **`TaskUndoController`** — undo toast auto-expire collaborator (same pattern as `ScheduleMutationService`).
4. **`ShellSurfaceSync`** — timeline debounce + widget / Live Activity / Focus Filter sync extracted from `AppShellState`.
5. Sheet router deferred — nested `ObservableObject` bindings stalled Swift type-checking on `LookAfterRootCanvas`; sheet `@Published` stays on shell for now.

## Next slices (same epic)

- Extract schedule reconcile / life-commitment blocks from `TasksViewModel`
- Extract bootstrap / factory-reset / proactive refresh from `AppShellState`
- Observation migration (`@Observable`) after seams stabilize
- Fill more of Composition for test doubles (fake `TaskStoring`)

## Tests

- `AppCompositionTests` — composition builds VMs
