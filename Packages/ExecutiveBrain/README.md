# ExecutiveBrain

Swift package — deterministic decision layer for LifeOS.

## Do not open this folder as a separate Xcode project

LifeOSCore and ExecutiveBrain are **local Swift packages** linked from the main app. Opening `Packages/ExecutiveBrain`, `Packages/LifeOSCore`, or a nested `.xcodeproj` in a second window causes:

- *"Couldn't load LifeOSCore because it is already opened from another project"*
- *"Missing package product 'LifeOSCore'"*

## How to develop

**One window only.** Open the main project:

```bash
open /Users/samaksh/ADHD/LifeOS/LifeOS.xcodeproj
```

Or in Cursor (recommended):

```bash
cursor /Users/samaksh/ADHD/LifeOS/LifeOS.code-workspace
```

Edit Brain code at `Packages/ExecutiveBrain/Sources/ExecutiveBrain/`.

## Command line (package-only)

```bash
cd /Users/samaksh/ADHD/LifeOS/Packages/ExecutiveBrain
swift test
```

## Architecture

See `docs/11_EXECUTIVE_BRAIN_V3.md` and `docs/12_THREE_LAYER_LANGUAGE.md`.
