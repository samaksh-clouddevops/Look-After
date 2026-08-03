#!/usr/bin/env bash
#
# reconfigure-signing.sh — Retarget LifeOS bundle IDs, App Groups, and dev team
# for building on another Mac / another Apple Developer account.
#
# Usage:
#   ./Scripts/reconfigure-signing.sh --prefix com.janedoe.flowos
#   ./Scripts/reconfigure-signing.sh --prefix com.janedoe.flowos --team ABCD123456
#   ./Scripts/reconfigure-signing.sh --prefix com.janedoe.flowos --clear-team
#   ./Scripts/reconfigure-signing.sh --interactive
#
# After running:
#   1. Mac owner signs into Xcode → Settings → Accounts
#   2. Open LookAfter.xcodeproj → Signing & Capabilities → pick their Team (both targets)
#   3. Register App Group + App IDs at developer.apple.com (script prints details)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# --- Defaults (current repo values) ---
OLD_PREFIX="com.samaksh.flowos"
OLD_GROUP="group.com.samaksh.flowos"
OLD_MAC_BUNDLE="com.samaksh.lifeos.mac"
OLD_FIREBASE_BUNDLE="com.samaksh.lifeos"
OLD_TEAM="QZYBP8F6F5"

NEW_PREFIX=""
NEW_GROUP=""
NEW_MAC_BUNDLE=""
NEW_TEAM=""
CLEAR_TEAM=1
DRY_RUN=0
INTERACTIVE=0
UPDATE_FIREBASE=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Required (unless --interactive):
  --prefix ID          New bundle ID prefix, e.g. com.janedoe.flowos

Optional:
  --app-group ID       App Group (default: group.<prefix>, e.g. group.com.janedoe.flowos)
  --mac-bundle ID      macOS bundle ID (default: <prefix>.mac)
  --team TEAMID        Set DEVELOPMENT_TEAM in project.pbxproj (10-char Apple Team ID)
  --clear-team         Remove hard-coded DEVELOPMENT_TEAM (default: on)
  --no-clear-team      Keep existing DEVELOPMENT_TEAM if not using --team
  --update-firebase    Also patch GoogleService-Info.plist BUNDLE_ID (cloud sync may break)
  --dry-run            Print changes without writing files
  --interactive        Prompt for values
  -h, --help           Show this help

Example (someone else's Mac — owner uses Personal Team):
  ./Scripts/reconfigure-signing.sh --prefix com.janedoe.flowos --clear-team

Then in Xcode: Settings → Accounts → sign in → pick Team on LookAfter-iOS + LookAfterWidget.
EOF
}

log() { printf '→ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }

validate_prefix() {
  local prefix="$1"
  if [[ ! "$prefix" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z0-9.-]+$ ]]; then
    warn "Invalid prefix: $prefix (expected reverse-DNS, e.g. com.janedoe.flowos)"
    exit 1
  fi
}

replace_in_file() {
  local file="$1"
  shift
  local -a expressions=("$@")
  if [[ ! -f "$file" ]]; then
    warn "Skip missing file: $file"
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] would patch: $file"
    return 0
  fi
  local expr
  for expr in "${expressions[@]}"; do
    sed -i '' "$expr" "$file"
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) NEW_PREFIX="$2"; shift 2 ;;
    --app-group) NEW_GROUP="$2"; shift 2 ;;
    --mac-bundle) NEW_MAC_BUNDLE="$2"; shift 2 ;;
    --team) NEW_TEAM="$2"; CLEAR_TEAM=0; shift 2 ;;
    --clear-team) CLEAR_TEAM=1; shift ;;
    --no-clear-team) CLEAR_TEAM=0; shift ;;
    --update-firebase) UPDATE_FIREBASE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --interactive|-i) INTERACTIVE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) warn "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if [[ "$INTERACTIVE" -eq 1 && -z "$NEW_PREFIX" ]]; then
  echo "Reconfigure LifeOS code signing for this Mac."
  echo ""
  read -r -p "New bundle ID prefix [com.example.flowos]: " NEW_PREFIX
  NEW_PREFIX="${NEW_PREFIX:-com.example.flowos}"
  read -r -p "Apple Team ID (10 chars, Enter to clear/have Xcode choose): " NEW_TEAM
  if [[ -n "$NEW_TEAM" ]]; then CLEAR_TEAM=0; else CLEAR_TEAM=1; fi
  read -r -p "Update GoogleService-Info.plist bundle ID? [y/N]: " fb
  [[ "$fb" =~ ^[Yy]$ ]] && UPDATE_FIREBASE=1
fi

if [[ -z "$NEW_PREFIX" ]]; then
  warn "Missing --prefix. Run with --interactive or see --help."
  exit 1
fi

validate_prefix "$NEW_PREFIX"

NEW_GROUP="${NEW_GROUP:-group.${NEW_PREFIX}}"
NEW_MAC_BUNDLE="${NEW_MAC_BUNDLE:-${NEW_PREFIX}.mac}"

if [[ "$NEW_PREFIX" == "$OLD_PREFIX" && "$NEW_GROUP" == "$OLD_GROUP" && -z "$NEW_TEAM" && "$CLEAR_TEAM" -eq 0 ]]; then
  warn "Nothing to change (prefix/group match current values)."
  exit 0
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.signing-backup-${TIMESTAMP}"
FILES=(
  "Config/LookAfter-iOS.entitlements"
  "Apps/LookAfterWidget/LookAfterWidget.entitlements"
  "Packages/LookAfterCore/Sources/LookAfterCore/Models/WidgetSnapshot.swift"
  "Packages/LookAfterAI/Sources/LookAfterAI/Security/KeychainStore.swift"
  "project.yml"
  "LookAfter.xcodeproj/project.pbxproj"
  "Config/GoogleService-Info.plist"
)

log "New prefix:      $NEW_PREFIX"
log "New App Group:   $NEW_GROUP"
log "New macOS ID:    $NEW_MAC_BUNDLE"
if [[ -n "$NEW_TEAM" ]]; then
  log "New Team ID:     $NEW_TEAM"
elif [[ "$CLEAR_TEAM" -eq 1 ]]; then
  log "Team:            (cleared — pick in Xcode after sign-in)"
else
  log "Team:            (unchanged)"
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  mkdir -p "$BACKUP_DIR"
  log "Backup → $BACKUP_DIR"
  for f in "${FILES[@]}"; do
    [[ -f "$ROOT/$f" ]] && cp "$ROOT/$f" "$BACKUP_DIR/$(basename "$f")"
  done
fi

# Order matters: replace longer / more specific IDs first.
PBX_EXPR=(
  "s|${OLD_PREFIX}\\.app\\.widget|${NEW_PREFIX}.app.widget|g"
  "s|${OLD_PREFIX}\\.LookAfterTests|${NEW_PREFIX}.LookAfterTests|g"
  "s|${OLD_PREFIX}\\.app|${NEW_PREFIX}.app|g"
  "s|${OLD_PREFIX}\\.ai-keys|${NEW_PREFIX}.ai-keys|g"
  "s|${OLD_MAC_BUNDLE}|${NEW_MAC_BUNDLE}|g"
  "s|${OLD_PREFIX}|${NEW_PREFIX}|g"
  "s|${OLD_GROUP}|${NEW_GROUP}|g"
)

if [[ -n "$NEW_TEAM" ]]; then
  PBX_EXPR+=("s|DEVELOPMENT_TEAM = ${OLD_TEAM};|DEVELOPMENT_TEAM = ${NEW_TEAM};|g")
elif [[ "$CLEAR_TEAM" -eq 1 ]]; then
  PBX_EXPR+=("/DEVELOPMENT_TEAM = ${OLD_TEAM};/d")
fi

replace_in_file "Config/LookAfter-iOS.entitlements" "s|${OLD_GROUP}|${NEW_GROUP}|g"
replace_in_file "Apps/LookAfterWidget/LookAfterWidget.entitlements" "s|${OLD_GROUP}|${NEW_GROUP}|g"
replace_in_file "Packages/LookAfterCore/Sources/LookAfterCore/Models/WidgetSnapshot.swift" "s|${OLD_GROUP}|${NEW_GROUP}|g"
replace_in_file "Packages/LookAfterAI/Sources/LookAfterAI/Security/KeychainStore.swift" \
  "s|${OLD_PREFIX}.ai-keys|${NEW_PREFIX}.ai-keys|g"
replace_in_file "project.yml" \
  "s|bundleIdPrefix: ${OLD_PREFIX}|bundleIdPrefix: ${NEW_PREFIX}|g" \
  "s|${OLD_GROUP}|${NEW_GROUP}|g" \
  "s|${OLD_PREFIX}\\.app\\.widget|${NEW_PREFIX}.app.widget|g" \
  "s|${OLD_PREFIX}\\.app|${NEW_PREFIX}.app|g" \
  "s|${OLD_MAC_BUNDLE}|${NEW_MAC_BUNDLE}|g"
replace_in_file "LookAfter.xcodeproj/project.pbxproj" "${PBX_EXPR[@]}"

if [[ "$UPDATE_FIREBASE" -eq 1 ]]; then
  replace_in_file "Config/GoogleService-Info.plist" \
    "s|<string>${OLD_FIREBASE_BUNDLE}</string>|<string>${NEW_PREFIX%.app}</string>|g" \
    "s|<string>${OLD_PREFIX}</string>|<string>${NEW_PREFIX}</string>|g"
  warn "Firebase BUNDLE_ID patched — cloud auth/sync only works if Firebase console matches."
else
  warn "GoogleService-Info.plist not changed (still ${OLD_FIREBASE_BUNDLE}). App runs; Firebase may not."
  warn "Pass --update-firebase to patch, or replace plist from Firebase console."
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  cat > "${ROOT}/signing.config.json" <<EOF
{
  "configuredAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "bundleIdPrefix": "${NEW_PREFIX}",
  "iosApp": "${NEW_PREFIX}.app",
  "iosWidget": "${NEW_PREFIX}.app.widget",
  "macApp": "${NEW_MAC_BUNDLE}",
  "appGroup": "${NEW_GROUP}",
  "developmentTeam": "${NEW_TEAM:-null}"
}
EOF
  log "Wrote signing.config.json"
fi

cat <<EOF

✅ Signing identifiers updated.

Next steps on this Mac:
──────────────────────
1. Xcode → Settings → Accounts → + → sign in with the Mac owner's Apple ID
2. Open LookAfter.xcodeproj
3. Targets LookAfter-iOS AND LookAfterWidget → Signing & Capabilities:
   • Enable "Automatically manage signing"
   • Team → owner's team (Personal Team is OK for local dev)
4. Apple Developer portal (developer.apple.com) — for widget + App Group:
   • Identifiers → App Groups → create: ${NEW_GROUP}
   • App IDs → ${NEW_PREFIX}.app → enable App Groups → select ${NEW_GROUP}
   • App IDs → ${NEW_PREFIX}.app.widget → same
   (Personal Team: Xcode often creates these on first build; if build fails, do manually.)
5. Product → Clean Build Folder, then build for Simulator or device

Bundle IDs now:
  iOS app:    ${NEW_PREFIX}.app
  Widget:     ${NEW_PREFIX}.app.widget
  macOS:      ${NEW_MAC_BUNDLE}
  App Group:  ${NEW_GROUP}

EOF

if [[ "$DRY_RUN" -eq 1 ]]; then
  warn "Dry run only — no files were modified."
fi
