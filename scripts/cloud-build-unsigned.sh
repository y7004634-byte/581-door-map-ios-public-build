#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/cloud-build"
DERIVED="$OUT/DerivedData"
LOG="$OUT/cloud-build.log"
RESULT="$OUT/cloud-build.result.txt"

mkdir -p "$OUT"
exec > >(tee "$LOG") 2>&1

echo "START $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "ROOT=$ROOT"
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
xcodegen --version

cd "$ROOT"
rm -rf DoorMap581.xcodeproj
xcodegen generate
test -d DoorMap581.xcodeproj
SIM_UDID="$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin).get("devices",{})
for runtime,items in d.items():
    for item in items:
        if item.get("isAvailable") and item.get("name","").startswith("iPhone"):
            print(item["udid"]); raise SystemExit(0)
raise SystemExit(1)
' || true)"

if [ -n "$SIM_UDID" ]; then
  echo "SIM_UDID=$SIM_UDID"
  xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
  xcodebuild     -project DoorMap581.xcodeproj     -scheme DoorMap581     -destination "platform=iOS Simulator,id=$SIM_UDID"     -configuration Debug     test
else
  echo "WARN no available iPhone simulator; compile tests only"
  xcodebuild     -project DoorMap581.xcodeproj     -scheme DoorMap581     -destination 'generic/platform=iOS Simulator'     -configuration Debug     build-for-testing
fi
rm -rf "$DERIVED"
xcodebuild   -project DoorMap581.xcodeproj   -scheme DoorMap581   -configuration Debug   -sdk iphoneos   -destination 'generic/platform=iOS'   -derivedDataPath "$DERIVED"   CODE_SIGNING_ALLOWED=NO   CODE_SIGNING_REQUIRED=NO   CODE_SIGN_IDENTITY=""   build

APP_PATH="$(find "$DERIVED/Build/Products/Debug-iphoneos" -maxdepth 1 -type d -name '*.app' | head -n 1)"
test -n "$APP_PATH"
echo "APP_PATH=$APP_PATH"

rm -rf "$OUT/Payload"
mkdir -p "$OUT/Payload"
cp -R "$APP_PATH" "$OUT/Payload/"
rm -f "$OUT/DoorMap581-unsigned.ipa"
(
  cd "$OUT"
  /usr/bin/zip -qry DoorMap581-unsigned.ipa Payload
)
IPA="$OUT/DoorMap581-unsigned.ipa"
test -s "$IPA"
SHA="$(shasum -a 256 "$IPA" | awk '{print $1}')"
APP_BIN="$(find "$OUT/Payload" -type f -perm -111 | head -n 1 || true)"

{
  echo "status=PASS"
  echo "finished=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "ipa=$IPA"
  echo "sha256=$SHA"
  echo "app=$APP_PATH"
  echo "simulator_udid=${SIM_UDID:-NONE}"
} | tee "$RESULT"

if [ -n "$APP_BIN" ]; then
  file "$APP_BIN" || true
fi
echo "RESULT PASS sha256=$SHA"
