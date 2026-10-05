import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';

const require=createRequire(import.meta.url);
const V=require(process.env.DOOR_TEST_ROOT+'/visual-motion.js');
const source=fs.readFileSync(process.env.DOOR_TEST_ROOT+'/door-map.js','utf8').replace(/\r\n/g,'\n');
function extract(name){
  const m=new RegExp('^  (?:async )?function '+name+'\\(','m').exec(source);
  assert.ok(m,name);
  return source.slice(m.index,source.indexOf('\n  }',m.index)+4);
}
const coords=[[120,24],[120,24.001],[120,24.002]];
const state={
  routeEnabled:true,navigationRequested:true,navigationActive:true,fitLocked:false,
  routeProgressIndex:0,displayLeadMeters:0,displayPosition:null,
  routeManeuvers:[{type:'turn',modifier:'right',routeIndex:0,location:[120,24.001]}],
  destination:{lng:120,lat:24.002},position:{lng:120,lat:24.0002,accuracy:5}
};
const ctx=vm.createContext({state,Number,Math,Array,routeCoordinates:()=>coords});
for(const name of ['haversineMeters','segmentProjection','progressProjection','nextRouteManeuver','advanceRouteProjection','navigationDisplayPosition'])vm.runInContext(extract(name),ctx);
const run=x=>vm.runInContext(x,ctx);
const dist=(a,b)=>run(`haversineMeters(${JSON.stringify(a)},${JSON.stringify(b)})`);

let raw={lng:120,lat:24.0002,accuracy:5,speed:10,ts:1000};
state.position=raw;
let display=run(`navigationDisplayPosition(${JSON.stringify(raw)},10)`);
assert(display.lat>raw.lat,'moving display should be ahead on route');
assert(state.displayLeadMeters>4&&state.displayLeadMeters<=10,'lead should be bounded and speed based');
assert(dist(raw,display)>4&&dist(raw,display)<=10.2);

state.displayLeadMeters=8;
raw={lng:120,lat:24.00095,accuracy:5,speed:10,ts:2000};state.position=raw;
display=run(`navigationDisplayPosition(${JSON.stringify(raw)},10)`);
assert(display.lat<24.001,'display must not cross the next turn');
assert(dist(display,{lng:120,lat:24.001})>=1.3,'keep a guard before turn point');

state.routeManeuvers=[];state.displayLeadMeters=8;
raw={lng:120,lat:24.00196,accuracy:5,speed:10,ts:3000};state.position=raw;
display=run(`navigationDisplayPosition(${JSON.stringify(raw)},10)`);
assert(display.lat<24.002,'display must not cross destination');
assert(dist(display,state.destination)>=1.3,'keep a guard before destination');

state.routeManeuvers=[{type:'turn',modifier:'right',routeIndex:0,location:[120,24.001]}];
state.displayLeadMeters=8;
raw={lng:120,lat:24.0002,accuracy:5,speed:0,ts:4000};state.position=raw;
display=run(`navigationDisplayPosition(${JSON.stringify(raw)},0)`);
assert(state.displayLeadMeters>5&&state.displayLeadMeters<8,'lead decays instead of snapping backward at a stop');
assert(display.lat>raw.lat);

state.displayLeadMeters=8;
raw={lng:120,lat:24.0003,accuracy:80,speed:10,ts:5000};state.position=raw;
display=run(`navigationDisplayPosition(${JSON.stringify(raw)},10)`);
assert.equal(state.displayLeadMeters,0,'poor accuracy disables display prediction');
assert.equal(display.lat,raw.lat);assert.equal(display.lng,raw.lng);

state.displayLeadMeters=8;
raw={lng:120.001,lat:24.0003,accuracy:5,speed:10,ts:6000};state.position=raw;
display=run(`navigationDisplayPosition(${JSON.stringify(raw)},10)`);
assert.equal(state.displayLeadMeters,0,'off-route fix disables lead');
assert.equal(display.lng,raw.lng);

const frozen=Object.freeze({lng:120,lat:24.0002,accuracy:5,speed:8,ts:7000});
state.position=frozen;state.displayLeadMeters=0;
run(`navigationDisplayPosition(${JSON.stringify(frozen)},8)`);
assert.deepEqual(frozen,{lng:120,lat:24.0002,accuracy:5,speed:8,ts:7000},'raw GPS object must remain untouched');

let now=0,seq=0;const callbacks=new Map();
const navState={fitLocked:false,navigationActive:true,navigationRequested:true,following:true,cameraUserOverride:false,position:{lng:120,lat:24}};
const marker={_map:null,setLngLat(){return this;},addTo(m){this._map=m;return this;}};
const map={};
const doc={hidden:false,addEventListener(){},removeEventListener(){}};
const controller=new V.Controller({map,marker,getState:()=>navState,documentRef:doc,clock:()=>now,raf:f=>{callbacks.set(++seq,f);return seq;},caf:id=>callbacks.delete(id)});
controller.push({lng:120,lat:24,accuracy:5,speed:8,ts:1000});
now=1000;
controller.push({lng:120.0001,lat:24,accuracy:5,speed:8,ts:2000});
assert.equal(controller.track.duration,0,'active navigation must not reintroduce the old interpolation lag');
controller.destroy();

assert(source.includes("maneuver.meters<=12?'現在'"),'sub-12m maneuver UI must say 現在');
assert(source.includes('displayPosition: null'));
assert(source.includes('const displayCurrent=navigationDisplayPosition(current,displaySpeed)'));
console.log('PASS navigation display lead: raw GPS preserved, route-bounded 0-10m lead, immediate riding display, turn/destination caps');
