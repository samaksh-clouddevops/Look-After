# Look After — full-app improvement program

**Living status:** 9 September 2026  
**Canvas:** `lookafter-full-app-improvement.canvas.tsx` (open beside chat)  
**Scope:** Whole product (~119k Swift LOC), not only iOS 26 A–J chrome.

## Program status

| Area | Status |
|---|---|
| iOS 26 chrome A–J | Engineering done |
| Q1 P0 (trust / ship / auth / PHI) | Shipped (feature-preserving; EventKit/HK bg kept) |
| Q2 reliability | Shipped |
| Q2b + backlog persistence | Shipped (H2–H4, CloudSyncOutbox, conflict policy) |
| Q3 architecture | Wave 1 shipped (`AppComposition`, surface sync, Inbox split) |
| Q4 a11y / L10n | Wave 1 shipped (Dynamic Type root, String Catalog chrome) |
| Fake-glass cleanup | Shipped |
| StoreKit vs product-key | **Deferred** — product-key + auth-proxy kept |
| macOS parity | Open |
| Deeper god-object / Observation | Open (Q3 next slices) |

## Wave notes (implementation audit)

| Wave | Document |
|---|---|
| Q1 P0 | [q1-p0-implementation-notes.md](q1-p0-implementation-notes.md) |
| Q2 reliability | [q2-reliability-slice-notes.md](q2-reliability-slice-notes.md) |
| Q2b persistence | [q2b-persistence-wave-notes.md](q2b-persistence-wave-notes.md) |
| Backlog clearance | [backlog-clearance-wave-notes.md](backlog-clearance-wave-notes.md) |
| Q3 architecture | [q3-architecture-wave1-notes.md](q3-architecture-wave1-notes.md) |
| Q4 a11y / L10n | [q4-a11y-l10n-wave1-notes.md](q4-a11y-l10n-wave1-notes.md) |
| Fake glass | [fake-glass-cleanup-notes.md](fake-glass-cleanup-notes.md) |
| iOS 26 plan | [ios26-revamp-plan.md](ios26-revamp-plan.md) |
| Chrome design | [../design/ios26-chrome.md](../design/ios26-chrome.md) |

## Locked product rules

- Do **not** remove or restrict features (EventKit writeOnly-as-authorized kept; HealthKit `enableBackgroundDelivery` kept).
- StoreKit deferred; product-key licensing kept.
- Opaque content + real Liquid Glass chrome; do not rewrite Brain/scheduling math casually.

## What to do next

1. **Q3 next slice** — life-commitment / schedule reconcile / bootstrap extracts; optional `ShellSheetsHost`.
2. **Q4 continue** — Briefing/Capture/Settings strings; `@ScaledMetric` chrome; XXXL layout passes.
3. **macOS** — Today + Capture + You parity, or reposition as desk companion.
4. **Ongoing** — Timeline/NOW device golden path; shrink QA IDs to executable RTM; retire dual-shell fiction in docs.

Open the canvas for the full P0 disposition table and quarter cards.
