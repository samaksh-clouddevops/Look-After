# WorldState field map (Android ↔ iOS)

Phase B2 expansion. Pure fields live in `com.lookafter.core.brain.WorldState`.

| Field | Type | Source | Coach / plan use |
|-------|------|--------|------------------|
| `currentEnergy` | 0..1 | Capacity engine (prefer) / readiness | Coach bias |
| `cognitiveLoad` | enum | open + meetings + readiness | Strip guidance |
| `sleepHoursLastNight` | Double? | Health Connect / demo | Recovery bias |
| `sleepQuality` | enum | hours + score | Sleep replies |
| `healthReadiness` | 0..1 | Health summary | Capacity input |
| `availableMinutes` | Int | until next event ∩ work | Planning window |
| `minutesUntilNextEvent` | Int? | calendar | Buffer language |
| `nextEventTitle` | String? | calendar | Briefing/calendar line |
| `isMeetingHeavyDay` | Bool | density BUSY/PACKED | Capacity + coach |
| `calendarEventCount` | Int | events in −4h…+14h | Density |
| `calendarDensity` | CLEAR…PACKED | event count bands | Coach / plan |
| `anchoredOpenCount` | Int | board | Breakdown |
| `flexibleOpenCount` | Int | board | Breakdown |
| `fluidOpenCount` | Int | board | Strip priority |
| `openTaskPressure` | 0..1 | count + minutes | Overwhelm |
| `capacityBand` | CapacityBand | ExecutiveCapacityEngine | Envelope |
| `capacityEnergyScore` | 0..1 | capacity | Prompts |
| `recommendedFocusMinutes` | Int | capacity | Focus CTAs |
| `isOverCommitted` | Bool | capacity | Force strip |
| `medicationRisk` | NONE…MISSED | med status map | Care priority |
| `medicationStatus` | sealed | inventory × clock | Med replies |
| `openTaskCount` | Int | active | Board |
| `completedTodayCount` | Int | completed | Briefing nudge |
| `plannedOpenMinutes` | Int | sum durations | Load |
| `heroTaskId` / reason | — | HeroTaskRanker | Decision |
| `consecutiveHighLoadDays` | Int | LifeState | Capacity |

## Golden helper

`BrainContextPack.fieldMap(world)` — stable string map for snapshot tests.

## Consumers

- Briefing narrative / capacity card  
- Brain World card  
- Streaming coach system prompt  
- LLM multi-day planner system prompt  
- Notification policy (via open/completed counts)  
