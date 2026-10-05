import hashlib,json
from pathlib import Path
repo=Path(__file__).resolve().parents[1]
source=repo.parent/'door-map-community-candidate'
names=['TEST_V0379_FIT_LOCK.mjs','TEST_V0380_CAMERA_OWNERSHIP.mjs','TEST_V0380_PIP_RUNTIME.mjs','TEST_V0381_MANUAL_ZOOM.mjs','TEST_V0382_NAV_DISPLAY_LEAD.mjs']
target=repo/'scripts/reference-tests';target.mkdir(exist_ok=True)
receipt={}
for name in names:
    raw=(source/name).read_bytes();text=raw.decode('utf-8').replace("'./public/", "process.env.DOOR_TEST_ROOT+'/ ".replace('/ ','/'))
    (target/name).write_text(text,encoding='utf-8')
    receipt[name]={'sourceSha256':hashlib.sha256(raw).hexdigest(),'adaptation':'IO root only; original cases and inputs unchanged'}
(target/'receipt.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')
print('Captured five current release regression suites, input cases unchanged')
