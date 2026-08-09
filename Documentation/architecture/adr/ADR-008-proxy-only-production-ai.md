# ADR-008: Proxy-only AI in production

**Status:** Proposed  
**Date:** 2026-08-09  
**Plan:** Phase 3 WP 3.2  

## Context

On-device GLM API keys are a security and cost-control risk. `AuthProxyClient` + Azure proxy already exist for licensed traffic.

## Decision

- **Release** builds: `ArchitectureFeatureFlags.proxyOnlyAI` defaults **true**; `GLMService` must not call z.ai with a local key.
- **Debug** builds: default false so engineers can use local keys.
- Staging/Production schemes point at the corresponding proxy base URL.
- Proxy enforces Firebase auth, quotas, and (later) App Check.

## Consequences

- Requires working proxy + license path for TestFlight/App Store AI features
- Local key UI becomes debug/settings-only or removed from production

## Alternatives considered

- Keep dual path forever in prod — rejected (key exfiltration risk).
- On-device only — rejected (no central quota).
