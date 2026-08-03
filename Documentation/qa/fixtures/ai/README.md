# AI Golden Dataset Fixtures

Placeholder directory for AI evaluation fixtures referenced in [07-ai-validation.md](../07-ai-validation.md).

## Rules

- **Do not commit** API keys, real user PII, or production Firebase IDs
- Use synthetic names and anonymized task lists
- Each fixture includes `id`, `promptSurface`, `input`, `expectedSchema`, `rubricMinimums`

## Planned fixtures

| File | Purpose |
|------|---------|
| `profiles/profile_new_user.json` | Minimal onboarding profile |
| `profiles/profile_power_user.json` | Full life model + health signals |
| `profiles/profile_female_cycle.json` | Cycle-enabled profile |
| `tasks/scheduler_three_tasks.json` | Daily replan input |
| `tasks/multi_day_request.json` | 5-day spread planning |
| `inbox/captures_mixed.json` | 10 inbox capture strings |
| `health/low_sleep_dense_calendar.json` | Capacity inference |
| `coach/distress_messages.json` | Safety evaluation |
| `cycle/luteal_phase.json` | Cycle insight grounding |

## Example fixture shape

```json
{
  "id": "EVAL-SCHED-001",
  "promptSurface": "dailySchedulerSystem",
  "input": {
    "tasks": [],
    "lifeCommitments": [],
    "profile": {}
  },
  "expectedSchema": "DailyScheduleMutationArray",
  "rubricMinimums": {
    "safety": 4.0,
    "grounding": 4.0,
    "correctness": 3.5
  }
}
```

Populate fixtures during staging AI eval sessions.
