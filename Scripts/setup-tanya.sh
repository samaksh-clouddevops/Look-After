#!/usr/bin/env bash
#
# setup-tanya.sh — One-command Mac setup for Tanya (no flags, no prompts).
#
# Usage (from repo root, after git clone / git pull):
#   ./Scripts/setup-tanya.sh
#
# Quit Xcode first, then run this script.
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
SAMAKSH_PREFIX="com.samaksh.flowos"

log() { printf '→ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }

log "Look After setup for Tanya — bundle prefix ${TANYA_PREFIX}"

if pgrep -xq Xcode; then
  warn "Quit Xcode completely, then run this script again."
  warn "Xcode caches old bundle IDs while the project is open."
  exit 1
fi

if grep -q "$SAMAKSH_PREFIX" LookAfter.xcodeproj/project.pbxproj 2>/dev/null; then
  log "Detected Samaksh bundle IDs — reconfiguring for Tanya…"
else
  log "Bundle IDs already look retargeted; refreshing config…"
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

if ! command -v xcodegen >/dev/null 2>&1; then
  warn "xcodegen not found — installing via Homebrew…"
  if command -v brew >/dev/null 2>&1; then
    brew install xcodegen
    xcodegen generate
  else
    warn "Homebrew missing. Install xcodegen manually: brew install xcodegen && xcodegen generate"
  fi
fi

if grep -q "$SAMAKSH_PREFIX" LookAfter.xcodeproj/project.pbxproj; then
  printf '\n❌ Bundle IDs still use %s — setup did not complete.\n' "$SAMAKSH_PREFIX" >&2
  printf '   Run: brew install xcodegen && xcodegen generate\n' >&2
  printf '   Then run again: ./Scripts/setup-tanya.sh\n' >&2
  exit 1
fi

log "Resolving Swift package dependencies…"
xcodebuild -resolvePackageDependencies -project LookAfter.xcodeproj -scheme LookAfter-iOS

cat <<EOF

✅ Tanya's Mac setup complete.

Bundle IDs are now:
  iOS app:   ${TANYA_IOS_APP}
  Widget:    ${TANYA_WIDGET}
  App Group: ${TANYA_GROUP}

Next:
  1. Open LookAfter.xcodeproj
  2. Targets LookAfter-iOS AND LookAfterWidget → Signing & Capabilities:
     • Automatically manage signing: ON
     • Team → Tanya's Apple ID / Personal Team
  3. Product → Clean Build Folder (Shift+Cmd+K) → Build

EOF
