# Infrastructure ops runbook (Phases 6–8)

**Branch:** `feature/arch-infra-implementation`  
**Related:** [MASTER-IMPLEMENTATION-PLAN.md](./MASTER-IMPLEMENTATION-PLAN.md), [environment-matrix.md](./environment-matrix.md)

---

## Phase 6 — Proxy & observability

### Request logging (6.1)

Auth-proxy runs `requestContextMiddleware` on every request:

- Assigns / echoes `x-request-id`
- Logs JSON access lines: method, path, status, ms, uid, hasAppCheck
- `GET /metrics/summary` (admin key) returns uptime snapshot

### Rate limits (6.2)

Existing IP + license rate limits remain in `middleware/rateLimit.ts`.  
Tune via config env vars already used by `loadConfig()`.

### App Check (6.4)

| Piece | Status |
|-------|--------|
| Client `AppCheckTokenProvider` | Stub (`NullAppCheckTokenProvider`) |
| Header | `X-Firebase-AppCheck` |
| Proxy enforce | Set `APP_CHECK_ENFORCE=true` when ready |

**Prod checklist before enforce:**

1. Link Firebase App Check SDK on iOS  
2. Register DeviceCheck / App Attest  
3. Inject real provider into `AppCheckConfiguration.provider`  
4. Attach token on `AuthProxyClient` requests  
5. Enable `APP_CHECK_ENFORCE` on staging first  

### Firestore rules tests (6.5)

Target CI job (manual until emulator harness lands):

```bash
firebase emulators:exec --only firestore "npm test --prefix rules-tests"
```

Rules live under project Firebase config (not duplicated here).

### Staging → prod deploy (6.7)

1. Deploy proxy image to **staging** slot  
2. Smoke: `/health`, licensed AI complete with test user  
3. Promote image tag to **prod**  
4. Watch access logs for 5xx spike; rollback image if error rate > threshold  

### Crash reporting (6.6)

Prefer Firebase Crashlytics when Firebase is configured; optional Sentry later.  
Client should only send non-PII breadcrumbs (auth transitions, outbox fail counts).

---

## Phase 7 — Brand / multi-account

### App Group dual-read (7.1–7.2)

| ID | Role |
|----|------|
| `group.com.lookafter` | Modern (read preferred) |
| `group.com.samaksh.flowos` | Legacy (current entitlement write primary) |

`AppGroupWidgetStore` dual-writes and dual-reads.  
**Entitlements still need modern group added** before modern container exists.

### BGTask dual-register (7.3)

| ID | Role |
|----|------|
| `com.lookafter.app.notification-refresh` | Preferred submit |
| `com.samaksh.flowos.app.notification-refresh` | Fallback |

Add **both** to `BGTaskSchedulerPermittedIdentifiers` in Info.plist before relying on modern ID.

### Per-user directories (7.4)

`UserStorageRoot.ensureUserDirectory(userId:)` → `Documents/users/{uid}/`  
New export files use this layout; existing SQLite files remain at Documents root until a migrate pass.

---

## Phase 8 — Polish

### LookAfterAppGroup package (8.1)

`Packages/LookAfterAppGroup` — widgets/intents depend on this instead of Features.

### Export (8.2)

```swift
let url = try await UserDataExportService.writeExportFile(userId: uid)
// or encrypted:
let data = try await UserDataExportService.exportEncrypted(userId: uid, passphrase: "…")
```

### Feature flags UX (8.3)

Debug Settings can dump:

```swift
ArchitectureFeatureFlags.debugSnapshot
SyncOutboxWorker.shared.debugStatus(userId:)
```

### Flag soak & delete (8.6)

After 2 stable releases with flags default **on**:

1. Remove dual-path branches  
2. Delete `useSessionContainer` / `useSyncOutbox` false paths  
3. Stop NotificationCenter dual-publish in EventBus  

---

## Enablement cheat sheet

```swift
ArchitectureFeatureFlags.useSessionContainer = true
ArchitectureFeatureFlags.useSyncOutbox = true
ArchitectureFeatureFlags.useBrainFacade = true
ArchitectureFeatureFlags.useTypedEventBus = true
// proxyOnlyAI defaults true in Release
```
