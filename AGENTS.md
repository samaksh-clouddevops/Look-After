# Agent guide — Look After

Swift / SwiftUI Apple app. Agent skills:

- [Swift Agent Skills](https://github.com/twostraws/Swift-Agent-Skills) (Paul Hudson)
- [swift-ios-skills](https://github.com/dpearson2699/swift-ios-skills) (local clone)

Installed / routed Cursor skills (read on Swift work):

- `swift-agent-skills` (router — both catalogs)
- `swiftui-pro`, `swift-concurrency-pro`, `swift-testing-pro` — Paul Hudson
- `~/.cursor/skills-src/swift-ios-skills/skills/<name>/SKILL.md` — dpearson pack (load only the matching skill)

## Role

Senior iOS engineer for Look After: executive-function companion (Today, Briefing, Brain, HealthKit, widgets, Live Activities, licensed AI via auth-proxy).

## Project constraints

- **Program target (Phase A landed):** iOS 26 / macOS 26, Swift 6, Xcode 26. Plan: `Documentation/qa/ios26-revamp-plan.md`.
- Liquid Glass / iOS 26 chrome APIs are in scope for Phase C onward. Do not keep dual-OS `#available` forks. AlarmKit / Foundation Models / PaperKit stay out until those epics.
- Swift concurrency: prefer `async/await`, structured tasks; avoid `DispatchQueue.main.async` for new code.
- Prefer modern SwiftUI (`foregroundStyle`, `NavigationStack`, two-parameter `onChange`, iOS 26 glass/motion in chrome PRs).
- Do not introduce third-party packages without asking.
- Secrets stay out of git (`credentials`, `.env`, API keys on Azure only).
- Preserve package module boundaries under `Packages/`.

## When editing code

1. Read the matching skill under `~/.cursor/skills/` **and** the matching dpearson skill under `~/.cursor/skills-src/swift-ios-skills/skills/` before large SwiftUI/concurrency/test changes.
2. Follow that skill’s checklist; load only named reference files.
3. Report real issues only — no nitpicks.
4. Match existing Look After patterns in the file you touch.
