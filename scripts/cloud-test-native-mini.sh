#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/cloud-build"
mkdir -p "$OUT/native-port"
exec > >(tee "$OUT/cloud-build.log") 2>&1
PHASE=preflight
finish(){ rc=$?; if [ "$rc" -ne 0 ]; then printf 'status=FAIL\nmode=NATIVE_MINI_ONLY_NO_IPA\nphase=%s\nexit=%s\n' "$PHASE" "$rc" > "$OUT/cloud-build.result.txt"; if [ -d "$OUT/native-tests.xcresult" ]; then xcrun xcresulttool get test-results summary --path "$OUT/native-tests.xcresult" > "$OUT/native-tests-summary.json" || true; xcrun xcresulttool export attachments --path "$OUT/native-tests.xcresult" --output-path "$OUT/native-port/failed-ui-evidence" || true; fi; fi; }
trap finish EXIT
cd "$ROOT"
test "$(uname -s)" = Darwin
test ! -e "$OUT/Payload"
PHASE=source-parse
find DoorMap581 DoorMap581Tests DoorMap581UITests NativeCoreTests -name '*.swift' -print0 | xargs -0 xcrun swiftc -frontend -parse
python3 - <<'PY'
from pathlib import Path
for p in ['DoorMap581/NativeDestinationMini.swift','DoorMap581/NativeMiniRaster.swift','DoorMap581/NativePortViewController.swift']:
 s=Path(p).read_text(); assert 'import WebKit' not in s and 'evaluateJavaScript(' not in s and 'NativeBundleServer(' not in s,p
assert 'canReplaceMapContent = true' in Path('DoorMap581/NativeMiniRaster.swift').read_text()
PY
xcodegen generate
xcrun simctl list devices available -j > "$OUT/simulator-devices.json"
SIM="$(python3 -c 'import json; d=json.load(open("cloud-build/simulator-devices.json"))["devices"]; print(next(x["udid"] for r,rows in d.items() if ".iOS-" in r for x in rows if x.get("isAvailable") and x["name"].startswith("iPhone")))')"
HELP="$(xcodebuild -help 2>&1 || true)"; TEST_FLAGS=(-testLanguage zh-Hant -testRegion TW)
if [[ "$HELP" == *"-collect-test-diagnostics"* ]]; then TEST_FLAGS+=(-collect-test-diagnostics never); fi
PHASE=mini-and-delivery-tests
xcodebuild -project DoorMap581.xcodeproj -scheme DoorMap581 -destination "platform=iOS Simulator,id=$SIM" -destination-timeout 60 -configuration Debug -derivedDataPath "$OUT/DerivedData" -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 "${TEST_FLAGS[@]}" -only-testing:DoorMap581UITests/NativeMiniUITests/testCloseRangeCorrectionCancelApplyAndReopen -resultBundlePath "$OUT/native-tests.xcresult" test
xcrun xcresulttool get test-results summary --path "$OUT/native-tests.xcresult" > "$OUT/native-tests-summary.json"
xcrun xcresulttool export attachments --path "$OUT/native-tests.xcresult" --output-path "$OUT/native-port/ui-evidence"
PHASE=device-compile
xcodebuild -project DoorMap581.xcodeproj -scheme DoorMap581 -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$OUT/DeviceDerived" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build-for-testing >/dev/null
PHASE=verify
python3 - <<'PY'
import datetime,hashlib,json,subprocess
from pathlib import Path
r=Path.cwd(); out=r/'cloud-build/native-port'; s=json.loads((r/'cloud-build/native-tests-summary.json').read_text())
assert s.get('passedTests')==1 and s.get('totalTestCount')==1 and s.get('failedTests')==0 and s.get('skippedTests')==0,s
assert not list((r/'cloud-build').glob('*.ipa'))
pngs=list((out/'ui-evidence').rglob('*.png')); assert len(pngs)>=4,len(pngs)
paths=['DoorMap581/NativeMiniRaster.swift','DoorMap581/NativeDestinationMini.swift','DoorMap581/NativePortViewController.swift','DoorMap581/NativeCore/NativeDeliveryCore.swift','DoorMap581/NativeCore/NativePlannedRoutes.swift','NativeCoreTests/NativeDeliveryCoreTests.swift','DoorMap581UITests/NativeMiniUITests.swift']
result={'status':'PASS','mode':'S4_NATIVE_MINI_DELIVERY_REAL_UI','at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'passed':1,'failed':0,'skipped':0,'carryForwardDeliveryUnitPasses':4,'appleSDKCompile':True,'newIPA':False,'physicalDeviceAccepted':False,'full26Complete':False,'sourceHashes':{p:hashlib.sha256((r/p).read_bytes()).hexdigest() for p in paths},'limits':['NLSC network tile readability not phone-accepted','Route service/live scooter planning not exercised here','Advanced UI and physical heat/power pending']}
(out/'S4_MINI_DELIVERY_RESULT.json').write_text(json.dumps(result,indent=2)+'\n')
PY
printf 'status=PASS\nmode=NATIVE_MINI_UI_REPAIR_ONLY_NO_IPA\ntests=1\ncarry_forward_delivery_units=4\nphysical_device=NOT_TESTED\nall26=NOT_COMPLETE\nfinished=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUT/cloud-build.result.txt"
