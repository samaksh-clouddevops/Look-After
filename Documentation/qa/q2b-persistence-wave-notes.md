# Q2b persistence wave (H2 / H3 / deletions)

Feature-preserving: offline Inbox/Health keep working; cloud remains optional merge.

## Shipped

1. **H2 Inbox local-first** — `InboxSQLiteStore` + `InboxRepository` reads/writes SQLite first; Firestore pull/push when authenticated (no throw when offline).
2. **H3 Health summaries SQLite** — `HealthSummarySQLiteStore` with one-time migrate from `health_summaries.json`; repository local paths updated.
3. **TaskDeletionRegistry** — durable App Support file + Firestore `task_deletions` tombstones; pull on `TaskRepository.warmLocalCache`.
4. **Factory reset** — clears inbox/health SQLite, deletion registry, task sync outbox; wipes `task_deletions` cloud collection.
5. **Tests** — inbox/health SQLite, deletion registry, factory-reset contract.

## Follow-up (cleared)

See [backlog-clearance-wave-notes.md](backlog-clearance-wave-notes.md) for H4 modules SQLite, generic `CloudSyncOutbox`, conflict monotonicity, Travel/Learning/Creativity file persistence, speech locale, and widget deep links.

## Still epic

- God-object / Composition / Observation (Q3)
- Dynamic Type / L10n / macOS (Q4)
- StoreKit product decision
