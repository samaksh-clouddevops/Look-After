# ADR-004: Platform APIs Isolated Behind Providers

## Status

Accepted — D2.3, reaffirmed D2.4 (2026-07-31)

## Context

FlowOS orchestration consumes signals from HealthKit, EventKit, WeatherKit, and device state. These APIs:

- Require platform frameworks not suitable for `LookAfterCore`.
- Have permission models that fail gracefully.
- Are difficult to unit test when called directly from business logic.

## Decision

**LookAfterCore defines protocols and DTOs only.** Platform implementations live in `LookAfterData` or the app layer:

| Signal | Protocol | Default Implementation |
|--------|----------|------------------------|
| Time | `TimeEnvironmentSignalProviderProtocol` | `DefaultTimeEnvironmentSignalProvider` |
| Health | `HealthEnvironmentSignalProviderProtocol` | Maps pre-fetched `HealthSummary` (no HealthKit in provider) |
| Calendar | `CalendarEnvironmentSignalProviderProtocol` | `EventKitCalendarEnvironmentSignalProvider` |
| Device | `DeviceEnvironmentSignalProviderProtocol` | `DefaultDeviceEnvironmentSignalProvider` |
| Weather | `WeatherEnvironmentSignalProviderProtocol` | `StubWeatherEnvironmentSignalProvider` |

`EnvironmentContextProvider` fuses injected providers and returns partial `EnvironmentContext` on failure.

`FlowSchedulingEngine` consumes fused `EnvironmentContext` only — never imports platform frameworks.

## Consequences

**Positive**

- LookAfterCore builds on macOS for fast CI without simulators.
- Each provider is individually mockable in tests.
- WeatherKit can remain disabled until licensed/configured.

**Negative**

- App composition root must wire real providers for production.
- Some signals (Focus Mode, Reduce Motion) need app-layer adapters for full fidelity.

## Alternatives Considered

- **HealthKit in LookAfterCore** — rejected; violates package layering and testability.
- **Single mega `EnvironmentService`** — rejected; prevents per-signal mocking and degradation.
