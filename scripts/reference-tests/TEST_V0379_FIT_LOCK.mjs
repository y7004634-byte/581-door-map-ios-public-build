import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createRequire} from 'node:module';

const require=createRequire(import.meta.url);
const F=require(process.env.DOOR_TEST_ROOT+'/fit-camera.js');
const app=fs.readFileSync(process.env.DOOR_TEST_ROOT+'/door-map.js','utf8').replace(/\r\n/g,'\n');
let passed=0;
const ok=(name,cond)=>{assert.ok(cond,name);passed++;console.log('PASS',name);};

ok('FIT lock trims route even when ordinary navigation was never toggled on',
  app.includes("(state.navigationRequested===false && !state.fitLocked)"));
ok('route display keeps a monotonic segment cursor',
  app.includes('const displayIndex=Math.max(priorIndex,p.index);') &&
  app.includes('state.routeProgressIndex=displayIndex;'));
ok('visible remainder cannot rebuild from a behind-cursor GPS projection',
  app.includes('let remaining=[displayProjection.coord,...coords.slice(displayIndex+1)];') &&
  app.includes("state.routeGeoJson,coords,displayIndex,displayProjection.coord[0],displayProjection.coord[1],remaining.length"));
ok('FIT lock requests target-above composition',
  app.includes('riderAnchor:true,targetAbove:true') &&
  app.includes('full:true,continuous:!!last,targetAbove:true'));

const viewport={width:390,height:800,edge:12,obstacles:[]};
const route=[
  [120.6736,24.1477],
  [120.6736,24.1530],
  [120.6790,24.1530]
];
const origin=route[0], destination=route.at(-1);
const gap=()=>Math.max(18,Math.min(42,viewport.height*.04));

const first=F.solve(route,origin,destination,viewport,{
  riderAnchor:true,targetAbove:true,full:true,maxZoom:18.85
});
ok('initial FIT keeps rider lower than destination',first && first.start[1]>first.end[1]+gap());
ok('initial FIT keeps rider in lower screen band',first && first.start[1]>=viewport.height*.66-1);

const continuous=F.solve(route,origin,destination,viewport,{
  riderAnchor:true,targetAbove:true,previousBearing:first.bearing,
  full:false,continuous:true,maxZoom:18.85
});
ok('continuous FIT preserves target-above orientation',
  continuous && continuous.start[1]>continuous.end[1]+gap());

const upside=(first.bearing+180)%360;
const localFromBad=F.solve(route,origin,destination,viewport,{
  riderAnchor:true,targetAbove:true,previousBearing:upside,
  full:false,continuous:true,maxZoom:18.85
});
ok('bad continuous orientation is rejected instead of preserved',
  localFromBad===null || localFromBad.start[1]>localFromBad.end[1]+gap());

const recovered=F.solve(route,origin,destination,viewport,{
  riderAnchor:true,targetAbove:true,previousBearing:upside,
  full:true,continuous:true,maxZoom:18.85
});
ok('full FIT search recovers destination-top rider-bottom',
  recovered && recovered.start[1]>recovered.end[1]+gap());

console.log(`PASS v0.3.78-fitlock2 FIT lock regression: ${passed} checks.`);
