# iOS 26 ship package

**Document ID:** REL-IOS26-SHIP  
**Revamp plan:** [QA-IOS26-01](../qa/ios26-revamp-plan.md)  
**Gate checklist:** [QA-12](../qa/12-release-checklist.md)

Phases **A–I** of the iOS 26 / macOS 26 revamp are implemented in code. Phase **J** is store readiness: assets, review notes, and an OS-floor-aware release checklist.

| J step | Artifact |
|---|---|
| J1 Screenshots / preview | [ios26-screenshot-shot-list.md](ios26-screenshot-shot-list.md) |
| J2 Review notes | [app-store-review-notes-ios26.md](app-store-review-notes-ios26.md) |
| J3 Release checklist | [12-release-checklist.md](../qa/12-release-checklist.md) (iOS 26 section) |

## OS floor (locked)

| Platform | Minimum |
|---|---|
| iPhone / iPad | **iOS 26.0** |
| Mac | **macOS 26.0** |
| Toolchain | Xcode 26.x, iOS 26 SDK |
| CI / local sim | `iPhone 17`, OS 26.5 (or current GM sim) |

`project.yml` deployment targets: `iOS: 26.0`, `macOS: 26.0`.

## Permission / privacy (J2)

Usage descriptions for Health, Calendar, Microphone, and Speech Recognition remain in spirit as shipped in Phase A. Confirm App Store Connect privacy nutrition labels still match.

**Done:** `PrivacyInfo.xcprivacy` shipped for the iOS app and widget targets (`Apps/LookAfter-iOS/PrivacyInfo.xcprivacy`, `Apps/LookAfterWidget/PrivacyInfo.xcprivacy`). Reconcile ASC privacy nutrition labels with the manifest before GA.

## Pre-upload commands

```bash
cd Look-After
xcodegen generate
xcodebuild -scheme LookAfter-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  build CODE_SIGNING_ALLOWED=NO
xcodebuild -scheme LookAfter-macOS \
  -destination 'platform=macOS' \
  build CODE_SIGNING_ALLOWED=NO
```

Then archive/sign on a paid Team machine for TestFlight / App Store.
