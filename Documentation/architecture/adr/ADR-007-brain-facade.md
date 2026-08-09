# ADR-007: BrainFacade single entry

**Status:** Proposed  
**Date:** 2026-08-09  
**Plan:** Phase 3 WP 3.1  

## Context

Recommendations come from ExecutiveBrain, FlowDirector, LLM planning, and capacity engines with parallel call paths. Duplication causes inconsistent hero decisions and hard tests.

## Decision

One **`BrainFacade`** protocol:

```text
recommend(input) async -> BrainOutput
```

Backends: Deterministic (ExecutiveBrain), FlowDirector, LLM assist. Router selects by flags, offline state, and confidence.

`BrainViewModel` depends only on the façade. Flag: `useBrainFacade`.

## Consequences

- Single place for executive-cost gates (e.g. no deep work after short sleep)
- Easier golden/EVP tests
- Backend feature flags remain product-level (`enableFlowDirector`) under the router

## Alternatives considered

- Keep dual paths forever — rejected (drift).
- LLM-only brain — rejected (offline + cost + safety).
