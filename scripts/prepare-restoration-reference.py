"""Bundle the immutable accepted reference; transform only native integration seams.
No production/F: writes or network calls. Pass the already captured public folder.
"""
from pathlib import Path
import base64, hashlib, json, math, os, re, shutil, sys

repo = Path(__file__).resolve().parents[1]
reference = Path(sys.argv[1]).resolve()
destination = repo / "DoorMap581" / "Behavior"
assert reference.name == "public" and (reference / "release.json").is_file()
release = json.loads((reference / "release.json").read_text(encoding="utf-8"))
assert release["cameraRevision"] == "fitlock6"
assert str(release["build"]).endswith("fitlock6")
assert not destination.exists(), "Do not overwrite a reviewed integration; update explicitly."
destination.mkdir()
receipt = {"referenceRelease": release, "freshLiveVerified": False,
           "freshLiveBlocker": "Normal /release.json request HTTP403; no access workaround",
           "originals": {}, "nativeChanges": []}
for src in sorted(reference.rglob("*")):
    if not src.is_file():
        continue
    relative = src.relative_to(reference)
    # Edge server configuration/code is evidence, not executable app content.
    if relative.name in ["_worker.js", "_headers", "_redirects"]:
        continue
    dst = destination / relative
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    receipt["originals"][relative.as_posix()] = hashlib.sha256(src.read_bytes()).hexdigest()

core = (destination / "door-map.js").read_text(encoding="utf-8")
def replace(old, new, reason):
    global core
    assert core.count(old) == 1, (reason, core.count(old))
    core = core.replace(old, new)
    receipt["nativeChanges"].append(reason)

replace("insetZoom: 18,", "insetZoom: 19.5,", "Native geographic inset default 19.5, independent of main camera")
replace("inset.touchZoomRotate.disable();", "inset.touchZoomRotate.enable();\n  inset.touchZoomRotate.disableRotation();\n  inset.on('zoomend',()=>{state.insetZoom=inset.getZoom();});", "Preserve manual NLSC geographic zoom; never rotate")
replace("inset.scrollZoom.disable();", "inset.scrollZoom.enable();", "Enable explicit mini zoom without affecting main")
replace("    state.destinationIntent = meta;", "    state.destinationIntent = meta;\n    window.__581AppleDestination=String(meta?.source||'').startsWith('apple');\n    const miniTargetKey=cleanDest.lat+','+cleanDest.lng;\n    if(state.nativeMiniTargetKey!==miniTargetKey){state.nativeMiniTargetKey=miniTargetKey;state.insetZoom=19.5;inset.jumpTo({center:[cleanDest.lng,cleanDest.lat],zoom:19.5,bearing:0,pitch:0});}", "New destination gets close geography; updates and reopen preserve manual draft")
replace("    window.__581AppleDestination=String(meta?.source||'').startsWith('apple');", "    window.__581AppleDestination=String(meta?.source||'').startsWith('apple');\n    if(window.__581AppleDestination){persist=false;window.webkit.messageHandlers.appleMapEngine.postMessage({type:'appleSelection',payload:{name:meta.placeName||'',address:meta.addressText||''}});}", "Apple POI information is main-only and not persisted")
replace("    if (stableUrl || state.destinationHandoffSource==='hash') {", "    if (window.__581AppleDestination || stableUrl || state.destinationHandoffSource==='hash') {", "Do not retain Apple search coordinates in a reusable browser URL")
replace("    state.rawDestination=raw;\n    state.destination=corrected;", "    state.rawDestination=raw;\n    if(window.__581AppleDestination){state.rawDestination={...corrected};state.destinationIntent={source:'inset-manual'};state.destinationInfo={};window.__581AppleDestination=false;}\n    state.destination=corrected;", "An explicit NLSC correction is a clean user-owned point, not exported Apple data")
replace("        if (state.destination) recenterInset({animate:false});", "        // Keep manual pan/zoom and unconfirmed correction on close/reopen.", "Do not reset the NLSC draft whenever the capsule reopens")
replace("    const officialRaw=includeOfficial ? await window.DoorOfficial?.near?.(dest,radiusM).catch(()=>[]) || [] : [];", "    const officialRaw=includeOfficial ? await window.DoorNativeBundle.officialNear(dest,radiusM).catch(()=>[]) : [];", "Read exact verified bundled doorplates before an optional bulk IDB install")
replace("    const heading=Number(ev?.detail?.heading);\n    if (!Number.isFinite(heading)) return;", "    const sample=ev?.detail||{},heading=Number(sample.heading),timestamp=Number(sample.timestamp),accuracy=Number(sample.accuracy);\n    if(sample.heading==null||!Number.isFinite(heading)||heading<0||heading>=360||!Number.isFinite(timestamp)||Date.now()-timestamp>=2500||timestamp>Date.now()+2000||!Number.isFinite(accuracy)||accuracy<0||accuracy>60)return;", "Validate real native compass accuracy/timestamp/range; null is not north")
replace("    state.lastOrientationAt=Date.now();", "    state.lastOrientationAt=timestamp;", "Heading freshness uses actual sensor timestamp, not delayed bridge receipt")
replace("speed:Number.isFinite(Number(d.speed))?Number(d.speed):null,", "speed:d.speed!=null&&Number.isFinite(Number(d.speed))?Number(d.speed):null,", "Null native GPS speed remains unavailable")
replace("heading:Number.isFinite(Number(d.heading))?Number(d.heading):null", "heading:d.heading!=null&&Number.isFinite(Number(d.heading))?Number(d.heading):null", "Null GPS course remains unavailable, never fabricated zero degrees")
replace("    if(d.warmStart===true && !state.position){", "    if(d.warmStart===true){\n      if(state.position){ensureGeolocationWatch();return;}", "A cached warm fix never replaces a trusted live route origin")
replace("userEl.className = 'user-marker';", "userEl.className = 'user-marker direction-unavailable';", "Do not show invented direction before a trustworthy sensor/course")
replace("    const target = compassFresh ? state.compassHeading : state.gpsCourse;\n    if (!Number.isFinite(target)) return;", "    const gpsFresh=state.position&&Date.now()-state.position.ts<2500&&Number(state.position.speed)>=1.2&&Number(state.position.accuracy)<=65;\n    const target = compassFresh ? state.compassHeading : (gpsFresh?state.gpsCourse:null);\n    userEl.classList.toggle('direction-unavailable',!Number.isFinite(target));\n    if (!Number.isFinite(target)) return;", "Hide stale direction; fresh compass wins even at rest/riding, GPS fallback is bounded")
replace("  window.addEventListener('door581:nativeNetwork',onNativeNetwork);", "  window.addEventListener('door581:nativeNetwork',onNativeNetwork);\n  window.addEventListener('door581:nativeLocationError',ev=>onPositionError(ev.detail||{code:2,message:'GPS 暫時無法定位'}));\n  window.addEventListener('door581:nativeLocationAuthorization',ev=>{if([1,2].includes(Number(ev.detail?.status)))onPositionError({code:1,message:'iOS 定位權限被拒絕'});});\n  setInterval(()=>{if(!document.hidden)updateHeading();},500);", "Wire native denied/unavailable errors to existing recovery UI and expire stale direction")
replace("    efficiencyDiagnostics:()=>", "    nativeDiagnostics:()=>({renderer:map.diagnostics(),position:state.position,display:state.displayPosition,heading:state.displayHeading,headingSource:Date.now()-state.lastOrientationAt<2500?'compass':'gps-or-unavailable',insetZoom:inset.getZoom(),insetCenter:inset.getCenter(),destination:state.destination,navigationRequested:state.navigationRequested,pip:state.pipView,routeEnabled:state.routeEnabled,following:state.following,fitLocked:state.fitLocked}),\n    efficiencyDiagnostics:()=>", "Expose rule and actual native renderer diagnostics separately")
replace("  document.body.dataset.theme = state.theme;\n  setHudCollapsed(true);", "  document.body.dataset.theme = state.theme;\n  window.DoorNativeBundle.installStateBridge({state,map,inset,cameraInteraction,locationError:onPositionError,position:onPosition,setDestination,acceptDeliveryRoute,setMode,clearDestination:()=>{stopFitLock('clear-destination');const enabled=state.routeEnabled;setRouteEnabled(false,{persist:false,request:false});state.destination=null;state.rawDestination=null;state.destinationIntent=null;state.destinationInfo={};state.navigationActive=false;state.navigationRequested=false;window.__581AppleDestination=false;for(const k of ['581-door-dest','581-door-dest-raw','581-door-dest-meta'])localStorage.removeItem(k);stabilizeBrowserUrl();clearNearbyPoiMarkers();setRouteEnabled(enabled,{persist:false,request:false});updateDestinationInfoUi();renderAll();syncMainScene();syncInsetScene();syncCameraControls();}});\n  setHudCollapsed(true);", "Native settings/deep-link/test seams reuse existing state machine")
replace("    if (persist) localStorage.setItem('581-door-theme', state.theme);", "    if (persist){localStorage.setItem('581-door-theme', state.theme);window.webkit.messageHandlers.appleMapEngine.postMessage({type:'themeSelection',payload:{theme:state.theme}});}", "Explicit original theme selection updates native Apple appearance")
(destination / "door-map.js").write_text(core, encoding="utf-8", newline="\n")

index = (destination / "index.html").read_text(encoding="utf-8")
index = index.replace("https://unpkg.com/maplibre-gl@5.12.0/dist/maplibre-gl.css", "./vendor/maplibre-gl.css")
index = index.replace("https://unpkg.com/maplibre-gl@5.12.0/dist/maplibre-gl.js", "./vendor/maplibre-gl.js")
anchor = '<script src="./maps-input.js'
assert index.count(anchor) == 1
index = index.replace(anchor, '<script src="./native-map-engine.js"></script>\n  <script src="./native-bundle-data.js"></script>\n  '+anchor)
index = index.replace('</head>', '<link rel="stylesheet" href="./native-main.css" />\n</head>')
index = index.replace('<title>', '<title>Apple 測試 · ')
index = index.replace('aria-label="門牌小窗固定倍率">18×','aria-label="門牌小窗倍率">19.5×')
sha = base64.b64encode(hashlib.sha384(core.encode()).digest()).decode()
index = re.sub(r'(<script src="\./door-map\.js[^\"]*" integrity=")[^"]+', lambda m:m[1]+"sha384-"+sha, index)
(destination / "index.html").write_text(index, encoding="utf-8", newline="\n")
(destination / "vendor").mkdir()
for filename in ["maplibre-gl.js", "maplibre-gl.css", "LICENSE.txt"]:
    shutil.copyfile(repo / "DoorMap581" / "MiniMap" / filename, destination / "vendor" / filename)
for filename in ["native-map-engine.js", "native-bundle-data.js", "native-main.css"]:
    shutil.copyfile(repo / "DoorMap581" / filename, destination / filename)

# Derived render tiles contain only real original OSM geometry. No Apple content.
data_root = destination / "native-data"
data_root.mkdir()
osm_manifest = json.loads((reference / "offline/taichung-prebuilt/manifest.json").read_text(encoding="utf-8"))
seen, tile_index, render_tiles, counts = set(), {}, {}, {"buildings":0,"roads":0,"openBuildingGeometriesSkipped":0}
def tile_xy(lng,lat,z=14):
    return int((lng+180)/360*2**z), int((1-math.asinh(math.tan(lat*math.pi/180))/math.pi)/2*2**z)
def render_feature(element):
    tags=element.get("tags",{});raw=element.get("geometry",[])
    coords=[[p["lon"],p["lat"]] for p in raw if "lon" in p and "lat" in p]
    if len(coords)<2:return None
    if tags.get("building") and tags["building"]!="no":
        if len(coords)<4 or coords[0]!=coords[-1]:counts["openBuildingGeometriesSkipped"]+=1;return None
        geometry={"type":"Polygon","coordinates":[coords]};counts["buildings"]+=1
    elif tags.get("highway"):
        geometry={"type":"LineString","coordinates":coords};counts["roads"]+=1
    else:return None
    return {"type":"Feature","id":element["type"]+":"+str(element["id"]),"properties":{**tags,"source":"osm-original-prebuilt"},"geometry":geometry}
for meta in osm_manifest["files"]:
    if meta["kind"]!="osm":continue
    path=reference / meta["path"].lstrip("/");payload=path.read_bytes()
    assert len(payload)==meta["bytes"] and hashlib.sha256(payload).hexdigest()==meta["sha256"]
    obj=json.loads(payload)
    for tile in obj["tiles"]:
        tile_index.setdefault(tile["key"],[]).append({"path":meta["path"],"part":tile.get("part",0)})
        for element in tile.get("elements",[]):
            key=(element.get("type"),element.get("id"))
            if key in seen:continue
            seen.add(key);feature=render_feature(element)
            if not feature:continue
            ring=feature["geometry"]["coordinates"]
            if feature["geometry"]["type"]=="Polygon":ring=ring[0]
            xy=[tile_xy(*c) for c in ring];xmin=min(x[0] for x in xy);xmax=max(x[0] for x in xy);ymin=min(x[1] for x in xy);ymax=max(x[1] for x in xy)
            if (xmax-xmin+1)*(ymax-ymin+1)>256:continue
            for x in range(xmin,xmax+1):
                for y in range(ymin,ymax+1):render_tiles.setdefault(f"{x}-{y}",[]).append(feature)
manifest={"version":"native-original-osm-fitlock6","tileZoom":14,"counts":counts,"tiles":{}}
(data_root / "osm").mkdir()
for key,features in sorted(render_tiles.items()):
    raw=json.dumps({"type":"FeatureCollection","features":features},ensure_ascii=False,separators=(",",":")).encode()
    (data_root / "osm" / (key+".json")).write_bytes(raw)
    manifest["tiles"][key]={"path":"/native-data/osm/"+key+".json","bytes":len(raw),"sha256":hashlib.sha256(raw).hexdigest()}
(data_root / "osm-manifest.json").write_text(json.dumps(manifest,separators=(",",":")),encoding="utf-8")
(data_root / "osm-file-index.json").write_text(json.dumps(tile_index,separators=(",",":")),encoding="utf-8")
receipt["derivedOSM"]=manifest
receipt["integrationHashes"]={n:hashlib.sha256((destination/n).read_bytes()).hexdigest() for n in ["index.html","door-map.js","native-map-engine.js","native-bundle-data.js","native-main.css"]}
(repo / "docs" / "RESTORATION_REFERENCE_RECEIPT.json").write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps({"release":release["build"],"originalFileCount":len(receipt["originals"]),"derivedOSMCounts":counts,"renderTiles":len(render_tiles),"bundleBytes":sum(p.stat().st_size for p in destination.rglob('*') if p.is_file()),"modifiedCoreSeams":len(receipt["nativeChanges"])},ensure_ascii=False))
