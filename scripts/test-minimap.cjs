const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const contract=require('../DoorMap581/MiniMap/nlsc-contract.js');
test('NLSC receives only viewport and device coordinates, dropping all Apple place fields',()=>{
  const value=contract.parse({center:[120.6,24.1],metersPerPoint:1,bearing:380,heading:30,rider:[120.61,24.11],
    place:{name:'Do not transfer',coordinate:[120.62,24.12]},applePOIs:[{name:'Never transfer'}],destination:[120.62,24.12],route:[]});
  assert.deepEqual(Object.keys(value).sort(),['bearing','center','heading','metersPerPoint','rider']);
  assert.equal(value.bearing,20);
  assert(!JSON.stringify(value).includes('transfer'));
});
test('invalid bridge inputs are rejected',()=>{
  for(const v of [null,{}, {center:[120,91],metersPerPoint:1},{center:[Infinity,24],metersPerPoint:1},
    {center:[120,24],metersPerPoint:0},{center:[120,24],metersPerPoint:'1'}]) assert.equal(contract.parse(v),null);
});
test('scale conversion round-trips and clamps to tile zoom range',()=>{
  for(const lat of [21,24.15,26])for(const meters of [0.25,0.5,1,2,5])for(const offset of [0,1,2]){
    const zoom=contract.zoom(meters,lat,offset);
    if(zoom>12&&zoom<21)assert(Math.abs(contract.meters(zoom,lat,offset)-meters)<1e-9);
  }
  assert.equal(contract.zoom(1e9,24),12);assert.equal(contract.zoom(0.00001,24),21);
});
test('mini map has only NLSC raster and device marker; no Apple search or polling',()=>{
  const text=fs.readFileSync(path.join(__dirname,'../DoorMap581/MiniMap/nlsc-map.js'),'utf8');
  assert(text.includes('/wmts/EMAP/default/GoogleMapsCompatible/{z}/{y}/{x}'));
  for(const forbidden of ['MKLocalSearch','applePOIs','mapkit','setInterval','localStorage','fetch('])assert(!text.includes(forbidden));
});
