# LifeOSCore

Shared domain models, scheduling engines, semantic layer, and design system for LifeOS.

## Do not open this folder as a separate Xcode project

LifeOSCore is a **local Swift package** consumed by `LifeOS.xcodeproj`. Opening `Packages/LifeOSCore` in its own Xcode/Cursor window while the main app is open causes:

- *"Couldn't load LifeOSCore because it is already opened from another project"*

## How to develop

Open the main project once:

```bash
cursor /Users/samaksh/ADHD/LifeOS/LifeOS.code-workspace
```

Edit Core code at `Packages/LifeOSCore/Sources/LifeOSCore/`.

## Command line

```bash
cd /Users/samaksh/ADHD/LifeOS/Packages/LifeOSCore
swift test
```
