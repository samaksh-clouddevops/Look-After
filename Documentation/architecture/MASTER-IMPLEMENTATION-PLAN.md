# Master Implementation Plan — Architecture & Infrastructure

**Document ID:** ARCH-MASTER-PLAN  
**Date:** 2026-08-09  
**Branch base:** `fix/bug-audit-remediation` (bug/perf already landed)  
**Status:** Planning — do not implement until phases are scheduled  
**Owner:** Engineering  
**Related:**  
- [mobile-infrastructure-roadmap.md](./mobile-infrastructure-roadmap.md) (storage/sync detail)  
- [dependencies.md](./dependencies.md)  
- [PERFORMANCE-DEEP-ANALYSIS.md](../qa/PERFORMANCE-DEEP-ANALYSIS.md)  
- [BUG-AUDIT-REPORT.md](../qa/BUG-AUDIT-REPORT.md)  
- ADRs in [adr/](./adr/)

---

## Purpose

Exact **what** to build and **in what order**, covering architecture *and* infrastructure improvements discussed after the bug/perf remediation wave.

**Rules for execution:**

1. Ship **one phase at a time**; each phase ends with green package tests + app boots.  
2. Prefer **additive dual-path** then delete legacy (no big-bang).  
3. One PR cluster per **work package** (WP) below; keep PRs reviewable.  
4. Do **not** rename App Group / BGTask IDs without the dual-read phase.  
5. Production AI keys stay off-device once proxy-only is enforced.

---

## Current baseline (after remediation branch)

| Already done | Remaining gap this plan closes |
|--------------|--------------------------------|
| Task SQLite + upsert mutations | Full-table paths still used for some rebuilds; modules still JSON |
| Auth await Firebase; identity races reduced | No formal Identity/Session lifecycle |
| FlowDirector serialized | Dual brain stacks still co-exist |
| Planning mutation confirm | AppShellState still god-object |
| PERF-001…024 code fixes | Shell observation / composition root incomplete |
| Capture offline queue drain-on-success | Generic **sync outbox** missing for Firestore |
| Auth-proxy service exists | Staging/prod env matrix, quotas, OTel incomplete |
| Package layering documented | Features monolith; DI not enforced |

---

## Guiding target architecture

```text
Apps (thin UI)
    ↓
Feature modules (Tasks | Planning | Briefing | Capture | …)
    ↓
SessionContainer (per authenticated / guest user)
    ├── IdentityService
    ├── TaskService + OutboxWorker
    ├── BrainFacade (Deterministic | Flow | LLM backends)
    ├── HealthGateway
    ├── NotificationPort
    └── EventBus (typed streams)
    ↓
LookAfterData | LookAfterAI | LookAfterHealth | LookAfterCore
    ↓
SQLite · Firestore · Azure auth-proxy · HealthKit · EventKit
```

---

## Dependency order (do not reorder casually)

```text
Phase 0  Foundations (docs, envs, flags, CI hooks)
    ↓
Phase 1  Identity + Session composition root
    ↓
Phase 2  Sync outbox + local-first remaining entities     ⎤ parallelizable
Phase 3  Brain façade + AI proxy-only prod                 ⎥ after Phase 1
    ↓                                                    ⎦
Phase 4  Split AppShellState / TasksViewModel / Features packages
    ↓
Phase 5  Event bus replaces NotificationCenter domain traffic
    ↓
Phase 6  Infra hardening (proxy HA, OTel, App Check, rules tests)
    ↓
Phase 7  Brand/entitlement migration + multi-account layout
    ↓
Phase 8  Polish (extensions package, export/backup, flags UX)
```

Phases **2 and 3** may run as two parallel workstreams after Phase 1, merging often to `main`.

---

## Phase 0 — Foundations (1 week)

**Goal:** Make later work safe, measurable, and reversible.

| WP | What to do | Deliverable | Exit criteria |
|----|------------|-------------|---------------|
| **0.1** | Adopt this doc as source of truth; link from README / future-work | PR docs only | Team agrees order |
| **0.2** | Define env matrix: `Debug-Mock`, `Staging`, `Production` schemes + xcconfig | 3 schemes | Staging build hits staging Firebase + proxy URL |
| **0.3** | Feature-flag registry (local UserDefaults + optional Remote Config stub) | `FeatureFlags.swift` | Flags: `useSessionContainer`, `useSyncOutbox`, `proxyOnlyAI`, `useBrainFacade`, `useTypedEventBus` |
| **0.4** | CI: run `swift test` on Core, Data, AI, Features on every PR | CI workflow | Red on failure |
| **0.5** | Add ADR stubs: Session composition, Outbox, Brain façade, Proxy-only AI | `adr/ADR-005…008` | ADRs merged |
| **0.6** | Inventory all `.shared` singletons and Notification.Name domain events | `Documentation/architecture/singleton-inventory.md` | List with owner package |

**Do not** start refactoring AppShellState in this phase.

**Order inside phase:** 0.1 → 0.5 → 0.2 → 0.3 → 0.4 → 0.6

---

## Phase 1 — Identity + Session composition root (2–3 weeks)

**Goal:** One place creates dependencies; bootstrap waits for stable identity.

### WP 1.1 — IdentityService

| Step | Action |
|------|--------|
| 1 | Create `IdentityService` protocol + implementation wrapping `FirebaseManager` |
| 2 | States: `signedOut`, `offlineGuest`, `firebaseUser(uid)` |
| 3 | Remove optimistic auth from call sites (already improved; audit leftovers) |
| 4 | Publish `identitySequence` / generation token; bootstrap cancels when generation changes |
| 5 | Unit tests: invalid password → not authenticated; nil auth listener clears session |

**Files (expected):**
`Packages/LookAfterData/.../Identity/IdentityService.swift`
Wire through `FirebaseManager` (thin facade).

### WP 1.2 — SessionContainer

| Step | Action |
|------|--------|
| 1 | Create `SessionContainer` holding: identity, taskStore, repos, glm/proxy, health gateway, event bus placeholder |
| 2 | Build via factory `SessionContainer.make(environment:flags:)` — **no** Feature imports of `.shared` for new code |
| 3 | `AppShellState` **constructs from** SessionContainer (wrapper first, not delete) |
| 4 | Flag `useSessionContainer`: off = legacy path; on = container path |
| 5 | Sign-out / factory reset calls `session.tearDown()` (cancel tasks, clear caches) |

### WP 1.3 — Bootstrap gate

| Step | Action |
|------|--------|
| 1 | `runBootstrapWork` only after `identity.isStable` |
| 2 | If UID swaps mid-bootstrap, abort and restart once |
| 3 | UITest hook: `uitest-bootstrap-complete` remains valid |
| 4 | Integration test: anonymous → upgrade UID reassigns once |

**Exit criteria Phase 1:**
App runs with flag on; cold launch; sign-out; factory reset; no UID double-bootstrap logs.

**Order:** 1.1 → 1.2 → 1.3

---

## Phase 2 — Sync outbox + local-first storage (3–4 weeks)

**Goal:** Never lose mutations when cloud fails; reduce JSON full-file stores.
**Aligns with** [mobile-infrastructure-roadmap.md](./mobile-infrastructure-roadmap.md) High tier.

### WP 2.1 — Generic Sync Outbox (do first)

| Step | Action |
|------|--------|
| 1 | SQLite table `sync_outbox` (id, entity_type, entity_id, op, payload, attempts, next_attempt_at, last_error) |
| 2 | `OutboxWorker` actor: drain with backoff; network monitor |
| 3 | Task create/update/delete enqueue instead of fire-and-forget Firestore |
| 4 | BGAppRefresh / BGProcessing hooks drain outbox |
| 5 | Metrics: pending count, fail age; Settings debug row |
| 6 | Tests: offline mutate → online drain; max attempts quarantine |

### WP 2.2 — Inbox local-first SQLite

| Step | Action |
|------|--------|
| 1 | `InboxSQLiteStore` + migration from memory/cloud-only |
| 2 | Repository reads local first; pull merges; pushes via outbox |
| 3 | Capture route → local inbox row always |

### WP 2.3 — Health summaries SQLite

| Step | Action |
|------|--------|
| 1 | Move `health_summaries` JSON → SQLite |
| 2 | HealthSyncService writes SQLite; outbox optional for cloud copy |
| 3 | Keep single-flight `ensureSynced` |

### WP 2.4 — Module entities JSON → SQLite

Order of migration (dependency-light first):

1. shopping_items
2. bills
3. relationships
4. journal_entries
5. analytics_cache

Each entity: schema → dual-read → dual-write → cutover → delete JSON path.

### WP 2.5 — Firestore offline + selective listeners

| Step | Action |
|------|--------|
| 1 | Enable Firestore persistent cache in prod/staging |
| 2 | Snapshot listeners only for active user `tasks` + `inbox` (not full tree) |
| 3 | Document conflict policy: LWW on `updatedAt` unless field-level merge required |

**Exit criteria Phase 2:**
Airplane mode create task + capture → reconnect → cloud matches; no silent drop; modules work offline read.

**Order:** 2.1 → 2.2 → 2.3 → 2.4 (can stack entities) → 2.5

---

## Phase 3 — Brain façade + production AI path (2–3 weeks)

**Goal:** One decision API; production cannot call z.ai with on-device keys.

### WP 3.1 — BrainFacade

| Step | Action |
|------|--------|
| 1 | Protocol `BrainFacade.recommend(input:) async → BrainOutput` |
| 2 | Backends: `DeterministicBrainBackend` (ExecutiveBrain), `FlowDirectorBackend`, `LLMAssistBackend` |
| 3 | Router chooses backend by flag + signal confidence + offline |
| 4 | `BrainViewModel` talks only to façade |
| 5 | Golden tests: sleep-deprived deep-work blocked; chronic deferral |

### WP 3.2 — Proxy-only production AI

| Step | Action |
|------|--------|
| 1 | Flag `proxyOnlyAI` default **true** for Release |
| 2 | `GLMService` refuses direct key path when flag on |
| 3 | Auth-proxy: enforce daily token quota per uid |
| 4 | Idempotency-Key header on `/ai/chat` |
| 5 | Staging integration test with service account |

### WP 3.3 — Prompt registry

| Step | Action |
|------|--------|
| 1 | Version prompts in `LookAfterAI/Prompts/vN/` |
| 2 | CI fixture tests for planning JSON + capacity schema |
| 3 | Hard caps already in PlanningPromptContextBuilder — keep enforced |

**Exit criteria Phase 3:**
Release build cannot use local GLM key; façade unit tests green; planning still confirms mutations.

**Order:** 3.1 → 3.2 → 3.3

---

## Phase 4 — Decompose god-objects & Features packages (3–5 weeks)

**Goal:** AppShellState thin; Features split; test seams.

### WP 4.1 — Extract services from AppShellState

Extract in this **exact order** (each PR removes code from shell):

1. `BootstrapCoordinator` (runBootstrapWork)
2. `CaptureSessionCoordinator` (router + inbox hooks)
3. `BriefingProjectionService` (projectBriefingSurface)
4. `ProactiveShellBridge` (snapshot builder)
5. `WidgetProjectionService` (already WidgetSyncService — inject only)
6. Leave shell as: holds SessionContainer + navigation-related UI state

### WP 4.2 — Split TasksViewModel

Extract types (new files, VM becomes façade):

1. `TaskListState` (arrays + revision + index cache)
2. `TaskRecurrenceService`
3. `TaskScheduleReconcileService`
4. `TaskTimeDisplayService`
5. `TaskCRUDService`

VM methods become one-liners delegating to services.

### WP 4.3 — Feature package split

Create SPM products incrementally (Apps depend on umbrella `LookAfterFeatures` that re-exports):

1. `LookAfterFeaturesTasks`
2. `LookAfterFeaturesPlanning`
3. `LookAfterFeaturesBriefing`
4. `LookAfterFeaturesCapture`
5. Rest stays in Features until later

**Do not** circular-depend; shared UI chrome stays Core design system.

### WP 4.4 — DI enforcement

| Step | Action |
|------|--------|
| 1 | New code: no `Something.shared` inside Features (SwiftLint custom rule or script) |
| 2 | Tests inject fakes for TaskStore, GLM, Identity |
| 3 | Delete dual init paths only after flag default on |

**Exit criteria Phase 4:**
AppShellState &lt; ~400 lines; TasksVM façade &lt; ~500 lines; features compile as separate targets.

**Order:** 4.1 → 4.2 → 4.3 → 4.4

---

## Phase 5 — Typed event bus (1–2 weeks)

**Goal:** Replace domain `NotificationCenter` with typed streams.

### WP 5.1

| Step | Action |
|------|--------|
| 1 | `SessionEvent` enum: `tasksChanged`, `scheduleChanged`, `focusEnded`, `identityChanged`, … |
| 2 | `EventBus` actor with `AsyncStream` per subscriber |
| 3 | Dual-publish: bus + NotificationCenter behind flag |
| 4 | Migrate ExperienceRootLifecycleModifier first
| 5 | Migrate proactive / widget / analytics listeners |
| 6 | Remove NotificationCenter dual-publish when no callers |

**Exit criteria:**
No domain `Notification.Name` posts in Features/Data for tasks/schedule (search CI).

**Order:** single WP sequenced 1→6

---

## Phase 6 — Infrastructure hardening (2–3 weeks)

**Goal:** Production ops quality for proxy + Firebase + client.

| WP | What | Exit |
|----|------|------|
| **6.1** | Auth-proxy: structured logging, request id, token usage metrics | Dashboard or log queries work |
| **6.2** | Auth-proxy: rate limit per uid + IP | Load test rejects abuse |
| **6.3** | OpenTelemetry (proxy) + correlate client signpost ids | Trace one planning call end-to-end |
| **6.4** | Firebase App Check on iOS + enforce on proxy | Unauthenticated API fails |
| **6.5** | Firestore security rules tests (emulator) | CI job green |
| **6.6** | Crash reporting (Crashlytics or Sentry) + non-PII breadcrumbs | Crash visible in console |
| **6.7** | Multi-stage deploy: staging slot → prod for proxy | Runbook doc |

**Order:** 6.1 → 6.2 → 6.4 → 6.5 → 6.3 → 6.6 → 6.7

---

## Phase 7 — Brand / entitlements / multi-account (2 weeks)

**Goal:** One brand story without breaking installs.

| WP | What | Exit |
|----|------|------|
| **7.1** | Dual-read App Group `group.com.lookafter` + legacy `group.com.samaksh.flowos` | Widgets load either |
| **7.2** | Migrate widget snapshot + intents on launch | One-time migration log |
| **7.3** | Dual-register BGTask identifiers; schedule new; stop old after 1 release | No missed BG |
| **7.4** | Per-user storage namespace: `Documents/users/{uid}/` | Second account no bleed |
| **7.5** | Remove legacy IDs in N+2 release | Inventory clean |

**Order:** 7.1 → 7.2 → 7.3 → 7.4 → 7.5 (7.5 deferred release)

---

## Phase 8 — Polish & productization (ongoing)

| WP | What |
|----|------|
| **8.1** | `LookAfterAppGroup` tiny package for extensions only |
| **8.2** | Encrypted export/backup of user data |
| **8.3** | Remote Config full UX for flags |
| **8.4** | Remaining DateFormatter static migration |
| **8.5** | Device perf gate: Focus open BUG-007 Instruments checklist in CI manual lane |
| **8.6** | Delete `useSessionContainer` legacy path after 2 stable releases |

---

## Cross-cutting standards (every phase)

1. **Tests:** domain logic unit-tested in package; no UI test for pure rules.
2. **Flags:** default new architecture off until soak; then default on; then delete old.
3. **Logging:** `os.Logger` subsystem `com.lookafter.*`; no PII.
4. **Migrations:** GRDB `DatabaseMigrator` version table for all SQLite.
5. **PR size:** prefer &lt; 400 lines logical diff; stack PRs.
6. **Docs:** update ADR when decision changes; tick WP in this file.

---

## Work package index (quick checklist)

| ID | Phase | Name | Depends on |
|----|-------|------|------------|
| 0.1–0.6 | 0 | Foundations | — |
| 1.1 | 1 | IdentityService | 0.3 |
| 1.2 | 1 | SessionContainer | 1.1 |
| 1.3 | 1 | Bootstrap gate | 1.2 |
| 2.1 | 2 | Sync outbox | 1.2 |
| 2.2 | 2 | Inbox SQLite | 2.1 |
| 2.3 | 2 | Health SQLite | 2.1 |
| 2.4 | 2 | Modules SQLite | 2.1 |
| 2.5 | 2 | Firestore listeners | 2.1 |
| 3.1 | 3 | BrainFacade | 1.2 |
| 3.2 | 3 | Proxy-only prod | 0.2, 3.1 |
| 3.3 | 3 | Prompt registry | 3.1 |
| 4.1 | 4 | Split AppShellState | 1.2 |
| 4.2 | 4 | Split TasksViewModel | 2.1 optional |
| 4.3 | 4 | Features packages | 4.2 |
| 4.4 | 4 | DI lint | 4.3 |
| 5.1 | 5 | Event bus | 1.2, 4.1 |
| 6.1–6.7 | 6 | Infra hardening | 3.2, 0.2 |
| 7.1–7.5 | 7 | Brand/multi-account | 2.x stable |
| 8.1–8.6 | 8 | Polish | 4–7 |

---

## Suggested calendar (example)

| Weeks | Focus |
|------:|-------|
| 1 | Phase 0 |
| 2–4 | Phase 1 |
| 5–8 | Phase 2 (stream A) \|\| Phase 3 (stream B) |
| 9–13 | Phase 4 |
| 14–15 | Phase 5 |
| 16–18 | Phase 6 |
| 19–20 | Phase 7 |
| 21+ | Phase 8 + delete flags |

Adjust to team size; single developer: serialize 2 then 3.

---

## Risks & mitigations

| Risk | Mitigation |
|------|------------|
| Session refactor breaks UI | Flag dual-path; fix screenshot tests |
| Outbox doubles writes | Idempotent Firestore doc ids; dedupe keys |
| Proxy-only blocks devs | Debug-Mock scheme keeps direct GLM |
| Package split merge hell | Umbrella target; move files git mv |
| Entitlement rename bricks widgets | Dual-read two releases minimum |
| Scope creep | No WP starts without prior phase exit check |

---

## Definition of Done (whole program)

- [ ] SessionContainer is default; AppShellState thin
- [ ] Outbox drains reliably offline→online
- [ ] Modules + inbox + health local-first SQLite
- [ ] BrainFacade only entry for recommendations
- [ ] Release builds proxy-only AI + App Check
- [ ] Typed event bus; domain NotificationCenter gone
- [ ] Staging env + CI package tests + rules tests
- [ ] Brand IDs migrated or dual-read complete
- [ ] ADRs 005–008 accepted
- [ ] Legacy flags removed after soak

---

## Immediate next actions (start implementation)

1. Merge/stabilize `fix/bug-audit-remediation` to main if not already.
2. Open PR for **Phase 0** (this doc + ADR stubs + flag registry + CI).
3. Kick **WP 1.1 IdentityService** as first code PR.

**Do not skip to Phase 4** before Phase 1 — extraction without SessionContainer recreates coupling.

---

## Change log

| Date | Change |
|------|--------|
| 2026-08-09 | Initial master plan from architecture/infra recommendations |
