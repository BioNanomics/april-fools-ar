#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NODE="$(command -v node)"
export PATH="$(dirname "$PROJECT_NODE"):$PATH"
export NODE_BINARY="$PROJECT_NODE"
cd "$PROJECT_ROOT"
PROJECT_REVISION="$(git rev-parse HEAD)"
PROJECT_DIRTY=false
if [[ -n "$(git status --porcelain)" ]]; then
  PROJECT_DIRTY=true
fi
PROJECT_BUILD_DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
ruby scripts/configure-ios.rb
xcodebuild -workspace ios/AprilFoolsAR.xcworkspace -scheme AprilFoolsAR \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "${APRIL_BUILD_DIR:-/tmp/april-fools-ar-build}" \
  APP_BUILD_COMMIT="$PROJECT_REVISION" \
  APP_BUILD_DATE_UTC="$PROJECT_BUILD_DATE" APP_BUILD_DIRTY="$PROJECT_DIRTY" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
PROJECT_APP="${APRIL_BUILD_DIR:-/tmp/april-fools-ar-build}/Build/Products/Release-iphoneos/AprilFoolsAR.app"
codesign --verify --deep --strict "$PROJECT_APP"
test "$(plutil -extract buildCommit raw -o - "$PROJECT_APP/BuildInfo.json")" = "$PROJECT_REVISION"
test "$(plutil -extract buildDateUTC raw -o - "$PROJECT_APP/BuildInfo.json")" = "$PROJECT_BUILD_DATE"
test "$(plutil -extract workingTreeDirty raw -o - "$PROJECT_APP/BuildInfo.json")" = "$PROJECT_DIRTY"
test "$(plutil -extract version raw -o - "$PROJECT_APP/BuildInfo.json")" = "$(plutil -extract CFBundleShortVersionString raw -o - "$PROJECT_APP/Info.plist")"
test "$(plutil -extract build raw -o - "$PROJECT_APP/BuildInfo.json")" = "$(plutil -extract CFBundleVersion raw -o - "$PROJECT_APP/Info.plist")"
printf 'Verified signed app build identity: %s, %s\n' "$PROJECT_REVISION" "$PROJECT_BUILD_DATE"
