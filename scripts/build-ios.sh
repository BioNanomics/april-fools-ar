#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NODE="$(command -v node)"
export PATH="$(dirname "$PROJECT_NODE"):$PATH"
export NODE_BINARY="$PROJECT_NODE"
cd "$PROJECT_ROOT"
PROJECT_REVISION="$(git rev-parse --short HEAD)"
if [[ -n "$(git status --porcelain)" ]]; then
  PROJECT_REVISION="${PROJECT_REVISION}-working"
fi
ruby scripts/configure-ios.rb
xcodebuild -workspace ios/AprilFoolsAR.xcworkspace -scheme AprilFoolsAR \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "${APRIL_BUILD_DIR:-/tmp/april-fools-ar-build}" \
  APP_BUILD_COMMIT="$PROJECT_REVISION" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
codesign --verify --deep --strict "${APRIL_BUILD_DIR:-/tmp/april-fools-ar-build}/Build/Products/Release-iphoneos/AprilFoolsAR.app"
