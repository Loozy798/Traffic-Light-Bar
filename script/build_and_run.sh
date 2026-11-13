#!/bin/bash
set -euo pipefail
MODE="${1:-run}"
case "$MODE" in run|--dashboard|--debug|--logs|--telemetry|--verify) ;; *) echo "Usage: $0 [--dashboard|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;; esac
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Traffic Light Bar"
BUNDLE_ID="Booster-Studio.Traffic-Light-Bar"
DERIVED_DIR="${TLB_DERIVED_DATA:-/private/tmp/traffic-light-bar-$UID}"
APP_BUNDLE="$DERIVED_DIR/Build/Products/Debug/$APP_NAME.app"
BUILD_LOG="/private/tmp/traffic-light-bar-build.log"
cd "$ROOT_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
if ! xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -configuration Debug -sdk macosx -derivedDataPath "$DERIVED_DIR" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build > "$BUILD_LOG" 2>&1; then
  tail -n 70 "$BUILD_LOG"
  exit 1
fi
case "$MODE" in
  --dashboard) open -n "$APP_BUNDLE" --args --dashboard ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs) open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry) open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  --verify)
    open -n "$APP_BUNDLE"
    for attempt in 1 2 3 4 5; do
      if pgrep -x "$APP_NAME" >/dev/null; then echo "Build and launch verified: $APP_BUNDLE"; exit 0; fi
      sleep 1
    done
    echo "Build succeeded, but app process was not found." >&2; exit 1 ;;
  run) open -n "$APP_BUNDLE" ;;
esac
