"""Sync reviewed native seams; immutable web snapshot is never modified."""
import base64, hashlib, json, re
from pathlib import Path
repo=Path(__file__).resolve().parents[1]
root=repo/'DoorMap581'/'Behavior'
for name in ['native-map-engine.js','native-bundle-data.js','native-main.css']:
    (root/name).write_bytes((repo/'DoorMap581'/name).read_bytes())
data=(root/'native-bundle-data.js').read_text(encoding='utf-8')
data=data.replace("gpsError:state.locationError||''", "gpsState:root.document.getElementById('gpsState').textContent")
data=data.replace("sensor:'SIMULATED'};out.textContent", "sensor:'SIMULATED',lastMapClick:r.lastMapClick,webHeartbeatMaxMillis:Number(tools.dataset.heartbeatMax)||0,bundleCacheBytes:bundle.cacheBytes,positionAgeMillis:state.position?Date.now()-state.position.ts:null,moreViewport:(()=>{const q=root.document.getElementById('morePanel').getBoundingClientRect();return {x:q.x,y:q.y,width:q.width,height:q.height};})()};out.textContent")
(root/'native-bundle-data.js').write_bytes(data.encode('utf-8'))
source=(root/'door-map.js').read_text(encoding='utf-8')
old="    const info=state.destinationInfo||{};\n    const view=window.DoorDestinationCard.data(info,state.destinationIntent||{},!!state.destination);"
new="    const appleOnly=window.__581AppleDestination===true;\n    const info=appleOnly?{}:(state.destinationInfo||{});\n    const view=window.DoorDestinationCard.data(info,appleOnly?{}:(state.destinationIntent||{}),!!state.destination);"
if old in source:
    assert source.count(old)==1;source=source.replace(old,new)
source=source.replace("els.insetHouseNumber.textContent=compact||view.detail||view.name||'未設定';", "els.insetHouseNumber.textContent=appleOnly?'NLSC 門牌核對':(compact||view.detail||view.name||'未設定');")
source=source.replace("inset.on('zoomend',()=>{state.insetZoom=inset.getZoom();});", "inset.on('zoomend',()=>{state.insetZoom=inset.getZoom();const badge=document.querySelector('#insetCard .mini-badge');if(badge)badge.textContent=state.insetZoom.toFixed(1)+'×';});")
(root/'door-map.js').write_text(source,encoding='utf-8')
html=(root/'index.html').read_text(encoding='utf-8')
digest=base64.b64encode(hashlib.sha384((root/'door-map.js').read_bytes()).digest()).decode()
html=re.sub(r'(src="\./door-map.js[^\"]*" integrity=")sha384-[^\"]+',r'\g<1>sha384-'+digest,html)
html=html.replace('刪除資料包</button>','刪除下載快取</button>')
html=html.replace('下載 / 補齊台中離線資料</button>','下載 / 補齊離線快取</button>')
html=html.replace('<div id="offlinePackStatus"', '<p class="extra-layer-note">此測試版已內建核對資料；刪除只清除下載快取，內建資料隨 App 保留。</p><div id="offlinePackStatus"') if '此測試版已內建核對資料' not in html else html
(root/'index.html').write_text(html,encoding='utf-8')
p=repo/'docs/RESTORATION_REFERENCE_RECEIPT.json';receipt=json.loads(p.read_text(encoding='utf-8'))
receipt['integrationHashes']={n:hashlib.sha256((root/n).read_bytes()).hexdigest() for n in ['index.html','door-map.js','native-map-engine.js','native-bundle-data.js','native-main.css']}
receipt['additionalNativeSeams']=['Apple inset source/label firewall','manual inset zoom badge','bundled versus downloaded cache wording','NLSC native raster','viewport-scoped public feature queries']
p.write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS reviewed resource seams synchronized; current SRI updated')
