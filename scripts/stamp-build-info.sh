#!/bin/bash
set -euo pipefail

STAMP_REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP_COMMIT="${APP_BUILD_COMMIT:-$(git -C "$STAMP_REPO_ROOT" rev-parse HEAD 2>/dev/null || printf unknown)}"
STAMP_DATE="${APP_BUILD_DATE_UTC:-$(date -u '+%Y-%m-%dT%H:%M:%SZ')}"
STAMP_DIRTY="${APP_BUILD_DIRTY:-}"
if [[ -z "$STAMP_DIRTY" ]]; then
  if [[ "$STAMP_COMMIT" == unknown || -n "$(git -C "$STAMP_REPO_ROOT" status --porcelain 2>/dev/null)" ]]; then
    STAMP_DIRTY=true
  else
    STAMP_DIRTY=false
  fi
fi
if [[ "$STAMP_DIRTY" != true && "$STAMP_DIRTY" != false ]]; then
  printf '%s\n' 'APP_BUILD_DIRTY must be true or false.' >&2
  exit 1
fi

STAMP_OUTPUT="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/BuildInfo.json"
mkdir -p "$(dirname "$STAMP_OUTPUT")"
STAMP_TEMP="$(mktemp "${TEMP_DIR:-${TMPDIR:-/tmp}}/AprilFoolsBuildInfo.XXXXXX")"
trap 'rm -f "$STAMP_TEMP"' EXIT
/usr/bin/plutil -create xml1 "$STAMP_TEMP"
/usr/bin/plutil -insert bundleId -string "${PRODUCT_BUNDLE_IDENTIFIER:?}" "$STAMP_TEMP"
/usr/bin/plutil -insert version -string "${MARKETING_VERSION:?}" "$STAMP_TEMP"
/usr/bin/plutil -insert build -string "${CURRENT_PROJECT_VERSION:?}" "$STAMP_TEMP"
/usr/bin/plutil -insert buildCommit -string "$STAMP_COMMIT" "$STAMP_TEMP"
/usr/bin/plutil -insert buildDateUTC -string "$STAMP_DATE" "$STAMP_TEMP"
/usr/bin/plutil -insert workingTreeDirty -bool "$STAMP_DIRTY" "$STAMP_TEMP"
/usr/bin/plutil -convert json -o "$STAMP_OUTPUT" "$STAMP_TEMP"
printf 'Stamped app %s (%s), source %s, built %s, modified sources %s\n' \
  "$MARKETING_VERSION" "$CURRENT_PROJECT_VERSION" "$STAMP_COMMIT" "$STAMP_DATE" "$STAMP_DIRTY"
