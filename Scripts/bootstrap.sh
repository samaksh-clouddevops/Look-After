#!/usr/bin/env bash
# First-run setup after clone — Firebase plist, Xcode project, Swift packages.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PLIST="Config/GoogleService-Info.plist"
EXAMPLE="Config/GoogleService-Info.plist.example"

if [[ ! -f "$PLIST" ]]; then
  cp "$EXAMPLE" "$PLIST"
  echo "Created $PLIST from example (offline/mock Firebase)."
fi

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
  echo "Regenerated LookAfter.xcodeproj"
else
  echo "Install XcodeGen: brew install xcodegen"
  exit 1
fi

echo "Resolving Swift package dependencies (Firebase, etc.)…"
xcodebuild -resolvePackageDependencies -project LookAfter.xcodeproj -scheme LookAfter-iOS

cat <<'EOF'

Next in Xcode:
  1. Open LookAfter.xcodeproj
  2. Targets LookAfter-iOS AND LookAfterWidget → Signing & Capabilities
     • Automatically manage signing: ON
     • Team: your Apple ID (Personal Team is OK)
  3. Product → Clean Build Folder (Shift+Cmd+K)
  4. Build — try Simulator first if device linking fails

If "Command Ld failed" persists on device:
  • Ensure both iOS app and Widget use the same Team
  • File → Packages → Reset Package Caches, then resolve again
  • Delete Derived Data: Xcode → Settings → Locations → Derived Data → arrow → delete LookAfter folder

EOF
