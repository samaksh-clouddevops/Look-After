#!/usr/bin/env bash
#
# setup-tanya.sh — One-command Mac setup for Tanya (no flags, no prompts).
#
# Usage (from repo root, after git clone / git pull):
#   ./Scripts/setup-tanya.sh
#
# Hardcoded for Tanya's machine:
#   • Bundle prefix: com.tanyachandravanshi.lookafter
#   • Clears Samaksh's DEVELOPMENT_TEAM (QZYBP8F6F5)
#   • Creates GoogleService-Info.plist, regenerates Xcode project, resolves packages
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# --- Tanya's identifiers (do not prompt) ---
TANYA_PREFIX="com.tanyachandravanshi.lookafter"
TANYA_IOS_APP="${TANYA_PREFIX}.app"
TANYA_WIDGET="${TANYA_PREFIX}.app.widget"
TANYA_GROUP="group.${TANYA_PREFIX}"

log() { printf '→ %s\n' "$*"; }

log "Look After setup for Tanya — bundle prefix ${TANYA_PREFIX}"

if ! command -v xcodegen >/dev/null 2>&1; then
  printf 'Install XcodeGen first: brew install xcodegen\n' >&2
  exit 1
fi

PLIST="Config/GoogleService-Info.plist"
EXAMPLE="Config/GoogleService-Info.plist.example"
if [[ ! -f "$PLIST" ]]; then
  cp "$EXAMPLE" "$PLIST"
  log "Created Config/GoogleService-Info.plist from example."
fi

log "Reconfiguring signing, bundle IDs, entitlements, and App Group…"
"$ROOT/Scripts/reconfigure-signing.sh" \
  --prefix "$TANYA_PREFIX" \
  --clear-team \
  --update-firebase

log "Resolving Swift package dependencies…"
xcodebuild -resolvePackageDependencies -project LookAfter.xcodeproj -scheme LookAfter-iOS

cat <<EOF

✅ Tanya's Mac setup complete.

Open LookAfter.xcodeproj, then for BOTH targets (LookAfter-iOS and LookAfterWidget):
  • Signing & Capabilities → Automatically manage signing: ON
  • Team → Tanya's Apple ID / Personal Team

Then: Product → Clean Build Folder (Shift+Cmd+K) → Build.

Your bundle IDs:
  iOS app:   ${TANYA_IOS_APP}
  Widget:    ${TANYA_WIDGET}
  App Group: ${TANYA_GROUP}

EOF
