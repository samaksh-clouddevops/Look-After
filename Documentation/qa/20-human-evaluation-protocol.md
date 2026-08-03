# 20. Human Evaluation Protocol

**Document ID:** QA-20  
**Parent:** [README.md](README.md)

Ground-truth human ratings for every AI/brain recommendation — builds the dataset that improves the product over time.

**Use with:** [15-decision-quality-framework.md](15-decision-quality-framework.md), [brain-bugs.md](brain-bugs.md)

---

## When to collect ratings

| Trigger | Rater | Timing |
|---------|-------|--------|
| Hero recommendation displayed | User (in-app) or study participant | After seeing, before acting |
| Hero recommendation completed/skipped | User | Within 30 min of action |
| Planning conversation apply | User + QA | After preview confirm |
| AI Coach actionable suggestion | User | End of session |
| Weekly staging audit | QA + Product panel | Batch review |

**Minimum for release:** 50 rated recommendations on staging build per release candidate.

---

## Rating form (per recommendation)

### Quantitative (1–5 unless noted)

| Metric | Question | 1 | 3 | 5 |
|--------|----------|---|---|---|
| **Helpful** | Did this help you make progress? | Not at all | Somewhat | Very |
| **Personalized** | Did this feel meant for you specifically? | Generic | Mixed | Tailored |
| **Correct timing** | Was now the right moment for this? | Wrong time | Okay | Perfect timing |
| **Clear** | Did you understand what it was asking? | Confusing | Mostly | Crystal clear |
| **Actionable** | Could you start immediately? | No idea how | With effort | Immediately |
| **Trustworthy** | Do you trust this suggestion? | Don't trust | Neutral | Fully trust |

### Binary + free text

| Field | Type |
|-------|------|
| **Would I follow it?** | Yes / No / Already did / N/A |
| **Why?** | Free text (required if any score ≤ 2 or Would follow = No) |

### Optional context (auto-captured when possible)

- Recommendation ID / brain tick timestamp  
- Hero task ID  
- Sleep band, capacity band  
- Experience mode (Classic / AI Executive)  
- GLM involved? (Y/N)  

---

## Aggregated indices

### Human Recommendation Score (HRS)

```
HRS = mean(Helpful, Personalized, Correct timing, Clear, Actionable, Trustworthy)
```

| HRS | Action |
|-----|--------|
| ≥ 4.0 | Exceeds bar |
| 3.5–3.9 | Ship with monitoring |
| 3.0–3.4 | Block GA until root cause |
| < 3.0 | Stop-the-line; brain review |

### Follow-through rate

```
FTR = (Would follow = Yes or Already did) / total ratings
```

**Target:** ≥ 65% on staging personas P1–P2.

---

## Study protocol (structured sessions)

### Participants

- n ≥ 5 per release candidate  
- Mix: new user (P1), power user (P2), accessibility (P4)  
- Consent for recording quotes (no PII in docs)

### Session script (45 min)

1. **10 min** — Onboarding / fixture profile load  
2. **15 min** — Free use; trigger ≥3 hero cycles  
3. **10 min** — Planning or coach feature  
4. **10 min** — Rate last 5 recommendations using form above  
5. **Debrief** — "When did the Brain feel wrong?"  

### Facilitator rules

- Do not defend the Brain  
- Capture **brain-bugs** live when user says "that's wrong"  
- Distinguish UX confusion from decision wrongness  

---

## Data storage

| Field | Storage recommendation |
|-------|------------------------|
| Ratings CSV | `Documentation/qa/eval-runs/YYYY-MM-DD-hrs.csv` (gitignore if PII) |
| Anonymized aggregates | Commit weekly summary to eval-runs |
| Free text | Issue tracker + brain-bugs linkage |

**CSV columns:**

```
eval_id, timestamp, persona, surface, helpful, personalized, timing, clear, actionable, trustworthy, would_follow, why, hrs, dqs, brain_bug_id
```

---

## Linking to Decision Quality

| Human signal | DQ dimension |
|--------------|--------------|
| Helpful + Actionable | Goal progress, User satisfaction |
| Correct timing | Energy optimization, Confidence calibration |
| Clear | Explainability |
| Trustworthy | Regret avoided (leading) |
| Would follow? No | Triggers DQ review + brain-bug |

Compute both **HRS** and **DQS** for same sample; correlate weekly.

**Target correlation:** HRS and DQS same direction ≥ 80% of samples.

---

## In-app prompt (future product spec)

When implementing in-product ratings:

- Max 1 prompt per day default (ADHD-respectful)  
- Thumbs down → optional "What would have been better?"  
- Never block user flow on rating  
- Sync anonymized aggregates only  

---

## QA panel weekly review

| Step | Owner |
|------|-------|
| Export last 7 days ratings | QA |
| Flag HRS < 3.0 or Would follow = No | QA |
| Triage: UX vs brain-decision vs hallucination | Product + Eng |
| File [brain-bugs.md](brain-bugs.md) entries | QA |
| Track fix in release notes | Eng |

---

## Release gate

Add to [12-release-checklist.md](12-release-checklist.md):

- [ ] n ≥ 50 human ratings on RC build  
- [ ] Mean HRS ≥ **3.8**  
- [ ] Follow-through rate ≥ **60%**  
- [ ] All "No + why" entries triaged  

---

## Test IDs

| ID | Description |
|----|-------------|
| LO-HUM-001 | Rating form completes without PII leak |
| LO-HUM-002 | 50-sample aggregation reproducible |
| LO-HUM-003 | HRS/DQS correlation computed for sprint |

---

## Cross-references

- [07-ai-validation.md](07-ai-validation.md) — LLM rubric (model-side)  
- [15-decision-quality-framework.md](15-decision-quality-framework.md) — decision-side  
- [18-ai-hallucination-audit.md](18-ai-hallucination-audit.md) — fabrication triage from free text
