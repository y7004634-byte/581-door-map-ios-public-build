from pathlib import Path
import gzip, hashlib, json
root=Path(__file__).resolve().parents[1]
bundle=(root/'DoorMap581/Behavior').resolve()
assert bundle.is_dir() and bundle.is_relative_to(root)
entries={}
for path in sorted(bundle.rglob('*.json')):
    if path.name=='release.json':continue
    assert path.resolve().is_relative_to(bundle)
    data=path.read_bytes();compressed=gzip.compress(data,compresslevel=6,mtime=0)
    assert gzip.decompress(compressed)==data
    target=path.with_suffix(path.suffix+'.gz')
    assert not target.exists()
    target.write_bytes(compressed)
    entries[path.relative_to(bundle).as_posix()]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'gzipBytes':len(compressed),'gzipSha256':hashlib.sha256(compressed).hexdigest()}
    path.unlink() # only the verified staging copy in this isolated workspace
(root/'docs/COMPRESSED_DATA_RECEIPT.json').write_text(json.dumps(entries,indent=2),encoding='utf-8')
print(json.dumps({'files':len(entries),'originalBytes':sum(x['bytes'] for x in entries.values()),'compressedBytes':sum(x['gzipBytes'] for x in entries.values()),'decodedIdentity':'all exact SHA256 matches'}))
