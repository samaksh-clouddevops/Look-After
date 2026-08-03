# 6. Edge Cases

**Document ID:** QA-06  
**Parent:** [README.md](README.md)

Systematic edge-case matrix for data, permissions, network, and device state.

---

## Edge Case Matrix

| ID | Category | Condition | Affected features | Expected behaviour | Test ID |
|----|----------|-----------|-------------------|-------------------|---------|
| EDGE-D01 | Data | No tasks | Briefing hero | Calm empty hero; suggest capture/onboarding | LO-IOS-FN-001 |
| EDGE-D02 | Data | No health data | Capacity card | Recovery/default band + connect prompt | LO-DATA-FN-011 |
| EDGE-D03 | Data | Partial health (1 night sleep) | Capacity | Lower confidence; no Peak Focus | LO-DATA-FN-011 |
| EDGE-D04 | Data | Corrupted local JSON store | Bootstrap | Reset corrupt store; user message | LO-DATA-FN-017 |
| EDGE-D05 | Data | Duplicate task IDs after merge | Task list | Dedupe via merge rules | LO-DATA-FN-001 |
| EDGE-D06 | Data | Empty life profile markdown | Life model compile | Skip compile; seed from structured sections | LO-CORE-FN-013 |
| EDGE-D07 | Data | 500+ tasks | TaskListView scroll | 60fps; pagination if implemented | LO-IOS-PERF-014 |
| EDGE-D08 | Data | Cycle anchor in future | Cycle dashboard | Validation error or clamp | LO-CORE-FN-050 |
| EDGE-D09 | Data | Period log mid-cycle (<14d gap) | Cycle anchor | No false period reset | LO-CORE-FN-051 |
| EDGE-D10 | Data | Behavior memory migration | FlowDirector | Migrator runs once | LO-DATA-FN-012 |

---

## Permission Edge Cases

| ID | Permission | Condition | Expected | Test |
|----|------------|-----------|----------|------|
| EDGE-P01 | HealthKit | Denied at onboarding | Skip path; briefing without health | FLOW-005 |
| EDGE-P02 | HealthKit | Revoked in Settings mid-session | Capacity degrades; reconnect prompt | INT-D |
| EDGE-P03 | Calendar | Denied | Timeline tasks-only; no calendar blocks | LO-IOS-FN-030 |
| EDGE-P04 | Calendar | Write denied, read granted | Read-only windows; no event create | FLOW-014 |
| EDGE-P05 | Microphone | Denied | Voice capture text fallback | FLOW-003 |
| EDGE-P06 | Speech Recognition | Denied | Transcript disabled; typing only | FLOW-003 |
| EDGE-P07 | Live Activities | Disabled system-wide | Focus session in-app only | LO-WGT-FN-003 |
| EDGE-P08 | Notifications | Denied | App functions; no push reminders | P2 |

**Info.plist keys:** `NSHealthShareUsageDescription`, `NSCalendarsFullAccessUsageDescription`, `NSCalendarsWriteOnlyAccessUsageDescription`, `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`

---

## Network Edge Cases

| ID | Condition | Expected | Test |
|----|-----------|----------|------|
| EDGE-N01 | No internet at launch | Auth blocked; cached data shown if previously synced | FLOW-001 |
| EDGE-N02 | Airplane mode after sync | Local CRUD works; queue sync | Persona P3 |
| EDGE-N03 | Slow 3G | GLM timeout → retry UI; no hang | LO-DATA-FN-015 |
| EDGE-N04 | API timeout (GLM) | AsyncTimeout fires; user message | LO-DATA-FN-015 |
| EDGE-N05 | Cancelled GLM request | No partial UI update | LO-AI-AI-001 |
| EDGE-N06 | Firebase offline persistence | Tasks readable/writable locally | LO-DATA-FN-017 |
| EDGE-N07 | Intermittent reconnect | Merge without duplicates | LO-DATA-FN-001 |

---

## Device State Edge Cases

| ID | Condition | Expected | Test |
|----|-----------|----------|------|
| EDGE-V01 | Device restart mid-focus | LA ended or recoverable session | FLOW-010 |
| EDGE-V02 | Timezone change | Task due dates recalc correctly | LO-CORE-FN-001 |
| EDGE-V03 | Clock change (manual) | Timer drift handled | LO-WGT-FN-003 |
| EDGE-V04 | Language change (system) | UI strings localize or fallback EN | P2 |
| EDGE-V05 | Dynamic Type XXXL | No clipped hero title | LO-IOS-A11Y-005 |
| EDGE-V06 | Dark mode (default) | Contrast passes | LO-IOS-A11Y-010 |
| EDGE-V07 | Reduce Motion on | Mode switch fade not scale | LO-IOS-A11Y-020 |
| EDGE-V08 | Low Power Mode | Background sync deferred | LO-DATA-FN-030 |
| EDGE-V09 | Storage full | Graceful save failure message | LO-DATA-FN-016 |
| EDGE-V10 | Low battery (<20%) | No excessive background work | LO-DATA-FN-030 |
| EDGE-V11 | Dynamic Island device | LA layout correct | LO-WGT-FN-003 |
| EDGE-V12 | iPad multitasking | Safe areas respected | LO-IOS-UX-002 |

---

## AI Edge Cases

| ID | Condition | Expected | Test |
|----|-----------|----------|------|
| EDGE-A01 | No GLM API key | Deterministic fallbacks; organize disabled | FLOW-020 |
| EDGE-A02 | Invalid API key | Clear error in settings; no crash | LO-AI-FN-003 |
| EDGE-A03 | GLM returns markdown fences | Parser strips; or retry | LO-AI-AI-001 |
| EDGE-A04 | GLM returns prose + JSON | Parser extracts JSON only | LO-AI-AI-001 |
| EDGE-A05 | Empty task list decide-for-me | Empty state; no hallucinated task | LO-AI-AI-025 |
| EDGE-A06 | Coach crisis language input | Safety response; no harmful advice | LO-AI-AI-020 |
| EDGE-A07 | Cycle insight male profile | Feature gated off entirely | LO-CORE-FN-052 |

---

## Brain Edge Cases

| ID | Condition | Expected | Test |
|----|-----------|----------|------|
| EDGE-B01 | All tasks completed | Rest/recovery intent | LO-BRAIN-FN-001 |
| EDGE-B02 | Conflicting signals (tired + deadline) | Decision documents tradeoff | LO-BRAIN-FN-005 |
| EDGE-B03 | Orchestrate during orchestrate | No deadlock; serial queue | LO-AI-FN-001 |
| EDGE-B04 | Factory reset during tick | Cancelled; clean state | FLOW-008 |

---

## Security Edge Cases

| ID | Condition | Expected | Test |
|----|-----------|----------|------|
| EDGE-S01 | API key in clipboard paste | Saved to Keychain only | LO-DATA-SEC-001 |
| EDGE-S02 | Sign out | In-memory caches cleared | LO-DATA-SEC-007 |
| EDGE-S03 | Jailbroken device | No additional crash; standard disclaimer P3 | P3 |
| EDGE-S04 | Health data in log | Never appears in os_log | LO-DATA-SEC-003 |
| EDGE-S05 | Shared device sign-in | userId scoping isolates data | LO-DATA-SEC-002 |

---

## Visual Edge Cases

| ID | Condition | Expected | Test |
|----|-----------|----------|------|
| EDGE-U01 | Long hero title (100+ chars) | Truncate with ellipsis | LO-IOS-UX-005 |
| EDGE-U02 | Zero-state all modules | EmptyStateView on each | LO-FEAT-FN-031 |
| EDGE-U03 | Toast stacking | Latest toast visible | LO-IOS-UX-003 |
| EDGE-U04 | Keyboard covers onboarding field | Scroll + dismiss toolbar | S25 |
| EDGE-U05 | Sheet on sheet | Dismiss order correct | S02 |

---

## Edge Case Execution Checklist

- [ ] All EDGE-D* data cases  
- [ ] All EDGE-P* permission cases (physical device)  
- [ ] All EDGE-N* network cases  
- [ ] All EDGE-V* device state cases  
- [ ] All EDGE-A* AI cases (staging GLM key)  
- [ ] All EDGE-B* brain cases  
- [ ] All EDGE-S* security cases  
- [ ] All EDGE-U* visual cases  

**Estimated effort:** 2 days manual on staging build.
