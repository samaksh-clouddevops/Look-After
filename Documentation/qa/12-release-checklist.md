# 12. Release Checklist

**Document ID:** QA-12  
**Parent:** [README.md](README.md)

Pre-release gate checklist for App Store / TestFlight GA.

---

## Build & Infrastructure

- [ ] Version and build number incremented in `Apps/LookAfter-iOS/Info.plist`
- [ ] `xcodegen generate` run if `project.yml` changed
- [ ] iOS build succeeds: `xcodebuild -scheme LookAfter-iOS -destination 'platform=iOS Simulator,name=iPhone 17' build`
- [ ] macOS build succeeds: `xcodebuild -scheme LookAfter-macOS -destination 'platform=macOS' build`
- [ ] Signing verified on physical device (Team ID, App Groups, entitlements)
- [ ] `./Scripts/reconfigure-signing.sh` run on non-owner Macs if needed
- [ ] `GoogleService-Info.plist` present locally (not committed); template documented in Config
- [ ] Firebase security rules reviewed for release environment
- [ ] No debug-only API endpoints in release configuration

---

## Automated Regression

- [ ] **Tier 1** — All package `swift test` pass (54 files)
- [ ] **Tier 2** — `xcodebuild -scheme LookAfter-iOS test` pass
- [ ] No new compiler warnings treated as errors in CI
- [ ] `.build/` and `build/` not in release artifact

---

## Manual P0 Validation

- [ ] **Tier 3 smoke** — FLOW-001 through FLOW-010 pass
- [ ] All **P0** test cases pass ([03-module-test-cases.md](03-module-test-cases.md))
- [ ] Interrupted flow INT-C on FLOW-002 (kill/relaunch)
- [ ] Physical device: HealthKit sync (FLOW-005)
- [ ] Physical device: Live Activity (FLOW-010)

---

## Defect Status

- [ ] **Zero open P0** defects
- [ ] **Zero open S1** defects
- [ ] **Zero open S2** defects (or explicit waivers with Product approval)
- [ ] All fixed defects have linked regression test or case ID

---

## AI & Brain Quality

- [ ] AI golden set evaluated on staging ([07-ai-validation.md](07-ai-validation.md))
- [ ] Safety score ≥ **4.0 / 5.0** average
- [ ] Grounding score ≥ **4.0 / 5.0** average
- [ ] Brain audit samples (BRAIN-FIX-001–004) reviewed
- [ ] No LLM shame language in coach/distress fixtures (LO-AI-AI-020)
- [ ] Red-team hallucination audit pass ([18-ai-hallucination-audit.md](18-ai-hallucination-audit.md)) — zero P0 fabrications

## Decision Quality Moat (Phase 6)

- [ ] Mean **DQS ≥ 3.8** on n ≥ 50 staging samples ([15-decision-quality-framework.md](15-decision-quality-framework.md))
- [ ] Mean **HRS ≥ 3.8** ([20-human-evaluation-protocol.md](20-human-evaluation-protocol.md))
- [ ] Follow-through rate ≥ **60%**
- [ ] LO-COST-001 Executive Cost ordering **PASS** ([19-executive-cost-validation.md](19-executive-cost-validation.md))
- [ ] LO-TWIN-001 morning vs night owl **PASS** ([17-digital-twin-validation.md](17-digital-twin-validation.md))
- [ ] LO-LEARN-001 gym skip adaptation **PASS** ([16-learning-validation.md](16-learning-validation.md))
- [ ] [brain-bugs.md](brain-bugs.md) reviewed — **zero open Critical**

---

## Performance

- [ ] Cold launch < **2.5s** on reference device (within 10% tolerance)
- [ ] Hero brain refresh < **2.0s**
- [ ] GLM planning end-to-end < **15s** on WiFi
- [ ] Memory steady-state < **250 MB**
- [ ] Results logged in [09-performance-benchmarks.md](09-performance-benchmarks.md) template

---

## Accessibility

- [ ] VoiceOver walkthrough: onboarding + hero + task complete
- [ ] Dynamic Type XXXL on TodayView, TaskListView, OnboardingView
- [ ] Reduce Motion on experience mode switch and focus timer
- [ ] All LO-IOS-A11Y **P0** cases pass

---

## Security & Privacy

- [ ] API keys stored in Keychain only (LO-DATA-SEC-001)
- [ ] Health data not in analytics payloads (LO-DATA-SEC-003)
- [ ] Factory reset clears sensitive data (LO-DATA-SEC-004)
- [ ] App Privacy labels match: Health, Calendar, Microphone, Speech Recognition
- [ ] Privacy policy URL live (if required for App Store)
- [ ] No API keys or PII in crash logs

---

## UX & Product

- [ ] 3-second test pass on S05, S14, S25, S30, S35
- [ ] Onboarding gender gating for cycle verified
- [ ] Experience mode switch data parity (FLOW-009)
- [ ] Empty states show helpful guidance (no dead ends)
- [ ] North-star metric instrumentation verified (meaningful task completion events)

---

## TestFlight Soak

- [ ] TestFlight build uploaded
- [ ] **48-hour** minimum soak with internal testers
- [ ] Zero crash-free rate regressions below **99%**
- [ ] No energy/battery anomaly reports
- [ ] Widget and background sync validated by ≥2 testers

---

## Documentation

- [ ] [Documentation/qa/](README.md) framework version noted in release notes
- [ ] Known issues list published (if any P3/waived S3)
- [ ] Runbook for GLM key setup for testers

---

## Production Readiness

- [ ] Score calculated per [14-production-readiness.md](14-production-readiness.md)
- [ ] Overall score ≥ **85 / 100**
- [ ] Sign-off signatures recorded (QA Lead, Eng Lead, Product)

---

## Release Sign-off Block

| Role | Name | Date | Build # | Approved |
|------|------|------|---------|----------|
| QA Lead | | | | ☐ |
| Engineering Lead | | | | ☐ |
| Product | | | | ☐ |

**Release decision:** ☐ Ship  ☐ Hold  ☐ Ship with waivers (attach waiver doc)

---

## Post-Release (within 72h)

- [ ] Monitor crash analytics
- [ ] Monitor GLM error rates / timeouts
- [ ] Verify Firebase auth success rate
- [ ] Triage user feedback against [13-risk-assessment.md](13-risk-assessment.md)
