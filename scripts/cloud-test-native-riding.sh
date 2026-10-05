#!/bin/bash
# Native sensor/camera integration only, no IPA and no physical-device claims.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/cloud-build"
mkdir -p "$OUT/native-port"
exec > >(tee "$OUT/cloud-build.log") 2>&1
PHASE=preflight
finish() {
 rc=$?
 if [ "$rc" -ne 0 ]; then
  printf 'status=FAIL\nmode=NATIVE_RIDING_ONLY_NO_IPA\nphase=%s\nexit=%s\n' "$PHASE" "$rc" > "$OUT/cloud-build.result.txt"
  if [ -d "$OUT/native-tests.xcresult" ]; then
   xcrun xcresulttool get test-results summary --path "$OUT/native-tests.xcresult" > "$OUT/native-tests-summary.json" || true
   xcrun xcresulttool export attachments --path "$OUT/native-tests.xcresult" --output-path "$OUT/native-port/failed-ui-evidence" || true
  fi
 fi
}
trap finish EXIT
cd "$ROOT"
test "$(uname -s)" = Darwin
test ! -e "$OUT/Payload"
PHASE=source-parsing
find DoorMap581 DoorMap581Tests DoorMap581UITests NativeCoreTests -name '*.swift' -print0 | xargs -0 xcrun swiftc -frontend -parse
python3 - <<'PY'
import plistlib
from pathlib import Path
p=plistlib.loads(Path('DoorMap581/Info.plist').read_bytes())
assert [s for x in p.get('CFBundleURLTypes',[]) for s in x.get('CFBundleURLSchemes',[])]==['door581-apple-test']
assert not p.get('UIBackgroundModes')
for n in ['NativeSensors.swift','NativeRidingCamera.swift','NativePortViewController.swift']:
 s=Path('DoorMap581',n).read_text();assert all(x not in s for x in ['import WebKit','evaluateJavaScript(','NativeBundleServer(']),n
PY
TEST_FLAGS=(-testLanguage zh-Hant -testRegion TW)
HELP="$(xcodebuild -help 2>&1 || true)"
if [[ "$HELP" == *"-collect-test-diagnostics"* ]]; then TEST_FLAGS+=(-collect-test-diagnostics never); fi
xcodegen generate
xcrun simctl list devices available -j > "$OUT/simulator-devices.json"
SIM="$(python3 -c 'import json; ds=json.load(open("cloud-build/simulator-devices.json"))["devices"]; print(next(d["udid"] for r,rows in ds.items() if ".iOS-" in r for d in rows if d.get("isAvailable") and d["name"].startswith("iPhone")))')"
PHASE=native-riding-tests
ONLY_FLAGS=(-only-testing:DoorMap581UITests/NativeRidingUITests/testFITPiPActualGeometryAndRealPinchRetainNativeOwner)
export DOOR_RIDING_TEST_COUNT=1
xcodebuild -project DoorMap581.xcodeproj -scheme DoorMap581 \
 -destination "platform=iOS Simulator,id=$SIM" -destination-timeout 60 \
 -configuration Debug -derivedDataPath "$OUT/DerivedData" -parallel-testing-enabled NO \
 -maximum-concurrent-test-simulator-destinations 1 "${TEST_FLAGS[@]}" \
 "${ONLY_FLAGS[@]}" \
 -resultBundlePath "$OUT/native-tests.xcresult" test
xcrun xcresulttool get test-results summary --path "$OUT/native-tests.xcresult" > "$OUT/native-tests-summary.json"
xcrun xcresulttool export attachments --path "$OUT/native-tests.xcresult" --output-path "$OUT/native-port/ui-evidence"
PHASE=verify-result
python3 - <<'PY'
import datetime,hashlib,json,subprocess,os
from pathlib import Path
r=Path.cwd();out=r/'cloud-build/native-port';s=json.loads((r/'cloud-build/native-tests-summary.json').read_text())
expected=int(os.environ['DOOR_RIDING_TEST_COUNT']);assert expected==1
assert s.get('passedTests')==expected and s.get('totalTestCount')==expected and s.get('failedTests')==0 and s.get('skippedTests')==0,s
assert not list((r/'cloud-build').glob('*.ipa'))
assert len(list((out/'ui-evidence').rglob('*.png')))>=4
paths=['DoorMap581/NativeSensors.swift','DoorMap581/NativeRidingCamera.swift','DoorMap581/NativePortViewController.swift','DoorMap581/SceneDelegate.swift','DoorMap581/NativeCore/NativeCameraPolicy.swift','DoorMap581Tests/NativeRidingTests.swift','DoorMap581UITests/NativeRidingUITests.swift']
result={'status':'PASS','mode':'S3_NATIVE_RIDING_SENSOR_FIXTURE_REAL_UI','at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'passed':expected,'failed':0,'skipped':0,'sourceHashes':{p:hashlib.sha256((r/p).read_bytes()).hexdigest() for p in paths},'newIPA':False,'physicalDeviceAccepted':False,'all26Complete':False,'limits':['Explicit simulated CLLocation/heading and route input; real MapKit/UIKit gestures','Full live route planning and 2D/3D navigation glue pending','NLSC/roles/layers/advanced features pending','Phone heat/power/memory/signing isolation unverified']}
(out/'S3_RIDING_RESULT.json').write_text(json.dumps(result,indent=2)+'\n')
PY
printf 'status=PASS\nmode=NATIVE_RIDING_ONLY_NO_IPA\ntests=1\nphysical_device=NOT_TESTED\nall26=NOT_COMPLETE\nfinished=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUT/cloud-build.result.txt"
