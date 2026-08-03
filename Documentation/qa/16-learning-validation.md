# 16. Learning Validation

**Document ID:** QA-16  
**Parent:** [README.md](README.md)

Validates that the Brain **improves over time** from behavior — not only that static rules fire correctly.

**Primary systems:** `BehaviorMemoryStore`, `DefaultBehaviorAnalysisEngine`, `FlowDirector.handleTaskCompleted` / `handleTaskDeferred`, `FlowSchedulingEngine`

---

## Learning hypothesis

> If the user repeatedly skips or defers the same commitment at the same temporal pattern, the Brain should shift recommendations — not repeat the same failing suggestion indefinitely.

Static rule pass + learning fail = **product failure** even with green unit tests.

---

## Learning signals (what the Brain must observe)

| Signal | Storage | Trigger |
|--------|---------|---------|
| Task completion | `BehaviorMemoryStore.recordCompletion` | Hero/task done |
| Task deferral | `BehaviorMemoryStore.recordDeferral` | Snooze / defer |
| Flow session end | `BehaviorMemoryStore.recordFlowSession` | Focus timer |
| Skip / abandon | Defer or short session duration | Implicit |

**Analysis:** `BehaviorAnalysisEngine` → snapshot → `FlowSchedulingEngine` / confidence adjustments.

---

## Canonical learning scenario (PASS criteria)

### LEARN-001 — Gym Tuesday skip → Wednesday shift

| Week | Event | Expected Brain behavior |
|------|-------|-------------------------|
| **Week 1** | Gym scheduled Tuesday | Suggest gym Tuesday |
| | User skips | Record deferral/skip in behavior memory |
| **Week 2** | Gym scheduled Tuesday | Suggest gym Tuesday (one skip insufficient) |
| | User skips again | Pattern confidence increases |
| **Week 3** | Gym would be Tuesday | **Move suggestion to Wednesday** (or next viable slot per life model) |
| | User completes | **PASS** — learning verified |

| Field | Value |
|-------|-------|
| **Test ID** | LO-LEARN-001 |
| **Priority** | P0 |
| **Severity** | S1 if no adaptation after 3 consistent skips |
| **Preconditions** | Recurring gym commitment in life model; behavior memory persisted |
| **Automation partial** | `BehaviorMemoryStoreTests.swift` — event recording only |
| **Manual** | 3-week simulated or accelerated fixture (inject 6 defer events) |

### Accelerated test procedure (staging)

1. Seed life model: gym Tue 7:00 AM  
2. Inject behavior events: `defer` gym task × 2 on Tuesdays (weeks 1–2)  
3. Trigger `FlowDirector.orchestrate()` on Tuesday week 3 morning  
4. **Pass:** Hero or schedule proposes Wed (or explains shift in why-now)  
5. User completes on Wed → record completion  
6. **Pass:** Week 4 maintains Wed bias until user changes pattern  

---

## Learning test catalog

### LO-LEARN-002 — Completion time drift

| Scenario | User always completes "deep work" 2h later than planned |
| Expected | Scheduling window slides later; not repeated 8 AM misfires |
| Priority | P1 |

### LO-LEARN-003 — Duration underestimate correction

| Scenario | User consistently takes 1.5× estimated minutes |
| Expected | Future estimates inflate for that task category |
| Priority | P1 |
| Code touchpoint | `PersonalAnalyticsEngine`, task semantic profile |

### LO-LEARN-004 — Deferral streak lowers confidence

| Scenario | Same task deferred 3× in 7 days |
| Expected | `flowConfidenceScore` drops; hero may switch task |
| Priority | P0 |
| Related | `FlowConfidenceEngineTests.swift` |

### LO-LEARN-005 — Flow session success reinforces hero type

| Scenario | User completes 3 focus sessions on writing tasks |
| Expected | Writing tasks elevated in hero eligibility when energy matches |
| Priority | P2 |

### LO-LEARN-006 — No learning from single anomaly

| Scenario | One skip after 10 completions |
| Expected | No schedule change from single event |
| Priority | P1 |
| Pass | Prevents overfitting |

### LO-LEARN-007 — Factory reset clears learning

| Scenario | Factory reset |
| Expected | Behavior memory empty; Week 1 defaults restored |
| Priority | P0 |
| Flow | FLOW-008 |

### LO-LEARN-008 — Cross-device learning (Firebase)

| Scenario | Defer on iOS; open macOS |
| Expected | Same behavior snapshot influences scheduling (when synced) |
| Priority | P2 |

---

## Learning validation matrix

| Pattern type | Min observations before adapt | Max weeks to adapt | Test ID |
|--------------|--------------------------------|--------------------|---------|
| Weekly recurring skip | 2 consecutive | 3 | LO-LEARN-001 |
| Daily defer same task | 3 in 7 days | 1 | LO-LEARN-004 |
| Duration mismatch | 5 completions | 2 | LO-LEARN-003 |
| Time-of-day shift | 4 completions off-slot | 2 | LO-LEARN-002 |

---

## Fixtures

Store under `Documentation/qa/fixtures/learning/`:

| File | Contents |
|------|----------|
| `gym_tuesday_skip.json` | 6 defer events, Tue gym task ID |
| `deep_work_late.json` | Completion timestamps +90 min |
| `focus_streak_writing.json` | 3 flow sessions, writing category |

Example event sequence:

```json
{
  "scenarioId": "LEARN-001",
  "taskId": "gym-tuesday",
  "events": [
    { "week": 1, "type": "defer", "dayOfWeek": 3 },
    { "week": 2, "type": "defer", "dayOfWeek": 3 },
    { "week": 3, "type": "expect_hero", "dayOfWeek": 4, "allowTuesday": false }
  ]
}
```

---

## Failure modes

| Failure | Symptom | Severity |
|---------|---------|----------|
| **No learning** | Same failing suggestion forever | S1 |
| **Over-learning** | One skip changes entire schedule | S2 |
| **Wrong axis** | Moves task time but not day | S2 |
| **Amnesia** | Learning lost after app restart | S1 |
| **Ghost learning** | Adapts to another user's data | S1 (security) |

---

## Evaluation log template

| Run ID | Scenario | Week/injection | Expected | Actual | Pass |
|--------|----------|----------------|----------|--------|------|
| LR-001 | LEARN-001 | 3 defer | Wed hero | | ☐ |

---

## Release gate

- [ ] LO-LEARN-001 accelerated fixture **PASS** on staging  
- [ ] LO-LEARN-004 **PASS**  
- [ ] LO-LEARN-007 **PASS** (reset clears memory)  
- [ ] No open S1 learning failures in [brain-bugs.md](brain-bugs.md)

---

## Relationship to other docs

| Doc | Relationship |
|-----|--------------|
| [15-decision-quality-framework.md](15-decision-quality-framework.md) | Learning should **improve** DQS over weeks |
| [17-digital-twin-validation.md](17-digital-twin-validation.md) | Twin parameters feed learning rate |
| [08-executive-brain-validation.md](08-executive-brain-validation.md) | Static pipeline tests |
| [11-regression-suite.md](11-regression-suite.md) | `BehaviorMemoryStoreTests` Tier 1 |
