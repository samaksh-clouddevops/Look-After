#!/usr/bin/env bash
#
# reconfigure-signing.sh — Retarget Look After bundle IDs, App Groups, and dev team
# for building on another Mac / another Apple Developer account.
#
# Usage:
#   ./Scripts/setup-tanya.sh                    # Tanya's Mac — no args needed
#   ./Scripts/reconfigure-signing.sh --prefix com.janedoe.lookafter
#   ./Scripts/reconfigure-signing.sh --prefix com.janedoe.lookafter --team ABCD123456
#   ./Scripts/reconfigure-signing.sh --prefix com.janedoe.lookafter --clear-team
#   ./Scripts/reconfigure-signing.sh --interactive
#
# After running:
#   1. Mac owner signs into Xcode → Settings → Accounts
#   2. Open LookAfter.xcodeproj → Signing & Capabilities → pick their Team (iOS + Widget)
#   3. Register App Group + App IDs at developer.apple.com (script prints details)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# --- Defaults (current repo values after LifeOS → Look After migration) ---
OLD_PREFIX="com.samaksh.flowos"
OLD_GROUP="group.com.samaksh.flowos"
OLD_IOS_APP="${OLD_PREFIX}.app"
OLD_IOS_WIDGET="${OLD_PREFIX}.app.widget"
OLD_MAC_BUNDLE="com.samaksh.lifeos.mac"          # legacy pre-migration macOS ID
OLD_MAC_BUNDLE_ALT="${OLD_PREFIX}.mac"           # alternate if already partially updated
OLD_FIREBASE_BUNDLE="com.samaksh.lifeos"         # legacy Firebase bundle (pre-migration)
OLD_FIREBASE_BUNDLE_ALT="${OLD_IOS_APP}"         # current dummy plist value
OLD_KEYCHAIN_SERVICE="${OLD_PREFIX}.ai-keys"
OLD_PERF_SUBSYSTEM="${OLD_IOS_APP}"
OLD_FLOW_DIRECTOR_SUBSYSTEM="com.flowos.app"
OLD_TEAM="QZYBP8F6F5"

NEW_PREFIX=""
NEW_GROUP=""
NEW_MAC_BUNDLE=""
NEW_IOS_APP=""
NEW_IOS_WIDGET=""
NEW_KEYCHAIN=""
NEW_TEAM=""
CLEAR_TEAM=1
DRY_RUN=0
INTERACTIVE=0
UPDATE_FIREBASE=0
REGENERATE=1

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Required (unless --interactive):
  --prefix ID          New bundle ID prefix, e.g. com.janedoe.lookafter

Optional:
  --app-group ID       App Group (default: group.<prefix>)
  --mac-bundle ID      macOS bundle ID (default: <prefix>.mac)
  --team TEAMID        Set DEVELOPMENT_TEAM in project.pbxproj (10-char Apple Team ID)
  --clear-team         Remove hard-coded DEVELOPMENT_TEAM (default: on)
  --no-clear-team      Keep existing DEVELOPMENT_TEAM if not using --team
  --update-firebase    Patch GoogleService-Info.plist BUNDLE_ID (cloud sync may break)
  --no-regenerate      Skip xcodegen after patching project.yml
  --dry-run            Print changes without writing files
  --interactive        Prompt for values
  -h, --help           Show this help

Current repo identifiers (replaced when you pass a new --prefix):
  iOS app:     ${OLD_IOS_APP}
  Widget:      ${OLD_IOS_WIDGET}
  macOS:       ${OLD_MAC_BUNDLE} (legacy) / ${OLD_MAC_BUNDLE_ALT}
  App Group:   ${OLD_GROUP}
  Firebase:    ${OLD_FIREBASE_BUNDLE_ALT} (legacy: ${OLD_FIREBASE_BUNDLE})

Example (someone else's Mac — owner uses Personal Team):
  ./Scripts/reconfigure-signing.sh --prefix com.janedoe.lookafter --clear-team

Tanya's Mac (zero config — run from repo root after git pull):
  ./Scripts/setup-tanya.sh

Then in Xcode: Settings → Accounts → sign in → pick Team on LookAfter-iOS + LookAfterWidget.
EOF
}

log() { printf '→ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }

validate_prefix() {
  local prefix="$1"
  if [[ ! "$prefix" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z0-9.-]+$ ]]; then
    warn "Invalid prefix: $prefix (expected reverse-DNS, e.g. com.janedoe.lookafter)"
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
    --no-regenerate) REGENERATE=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --interactive|-i) INTERACTIVE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) warn "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if [[ "$INTERACTIVE" -eq 1 && -z "$NEW_PREFIX" ]]; then
  echo "Reconfigure Look After code signing for this Mac."
  echo ""
  read -r -p "New bundle ID prefix [com.example.lookafter]: " NEW_PREFIX
  NEW_PREFIX="${NEW_PREFIX:-com.example.lookafter}"
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
NEW_IOS_APP="${NEW_PREFIX}.app"
NEW_IOS_WIDGET="${NEW_PREFIX}.app.widget"
NEW_KEYCHAIN="${NEW_PREFIX}.ai-keys"

if [[ "$NEW_PREFIX" == "$OLD_PREFIX" && "$NEW_GROUP" == "$OLD_GROUP" && -z "$NEW_TEAM" && "$CLEAR_TEAM" -eq 0 ]]; then
  warn "Nothing to change (prefix/group match current values)."
  exit 0
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.signing-backup-${TIMESTAMP}"
FILES=(
  "Config/LookAfter-iOS.entitlements"
  "Config/LookAfter-macOS.entitlements"
  "Apps/LookAfterWidget/LookAfterWidget.entitlements"
  "Packages/LookAfterCore/Sources/LookAfterCore/Models/WidgetSnapshot.swift"
  "Packages/LookAfterAI/Sources/LookAfterAI/Security/KeychainStore.swift"
  "Apps/LookAfter-iOS/Services/PerformanceSignposts.swift"
  "Apps/LookAfter-iOS/Services/FlowDirectorIntegrationLog.swift"
  "project.yml"
  "LookAfter.xcodeproj/project.pbxproj"
  "Config/GoogleService-Info.plist"
  "Config/signing.config.json"
)

log "New prefix:      $NEW_PREFIX"
log "New iOS app:     $NEW_IOS_APP"
log "New widget:      $NEW_IOS_WIDGET"
log "New App Group:   $NEW_GROUP"
log "New macOS ID:    $NEW_MAC_BUNDLE"
log "New Keychain:    $NEW_KEYCHAIN"
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
  "s|${OLD_IOS_WIDGET}|${NEW_IOS_WIDGET}|g"
  "s|${OLD_PREFIX}\\.LookAfterSnapshotTests|${NEW_PREFIX}.LookAfterSnapshotTests|g"
  "s|${OLD_PREFIX}\\.LookAfterUITests|${NEW_PREFIX}.LookAfterUITests|g"
  "s|${OLD_PREFIX}\\.LookAfterTests|${NEW_PREFIX}.LookAfterTests|g"
  "s|${OLD_PREFIX}\\.LifeOSTests|${NEW_PREFIX}.LookAfterTests|g"
  "s|${OLD_PREFIX}\\.LifeOSUITests|${NEW_PREFIX}.LookAfterUITests|g"
  "s|${OLD_IOS_APP}|${NEW_IOS_APP}|g"
  "s|${OLD_KEYCHAIN_SERVICE}|${NEW_KEYCHAIN}|g"
  "s|${OLD_MAC_BUNDLE}|${NEW_MAC_BUNDLE}|g"
  "s|${OLD_MAC_BUNDLE_ALT}|${NEW_MAC_BUNDLE}|g"
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
  "s|${OLD_KEYCHAIN_SERVICE}|${NEW_KEYCHAIN}|g"
replace_in_file "Apps/LookAfter-iOS/Services/PerformanceSignposts.swift" \
  "s|${OLD_PERF_SUBSYSTEM}|${NEW_IOS_APP}|g"
replace_in_file "Apps/LookAfter-iOS/Services/FlowDirectorIntegrationLog.swift" \
  "s|${OLD_FLOW_DIRECTOR_SUBSYSTEM}|${NEW_IOS_APP}|g"
replace_in_file "project.yml" \
  "s|bundleIdPrefix: ${OLD_PREFIX}|bundleIdPrefix: ${NEW_PREFIX}|g" \
  "s|${OLD_GROUP}|${NEW_GROUP}|g" \
  "s|${OLD_IOS_WIDGET}|${NEW_IOS_WIDGET}|g" \
  "s|${OLD_IOS_APP}|${NEW_IOS_APP}|g" \
  "s|${OLD_MAC_BUNDLE}|${NEW_MAC_BUNDLE}|g" \
  "s|${OLD_MAC_BUNDLE_ALT}|${NEW_MAC_BUNDLE}|g" \
  "s|${OLD_KEYCHAIN_SERVICE}|${NEW_KEYCHAIN}|g"
replace_in_file "LookAfter.xcodeproj/project.pbxproj" "${PBX_EXPR[@]}"

if [[ "$UPDATE_FIREBASE" -eq 1 ]]; then
  replace_in_file "Config/GoogleService-Info.plist" \
    "s|<string>${OLD_FIREBASE_BUNDLE}</string>|<string>${NEW_IOS_APP}</string>|g" \
    "s|<string>${OLD_FIREBASE_BUNDLE_ALT}</string>|<string>${NEW_IOS_APP}</string>|g" \
    "s|<string>${OLD_PREFIX}</string>|<string>${NEW_PREFIX}</string>|g"
  warn "Firebase BUNDLE_ID patched to ${NEW_IOS_APP} — cloud auth/sync only works if Firebase console matches."
else
  warn "GoogleService-Info.plist not changed (${OLD_FIREBASE_BUNDLE_ALT}). App runs; Firebase may not."
  warn "Pass --update-firebase to patch, or replace plist from Firebase console."
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  TEAM_JSON="null"
  [[ -n "$NEW_TEAM" ]] && TEAM_JSON="\"${NEW_TEAM}\""
  cat > "${ROOT}/Config/signing.config.json" <<EOF
{
  "configuredAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "bundleIdPrefix": "${NEW_PREFIX}",
  "iosApp": "${NEW_IOS_APP}",
  "iosWidget": "${NEW_IOS_WIDGET}",
  "macApp": "${NEW_MAC_BUNDLE}",
  "appGroup": "${NEW_GROUP}",
  "keychainService": "${NEW_KEYCHAIN}",
  "developmentTeam": ${TEAM_JSON},
  "profiles": {
    "ios": "Look After iOS Development",
    "macos": "Look After macOS Development"
  }
}
EOF
  log "Wrote Config/signing.config.json"

  if [[ "$REGENERATE" -eq 1 ]]; then
    if command -v xcodegen >/dev/null 2>&1; then
      log "Regenerating LookAfter.xcodeproj with xcodegen…"
      xcodegen generate
    else
      warn "xcodegen not found — run 'brew install xcodegen && xcodegen generate' to sync project.yml → .xcodeproj"
    fi
  fi
fi

cat <<EOF

✅ Look After signing identifiers updated.

Next steps on this Mac:
──────────────────────
1. Xcode → Settings → Accounts → + → sign in with the Mac owner's Apple ID
2. Open LookAfter.xcodeproj
3. Targets LookAfter-iOS AND LookAfterWidget → Signing & Capabilities:
   • Enable "Automatically manage signing"
   • Team → owner's team (Personal Team is OK for local dev)
4. Apple Developer portal (developer.apple.com):
   • Identifiers → App Groups → create: ${NEW_GROUP}
   • App IDs → ${NEW_IOS_APP} → enable App Groups → select ${NEW_GROUP}
   • App IDs → ${NEW_IOS_WIDGET} → same
   • App IDs → ${NEW_MAC_BUNDLE} → macOS target (if building LookAfter-macOS)
   (Personal Team: Xcode often creates these on first build; if build fails, do manually.)
5. Product → Clean Build Folder, then build for Simulator or device

Bundle IDs now:
  iOS app:    ${NEW_IOS_APP}
  Widget:     ${NEW_IOS_WIDGET}
  macOS:      ${NEW_MAC_BUNDLE}
  App Group:  ${NEW_GROUP}

EOF

if [[ "$DRY_RUN" -eq 1 ]]; then
  warn "Dry run only — no files were modified."
fi
