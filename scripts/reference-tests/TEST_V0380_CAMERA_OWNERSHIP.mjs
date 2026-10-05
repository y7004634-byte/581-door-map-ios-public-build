import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url),A=require(process.env.DOOR_TEST_ROOT+'/camera-interaction.js');
let passed=0;const test=(name,fn)=>{fn();passed++;console.log('PASS',name);};
function rig(mode='heading'){
 const state={mode:'heading',following:mode!=='fit',cameraUserOverride:false,fitLocked:mode==='fit',navigationActive:mode!=='fit',navigationRequested:mode!=='fit'};
 const tasks=new Map(),data=new Map();let seq=0,stops=0,resumes=0,hidden=false,editing=false,writes=0;
 const storage={getItem:k=>data.get(k)||null,setItem:(k,v)=>{data.set(k,v);writes++;}};
 const c=new A.Controller({getState:()=>state,storage,isHidden:()=>hidden,isEditing:()=>editing,stop:()=>stops++,resume:()=>resumes++,setTimer:(f,t)=>{tasks.set(++seq,{f,t});return seq;},clearTimer:id=>tasks.delete(id)});
 c.selectionChanged();
 return {state,c,tasks,data,storage,set hidden(v){hidden=v;},set editing(v){editing=v;},get stops(){return stops;},get resumes(){return resumes;},get writes(){return writes;},flush(){for(const [id,t] of [...tasks]){tasks.delete(id);t.f();}}};
}
for(const mode of ['heading','fit']){
 test(mode+' touch landing and release retain selected mode',()=>{
  const r=rig(mode),before=[r.state.following,r.state.fitLocked,r.state.cameraUserOverride];
  r.c.handle({type:'pointerdown',pointerId:1,clientX:170,clientY:500});
  assert.equal(r.state.cameraGestureHold,true);assert.deepEqual([r.state.following,r.state.fitLocked,r.state.cameraUserOverride],before);
  r.c.end({type:'pointerup',pointerId:1});assert.equal(r.state.cameraGestureHold,false);assert.equal(r.resumes,1);assert.equal(r.tasks.size,0);
 });
 test(mode+' drag pauses then automatically resumes without unlocking',()=>{
  const r=rig(mode);r.c.handle({type:'touchstart',touches:[{clientX:150,clientY:400}]});
  r.c.move({type:'touchmove',touches:[{clientX:250,clientY:480}]});
  r.c.handle({type:'dragstart',originalEvent:{type:'touchmove',touches:[{clientX:250,clientY:480}]}});
  r.c.end({type:'touchend',touches:[]});assert.equal(r.tasks.size,1);assert.equal(r.state.cameraUserOverride,false);assert.equal(r.state.fitLocked,mode==='fit');
  r.flush();assert.equal(r.resumes,1);assert.equal(r.state.cameraGestureHold,false);assert.equal(r.c.protected(),true);
 });
 test(mode+' app-switch cancellation clears a lost touch but preserves owner',()=>{
  const r=rig(mode);r.c.handle({type:'pointerdown',pointerId:7,clientX:390,clientY:810});r.c.move({clientX:320,clientY:500});
  r.hidden=true;r.c.lifecycle(false);r.c.end({type:'pointercancel',pointerId:7});assert.equal(r.resumes,0);assert.equal(r.state.cameraGestureHold,false);assert.equal(r.tasks.size,0);
  r.hidden=false;r.c.lifecycle(true);assert.equal(r.resumes,1);assert.equal(r.c.protected(),true);
 });
 test(mode+' background never leaves a timer or writes a camera frame',()=>{
  const r=rig(mode);r.c.handle({type:'wheel'});assert.equal(r.tasks.size,1);r.hidden=true;r.c.lifecycle(false);r.flush();assert.equal(r.tasks.size,0);assert.equal(r.resumes,0);assert.equal(r.c.protected(),true);
 });
 test(mode+' preference persists across a new document without coordinates',()=>{
  const r=rig(mode);r.state.position={lat:24,lng:120};r.c.persist();const p=A.readPreference(r.storage);
  assert.equal(p.owner,mode);assert.equal(p.mode,'heading');assert(!JSON.stringify(p).includes('lat'));assert(!JSON.stringify(p).includes('120'));
  const before=r.writes;r.c.persist();r.c.persist();assert.equal(r.writes,before);
 });
}
test('two-finger pointer/touch compatibility events cannot release FIT early',()=>{
 const r=rig('fit');for(const id of [1,2])r.c.begin({type:'pointerdown',pointerId:id,clientX:100*id,clientY:400});
 r.c.begin({type:'touchstart',touches:[{clientX:100,clientY:400},{clientX:200,clientY:400}]});
 const stoppedBeforeZoomStart=r.stops;
 r.c.handle({type:'zoomstart',originalEvent:{type:'touchmove',touches:[{},{}]}});
 assert.equal(r.stops,stoppedBeforeZoomStart,'MapLibre zoomstart must not stop the user pinch');
 r.c.end({type:'pointerup',pointerId:1});assert.equal(r.state.cameraGestureHold,true);assert.equal(r.resumes,0);
 r.c.end({type:'pointerup',pointerId:2});r.flush();assert.equal(r.state.fitLocked,true);assert.equal(r.state.cameraGestureHold,false);
});
test('explicit manual choice cancels delayed automatic return',()=>{
 const r=rig('fit');r.c.handle({type:'wheel'});r.state.fitLocked=false;r.state.following=false;r.state.cameraUserOverride=true;r.state.navigationActive=false;r.state.navigationRequested=false;r.c.selectionChanged();
 r.flush();r.c.lifecycle(true);assert.equal(r.resumes,0);assert.equal(A.readPreference(r.storage).owner,'manual');
});
test('explicit FIT-to-heading choice clears pending touch hold',()=>{
 const r=rig('fit');r.c.begin({type:'pointerdown',pointerId:1});r.state.fitLocked=false;r.state.following=true;r.state.mode='heading';r.state.navigationRequested=true;r.c.selectionChanged();assert.equal(r.state.cameraGestureHold,false);assert.equal(r.tasks.size,0);
});
test('programmatic camera events and typing do not start a gesture',()=>{
 const r=rig();assert.equal(r.c.handle({type:'zoomstart'}),false);assert.equal(r.c.handle({type:'keydown',key:'a'}),false);assert.equal(r.stops,0);assert.equal(r.state.cameraGestureHold,undefined);
});
test('editing remains an explicit separate camera owner',()=>{
 const r=rig('fit');r.editing=true;assert.equal(r.c.handle({type:'touchstart'}),false);r.c.lifecycle(true);assert.equal(r.resumes,0);
});
test('malformed persisted settings fail safely',()=>{
 for(const s of ['bad','null','{}','{"v":1,"owner":"bad","mode":"heading"}'])assert.equal(A.readPreference({getItem:()=>s}),null);
});
// Execute actual controller functions, not just search for marker strings.
const source=fs.readFileSync(process.env.DOOR_TEST_ROOT+'/door-map.js','utf8').replace(/\r\n/g,'\n');
function extract(name){const m=new RegExp('^  (?:async )?function '+name+'\\(','m').exec(source);assert(m,name);return source.slice(m.index,source.indexOf('\n  }',m.index)+4);}
test('actual touch handler delegates to retained ownership controller',()=>{
 const r=rig(),ctx=vm.createContext({state:r.state,cameraInteraction:r.c,map:{stop(){}},syncCameraControls(){},holdFitForTouch:raw=>r.c.begin(raw),stopFitLock(){throw Error('Unexpected unlock');}});
 vm.runInContext(extract('releaseAutoFollowOnUserGesture'),ctx);
 vm.runInContext("releaseAutoFollowOnUserGesture({type:'touchstart',touches:[{clientX:200,clientY:500}]})",ctx);
 assert.equal(r.state.following,true);assert.equal(r.state.cameraUserOverride,false);assert.equal(r.state.cameraGestureHold,true);
});
test('actual ordinary follow and FIT update do no work during input hold',()=>{
 for(const name of ['followCamera','updateFitCamera']){const ctx=vm.createContext({state:{cameraGestureHold:true}});vm.runInContext(extract(name),ctx);vm.runInContext(name+'({force:true})',ctx);}
});
test('actual startup overview does not overwrite restored heading choice',()=>{
 const state={fitLocked:false,cameraRestorePending:true,following:true,cameraUserOverride:false,position:{lat:24,lng:120},autoFitRoutePending:true};let frames=0;
 const ctx=vm.createContext({state,followCamera:()=>frames++});vm.runInContext(extract('showRouteOverview'),ctx);vm.runInContext('showRouteOverview()',ctx);assert.equal(frames,1);assert.equal(state.following,true);assert.equal(state.autoFitRoutePending,false);
});
console.log('PASS camera ownership behavioural checks: '+passed);
