#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$ROOT/logs-mac"
mkdir -p "$LOG_DIR"
STAMP="$(date '+%Y%m%d-%H%M%S')"
LOG="$LOG_DIR/build-$STAMP.log"
RESULT="$LOG_DIR/build-$STAMP.result"

exec > >(tee "$LOG") 2>&1
echo "START=$(date -Iseconds)"
echo "ROOT=$ROOT"

fail() {
  echo "STATUS=FAIL" > "$RESULT"
  echo "LOG=$LOG" >> "$RESULT"
  echo "REASON=$1" >> "$RESULT"
  echo "FAIL: $1"
  exit 1
}

command -v xcodebuild >/dev/null || fail "xcodebuild missing"
command -v xcodegen >/dev/null || fail "xcodegen missing"

xcodebuild -version
xcodegen --version
cd "$ROOT"
xcodegen generate --spec project.yml

xcodebuild \
  -project DoorMap581.xcodeproj \
  -scheme DoorMap581 \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

SIM_ID="$(
  xcrun simctl list devices available 2>/dev/null |
    sed -nE 's/.*iPhone[^()] *\(([0-9A-Fa-f-]{36})\).*/\1/p' |
    head -n 1
)"

if [[ -n "$SIM_ID" ]]; then
  echo "SIMULATOR_ID=$SIM_ID"
  xcodebuild \
    -project DoorMap581.xcodeproj \
    -scheme DoorMap581 \
    -destination "platform=iOS Simulator,id=$SIM_ID" \
    test
else
  echo "SIMULATOR_TEST=SKIPPED_NO_AVAILABLE_IPHONE_SIMULATOR"
fi

{
  echo "STATUS=PASS"
  echo "LOG=$LOG"
  echo "XCODE=$(xcodebuild -version | tr '\n' ' ')"
  echo "XCODEGEN=$(xcodegen --version)"
  if [[ -n "$SIM_ID" ]]; then
    echo "SIMULATOR_TEST=PASS"
  else
    echo "SIMULATOR_TEST=SKIPPED_NO_AVAILABLE_IPHONE_SIMULATOR"
  fi
  echo "FINISH=$(date -Iseconds)"
} > "$RESULT"

echo "RESULT=$RESULT"
echo "STATUS=PASS"
