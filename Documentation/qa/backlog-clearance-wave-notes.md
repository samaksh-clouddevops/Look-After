# Backlog clearance wave (post-Q2b)

Feature-preserving. Continues local-first persistence + sync durability without locking features.

## Cleared this wave

1. **H4 module SQLite** — `ModuleEntitySQLiteStore` (`modules.sqlite`) for bills / shopping / relationships / journal; JSON migrate-once; repositories rewritten local-first.
2. **Generic `CloudSyncOutbox`** — collection + documentId queue; migrates legacy `task_sync_outbox`; `TaskSyncOutbox` is a thin facade. Inbox + health + module writes enqueue here.
3. **Conflict beyond LWW** — `TaskMerge.prefer` uses deletion tombstones + **status monotonicity** (completed beats newer pending) then LWW.
4. **Travel / Learning / Creativity** — UserDefaults blobs → `LocalPersistenceManager` protected JSON (with one-time UD migrate).
5. **Speech locale** — preferred device language, `en-US` fallback.
6. **Widget deep links** — `lookafter://today` `widgetURL` + `CFBundleURLTypes` + `LookAfterDeepLink` → `NotificationRouter`.
7. **Factory reset** — clears module SQLite + cloud sync outbox; adds `journal_entries` cloud wipe.

## Still epic (not “done” as engineering backlog items)

| Epic | Why deferred |
|---|---|
| StoreKit / ASC 3.1.1 | **Deferred — ignore for now**; keep product-key + auth-proxy as-is |
| God-object splits (`TasksViewModel`, `AppShellState`, Composition/) | Multi-week Q3 architecture |
| Observation migration | Couples to god-object work |
| Dynamic Type root + String Catalogs | **Wave 1 shipped** — see [q4-a11y-l10n-wave1-notes.md](q4-a11y-l10n-wave1-notes.md); more UI strings / locales later |
| macOS Today/Capture/You parity | Platform product + large UI |
| Fake-glass cleanup pass | **Shipped** — see [fake-glass-cleanup-notes.md](fake-glass-cleanup-notes.md) |
| Full field-level CRDT sync | Outbox + status policy is enough for now |

## Tests added/extended

- Module SQLite round-trip / replace+delete
- CloudSyncOutbox coalesce
- TaskMerge status + tombstone cases
