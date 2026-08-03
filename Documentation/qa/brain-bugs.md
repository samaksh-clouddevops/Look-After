# Brain Bugs Log

**Document ID:** QA-BRAIN-BUGS  
**Parent:** [README.md](README.md)

Track **decision mistakes** separately from software bugs.

> A recommendation can be technically correct (no crash, no API error) and still be the wrong decision.

**Issue tracker label:** `brain-decision`  
**Sub-labels:** `hallucination`, `executive-cost`, `learning-fail`, `twin-ignore`, `timing-wrong`

---

## When to file here vs issue tracker

| Situation | Where |
|-----------|-------|
| Crash, data loss, auth failure | Issue tracker (S1–S4) |
| Wrong recommendation, bad timing, ignored sleep | **Here** + `brain-decision` label |
| Invented medication, fake calendar event | **Here** + `hallucination` — **P0** |
| Brain improved after user skipped 3× but didn't adapt | **Here** + `learning-fail` |

---

## Entry template

```markdown
### Brain Issue #{NNN}

**Filed:** YYYY-MM-DD  
**Status:** Open | Investigating | Fixed | Won't fix  
**Severity:** Critical | Major | Minor  
**Category:** executive-cost | hallucination | learning | twin | timing | goal-mismatch | overconfidence  
**Priority:** P0 | P1 | P2  

#### Scenario
(What was the user's state? Sleep, calendar, tasks, energy, cycle, etc.)

#### Recommendation (what Brain issued)
(Exact hero text / intent / planning mutation)

#### Expected (what should have happened)
(Alternative with lower Executive Cost or better outcome)

#### Root cause
(e.g. Energy model overweighted deadlines; GLM overrode brain; behavior memory not read)

#### Evidence
- Brain Inspector trace: …
- DQ-EVAL / HRS link: …
- Exec Cost audit: …

#### Fixed in
(e.g. ExecutiveBrain v3.4, build ___, PR ___)

#### Regression
(Test ID or fixture to prevent recurrence)
```

---

## Example entries

### Brain Issue #12

**Filed:** 2026-08-01  
**Status:** Open  
**Severity:** Critical  
**Category:** executive-cost  
**Priority:** P0  

#### Scenario
User slept **4h 52m**. Calendar shows 4 meetings before noon. Cognitive load: overloaded.

#### Recommendation
**Start 90-minute deep work** on quarterly report.

#### Expected
**20-minute recovery walk** or split micro-task — Executive Cost 18 vs 54 ([19-executive-cost-validation.md](19-executive-cost-validation.md)).

#### Root cause
Energy model underweighted sleep deficit; deadline urgency overweighted in `DecisionEngine` / hero eligibility.

#### Evidence
- DQ-EVAL-012 DQS 1.8  
- Human eval: Would follow? **No** — "I knew I'd fail"  
- LO-COST-001 **FAIL**

#### Fixed in
_TBD — ExecutiveBrain / SimulationEngine weight tuning_

#### Regression
LO-COST-001, LO-TWIN-003, DQ-EVAL fixture `sleep_deprived_deadline.json`

---

### Brain Issue #H-001

**Filed:** 2026-08-02  
**Status:** Fixed  
**Severity:** Critical  
**Category:** hallucination  
**Priority:** P0  

#### Scenario
No medications configured in profile or Medication module.

#### Recommendation
Coach: "Take your **Adderall at 2 PM** with lunch."

#### Expected
"I don't see medications set up — add them in Medication settings."

#### Root cause
GLM coach prompt lacked hard guard when med list empty.

#### Fixed in
LifeOSPrompts coach guard + empty-state check — build 1.0.1

#### Regression
LO-HALL-001

---

### Brain Issue #L-003

**Filed:** 2026-08-03  
**Status:** Investigating  
**Severity:** Major  
**Category:** learning-fail  
**Priority:** P1  

#### Scenario
User deferred **Tuesday gym** 3 consecutive weeks.

#### Recommendation
Week 4: Still hero **Tuesday 7 AM gym**.

#### Expected
Shift to Wednesday per [16-learning-validation.md](16-learning-validation.md) LEARN-001.

#### Root cause
Behavior defer events recorded but `FlowSchedulingEngine` not shifting recurring commitment.

#### Regression
LO-LEARN-001

---

## Severity guide (brain-specific)

| Severity | Definition | SLA |
|----------|------------|-----|
| **Critical** | Health/safety wrongness, fabrication, sustained harm to trust | Fix before ship |
| **Major** | Consistently wrong class of decisions for persona | Fix within sprint |
| **Minor** | Occasional suboptimal; acceptable tradeoff explained | Backlog |

---

## Weekly review checklist

- [ ] All new `brain-decision` issues copied or linked here  
- [ ] Critical count = 0 for release branch  
- [ ] Each Fixed entry has regression test ID  
- [ ] Trends: top 3 root cause categories  
- [ ] Feed patterns into [16-learning-validation.md](16-learning-validation.md) fixtures  

---

## Metrics

| Metric | Target |
|--------|--------|
| Open Critical brain bugs | 0 at ship |
| Mean time to fix Critical | < 5 days |
| Repeat root cause | 0 per quarter |
| Brain bugs / 100 decisions | Trend down |

---

## Cross-references

- [15-decision-quality-framework.md](15-decision-quality-framework.md)  
- [18-ai-hallucination-audit.md](18-ai-hallucination-audit.md)  
- [19-executive-cost-validation.md](19-executive-cost-validation.md)  
- [20-human-evaluation-protocol.md](20-human-evaluation-protocol.md)

---

## Change log

| Date | Change |
|------|--------|
| 2026-08 | Initial log with examples #12, #H-001, #L-003 |
