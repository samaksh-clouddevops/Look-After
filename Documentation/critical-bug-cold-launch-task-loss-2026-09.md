# CRITICAL Bug — Cold-Launch Task Creation Wipes Entire Local Task Database

**Status:** CONFIRMED FUNCTIONAL BUG (verified, adversarially re-checked)
**Severity:** CRITICAL — silent, unrecoverable data loss
**Feature:** Task persistence / app cold-launch lifecycle

## Files Involved
- `Packages/LookAfterData/Sources/LookAfterData/Repositories/Repositories.swift`
- `Packages/LookAfterData/Sources/LookAfterData/Persistence/TaskSQLiteStore.swift`
- `Apps/LookAfter-iOS/Experience/AppShellState.swift`

## Exact Locations
- `TaskRepository.allLocalTasks()` — Repositories.swift:215-225
- `TaskRepository.saveLocally()` — Repositories.swift:202-211
- `TaskRepository.persistAllLocally()` — Repositories.swift:227-231
- `TaskSQLiteStore.replaceAll()` — TaskSQLiteStore.swift:153-158
- `AppShellState.runBootstrapWork()` — AppShellState.swift:196-220

## Expected Behavior
Creating one new task must never affect any other previously persisted task, regardless of when in the app lifecycle the create happens.

## Actual Behavior
If `TaskRepository.create()`/`update()`/`delete()` is invoked **before** `warmLocalCache()` has completed in the current process, `allLocalTasks()` returns `[]` (the static `cachedAll` is `nil` on every fresh process launch). `saveLocally` then builds a "full task list" containing only the new/edited task and calls `persistAllLocally`, which calls `taskStore.replaceAllAsync(tasks)`. `TaskSQLiteStore.replaceAll` does:

```swift
try TaskRecord.deleteAll(db)   // deletes every row for every user
for task in tasks { try TaskRecord(task: task).insert(db) }  // reinserts only the new list
```

This deletes **every previously persisted task for every user on the device** and replaces the table with just the one task involved in the racing call.

## Trigger
Any code path that calls `taskRepo.create/update/delete` before `TaskStore/TaskRepository.warmLocalCache()` finishes on a cold process.

## Concretely Reachable Path

`AppShellState.runBootstrapWork()`:
```swift
line 202: LookAfterIntentBridge.shared.register(shell: self, userId: userId)   // intents become live NOW
...
line 216: async let taskLoad: Void = tasksVM.loadTasks(userId: userId)        // warmLocalCache starts HERE, concurrently
line 219: _ = await (brainLoad, taskLoad, moduleLoad, inboxLoad)
```

`register()` makes `LookAfterIntentBridge.shared` immediately able to service Siri/Shortcuts/widget intents (e.g. `.capture`) via `enqueueOrPerform` → `perform(action: .capture, ...)` → `shell.inboxVM.routeCapture(...)` → `CaptureRouter.shared.route(...)`, which can create a task/inbox item directly — **before** `taskLoad` (which performs the disk warm-up) has resolved, because they run concurrently and `register()` happens strictly earlier in program order.

## Preconditions
- Fresh process launch (cold start, or resumed-from-terminated state) with existing tasks already stored in `tasks.sqlite`.
- A Siri Shortcut, widget button, or Live Activity action that triggers `LookAfterIntentBridge.perform()` fires in the short window between `register()` and `taskLoad`'s warm-up completing (e.g., user relaunches app via a widget "Capture" tap, or a queued Shortcut runs on launch).

## Reproduction Steps
```text
1. Populate tasks.sqlite with N existing tasks (normal usage over time).
2. Force-quit the app (fully cold process).
3. Trigger a Siri/Shortcuts/widget "Capture" or similar create-path intent at the
   moment the app relaunches, so LookAfterIntentBridge.perform() executes
   concurrently with the very first tasksVM.loadTasks(userId:) call.
4. Open the app normally afterward.
```

## Execution Path
```text
Cold launch → runBootstrapWork()
 → LookAfterIntentBridge.register(shell) [intents now live]
 → (concurrently) intent .capture fires → routeCapture → taskRepo.create(task)
 → TaskRepository.saveLocally(task)
 → allLocalTasks() → cachedAll == nil → returns []
 → persistAllLocally([task]) → taskStore.replaceAllAsync([task])
 → TaskSQLiteStore.replaceAll: DELETE ALL rows, INSERT only [task]
 → (concurrently) tasksVM.loadTasks → warmLocalCache → taskStore.loadAllAsync()
   now reads a table that has already been wiped to a single row
 → all previously existing tasks for all users are gone from disk
```

## Root Cause
`TaskRepository.allLocalTasks()` silently treats "cache not yet warmed" the same as "no tasks exist," and `persistAllLocally` always does a destructive full-table replace rather than an incremental upsert. There is no guard preventing mutation methods (`create`/`update`/`delete`) from running before `warmLocalCache()` resolves, and `LookAfterIntentBridge.register()` is wired before the warm-up `async let` in `runBootstrapWork`.

## User Impact
Silent, unrecoverable loss of all locally stored tasks (across all accounts ever used on that device), triggerable by an ordinary user action (a shortcut/widget tap) at an unlucky moment during app launch. Firestore sync can partially recover data for a signed-in, online user, but any task not currently in Firestore, or a device used offline/guest, loses data permanently.

## Evidence
- `Repositories.swift:215-225` (`allLocalTasks` returns `[]` when uncached — logged as a known/expected condition in DEBUG builds).
- `TaskSQLiteStore.swift:153-158` (`replaceAll` is `deleteAll` + reinsert of only the given list — a full destructive replace, not scoped by user).
- `AppShellState.swift:196-220` shows `register()` (making intents live) strictly precedes the `taskLoad` warm-up `async let`.
- Existing test `TaskStoreTests.testWarmLocalCachePopulatesMemoryWithoutBlockingPath` explicitly exercises "create before warm" and demonstrates `hasWarmedLocalCache` can be false immediately after a `create()` — confirming the maintainers are aware `create()` can run pre-warm, but the test only checks a single-task scenario and does not assert that pre-existing tasks survive.

## Adversarial (Disprove) Pass
- Checked whether `CaptureRouter`/`routeCapture` might itself call `warmLocalCache` first — no such call found in `InboxViewModel.routeCapture`/`quickCapture`.
- Checked whether `LookAfterIntentBridge.enqueueOrPerform` requires the shell to have finished bootstrap — it only requires `shell` to be non-nil and a resolvable `userId`; `shell` is set and `register()` called at line 202, before bootstrap completes.
- Checked whether `warmLocalCache`'s merge logic (`TaskMerge.merge`) could reconstitute the deleted rows — it merges `cachedAll` (in-memory) with a **fresh disk read**; if the destructive `replaceAllAsync` write from the racing `create()` completes before the warm-up's disk read, the disk read itself returns only the single surviving task, so nothing to merge back in. The race window is real (both are async DB operations on the same `DatabaseQueue` with no ordering guarantee relative to each other).
- Could not find any mutex/actor serializing `create()` against `warmLocalCache()` — `TaskRepository` is `@MainActor`, but `warmLocalCache`'s `await taskStore.loadAllAsync()` suspends, allowing another `@MainActor` call (e.g. `create()`, dispatched from a Task) to interleave before it resumes.
- **Conclusion: bug survives the disprove attempt. Retained as CONFIRMED CRITICAL.**

## Confidence
High — the persistence-layer defect (destructive full replace on an unwarmed cache) is unconditionally reachable from code alone; the only variable is the real-world timing window for the intent-based trigger, which is plausible given the exact call ordering in `runBootstrapWork`.

## Recommended Fix
1. Make `persistAllLocally` non-destructive (upsert instead of delete-all+reinsert), **or**
2. Gate all mutation methods behind a guaranteed `await warmLocalCache()` (e.g. an actor-serialized "ensure warm" call at the top of `create`/`update`/`delete`), **and**
3. Reorder `runBootstrapWork` so `LookAfterIntentBridge.register()` happens only after `taskLoad` completes (or queue intents until then).

## Suggested Regression Test
```text
Test: TaskRepository_CreateBeforeWarmDoesNotDeleteExistingDiskData
1. Write N tasks directly via TaskSQLiteStore (simulating prior session data).
2. Create a fresh TaskRepository instance, call TaskRepository.invalidateLocalCache()
   to simulate a cold process (cachedAll == nil).
3. Call repo.create(newTask) WITHOUT calling warmLocalCache() first.
4. Await outstanding replaceAllAsync work, then read taskStore.loadAllAsync() directly.
Expected: all N original tasks + newTask are present.
Currently: only newTask is present — test should fail against current code,
confirming the bug, and pass once persistAllLocally becomes non-destructive
or create()/update()/delete() are guarded to warm first.
```
