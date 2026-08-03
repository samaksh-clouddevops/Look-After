# LifeOS Packages

All folders here are **Swift packages** (each has a `Package.swift`). They are **not** standalone Xcode apps.

## One workspace rule

Open **only** the main project — never individual package folders in a second window:

```bash
cursor /Users/samaksh/ADHD/LifeOS/LifeOS.code-workspace
```

| Package | Role |
|---------|------|
| `LifeOSCore` | Domain, scheduling, semantics, UI design system |
| `ExecutiveBrain` | Deterministic decision engine |
| `LifeOSAI` | LLM providers, semantic understanding |
| `LifeOSData` | Persistence, Firebase |
| `LifeOSFeatures` | ViewModels, feature logic |
| `LifeOSHealth` | HealthKit |

## If you see package errors

1. Close all Xcode/Cursor windows
2. Reopen `LifeOS.code-workspace` (not `Packages/…`)
3. In Xcode: **File → Packages → Reset Package Caches** (if needed)

## Command-line tests per package

```bash
cd Packages/LifeOSCore && swift test
cd Packages/ExecutiveBrain && swift test
```
