# LifeOS Documentation

Architecture and contributor guides for the LifeOS monorepo.

## Quick links

| Document | Purpose |
|----------|---------|
| [getting-started.md](getting-started.md) | Clone, open, first build |
| [build-and-test.md](build-and-test.md) | xcodebuild and swift test commands |
| [package-guide.md](package-guide.md) | Where to put new code |
| [architecture/dependencies.md](architecture/dependencies.md) | Package dependency graph |
| [architecture/macOS-shared-views.md](architecture/macOS-shared-views.md) | Why macOS compiles iOS views |
| [architecture/adr/](architecture/adr/) | Architecture decision records |
| [architecture/WIDGET_SYSTEM_V2.md](architecture/WIDGET_SYSTEM_V2.md) | Widget System V2 — Executive Brain ecosystem |
| [ATTENTION_OS_SPEC.md](ATTENTION_OS_SPEC.md) | Attention OS product spec |
| [future-work.md](future-work.md) | Deferred improvements |

## Repository layout

```
LifeOS/
├── Apps/              # iOS, macOS, Widget targets
├── Assets/            # Shared asset catalogs (future)
├── Config/            # Entitlements, GoogleService-Info, signing template
├── Documentation/     # This folder
├── Packages/          # Six Swift packages
├── Scripts/           # Developer scripts
├── Tools/             # CI helpers (future)
├── Tests/             # Integration tests (future)
├── project.yml        # XcodeGen source of truth
└── LookAfter.xcodeproj/  # Generated — do not hand-edit
```

## Package overview

See [Packages/README.md](../Packages/README.md).
