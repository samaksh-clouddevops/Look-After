# Build and Test

Run all commands from the **LifeOS repo root**.

## Regenerate Xcode project

```bash
xcodegen generate
```

Run after any change to `project.yml` or top-level folder moves.

## iOS build

```bash
xcodebuild -scheme LookAfter-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
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
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

## Package unit tests

```bash
cd Packages/LookAfterCore && swift test
cd Packages/ExecutiveBrain && swift test
cd Packages/LookAfterData && swift test
cd Packages/LookAfterFeatures && swift test
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Missing scheme | `xcodegen generate` |
| Stale DerivedData | Delete `~/Library/Developer/Xcode/DerivedData/LifeOS-*` |
| Signing errors | `./Scripts/reconfigure-signing.sh` |
| Package not found | Clean build folder in Xcode (⇧⌘K) |
