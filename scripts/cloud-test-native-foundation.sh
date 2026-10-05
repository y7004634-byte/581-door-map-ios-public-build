#!/bin/bash
# Necessary Apple SDK verification of the new Swift foundation only; NO IPA.
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$TASK_ROOT/cloud-build"
mkdir -p "$OUT/native-port"
exec > >(tee "$OUT/cloud-build.log") 2>&1
PHASE=preflight
finish() {
    rc=$?
    if [ "$rc" -ne 0 ]; then
        printf 'status=FAIL\nmode=NATIVE_FOUNDATION_ONLY_NO_IPA\nphase=%s\nexit=%s\n' "$PHASE" "$rc" > "$OUT/cloud-build.result.txt"
        if [ -d "$OUT/native-tests.xcresult" ]; then
            xcrun xcresulttool get test-results summary --path "$OUT/native-tests.xcresult" > "$OUT/native-tests-summary.json" || true
        fi
    fi
}
trap finish EXIT
cd "$TASK_ROOT"
test "$(uname -s)" = Darwin
test ! -e "$OUT/DerivedData"
test ! -e "$OUT/Payload"
echo "NATIVE FOUNDATION START $(date -u +%Y-%m-%dT%H:%M:%SZ)"
xcodebuild -version
PHASE=parse-native-source
find DoorMap581 DoorMap581Tests DoorMap581UITests NativeCoreTests -name '*.swift' -print0 | xargs -0 xcrun swiftc -frontend -parse
xcodegen generate
PHASE=simulator-foundation-tests
xcrun simctl list devices available -j > "$OUT/simulator-devices.json"
SIM_UDID="$(python3 -c '
import json,sys
for runtime,items in json.load(open(sys.argv[1])).get("devices",{}).items():
    if ".iOS-" not in runtime: continue
    for item in items:
        if item.get("isAvailable") and item.get("name","").startswith("iPhone"):
            print(item["udid"]); raise SystemExit(0)
raise SystemExit("No iPhone simulator; no PASS")
' "$OUT/simulator-devices.json")"
xcodebuild -project DoorMap581.xcodeproj -scheme DoorMap581 \
    -destination "platform=iOS Simulator,id=$SIM_UDID" -destination-timeout 60 \
    -configuration Debug -derivedDataPath "$OUT/DerivedData" \
    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
    -testLanguage zh-Hant -testRegion TW \
    -only-testing:DoorMap581Tests/NativeSearchCoreTests \
    -only-testing:DoorMap581Tests/NativeOfflineStoreTests \
    -only-testing:DoorMap581Tests/NativeSeedTests \
    -resultBundlePath "$OUT/native-tests.xcresult" test
xcrun xcresulttool get test-results summary --path "$OUT/native-tests.xcresult" > "$OUT/native-tests-summary.json"
PHASE=verify-result
python3 - <<'PY'
import json,subprocess,hashlib,datetime
from pathlib import Path
root=Path.cwd(); summary=json.loads((root/'cloud-build/native-tests-summary.json').read_text())
assert summary.get('passedTests')==26, summary
assert summary.get('failedTests')==0 and summary.get('skippedTests')==0, summary
files=sorted((root/'DoorMap581/NativeCore').glob('*.swift'))
receipt={'status':'PASS','mode':'NATIVE_FOUNDATION_IOS_SIMULATOR_ONLY','tests':26,'failures':0,'skipped':0,'newIPA':False,'fullNativeUIAccepted':False,'physicalDeviceAccepted':False,'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'files':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
(root/'cloud-build/native-port/FOUNDATION_IOS_RESULT.json').write_text(json.dumps(receipt,indent=2)+'\n')
PY
printf 'status=PASS\nmode=NATIVE_FOUNDATION_ONLY_NO_IPA\ntests=26\nphysical_device=NOT_TESTED\nfull_native_ui=NOT_TESTED\nfinished=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUT/cloud-build.result.txt"
cat "$OUT/cloud-build.result.txt"
