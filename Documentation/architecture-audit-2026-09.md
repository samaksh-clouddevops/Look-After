# LookAfter Repository Architecture & Bug Audit

_Date: 2026-09-12_

## 1. Executive Summary

LookAfter is a modular Swift Package–based iOS/macOS app (`LookAfterCore`, `LookAfterData`, `LookAfterAI`, `LookAfterFeatures`, `LookAfterHealth`, `LookAfterIntegrations`, `ExecutiveBrain`) composed at the app layer via `AppComposition` / `AppShellState`. The module boundaries are a good foundation, but three systemic problems dominate the risk profile:

1. **A pervasive `.shared` singleton culture** (`TaskStore.shared`, `GLMService.shared`, `GLMKeyManager.shared`, `TimelineService.shared`, `AccountIdentity.shared`, `BackgroundAnalyticsService.shared`, `FactoryResetManager.shared`, `NotificationCoordinator.shared`, `WidgetSyncService.shared`, `LiveActivityManager.shared`, `CaptureRouter.shared`, `LookAfterIntentBridge.shared`, `AccountabilityScheduler`, `ResumeEngine.shared`, etc.) creates hidden global mutable state and implicit coupling that undermines the otherwise-clean `AppComposition` DI seam.
2. **`AppShellState` is a 1,129-line God Object** that owns bootstrap, factory reset, calendar sync, widget sync, notification wiring, context refresh debouncing, and cross-module orchestration — with no `deinit` to tear down two `NotificationCenter` observers it registers.
3. **User-scoped mutable singletons** (notably `TaskStore.lastUserId`) create real risk of cross-account data leakage during account switching, since the "current user" is tracked as instance state on a shared singleton rather than being threaded explicitly through every call.

None of these are "the app is unusable" bugs today (the code shows real engineering care — debouncing, cancellation guards, suppression depths), but they are exactly the class of problems that turn into **hard-to-reproduce production bugs as the team and codebase grow**: race conditions on account switch, stale AI usage data, notification-based coupling that's invisible in code review, and testability collapse due to singleton dependencies baked into "testable" classes.

## 2. Repository Architecture Overview

```text
Apps/
  LookAfter-iOS      — SwiftUI app target, composition root (AppShellState, ContentView)
  LookAfter-macOS    — separate app target, its own composition
  LookAfterWidget    — WidgetKit extension (shares persistence via App Group)
Packages/
  LookAfterCore      — models, protocols, persistence primitives, utilities (35 subfolders — very broad)
  LookAfterData       — repositories/stores (TaskStore, TaskSQLiteStore, TaskRepository)
  LookAfterAI         — GLMService (LLM networking), key management, prompts
  LookAfterFeatures   — ViewModels, composition (AppComposition), Timeline, orchestration
  LookAfterHealth     — HealthKit integration
  LookAfterIntegrations — Calendar/Email/etc. integrations
  ExecutiveBrain      — deterministic decision engine (no LLM, no SwiftUI) — good separation
services/auth-proxy, firebase/functions — backend-adjacent code
```

`LookAfterCore` is used by every other package — it is the lowest layer, but its 35 subdirectories indicate **"Core" has become a dumping ground** rather than a genuine kernel — a common precursor to circular-dependency pressure and unclear ownership as the app grows.

## 3. Architecture Map

```text
SwiftUI Views
   ↓ @EnvironmentObject
AppShellState (God Object, @MainActor, ObservableObject)
   ├─ owns: AppComposition (DI seam — good)
   ├─ owns: TasksViewModel, LifeModulesViewModel, ADHDViewModel, DailyBriefingViewModel,
   │        InboxViewModel, BrainViewModel, ContextOrchestrator, ContinueSessionController
   ├─ reaches around DI into: FactoryResetManager.shared, BackgroundAnalyticsService.shared,
   │        BackgroundAnalyticsScheduler.shared, WidgetSyncService.shared, LiveActivityManager.shared,
   │        NotificationCoordinator.shared, CaptureRouter.shared, LookAfterIntentBridge.shared,
   │        ExecutionEnvironmentCoordinator.shared, ResumeEngine.shared, AccountIdentity.shared
   ↓
ViewModels (TaskStore, TimelineService — themselves ALSO singletons via .shared)
   ↓
Repositories (TaskRepository) → TaskSQLiteStore (GRDB dbQueue)
   ↓                                   ↘
GLMService.shared (LLM networking)     UserDefaults / Keychain / JSON file stores
   ↓
GLMKeyManager.shared (NSLock-protected key rotation) → Keychain
```

**Problematic dependency paths:**
- `AppShellState` → 15+ `.shared` singletons directly, bypassing `AppComposition`. Half the app's dependencies are injected, half are reached via global statics — an **inconsistent DI boundary**.
- `TaskStore.shared` and `TimelineService.shared` are `@MainActor` singletons that are also constructor-injectable via `AppComposition`, so production code and tests can accidentally share the same singleton unless every call site overrides the default.

## 4. Critical / High-Severity Findings

### [HIGH] `TaskStore` tracks "current user" as shared mutable instance state on a singleton
**Files:** `Packages/LookAfterData/Sources/LookAfterData/Stores/TaskStore.swift:7,13,33-49,120,161-167`

**Problem:** `TaskStore.shared` has a private `var lastUserId: String`. `delete(_:)` unconditionally uses `lastUserId` (line 120) rather than the id of the task being deleted; `republishAfterMutation` falls back to `lastUserId` whenever the caller passes an empty string.

**Failure Scenario:** User A signs out, User B signs in. Before async bootstrap for B finishes, a still-in-flight `delete(id:)` call queued before sign-out executes using whatever `lastUserId` is at that moment (already `"userB"`). Result: User A's delete gets attributed under User B's id, or vice versa — cross-account data leakage during account switching.

**Root Cause:** No single owner of "current user"; identity is smeared across `AccountIdentity.shared`, `TaskStore.lastUserId`, and ad hoc parameters in `AppShellState`.

**Recommended Fix:** Require explicit `userId` on every mutating call; remove the `lastUserId` fallback. Long-term: introduce a `UserSession` object owning per-user stores, recreated on account switch instead of mutating a shared singleton's internal pointer.

### [HIGH] `AppShellState` God Object with no `deinit`; two `NotificationCenter` observers never removed
**Files:** `Apps/LookAfter-iOS/Experience/AppShellState.swift:37-38,96-120`

**Problem:** `init` registers observers for `.deferralRecoveryScriptReady` and `.analyticsDataDidChange`, storing tokens in `deferralRecoveryObserver`/`taskCompletedObserver`, but no `deinit` removes them.

**Failure Scenario:** Any test harness or preview that constructs multiple `AppShellState` instances accumulates dangling `NotificationCenter` closures (guarded by `[weak self]`, so no crash, but wasted CPU and misleading behavior in tests as stale registrations still fire).

**Recommended Fix:** Add `deinit { NotificationCenter.default.removeObserver(...) }` for both tokens. Long-term: replace ad hoc `NotificationCenter` wiring with typed `AsyncStream`/Combine publishers cancelled in `deinit`.

### [HIGH] Inconsistent DI: `AppComposition` exists but is bypassed by 15+ direct `.shared` references
**Files:** `Packages/LookAfterFeatures/Sources/LookAfterFeatures/Composition/AppComposition.swift:9-27`, `Apps/LookAfter-iOS/Experience/AppShellState.swift` (multiple lines)

**Problem:** `AppComposition`'s own doc comment says "prefer constructing through here instead of ad-hoc `.shared` soup," yet `AppShellState` directly references 15+ singletons (`ExecutionEnvironmentCoordinator`, `WidgetSyncService`, `DeferralRecoveryCoordinator`, `FactoryResetManager`, `BackgroundAnalyticsService/Scheduler`, `LookAfterIntentBridge`, `CaptureRouter`, `CaptureOfflineQueue`, `NotificationCoordinator`, `LiveActivityManager`, `ResumeEngine`, `AccountabilityScheduler`, `NotificationScheduler`, `MedicationStore`, `UserLifeProfileStore`, `LifeModelStore`).

**Impact:** `AppShellState` cannot be unit-tested in isolation; every new engineer must learn "which of the 20 singletons need resetting" (evidenced by the long manual list in `performFactoryReset`/`clearInMemoryState`).

**Recommended Fix:** Extend `AppComposition` to own all cross-cutting services, injected via initializer; gate direct `.shared` access to composition-only visibility. Consider a custom lint rule banning `.shared` outside `Composition/`.

## 5. Medium-Severity Findings

### [MEDIUM] GLM key-rotation has a check-then-act race under concurrent AI requests
**Files:** `Packages/LookAfterAI/Sources/LookAfterAI/GLM/Service/GLMService.swift:345-360`, `Packages/LookAfterAI/Sources/LookAfterAI/GLM/Providers/GLMKeyManager.swift:29-43,125-158,202-220`

Each `GLMKeyManager` method individually locks via `NSLock`, but `GLMService.executeWithRotation`'s "read eligible keys → use key → mark result" sequence is not atomic as a whole. Concurrent callers (e.g., 4-way `async let` bootstrap in `AppShellState.runBootstrapWork`) can all snapshot the same "healthy" key, all fail together on rate-limit, and all pile onto the same fallback key — a retry storm that exhausts it too, degrading AI features for the full cooldown window (up to 3600s).

**Fix:** Convert `GLMKeyManager` to an `actor`; have `executeWithRotation` reserve/checkout a key before use so concurrent callers load-balance naturally.

### [MEDIUM] `refreshContext` re-entrancy queue can drop a different user's pending refresh
**Files:** `Apps/LookAfter-iOS/Experience/AppShellState.swift:519-528,612-666`

Single-slot `pendingContextRefresh` (last-write-wins) is keyed only by whichever call arrived most recently. During an account switch, a stale background-loop refresh for the old user can overwrite a legitimate queued refresh for the new user, leaving the UI stale for up to 60s.

**Fix:** Key the pending queue by `userId`, or cancel/restart `startContextLoop` synchronously at account-switch time and drop stale-user requests explicitly.

### [MEDIUM] `TaskSQLiteStore.replaceAllAsync` fire-and-forget write has no ordering guarantee vs. subsequent reads
**Files:** `Packages/LookAfterData/Sources/LookAfterData/Persistence/TaskSQLiteStore.swift:88-99`

`replaceAllAsync` spawns an unstructured `Task.detached` and returns immediately. A caller doing `replaceAllAsync(tasks); await loadAllAsync()` has no causal guarantee the write reaches the DB queue before the read, risking stale-data flicker after bulk operations.

**Fix:** Make the write genuinely awaitable; only use true fire-and-forget where no immediate read follows.

### [MEDIUM] Global `NotificationCenter.taskListDidChange` duplicates `@Published` observation
**Files:** `Packages/LookAfterData/Sources/LookAfterData/Stores/TaskStore.swift:169-172`

`TaskStore` is already an `ObservableObject` with `@Published var snapshot`, yet every mutation also posts a parameterless, user-agnostic notification. This creates an invisible dependency graph and, combined with the `lastUserId` race, can propagate cross-account UI updates broadly.

**Fix:** Reserve `NotificationCenter` for cross-process signaling only (widget/App Group); route in-process reactions through `@Published`.

## 6. Systemic Architecture Problems

1. **No single owner of "current user."** `AccountIdentity`, `TaskStore.lastUserId`, `AppShellState.bootstrappedUserId` each independently track identity.
2. **Composition root exists but is optional, not enforced.** `AppComposition` is bypassed everywhere inconvenient.
3. **`ObservableObject`/`@Published` and `NotificationCenter` used redundantly for the same signal**, doubling the surface area for state-sync bugs.
4. **God Object orchestration (`AppShellState`) mixes lifecycle, bootstrap, DI, and business orchestration.**
5. **"Core" package has become a catch-all** (35 subfolders) rather than a true kernel.

## 7. Top 10 Issues

| # | Issue | Area | Next action |
|---|-------|------|--------------|
| 1 | `TaskStore.lastUserId` cross-account race | State/Concurrency | Require explicit `userId` on all mutations |
| 2 | `AppShellState` bypasses `AppComposition` | Architecture | Route all `.shared` access through composition |
| 3 | `AppShellState` missing `deinit` for observers | Memory | Add `deinit` cleanup |
| 4 | GLM key-rotation race under concurrency | Concurrency/Networking | Actor-ize `GLMKeyManager` |
| 5 | `refreshContext` single-slot pending queue | State | Key queue by `userId` |
| 6 | `TaskSQLiteStore.replaceAllAsync` fire-and-forget | Persistence/Concurrency | Make awaitable |
| 7 | Redundant `NotificationCenter` + `@Published` | Architecture/State | Consolidate on `@Published` |
| 8 | Multiple sources of "current user" | Architecture | Introduce `UserSession` |
| 9 | `LookAfterCore` as catch-all (35 subfolders) | Architecture | Split into focused sub-packages |
| 10 | `GLMService.stream`'s inner `Task` may outlive dismissed screen | Concurrency | Add `onTermination` cancellation |

## 8. Prioritized Remediation Plan

| Rank | Severity | Issue | Impact | Fix Complexity |
|------|----------|-------|--------|-----------------|
| 1 | HIGH | `TaskStore.lastUserId` cross-account race | Data leak across accounts | Medium |
| 2 | HIGH | `AppShellState` bypasses `AppComposition` | Testability/coupling | High (incremental) |
| 3 | HIGH | Missing `deinit` in `AppShellState` | Test/preview flakiness | Low |
| 4 | MEDIUM | GLM key-rotation race | Bursty AI outages | Medium |
| 5 | MEDIUM | `refreshContext` pending-queue coalescing | Stale UI post-switch | Low |
| 6 | MEDIUM | `replaceAllAsync` fire-and-forget | Rare stale-read flicker | Low |
| 7 | MEDIUM | Notification/Published redundancy | Hidden coupling | Medium |
| 8 | LOW | `LookAfterCore` catch-all growth | Long-term maintainability | High |

## 9. Recommended Target Architecture

**Current:** `AppShellState` (God Object) → 15+ `.shared` singletons + `AppComposition` (partial); `TaskStore.shared` with user id smeared across 3 places.

**Recommended (incremental):**
```text
UserSession (created on sign-in, destroyed on sign-out)
   owns: TaskStore, TimelineService, HealthStore  (scoped, not static singletons)
AppComposition (extended to own ALL cross-cutting services, not just 4)
AppShellState split into:
   - AppBootstrapCoordinator (launch/account-switch/factory-reset orchestration)
   - AppShellState (thin ViewModel aggregator for SwiftUI, no business logic)
```

**Migration path:**
1. Add the `deinit` fix immediately (zero risk).
2. Require explicit `userId` on `TaskStore` mutations; remove `lastUserId` fallback (call sites already pass `userId` almost everywhere).
3. Incrementally move `.shared` references inside `AppShellState` into `AppComposition` properties, one subsystem at a time.
4. Only after 1–3 stabilize, consider splitting `AppShellState` into bootstrap vs. presentation concerns.

## 10. Fix Log

### 2026-09-12 — Finding #1 (`TaskStore.lastUserId` cross-account race) — FIXED

Root cause confirmed: `TaskStore.delete(_:)` and `TaskRepository.delete(_:)`/`deleteTaskFromFirestore(_:)` resolved the "current user" from instance-mutable `lastUserId` / `firebase.currentUserId` at the point the async call resumed, not from the user who initiated the delete. An account switch between task-swipe and Firestore-outbox-enqueue could attribute a delete to the wrong account.

**Change:** Added an explicit `userId: String` parameter threaded through the whole call chain:

- `TaskStoring.delete(_:userId:)` (protocol)
- `TaskStore.delete(_:userId:)`
- `TaskRepository.delete(_:userId:)` / `deleteTaskFromFirestore(_:userId:)`
- All call sites in `TasksViewModel` (7 sites) and `CaptureRouter.undoTask`
- Test mocks `InMemoryTaskStore` and `RescheduleTestTaskStore`

No `lastUserId` fallback remains on the delete path; callers must supply the owning `task.userId` (or session `userId` where the task object isn't in scope).

**Build/verification note:** This workspace's interactive environment is Windows, and Swift Package Manager cannot resolve/checkout this repo's dependencies here — `swift build` fails during dependency checkout with `unable to create symlink ... Permission denied` for `GRDB.swift`, `promises`, and `nanopb` (Firebase SDK transitive deps use symlinks in their checked-out sources, which requires Developer Mode / elevated permissions or a case-sensitive/symlink-capable filesystem on Windows). This is an environment limitation, not a code defect.

**Action required on macOS:** Run `swift build` and the full test suite (in particular `LookAfterDataTests/TaskStoreTests`, `LookAfterFeaturesTests/TasksViewModelInteractionTests`, `LookAfterFeaturesTests/PlanMutationApplierRescheduleTests`) to confirm:

1. The package compiles with the new `delete(_:userId:)` signature everywhere.
2. No other conformer of `TaskStoring` (beyond the two test mocks already updated) is missing the new parameter.
3. Existing delete/undo tests still pass with the explicit `userId` threaded through.
