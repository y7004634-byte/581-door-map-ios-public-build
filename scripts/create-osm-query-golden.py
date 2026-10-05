"""Capture the former whole-document query results from unchanged accepted data."""
import gzip
import hashlib
import json
import math
from pathlib import Path
import subprocess

repo = Path(__file__).resolve().parents[1]
root = repo / "DoorMap581/Behavior"
baseline = "45fe6278e9ab9d5266099698d7e107d4aa518d18"
original_index = subprocess.check_output(["git", "show", baseline + ":DoorMap581/Behavior/native-data/osm-file-index.json.gz"], cwd=repo)
index = json.loads(gzip.decompress(original_index))
receipts = json.loads(subprocess.check_output(["git", "show", baseline + ":docs/COMPRESSED_DATA_RECEIPT.json"], cwd=repo))
documents = {}
for name in {r["path"] for rs in index.values() for r in rs}:
    packed = (root / (name.lstrip("/") + ".gz")).read_bytes()
    assert hashlib.sha256(packed).hexdigest() == receipts[name.lstrip("/")]["gzipSha256"]
    documents[name] = json.loads(gzip.decompress(packed))

def response(lat, lng, radius):
    x = math.floor((lng + 180) / 360 * 4096)
    y = math.floor((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * 4096)
    dlat = min(8000, max(50, radius)) / 111320
    dlng = dlat / max(.3, math.cos(math.radians(lat)))
    def inside(p):
        return "lat" in p and "lon" in p and abs(p["lat"]-lat) <= dlat and abs(p["lon"]-lng) <= dlng
    def near(row):
        if inside(row) or inside(row.get("center", {})):
            return True
        geometry = row.get("geometry", []) + [p for m in row.get("members", []) for p in m.get("geometry", [])]
        if any(inside(p) for p in geometry):
            return True
        lats = [p["lat"] for p in geometry if "lat" in p]
        lngs = [p["lon"] for p in geometry if "lon" in p]
        return bool(lats and lngs and max(lats) >= lat-dlat and min(lats) <= lat+dlat and max(lngs) >= lng-dlng and min(lngs) <= lng+dlng)
    seen, out = set(), []
    for tx in range(x-1, x+2):
        for ty in range(y-1, y+2):
            key = f"12/{tx}/{ty}"
            for record in index.get(key, []):
                tile = next(t for t in documents[record["path"]]["tiles"] if t["key"] == key and t.get("part", 0) == record.get("part", 0))
                for row in tile["elements"]:
                    identity = str(row.get("type", "")) + ":" + str(row.get("id", ""))
                    if near(row) and identity not in seen:
                        seen.add(identity); out.append(row)
    return {"elements": out, "source": "accepted-original-prebuilt", "complete": True}

cases = [(24.147663,120.672973,50), (24.147663,120.672973,250), (24.16,120.67,1200), (24.22,120.59,250), (24.10,120.70,250), (24.18,120.73,250), (24.25,120.72,250), (24.09,120.67,250), (24.147663,120.672973,8000)]
golden = []
for lat,lng,radius in cases:
    result = response(lat,lng,radius)
    golden.append({"latitude": lat,"longitude": lng,"radius": radius,"query": f"[out:json];way(around:{radius},{lat},{lng});out geom;","expected": result})
    print(json.dumps({"latitude":lat,"longitude":lng,"radius":radius,"elements":len(result["elements"]),"types":sorted({r["type"] for r in result["elements"]})}))
directory = repo / "DoorMap581Tests/Fixtures"
directory.mkdir(parents=True, exist_ok=True)
raw = json.dumps({"source":baseline,"originalIndexSHA256":hashlib.sha256(original_index).hexdigest(),"cases":golden}, ensure_ascii=False, separators=(",", ":")).encode()
packed = gzip.compress(raw,compresslevel=9,mtime=0)
(directory / "osm-query-baseline.json.gz").write_bytes(packed)
print(json.dumps({"goldenRawBytes":len(raw),"goldenGzipBytes":len(packed),"shippingIPAResource":False}))
