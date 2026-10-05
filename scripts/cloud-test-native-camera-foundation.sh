#!/bin/bash
# New S3 pure-native rules and actual Apple SDK compilation; no IPA, no device claim.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/cloud-build"
mkdir -p "$OUT/native-port"
exec > >(tee "$OUT/cloud-build.log") 2>&1
PHASE=preflight
finish(){
 rc=$?
 if [ "$rc" -ne 0 ]; then
  printf 'status=FAIL\nmode=NATIVE_CAMERA_FOUNDATION_ONLY_NO_IPA\nphase=%s\nexit=%s\n' "$PHASE" "$rc" > "$OUT/cloud-build.result.txt"
 fi
}
trap finish EXIT
cd "$ROOT"
test "$(uname -s)" = Darwin
test ! -e "$OUT/Payload"
echo "NATIVE CAMERA FOUNDATION START $(date -u +%Y-%m-%dT%H:%M:%SZ)"
xcodebuild -version
PHASE=source-parsing
find DoorMap581 DoorMap581Tests DoorMap581UITests NativeCoreTests -name '*.swift' -print0 | xargs -0 xcrun swiftc -frontend -parse
PHASE=new-camera-golden-tests
swift test --configuration release --filter NativeCameraGoldenTests 2>&1 | tee "$OUT/native-port/camera-native-tests.log"
PHASE=golden-test-count
python3 - <<'PY'
import re
from pathlib import Path
log=Path('cloud-build/native-port/camera-native-tests.log').read_text()
assert len(re.findall(r"Test Case '-\[.*NativeCameraGoldenTests .*\]' passed",log))==12 or len(re.findall(r"Test Case 'NativeCameraGoldenTests\..*' passed",log))==12, log[-12000:]
assert re.search(r'Executed 12 tests, with 0 failures',log), log[-12000:]
assert 'skipped' not in '\n'.join(x for x in log.splitlines() if 'Test Case' in x).lower()
PY
PHASE=apple-sdk-build-for-testing
xcodegen generate
xcodebuild -project DoorMap581.xcodeproj -scheme DoorMap581 \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  -derivedDataPath "$OUT/DerivedData" CODE_SIGNING_ALLOWED=NO build-for-testing \
  > "$OUT/native-port/camera-apple-build.log" 2>&1
PHASE=verify-source-and-artifact
python3 - <<'PY'
import datetime,hashlib,json,subprocess
from pathlib import Path
root=Path.cwd();out=root/'cloud-build/native-port'
paths=['DoorMap581/NativeCore/NativeCameraGeometry.swift','DoorMap581/NativeCore/NativeFitCamera.swift','DoorMap581/NativeCore/NativeCameraPolicy.swift','DoorMap581/NativeCore/NativeCameraInteraction.swift','NativeCoreTests/NativeCameraGoldenTests.swift','NativeCoreTests/NativeCoreFixtures/camera-golden.json']
for rel in paths:
    assert (root/rel).is_file(), rel
    if rel.startswith('DoorMap581'):
        text=(root/rel).read_text()
        assert not any(x in text for x in ['import WebKit','import JavaScriptCore','evaluateJavaScript','NativeBundleServer(']),rel
build=(out/'camera-apple-build.log').read_text();assert '** TEST BUILD SUCCEEDED **' in build,build[-8000:]
golden=json.loads((root/'NativeCoreTests/NativeCoreFixtures/camera-golden.json').read_text())
receipt={'status':'PASS','mode':'S3_PURE_RULES_MACOS_TESTED_IOS_SDK_COMPILED','at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'passed':12,'failed':0,'skipped':0,'appleSDKCompiled':True,'actualiOSSensorOrCameraUIRun':False,'newIPA':False,'physicalDeviceAccepted':False,'all26Complete':False,'sourceHashes':{p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in paths},'goldenCounts':{k:len(golden[k]) for k in ['fitCases','projectionCases','leadTraces','viewportCases','arrivalCases','headingTraces','bearingTraces','gestureTraces']}}
(out/'S3_CAMERA_FOUNDATION_RESULT.json').write_text(json.dumps(receipt,indent=2)+'\n')
PY
printf 'status=PASS\nmode=NATIVE_CAMERA_FOUNDATION_ONLY_NO_IPA\ntests=12\nios_sdk=COMPILED_NOT_SENSOR_UI_TESTED\nphysical_device=NOT_TESTED\nfinished=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUT/cloud-build.result.txt"
cat "$OUT/cloud-build.result.txt"
