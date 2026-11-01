#!/bin/bash
# Archives the Release build and uploads it to App Store Connect (TestFlight).
#
#   scripts/testflight.sh --dry-run   print every command, run nothing
#   scripts/testflight.sh             bootstrap, archive, export + upload
#
# The build number (CURRENT_PROJECT_VERSION) is the local time as
# YYYYMMDDHHMM, passed to xcodebuild as a build setting, so project.yml is never edited.
# Release builds point at https://play.conleychaos.com and register no custom URL scheme.
#
# Signing is automatic (team B222J9J7B8). By default Xcode's signed-in account is used. To
# authenticate with an App Store Connect API key instead, export all three (never commit them):
#   ASC_KEY_ID      the key's ID
#   ASC_ISSUER_ID   the issuer ID shown on the Keys page
#   ASC_KEY_PATH    path to the AuthKey_<ID>.p8 file (keep it outside the repo)
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "usage: scripts/testflight.sh [--dry-run]" >&2; exit 64 ;;
  esac
done

BUILD_NUMBER="$(date +%Y%m%d%H%M)"
ARCHIVE=build/Pounce.xcarchive
EXPORT=build/export

auth=()
if [ -n "${ASC_KEY_ID:-}" ] || [ -n "${ASC_ISSUER_ID:-}" ] || [ -n "${ASC_KEY_PATH:-}" ]; then
  : "${ASC_KEY_ID:?set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH together}"
  : "${ASC_ISSUER_ID:?set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH together}"
  : "${ASC_KEY_PATH:?set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH together}"
  auth=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

# run <cmd...>: prints the command (shell-quoted); runs it unless --dry-run.
run() {
  printf '+'; printf ' %q' "$@"; printf '\n'
  [ "$DRY_RUN" -eq 1 ] || "$@"
}

[ "$DRY_RUN" -eq 1 ] && echo "dry run: nothing below is executed"
echo "build number: $BUILD_NUMBER"

run scripts/bootstrap.sh
run rm -rf "$ARCHIVE" "$EXPORT"
run xcodebuild archive \
  -project Pounce.xcodeproj -scheme Pounce -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
  -allowProvisioningUpdates ${auth[@]+"${auth[@]}"}
run xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath "$EXPORT" \
  -allowProvisioningUpdates ${auth[@]+"${auth[@]}"}

if [ "$DRY_RUN" -eq 1 ]; then echo "dry run complete"; else echo "uploaded build $BUILD_NUMBER to App Store Connect"; fi
