# Q2 reliability slice (feature-preserving)

Follow-on to Q1 P0. No product surfaces removed.

## Done in this slice

1. **AuthProxy 401 → forceRefresh → single retry** (`AuthProxyClient` JSON + speech)
2. **BGTask completion** — expiration paths call `setTaskCompleted(success: false)` once (notification refresh + behavioral telemetry); notification refresh also registered in `didFinishLaunching`
3. **Apple Sign-In credential monitor** — `getCredentialState` on launch/foreground + revoke notification → `signOut()` (local data kept)
4. **Live Activity `staleDate`** — focus uses session/window end; Now Pin uses `pinWindowEnd` (fallback 30m)

## Still next (Q2+ backlog, not started here)

- Infra H2–H4 (Inbox / health summaries / modules → SQLite)
- TaskDeletionRegistry cloud sync + conflict policy beyond LWW
- Factory-reset contract tests
- God-object splits / Composition root / Observation migration
- Dynamic Type / String Catalogs / macOS parity
- StoreKit decision
- Fake-glass cleanup / speech locale / widgetURL
