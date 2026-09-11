# Build and Test

Run all commands from the **LifeOS repo root**.

## Regenerate Xcode project

```bash
xcodegen generate
```

Run after any change to `project.yml` or top-level folder moves.

## iOS build

Requires **Xcode 26** (iOS 26 / macOS 26 SDK).

```bash
xcodebuild -scheme LookAfter-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  build
```

## macOS build

```bash
xcodebuild -scheme LookAfter-macOS \
  -destination 'platform=macOS' \
  build
```

## Xcode test suite

```bash
xcodebuild -scheme LookAfter-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  test
```

## Package unit tests

```bash
cd Packages/LookAfterCore && swift test
cd Packages/ExecutiveBrain && swift test
cd Packages/LookAfterData && swift test
cd Packages/LookAfterFeatures && swift test
```

## UX agent screenshots

Capture core screens for Cursor + `ui-ux-pro-max` review:

```bash
./Scripts/capture-ux-review.sh
```

See [qa/ux-agent-screenshot-pipeline.md](qa/ux-agent-screenshot-pipeline.md). Output: `screenshots/ux-agent/latest/`.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Missing scheme | `xcodegen generate` |
| Stale DerivedData | Delete `~/Library/Developer/Xcode/DerivedData/LifeOS-*` |
| Signing errors | `./Scripts/reconfigure-signing.sh` |
| Package not found | Clean build folder in Xcode (⇧⌘K) |
