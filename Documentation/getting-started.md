# Getting Started

## Prerequisites

- macOS with Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Clone and open

```bash
git clone <repo-url> Look-After
cd Look-After
./Scripts/bootstrap.sh
open LookAfter.xcodeproj
```

`Config/GoogleService-Info.plist` is included as a **dummy template** (offline mode). Replace it with your Firebase console download for cloud sync.

Or open `LookAfter.code-workspace`.

## Firebase (optional — cloud sync)

Replace the dummy config with your project file from the Firebase console:

```bash
cp /path/to/your/GoogleService-Info.plist Config/GoogleService-Info.plist
```

If the file is missing after clone, run `./Scripts/bootstrap.sh` or:

```bash
cp Config/GoogleService-Info.plist.example Config/GoogleService-Info.plist
```

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
