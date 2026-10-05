#!/bin/bash
# New native UIKit + public-data/offline integration only. No IPA or production write.
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$TASK_ROOT/cloud-build"
mkdir -p "$OUT/native-port"
exec > >(tee "$OUT/cloud-build.log") 2>&1
PHASE=preflight
finish() {
    rc=$?
    if [ "$rc" -ne 0 ]; then
        printf 'status=FAIL\nmode=NATIVE_SURFACE_REPAIR_ONLY_NO_IPA\nphase=%s\nexit=%s\n' "$PHASE" "$rc" > "$OUT/cloud-build.result.txt"
        if [ -d "$OUT/native-tests.xcresult" ]; then
            xcrun xcresulttool get test-results summary --path "$OUT/native-tests.xcresult" > "$OUT/native-tests-summary.json" || true
            xcrun xcresulttool export attachments --path "$OUT/native-tests.xcresult" --output-path "$OUT/native-port/failed-ui-evidence" || true
        fi
    fi
}
trap finish EXIT
cd "$TASK_ROOT"
test "$(uname -s)" = Darwin
test ! -e "$OUT/DerivedData"
echo "NATIVE SURFACE REPAIR START $(date -u +%Y-%m-%dT%H:%M:%SZ)"
PHASE=parse-native-source
find DoorMap581 DoorMap581Tests DoorMap581UITests NativeCoreTests -name '*.swift' -print0 | xargs -0 xcrun swiftc -frontend -parse
python3 - <<'PY'
import plistlib
from pathlib import Path
p=plistlib.loads(Path('DoorMap581/Info.plist').read_bytes())
schemes=[s for x in p.get('CFBundleURLTypes',[]) for s in x.get('CFBundleURLSchemes',[])]
assert schemes==['door581-apple-test'], schemes
assert not p.get('UIBackgroundModes'), 'No new background capability permitted'
for name in ['NativePortViewController.swift','NativeOfflineViewController.swift','NativeSearchRepository.swift','NativeAppleSearchProvider.swift','NativeSearchMapPresenter.swift']:
    s=Path('DoorMap581',name).read_text()
    assert 'import WebKit' not in s and 'evaluateJavaScript(' not in s and 'NativeBundleServer(' not in s, name
PY
# Reuse the existing build8 bounded diagnostics policy; keep explicit test attachments.
TEST_FLAGS=(-testLanguage zh-Hant -testRegion TW)
XCODE_HELP="$(xcodebuild -help 2>&1 || true)"
if [[ "$XCODE_HELP" == *"-collect-test-diagnostics"* ]]; then
    TEST_FLAGS+=(-collect-test-diagnostics never)
fi
xcodegen generate
PHASE=simulator-native-surface-tests
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
ONLY_FLAGS=(-only-testing:DoorMap581UITests/NativeSurfaceUITests/testPagingAreaResearchAndClearDoNotLosePoolOrResurrectOldPins)
export DOOR_EXPECTED_NATIVE_TESTS=1
if [ "${DOOR_NATIVE_DENSE_UI_ONLY:-false}" != true ]; then
    ONLY_FLAGS+=(-only-testing:DoorMap581Tests/NativeSearchMapLayoutTests -only-testing:DoorMap581Tests/NativeSearchPresentationTests -only-testing:DoorMap581UITests/NativeSurfaceUITests/testTopSearchMoreShortcutPinsAndSelectionUseOneNativeFlow)
    export DOOR_EXPECTED_NATIVE_TESTS=11
fi
xcodebuild -project DoorMap581.xcodeproj -scheme DoorMap581 \
    -destination "platform=iOS Simulator,id=$SIM_UDID" -destination-timeout 60 \
    -configuration Debug -derivedDataPath "$OUT/DerivedData" \
    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
    "${TEST_FLAGS[@]}" \
    "${ONLY_FLAGS[@]}" \
    -resultBundlePath "$OUT/native-tests.xcresult" test
xcrun xcresulttool get test-results summary --path "$OUT/native-tests.xcresult" > "$OUT/native-tests-summary.json"
xcrun xcresulttool export attachments --path "$OUT/native-tests.xcresult" --output-path "$OUT/native-port/ui-evidence"
PHASE=verify-result
python3 - <<'PY'
import json,subprocess,hashlib,datetime,os
from pathlib import Path
root=Path.cwd(); s=json.loads((root/'cloud-build/native-tests-summary.json').read_text())
expected=int(os.environ['DOOR_EXPECTED_NATIVE_TESTS']);assert expected in (1,11)
assert s.get('passedTests')==expected and s.get('totalTestCount')==expected, s
assert s.get('failedTests')==0 and s.get('skippedTests')==0, s
assert not list((root/'cloud-build').glob('*.ipa')), 'Partial UI must not be delivered as full native IPA'
files=[root/'DoorMap581'/n for n in ['NativePortViewController.swift','NativeOfflineViewController.swift','NativeSearchRepository.swift','NativeAppleSearchProvider.swift','SceneDelegate.swift','NativeCore/NativeCommunityIndex.swift','NativeCore/NativeSearchMapLayout.swift','NativeSearchMapPresenter.swift']]
result={'status':'PASS','mode':'NATIVE_S2_DENSE_UI_ONLY' if expected==1 else 'NATIVE_S2_TARGETED_MAP_REPAIR_IOS_SIMULATOR_ONLY','tests':expected,'failures':0,'skipped':0,'newIPA':False,'fullNativeAppAccepted':False,'physicalDeviceAccepted':False,'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sourceFiles':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},'limits':['Map center simulated; no sensor/riding acceptance','Live Apple service untested','S3 navigation/FIT/PiP/NLSC/layers/advanced workflows pending','Network offline update/delete UI not implemented']}
(root/'cloud-build/native-port/S2_REPAIR_IOS_RESULT.json').write_text(json.dumps(result,indent=2)+'\n')
PY
printf 'status=PASS\nmode=NATIVE_SURFACE_REPAIR_ONLY_NO_IPA\ntests=%s\nphysical_device=NOT_TESTED\nfull_native_app=NOT_FINISHED\nfinished=%s\n' "$DOOR_EXPECTED_NATIVE_TESTS" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUT/cloud-build.result.txt"
cat "$OUT/cloud-build.result.txt"
