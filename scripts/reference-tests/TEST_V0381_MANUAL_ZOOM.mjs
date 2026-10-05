import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source=fs.readFileSync(process.env.DOOR_TEST_ROOT+'/door-map.js','utf8').replace(/\r\n/g,'\n');
function extract(name){
  const m=new RegExp('^  (?:async )?function '+name+'\\(','m').exec(source);
  assert.ok(m,name);
  return source.slice(m.index,source.indexOf('\n  }',m.index)+4);
}
let zoom=16;
const state={fitLocked:true,following:false,cameraUserOverride:false,cameraGestureStartZoom:null,cameraZoomOffset:0,fitNeedsRefresh:false};
const map={getZoom:()=>zoom};
const ctx=vm.createContext({state,map,Number,Math});
vm.runInContext(extract('beginManualZoomCapture'),ctx);
vm.runInContext(extract('commitManualZoomCapture'),ctx);

vm.runInContext("beginManualZoomCapture({originalEvent:{type:'touchmove'}})",ctx);
zoom=17.25;
vm.runInContext("commitManualZoomCapture({originalEvent:{type:'touchend'}})",ctx);
assert.ok(Math.abs(state.cameraZoomOffset-1.25)<1e-9);
assert.equal(state.fitLocked,true);
assert.equal(state.fitNeedsRefresh,true);

state.fitNeedsRefresh=false;
zoom=17.25;
vm.runInContext("beginManualZoomCapture({originalEvent:{type:'touchmove'}})",ctx);
zoom=16.75;
vm.runInContext("commitManualZoomCapture({originalEvent:{type:'touchend'}})",ctx);
assert.ok(Math.abs(state.cameraZoomOffset-.75)<1e-9);
assert.equal(state.fitLocked,true);

const before=state.cameraZoomOffset;
vm.runInContext("beginManualZoomCapture({})",ctx);
zoom=18;
vm.runInContext("commitManualZoomCapture({})",ctx);
assert.equal(state.cameraZoomOffset,before);

assert.ok(source.includes("plan.zoom=Math.max(12,Math.min(20.5,autoFitZoom+zoomOffset))"));
assert.ok(source.includes("zoom+(Number(state.cameraZoomOffset)||0)"));
assert.ok(source.includes("map.on('zoomstart', beginManualZoomCapture)"));
assert.ok(source.includes("map.on('zoomend', commitManualZoomCapture)"));
console.log('PASS manual pinch zoom remains an offset while FIT/navigation ownership stays locked');
