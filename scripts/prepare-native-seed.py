"""Derive native seed metadata from already accepted build8 resource receipts.
No network, no dataset rebuild, no changes to original Behavior resources.
"""
from pathlib import Path
import hashlib, json, subprocess
root=Path(__file__).resolve().parents[1]
source=root/'docs/COMPRESSED_DATA_RECEIPT.json'
def sha(b): return hashlib.sha256(b).hexdigest()
def canonical(obj): return json.dumps(obj,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode('utf-8')
expected=subprocess.check_output(['git','-C',str(root),'show','e81f322:docs/COMPRESSED_DATA_RECEIPT.json'])
assert source.read_bytes().replace(b'\r\n',b'\n')==expected.replace(b'\r\n',b'\n'), 'ACCEPTED_RECEIPT_CHANGED'
records=json.loads(source.read_text(encoding='utf-8-sig'))
assert len(records)==3122, len(records)
files=[]; decoded={}
for path, value in sorted(records.items()):
    parts=Path(path).parts
    assert not path.startswith('/') and '..' not in parts and '\\' not in path and ':' not in path
    component=path.split('/')[0]
    if component=='offline': component=path.split('/')[1]
    file=root/'DoorMap581/Behavior'/(path+'.gz')
    assert file.is_file() and file.stat().st_size==value['gzipBytes'], 'ACCEPTED_RESOURCE_MISSING_OR_RESIZED:'+path
    files.append({'path':path+'.gz','component':component,'bytes':value['gzipBytes'],'sha256':value['gzipSha256']})
    decoded[path]={'bytes':value['bytes'],'sha256':value['sha256']}
manifest={'schema':1,'packageID':'door581-appletest-public-data','version':'fitlock6-build8-seed-v1','requiredComponents':sorted({f['component'] for f in files}),'files':files}
catalog={'schema':1,'manifest':manifest,'decoded':decoded}
data=canonical(catalog); output=root/'DoorMap581/NativeData'; output.mkdir(exist_ok=True)
target=output/'seed-catalog.json'
if target.exists(): assert target.read_bytes()==data, 'EXISTING_CATALOG_DIFFERS'
target.write_bytes(data)
constants='''// Generated from accepted build8 metadata, not a new data source.
import Foundation

enum NativeSeedIdentity {
    static let catalogSHA256 = "%s"
    static let manifestSHA256 = "%s"
    static let fileCount = %d
    static let storedBytes: Int64 = %d
}
'''%(sha(data),sha(canonical(manifest)),len(files),sum(f['bytes'] for f in files))
(root/'DoorMap581/NativeSeedIdentity.swift').write_text(constants,encoding='utf-8',newline='\n')
report={'status':'DERIVED_METADATA_ONLY','sourceReceiptSHA256':sha(source.read_bytes()),'catalogSHA256':sha(data),'manifestSHA256':sha(canonical(manifest)),'files':len(files),'components':manifest['requiredComponents'],'storedBytes':sum(f['bytes'] for f in files),'decodedBytes':sum(f['bytes'] for f in decoded.values()),'originalResourceChanges':0,'networkRequests':0}
(root/'docs/native-port/SEED_CATALOG_RESULT.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
