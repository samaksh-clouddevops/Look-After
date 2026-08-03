# Getting Started

## Prerequisites

- macOS with Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Clone and open

```bash
git clone <repo-url> LifeOS
cd LifeOS
xcodegen generate
open LookAfter.xcodeproj
```

Or open `LifeOS.code-workspace`.

## Firebase (optional)

Copy your Firebase config:

```bash
cp /path/to/your/GoogleService-Info.plist Config/GoogleService-Info.plist
```

This file is gitignored. The app runs without it (local-only mode).

## Signing

For device builds, run:

```bash
./Scripts/reconfigure-signing.sh
```

## Select a scheme

| Scheme | Platform |
|--------|----------|
| LookAfter-iOS | iPhone / iPad |
| LookAfter-macOS | macOS |
| LookAfterWidget | Widget extension (built with iOS) |

## Next steps

- [build-and-test.md](build-and-test.md) — verify your setup
- [package-guide.md](package-guide.md) — where to add code
