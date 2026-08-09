# Environment matrix (Phase 0 WP 0.2)

**Status:** Spec — schemes/xcconfig wiring incremental  
**Related:** [MASTER-IMPLEMENTATION-PLAN.md](./MASTER-IMPLEMENTATION-PLAN.md), ADR-008

---

## Environments

| Env | Purpose | Firebase | Auth-proxy | On-device GLM key | Architecture flags defaults |
|-----|---------|----------|------------|------------------|-----------------------------|
| **Debug-Mock** | Offline / UI tests | Mock / no real project | optional localhost | allowed | all arch flags **off** except developer overrides |
| **Staging** | TestFlight internal | Staging Firebase project | Staging Azure URL | **discouraged** | `proxyOnlyAI` on when proxy configured |
| **Production** | App Store | Prod Firebase | Prod Azure URL | **forbidden** | `proxyOnlyAI` **true** (Release default) |

---

## Configuration sources

| Setting | Source today | Target |
|---------|--------------|--------|
| Firebase options | `GoogleService-Info.plist` / mock | Per-scheme plist or build setting |
| Auth-proxy base URL | Bundle `AuthProxy` config | xcconfig `AUTH_PROXY_BASE_URL` |
| GLM direct key | Keychain / UserDefaults legacy | Debug only; prod via proxy |
| Feature flags | `ArchitectureFeatureFlags` UserDefaults | + Remote Config later (Phase 8) |

---

## Xcode schemes (target state)

| Scheme | Configuration | Notes |
|--------|---------------|-------|
| `LookAfter-iOS` | Debug | Current default = Debug-Mock behavior |
| `LookAfter-iOS-Staging` | Staging | To add: distinct bundle id suffix `.staging` optional |
| `LookAfter-iOS-Release` | Release | Production |

Until Staging scheme exists: document proxy URL in internal runbook; set via launch args / env in CI.

### Suggested launch arguments (UITest / local)

```
-lookafter.arch.useSessionContainer YES
-lookafter.arch.useSyncOutbox YES
```

(Wire parser in Phase 1 when SessionContainer lands.)

---

## Checklist before claiming “Staging works”

- [ ] Staging `GoogleService-Info.plist` not committed if secret; use CI secret or private storage  
- [ ] Staging proxy health endpoint green  
- [ ] Firebase Auth test user can obtain ID token  
- [ ] One GLM complete via proxy succeeds  
- [ ] Crash/log sink does not point at prod  

---

## Security

- Never commit service account JSON or prod GLM keys.  
- `services/auth-proxy` uses env vars / Azure Key Vault in deploy.  
- App Check enforcement is Phase 6.
