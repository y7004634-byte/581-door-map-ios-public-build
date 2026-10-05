#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; OUT="$ROOT/cloud-build"
mkdir -p "$OUT/native-port"; exec > >(tee "$OUT/cloud-build.log") 2>&1
PHASE=preflight
finish(){ rc=$?; if [ "$rc" -ne 0 ]; then printf 'status=FAIL\nmode=NATIVE_PERSONAL_ONLY_NO_IPA\nphase=%s\nexit=%s\n' "$PHASE" "$rc" > "$OUT/cloud-build.result.txt"; if [ -d "$OUT/native-tests.xcresult" ]; then xcrun xcresulttool get test-results summary --path "$OUT/native-tests.xcresult" > "$OUT/native-tests-summary.json" || true; xcrun xcresulttool export attachments --path "$OUT/native-tests.xcresult" --output-path "$OUT/native-port/failed-ui-evidence" || true; fi; fi; }
trap finish EXIT
cd "$ROOT"; test "$(uname -s)" = Darwin; test ! -e "$OUT/Payload"
PHASE=parse
find DoorMap581 DoorMap581Tests DoorMap581UITests NativeCoreTests -name '*.swift' -print0 | xargs -0 xcrun swiftc -frontend -parse
python3 - <<'PY'
from pathlib import Path
s=Path('DoorMap581/NativePersonalStore.swift').read_text()
for token in ['2_500_000','personal.previous.json','com.door581.appletest','routeMemories','avoidAreas']: assert token in s,token
s=Path('DoorMap581/NativePortViewController.swift').read_text(); assert 'native-more-backup' in s and 'UIDocumentPickerDelegate' in s and 'mergeRouteMemories' in s
assert 'import WebKit' not in s
PY
xcodegen generate
xcrun simctl list devices available -j > "$OUT/simulator-devices.json"
SIM="$(python3 -c 'import json; d=json.load(open("cloud-build/simulator-devices.json"))["devices"]; print(next(x["udid"] for r,rows in d.items() if ".iOS-" in r for x in rows if x.get("isAvailable") and x["name"].startswith("iPhone")))')"
HELP="$(xcodebuild -help 2>&1 || true)"; TEST_FLAGS=(-testLanguage zh-Hant -testRegion TW); if [[ "$HELP" == *"-collect-test-diagnostics"* ]]; then TEST_FLAGS+=(-collect-test-diagnostics never); fi
PHASE=personal-tests
xcodebuild -project DoorMap581.xcodeproj -scheme DoorMap581 -destination "platform=iOS Simulator,id=$SIM" -destination-timeout 60 -configuration Debug -derivedDataPath "$OUT/DerivedData" -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 "${TEST_FLAGS[@]}" -only-testing:DoorMap581Tests/NativePersonalStoreTests -only-testing:DoorMap581UITests/NativePersonalUITests -resultBundlePath "$OUT/native-tests.xcresult" test
xcrun xcresulttool get test-results summary --path "$OUT/native-tests.xcresult" > "$OUT/native-tests-summary.json"
xcrun xcresulttool export attachments --path "$OUT/native-tests.xcresult" --output-path "$OUT/native-port/ui-evidence"
PHASE=device-compile
xcodebuild -project DoorMap581.xcodeproj -scheme DoorMap581 -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$OUT/DeviceDerived" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build-for-testing >/dev/null
PHASE=verify
python3 - <<'PY'
import datetime,hashlib,json,subprocess
from pathlib import Path
r=Path.cwd(); out=r/'cloud-build/native-port'; s=json.loads((r/'cloud-build/native-tests-summary.json').read_text())
assert s.get('passedTests')==4 and s.get('totalTestCount')==4 and s.get('failedTests')==0 and s.get('skippedTests')==0,s
assert not list((r/'cloud-build').glob('*.ipa'))
pngs=list((out/'ui-evidence').rglob('*.png')); assert len(pngs)>=1,len(pngs)
paths=['DoorMap581/NativePersonalStore.swift','DoorMap581/NativePortViewController.swift','DoorMap581Tests/NativePersonalStoreTests.swift','DoorMap581UITests/NativePersonalUITests.swift']
result={'status':'PASS','mode':'S7_NATIVE_PERSONAL_REAL_UI','at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'passed':4,'failed':0,'skipped':0,'appleSDKCompile':True,'newIPA':False,'physicalDeviceAccepted':False,'full26Complete':False,'sourceHashes':{p:hashlib.sha256((r/p).read_bytes()).hexdigest() for p in paths},'limits':['System share/document picker not physically exercised','Route-memory application to route generation remains a later gate','Physical app-sandbox/signing isolation pending']}
(out/'S7_PERSONAL_RESULT.json').write_text(json.dumps(result,indent=2)+'\n')
PY
printf 'status=PASS\nmode=NATIVE_PERSONAL_ONLY_NO_IPA\ntests=4\nphysical_device=NOT_TESTED\nall26=NOT_COMPLETE\nfinished=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUT/cloud-build.result.txt"
