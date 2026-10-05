// Development-only oracle. Never included in, or executed by, the iOS app.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),zlib=require('node:zlib');
const ref=process.argv[2],out=process.argv[3];if(!ref||!out)throw Error('Usage: make-native-search-golden REFERENCE_DIR OUTPUT');
const code=fs.readFileSync(path.join(ref,'search-core.js'));
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
if(sha(code)!=='8a05dba5db6837c3d26d18b0b3685f028fc23a192b6b78fadb4c4227ca6185d3')throw Error('Unexpected accepted reference');
const C=require(path.resolve(ref,'search-core.js'));
const indexPath=path.join(ref,'offline/taichung-prebuilt/search-index.json');
const data=fs.existsSync(indexPath)?fs.readFileSync(indexPath):zlib.gunzipSync(fs.readFileSync(indexPath+'.gz'));
if(sha(data)!=='47e82698f8901f85193c2e726d4dd1d2c2f51d96878f2ec9fb0d1c5968591718')throw Error('Unexpected accepted index');
const rows=JSON.parse(data).rows.map(C.fromRow),center={lat:24.135,lng:120.688};
const queries=['火鍋','加油站','全家','7-11','711','三媽','50嵐','胖老爹','清新福全','清心福全','麥當勞','Family Mart','中油公園路加油站','永隆門市','全家便利商店 台中興大店','銀行','咖啡','藥局','診所','台中市西區民生路100號','台中 麥當勞','麥當牢','中油 公園路','築間','自助洗衣','7－11','超商','restaurant'];
const isAddress=q=>/(?:\d+.*(?:號|路|街|大道|段|巷|弄)|(?:路|街|大道|段|巷|弄).*[0-9０-９]|(?:市|縣).*(?:區|鄉|鎮).*(?:路|街|大道))/i.test(q);
const cases=[];
for(const q of queries){const ranked=C.rankResults([rows],q,center),window=isAddress(q)?ranked:ranked.map((r,i)=>({r,i,d:C.meters(center,r)})).sort((a,b)=>a.d-b.d||a.i-b.i);let list,pins,radius=null;if(isAddress(q)){list=ranked;pins=ranked;}else{const primary=window.filter(x=>x.d<=3000);radius=primary.length>=6?3000:8000;list=window.filter(x=>x.d<=radius).map(x=>x.r);pins=primary.map(x=>x.r);}cases.push({query:q,center,ids:ranked.map(C.key),priorities:ranked.map(x=>x.matchPriority),kinds:ranked.map(x=>x.matchKind),listIDs:list.map(C.key),pinIDs:pins.map(C.key),radius});}
const strings=['臺灣 7－11','ＡＢＣ１２３','麦当劳','Family Mart','咖啡☕️','a\u0301 BC','台中（西區） 公益路','711','７－１１','空　白','第12-3號','A_B·C','統一超商','咖啡／餐廳','foo™','İIıi','😀店家'];
const normalizations=strings.map(text=>({text,normalized:C.normalize(text),tokens:C.remotePlan(text).tokens}));
let seed=581;const rnd=()=>{seed=(1664525*seed+1013904223)>>>0;return seed;};const chars=['中','台','東','門','全','家','a','b','1','2'];const edits=[];for(let n=0;n<400;n++){let a=Array.from({length:2+rnd()%7},()=>chars[rnd()%chars.length]).join('');let b=Array.from(a);const i=rnd()%b.length;if(n%4===0)b.splice(i,1);else if(n%4===1)b.splice(i,0,chars[rnd()%chars.length]);else if(n%4===2)b[i]=chars[rnd()%chars.length];else if(i+1<b.length)[b[i],b[i+1]]=[b[i+1],b[i]];b=b.join('');edits.push({a,b,expected:C.oneEdit(a,b)});}
fs.mkdirSync(path.dirname(out),{recursive:true});
const result=JSON.stringify({sourceHash:sha(code),indexHash:sha(data),rows:rows.length,cases,normalizations,edits},null,2)+'\n';
if(fs.existsSync(out)&&!fs.readFileSync(out).equals(Buffer.from(result)))throw Error('Existing golden differs: review before replacing');
fs.writeFileSync(out,result);console.log(JSON.stringify({queries:cases.length,normalizations:normalizations.length,edits:edits.length,bytes:fs.statSync(out).size,sha256:sha(fs.readFileSync(out))}));
