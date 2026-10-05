import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url),F=require(process.env.DOOR_TEST_ROOT+'/fit-camera.js');
const s=fs.readFileSync(process.env.DOOR_TEST_ROOT+'/door-map.js','utf8').replace(/\r\n/g,'\n');
function fn(name){const m=new RegExp('^  (?:async )?function '+name+'\\(','m').exec(s);assert(m,name);return s.slice(m.index,s.indexOf('\n  }',m.index)+4);}
let passed=0;const test=(n,f)=>{f();passed++;console.log('PASS',n);};
function element(r){return {hidden:false,getClientRects:()=>[r],getBoundingClientRect:()=>({...r,width:r.right-r.left,height:r.bottom-r.top})};}
function viewport(width=393,height=852){
 const state={pipView:true,insetCollapsed:true},r={left:0,top:0,right:width,bottom:height,width,height};
 const buttons=[{left:width-77,right:width-10,top:height*.586,bottom:height*.667},{left:width-66,right:width-19,top:height*.679,bottom:height*.733},{left:width-66,right:width-19,top:height*.739,bottom:height*.793},{left:width-66,right:width-19,top:height*.799,bottom:height*.853},{left:width-66,right:width-19,top:height*.859,bottom:height*.913}].map(element);
 const card=element({left:10,right:width-79,top:height*.861,bottom:height*.927});
 const doc={hidden:false,querySelectorAll:()=>buttons,getElementById:id=>id==='insetCard'?card:null};
 const map={getContainer:()=>({getBoundingClientRect:()=>r,clientWidth:width,clientHeight:height})};
 const ctx=vm.createContext({state,map,document:doc,window:{innerWidth:width,innerHeight:height},els:{topHud:element({left:10,right:254,top:60,bottom:130})}});
 for(const n of ['fitPipBottom','fitViewport','navigationViewport'])vm.runInContext(fn(n),ctx);
 return {ctx,state,view:()=>JSON.parse(JSON.stringify(vm.runInContext('fitViewport()',ctx)))};
}
for(const [w,h] of [[393,852],[390,844],[430,932],[375,812]])test(w+'x'+h+' PiP protection includes status offset and full video height',()=>{
 const r=viewport(w,h),v=r.view(),pip=v.obstacles.find(x=>x.left===0&&x.right===w&&x.top===0);
 // This is a top-positioned 16:9 preset, not a claim to observe an OS PiP rectangle.
 const observedBottom=w===393?267:64+(w-20)*9/16;
 assert(pip.bottom>=observedBottom+8,{pip,observedBottom});assert(pip.bottom<h*.42);
 const nav=vm.runInContext('navigationViewport()',r.ctx);assert(nav.top>=pip.bottom);
});
test('PiP off removes only the PiP reservation and restores ordinary HUD obstacle',()=>{
 const r=viewport();r.state.pipView=false;const v=r.view();assert(!v.obstacles.some(x=>x.left===0&&x.right===393&&x.top===0));assert(v.obstacles.some(x=>x.left===5&&x.top===55));
});
test('zero/invalid height cannot produce NaN',()=>{
 const r=viewport();for(const h of ['NaN','0','-1'])assert.equal(vm.runInContext('fitPipBottom('+h+')',r.ctx),0);
});
test('actual FIT solver keeps entire destination glyph below real screenshot PiP',()=>{
 const v=viewport().view(),origin=[120.668,24.12],route=[origin,[120.66815,24.1206],[120.668,24.1215]],dest=route.at(-1);
 const plan=F.solve(route,origin,dest,v,{full:true,riderAnchor:true,targetAbove:true,maxZoom:18.85});assert(plan);assert(F.contains(plan,route,origin,dest,v));
 const a=F.project(origin,plan,v.width,v.height),b=F.project(dest,plan,v.width,v.height);
 assert(b[1]-46>267);assert(a[1]>b[1]+32);assert(a[1]>=v.height*.66-1);
});
test('shortening straight remaining route still increases FIT scale with PiP enabled',()=>{
 const v=viewport().view(),dest=[120.668,24.125];let last=-Infinity;
 for(const meters of [800,400,151,149,75,20]){
  const origin=[dest[0],dest[1]-meters/111320],route=[origin,dest];
  const plan=F.solve(route,origin,dest,v,{full:true,riderAnchor:true,targetAbove:true,maxZoom:meters<=150?20:18.85});
  assert(plan);assert(plan.zoom>=last-.001,{meters,zoom:plan.zoom,last});assert(plan.zoom<=(meters<=150?20:18.85));assert(F.project(dest,plan,v.width,v.height)[1]-46>267);last=plan.zoom;
 }
});
test('actual FIT-without-navigation route trim runs on successive positions, not reroutes',()=>{
 const coords=[[120.668,24.12],[120.668,24.121],[120.668,24.122],[120.668,24.123]];
 const full={type:'FeatureCollection',features:[{type:'Feature',geometry:{type:'LineString',coordinates:coords},properties:{}}]};
 const state={fitLocked:true,navigationRequested:false,routeProgressIndex:0,routeGeoJson:full,destination:{lng:120.668,lat:24.123}};const writes=[];
 const ctx=vm.createContext({state,planner:null,map:{},submitSceneData:(m,id,data)=>writes.push(data),updateQuickRouteMetrics(){},updateInsetTitle(){},emptyFeatureCollection:()=>({type:'FeatureCollection',features:[]})});
 for(const n of ['haversineMeters','segmentProjection','routeCoordinates','progressProjection','updateRouteProgressDisplay'])vm.runInContext(fn(n),ctx);
 for(const lat of [24.1204,24.1214,24.1224]){state.position={lng:120.668,lat};vm.runInContext('updateRouteProgressDisplay()',ctx);assert.equal(state.routeGeoJson,full);const rem=state.routeDisplayGeoJson.features[0].geometry.coordinates;assert(Math.abs(rem[0][1]-lat)<1e-8);assert(rem.slice(1).every(p=>p[1]>=lat));}
 assert.equal(writes.length,3);
});
console.log('PASS PiP / actual progress behavioural checks: '+passed);
