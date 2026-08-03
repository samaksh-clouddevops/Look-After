# 23. UI Intelligence Validation

**Document ID:** QA-23  
**Validation Layer:** Cross-cutting  
**Parent:** [README.md](README.md)

Cognitive load metrics per screen — not layout alone.

---

## Metrics (from spec)

| Metric | Weight | Source |
|--------|--------|--------|
| Visible action count | 20% | Accessibility tree |
| Estimated reading time | 15% | Text length heuristics |
| Scroll distance to primary CTA | 20% | XCUITest geometry (Phase 2) |
| Decisions before hero action | 25% | Interaction graph |
| Time to primary task | 20% | XCUITest timing (Phase 2) |

**Cognitive load score** = weighted sum (0–100). Threshold: ≤ 60 for P0 screens.

---

## Test Cases

### UI-INT-S05-01 — TodayView cognitive load

| Field | Value |
|-------|-------|
| Priority | P1 |
| Screen | S05 TodayView |
| Expected | Cognitive load ≤ 60; hero visible without scroll on iPhone 17 |
| Automation | UIIntelligenceRunner (Phase 2) |

### UI-INT-S14-01 — BrainInspector load

| Field | Value |
|-------|-------|
| Priority | P2 |
| Screen | S14 BrainInspector |
| Expected | ≤ 8 visible actions on default trace |

### UI-INT-S25-01 — Planning surface load

| Field | Value |
|-------|-------|
| Priority | P1 |
| Screen | S25 Planning |
| Expected | Primary CTA within 1.5 screens scroll |

---

## Phase 1

Spec + RTM entries + `not_implemented` status. Phase 2: S05, S14, S25 only.
