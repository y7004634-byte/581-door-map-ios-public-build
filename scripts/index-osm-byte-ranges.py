"""Index exact tile byte ranges in the unchanged accepted OSM bulk resources.

Only the derived native index/its receipt change. No tile, row or geometry is removed.
The range and whole-file hashes prove that runtime selective parsing uses original bytes.
"""
import gzip
import hashlib
import json
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
root = repo / "DoorMap581/Behavior"
index_path = root / "native-data/osm-file-index.json.gz"
index = json.loads(gzip.decompress(index_path.read_bytes()))
decoder = json.JSONDecoder()

def sha(data):
    return hashlib.sha256(data).hexdigest()

def ranges(raw):
    text = raw.decode("utf-8")
    cursor = 1
    while True:
        while text[cursor] in " \r\n\t,":
            cursor += 1
        key, cursor = decoder.raw_decode(text, cursor)
        while text[cursor] in " \r\n\t:":
            cursor += 1
        if key == "tiles":
            break
        _, cursor = decoder.raw_decode(text, cursor)
    assert text[cursor] == "["
    cursor += 1
    prior_char = 0
    prior_byte = 0
    result = {}
    while True:
        while text[cursor] in " \r\n\t,":
            cursor += 1
        if text[cursor] == "]":
            break
        start = cursor
        tile, cursor = decoder.raw_decode(text, cursor)
        byte_start = prior_byte + len(text[prior_char:start].encode("utf-8"))
        byte_end = byte_start + len(text[start:cursor].encode("utf-8"))
        identity = (tile["key"], tile.get("part", 0))
        assert identity not in result
        piece = raw[byte_start:byte_end]
        assert json.loads(piece) == tile
        result[identity] = {"byteOffset": byte_start, "byteLength": len(piece), "tileSHA256": sha(piece), "fileBytes": len(raw), "fileSHA256": sha(raw)}
        prior_char, prior_byte = cursor, byte_end
    assert len(result) == len(json.loads(raw)["tiles"])
    return result

paths = sorted({record["path"] for records in index.values() for record in records})
indexed = {}
for name in paths:
    raw = gzip.decompress((root / (name.lstrip("/") + ".gz")).read_bytes())
    indexed[name] = ranges(raw)
records = 0
for key, items in index.items():
    for record in items:
        record.update(indexed[record["path"]][(key, record.get("part", 0))])
        records += 1
raw_index = json.dumps(index, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
packed = gzip.compress(raw_index, compresslevel=9, mtime=0)
index_path.write_bytes(packed)
receipt_path = repo / "docs/COMPRESSED_DATA_RECEIPT.json"
receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
receipt["native-data/osm-file-index.json"] = {"bytes": len(raw_index), "sha256": sha(raw_index), "gzipBytes": len(packed), "gzipSha256": sha(packed)}
receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
print(json.dumps({"bulkFilesUnchanged": len(paths), "tileKeys": len(index), "indexedParts": records, "indexBytes": len(raw_index), "indexGzipBytes": len(packed)}))
