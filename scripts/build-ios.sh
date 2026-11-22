#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NODE="$(command -v node)"
export PATH="$(dirname "$PROJECT_NODE"):$PATH"
export NODE_BINARY="$PROJECT_NODE"
cd "$PROJECT_ROOT"
PROJECT_UNSIGNED=false
PROJECT_ACTION=build
for argument in "$@"; do
  case "$argument" in
    --unsigned) PROJECT_UNSIGNED=true ;;
    --archive) PROJECT_ACTION=archive ;;
    *) printf 'Usage: %s [--unsigned] [--archive]\n' "$0" >&2; exit 2 ;;
  esac
done
if [[ "$PROJECT_UNSIGNED" = false && -z "${IOS_DEVELOPMENT_TEAM:-}" ]]; then
  printf 'Set IOS_DEVELOPMENT_TEAM explicitly for signing, or pass --unsigned. No Apple account or provisioning changes are automatic.\n' >&2
  exit 2
fi
ruby scripts/configure-ios.rb
PROJECT_REVISION="$(git rev-parse HEAD)"
PROJECT_DIRTY=false
if [[ -n "$(git status --porcelain)" ]]; then
  PROJECT_DIRTY=true
fi
PROJECT_BUILD_DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
PROJECT_BUILD_DIR="${APRIL_BUILD_DIR:-/tmp/april-fools-ar-build}"
PROJECT_ARCHIVE="${APRIL_ARCHIVE_PATH:-$PROJECT_BUILD_DIR/AprilFoolsAR.xcarchive}"
PROJECT_OPTIONS=()
if [[ "$PROJECT_UNSIGNED" = true ]]; then
  PROJECT_OPTIONS+=(CODE_SIGNING_ALLOWED=NO)
else
  PROJECT_OPTIONS+=("DEVELOPMENT_TEAM=$IOS_DEVELOPMENT_TEAM")
fi
if [[ "$PROJECT_ACTION" = archive ]]; then
  PROJECT_OPTIONS+=(-archivePath "$PROJECT_ARCHIVE")
fi
xcodebuild -workspace ios/AprilFoolsAR.xcworkspace -scheme AprilFoolsAR \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$PROJECT_BUILD_DIR" \
  APP_BUILD_COMMIT="$PROJECT_REVISION" \
  APP_BUILD_DATE_UTC="$PROJECT_BUILD_DATE" APP_BUILD_DIRTY="$PROJECT_DIRTY" \
  "${PROJECT_OPTIONS[@]}" "$PROJECT_ACTION"
if [[ "$PROJECT_ACTION" = archive ]]; then
  PROJECT_APP="$PROJECT_ARCHIVE/Products/Applications/AprilFoolsAR.app"
else
  PROJECT_APP="$PROJECT_BUILD_DIR/Build/Products/Release-iphoneos/AprilFoolsAR.app"
fi
if [[ "$PROJECT_UNSIGNED" = false ]]; then
  codesign --verify --deep --strict "$PROJECT_APP"
fi
test -s "$PROJECT_APP/main.jsbundle"
test "$(plutil -extract CFBundleIdentifier raw -o - "$PROJECT_APP/Info.plist")" = com.bionanomics.aprilfoolsar
test "$(plutil -extract buildCommit raw -o - "$PROJECT_APP/BuildInfo.json")" = "$PROJECT_REVISION"
test "$(plutil -extract buildDateUTC raw -o - "$PROJECT_APP/BuildInfo.json")" = "$PROJECT_BUILD_DATE"
test "$(plutil -extract workingTreeDirty raw -o - "$PROJECT_APP/BuildInfo.json")" = "$PROJECT_DIRTY"
test "$(plutil -extract version raw -o - "$PROJECT_APP/BuildInfo.json")" = "$(plutil -extract CFBundleShortVersionString raw -o - "$PROJECT_APP/Info.plist")"
test "$(plutil -extract build raw -o - "$PROJECT_APP/BuildInfo.json")" = "$(plutil -extract CFBundleVersion raw -o - "$PROJECT_APP/Info.plist")"
printf 'Verified app build identity: %s, %s\n%s\n' "$PROJECT_REVISION" "$PROJECT_BUILD_DATE" "$PROJECT_APP"
