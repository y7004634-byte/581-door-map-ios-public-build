// New S3 oracle fixtures from the pinned accepted rules, never runtime JS.
const fs=require('fs'),path=require('path'),vm=require('vm'),crypto=require('crypto'),assert=require('assert/strict');
const root=path.resolve(__dirname,'..'),ref='C:/CodexWork/2026-10-04/task/door-map-community-candidate/public';
const owner=JSON.parse(fs.readFileSync(path.join(root,'.git/door581-native-writer.lock.json'),'utf8').replace(/^\uFEFF/,''));
assert.equal(owner.foregroundSessionID,'GPT_DC_S2_REPAIR_20261005_1604');assert.equal(owner.foregroundWriterActive,true);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex'),sourceHashes={};
const required={'fit-camera.js':'6abd9b6f54b00a8c5ac6006742cdafb63a58fce996635a90afc1f8a728577d79','camera-interaction.js':'b3ca450ebb0f8da21f70427177395304e0458f52edc316978006ac5186d444af','door-map.js':'23539b4a75598aee270478796528153b87274877ca635be9ac0cd68c1f762cf6'};
for(const file of [...Object.keys(required),'arrival-camera.js']){sourceHashes[file]=sha(fs.readFileSync(path.join(ref,file)));if(required[file])assert.equal(sourceHashes[file],required[file],file);}
const Fit=require(path.join(ref,'fit-camera.js')),Arrival=require(path.join(ref,'arrival-camera.js')),Interaction=require(path.join(ref,'camera-interaction.js'));
const source=fs.readFileSync(path.join(ref,'door-map.js'),'utf8').replace(/\r\n/g,'\n');
function extract(name){
 const m=new RegExp('^  function '+name+'\\(','m').exec(source);assert(m,name);const start=source.indexOf('{',m.index);let depth=0,quote='',comment='';
 for(let i=start;i<source.length;i++){const c=source[i],n=source[i+1];if(comment==='line'){if(c==='\n')comment='';continue;}if(comment==='block'){if(c==='*'&&n==='/'){comment='';i++;}continue;}if(quote){if(c==='\\'){i++;continue;}if(c===quote)quote='';continue;}if(c==='/'&&n==='/'){comment='line';i++;continue;}if(c==='/'&&n==='*'){comment='block';i++;continue;}if(c==='"'||c==="'"||c==='`'){quote=c;continue;}if(c==='{')depth++;if(c==='}'&&--depth===0)return source.slice(m.index,i+1);}
 throw Error('Unterminated function '+name);
}
const point=p=>({lat:p[1],lng:p[0]}),arr=p=>[p.lng,p.lat];
const options=o=>({maxZoom:20,previousBearing:null,full:true,continuous:false,riderAnchor:false,targetAbove:false,anchorBounds:null,...o});
const nativeCamera=c=>c?{center:point(c.center),zoom:c.zoom,bearing:c.bearing,pitch:c.pitch,start:{x:c.start[0],y:c.start[1]},end:{x:c.end[0],y:c.end[1]},preference:c.preference,scale:c.scale,riderAnchor:!!c.riderAnchor,targetAbove:!!c.targetAbove,stabilityHeld:!!c.stabilityHeld,stats:c.stats}:null;
const paths=[
 {name:'north-turns',p:[[120.688,24.135],[120.688,24.14],[120.691,24.143],[120.689,24.146],[120.686,24.149]]},
 {name:'east',p:[[120.66,24.13],[120.664,24.13],[120.664,24.132],[120.681,24.132]]},
 {name:'west-diagonal',p:[[120.69,24.14],[120.684,24.133],[120.68,24.13],[120.675,24.131]]},
 {name:'large-loop',p:[[120.68,24.13],[120.705,24.13],[120.705,24.16],[120.66,24.16],[120.66,24.132],[120.6803,24.132]]},
 {name:'short',p:[[120.68,24.13],[120.6803,24.1302],[120.68035,24.1305]]},
 {name:'dense-zigzag',p:Array.from({length:97},(_,i)=>[120.68+(i%4<2?0:0.001),24.13+i*0.00012])},
 {name:'dateline',p:[[179.995,23],[179.999,23.002],[-179.995,23.004],[-179.990,23.006]]},
 {name:'high-latitude',p:[[12,84.5],[12.2,84.52],[12.4,84.49]]},
 {name:'coincident',p:[[120.68,24.13],[120.68,24.13]]}
];
const fitCases=[];
for(const shape of paths)for(const [width,height] of [[390,844],[844,390]])for(const anchored of [false,true]){
 const vp={width,height,edge:12,obstacles:anchored?[{left:0,top:0,right:width,bottom:Math.min(height*.26,205)+Math.min(height*.08,64)+12},{left:width-75,top:height-220,right:width,bottom:height-20}]:[]};
 const opt=options({riderAnchor:anchored,targetAbove:anchored,maxZoom:shape.name==='short'?20:18.85});
 const origin=shape.p[0],destination=shape.p.at(-1),c=Fit.solve(shape.p,origin,destination,vp,opt);
 fitCases.push({name:shape.name+'-'+width+'-'+anchored,path:shape.p.map(point),origin:point(origin),destination:point(destination),viewport:vp,options:opt,expected:nativeCamera(c)});
 if(c&&anchored&&shape.name==='north-turns')for(const bad of [false,true]){
  const next=options({...opt,previousBearing:c.bearing+(bad?180:0),full:false,continuous:true});
  fitCases.push({name:'continuous-'+width+'-'+bad,path:shape.p.map(point),origin:point(origin),destination:point(destination),viewport:vp,options:next,expected:nativeCamera(Fit.solve(shape.p,origin,destination,vp,next))});
 }
}
for(const kind of ['empty-line','full-block','invalid-viewport']){
 const p=paths[0].p,vp={width:kind==='invalid-viewport'?60:390,height:844,edge:12,obstacles:kind==='full-block'?[{left:0,top:0,right:390,bottom:844}]:[]},line=kind==='empty-line'?[]:p,opt=options();
 fitCases.push({name:kind,path:line.map(point),origin:point(p[0]),destination:point(p.at(-1)),viewport:vp,options:opt,expected:nativeCamera(Fit.solve(line,p[0],p.at(-1),vp,opt))});
}
let epoch=200000,mono=1000;
const state={position:null,displayPosition:null,routeProgressIndex:0,routeEnabled:true,navigationRequested:true,navigationActive:true,fitLocked:false,routeManeuvers:[],destination:null,pipView:true,insetCollapsed:true,following:false,displayHeading:NaN,compassHeading:NaN,gpsCourse:NaN,lastOrientationAt:0,lastHeadingSmoothAt:0};
let route=[],size={width:390,height:844},hud=50,card=56;
const ctx=vm.createContext({state,Date:{now:()=>epoch},performance:{now:()=>mono},document:{hidden:true,getElementById:()=>({getBoundingClientRect:()=>({height:card})})},map:{getContainer:()=>({getBoundingClientRect:()=>size})},els:{topHud:{getBoundingClientRect:()=>({height:hud})}},window:{},routeCoordinates:()=>route,STABLE_3D_ZOOM:16.8,STABLE_3D_ARRIVAL_ZOOM:18.15,STABLE_3D_BEARING_DEADZONE:3,STABLE_3D_BEARING_RATE_DPS:58});
for(const name of ['normalizeAngle','normalizeSigned','smoothAngle','haversineMeters','bearingBetween','segmentProjection','progressProjection','nextRouteManeuver','advanceRouteProjection','navigationDisplayPosition','fitPipBottom','navigationViewport','routeForwardBearing','stable3dBearing','stable3dArrivalZoom','updateHeading'])vm.runInContext(extract(name),ctx);
const run=(name,...args)=>{ctx.__args=args;return vm.runInContext(name+'(...__args)',ctx);};
const projectionCases=[];
for(const shape of paths.slice(0,7))for(const cursor of [0,Math.max(0,shape.p.length-5)])for(const offset of [0,0.0004]){
 route=shape.p;state.routeProgressIndex=cursor;const raw={lng:shape.p[0][0]+offset,lat:shape.p[0][1]+.00012},p=run('progressProjection',raw,route),advanced=p?run('advanceRouteProjection',p,route,37):null;
 projectionCases.push({name:shape.name+'-'+cursor+'-'+offset,raw,path:route.map(point),cursor,meters:37,expected:p?{t:p.t,distance:p.distance,index:p.index,coordinate:point(p.coord)}:null,advanced});
}
const leadTraces=[];
for(const initial of [0,8]){
 route=[[120,24],[120,24.001],[120,24.002]];state.routeProgressIndex=0;state.displayLeadMeters=initial;state.destination={lng:120,lat:24.002};
 const steps=[];
 for(const [lat,lng,speed,accuracy,riding,turn] of [[24.0002,120,10,5,true,true],[24.00095,120,10,5,true,true],[24.00196,120,10,5,true,false],[24.0002,120,0,5,true,true],[24.0003,120,10,80,true,true],[24.0003,120.001,10,5,true,true],[24.0002,120,8,35,true,true],[24.0002,120,8,5,false,true],[24.0002,120,8,5,true,true],[24.002,120,8,5,true,false]]){
  state.routeEnabled=riding;state.routeManeuvers=turn?[{type:'turn',modifier:'right',name:'',routeIndex:0,location:[120,24.001]}]:[];
  const raw=Object.freeze({lat,lng,accuracy,speed,ts:epoch});state.position=raw;
  const out=run('navigationDisplayPosition',raw,speed);
  steps.push({raw:{lat,lng},speed,accuracy,riding,cursor:0,destination:state.destination,maneuvers:state.routeManeuvers.map(m=>({...m,location:point(m.location)})),expected:{lat:out.lat,lng:out.lng},leadMeters:state.displayLeadMeters});
 }
 leadTraces.push({initial,path:route.map(point),steps});
}
const viewportCases=[];
for(const [width,height] of [[390,844],[402,874],[844,390],[320,568]])for(const pip of [false,true])for(const collapsed of [false,true]){
 size={width,height};hud=78;card=94;state.pipView=pip;state.insetCollapsed=collapsed;
 const v=run('navigationViewport');viewportCases.push({width,height,pip,hudHeight:hud,collapsedInsetHeight:collapsed?card:56,pipBottom:pip?run('fitPipBottom',height,width):0,expected:{top:v.top,bottom:v.bottom,left:v.left,right:v.right,anchorY:v.anchorY,offsetY:v.offset[1]},arrival:Arrival.padding(v,pip)});
}
const arrivalCases=[];for(const distance of [0,12,199,200,201,249,250,251,349,350,351,499,500,501,549,550,551,599,600,601,799,800,801,1200])for(const previous of [false,true])arrivalCases.push({distance,previous,active:Arrival.active(previous,distance),locked:Arrival.shouldLock(previous,distance),zoom:run('stable3dArrivalZoom',distance)});
const headingTraces=[];
for(const initial of [null,358,180]){
 state.displayHeading=initial===null?NaN:initial;state.lastHeadingSmoothAt=0;const steps=[];
 for(const [value,age,course,elapsed] of [[1,10,170,33],[359,20,180,33],[2,100,180,65],[90,2499,270,100],[90,2501,270,100],[null,0,null,33],[180,10,0,150],[181,0,0,10]]){
  mono+=elapsed;epoch+=elapsed;state.compassHeading=value===null?NaN:value;state.lastOrientationAt=epoch-age;state.gpsCourse=course===null?NaN:course;run('updateHeading');
  steps.push({compass:value===null?null:{value,timestampMS:epoch-age,accuracy:1,source:'native-true-heading'},course,nowMS:epoch,monotonicMS:mono,expected:Number.isFinite(state.displayHeading)?state.displayHeading:null});
 }
 headingTraces.push({initial,steps});
}
const bearingTraces=[];for(const initial of [null,358,180]){let last=initial===null?NaN:initial;const steps=[];for(const [target,elapsed] of [[1,.18],[2,.033],[90,.18],[270,.05],[180,1.5],[359,2],[2,0]]){last=run('stable3dBearing',{points:[]},last,elapsed,target);steps.push({target,elapsed,expected:last});}bearingTraces.push({initial,steps});}
const selection=s=>({fitLocked:!!s.fitLocked,following:!!s.following,cameraUserOverride:!!s.cameraUserOverride,navigationActive:!!s.navigationActive,navigationRequested:!!s.navigationRequested,headingMode:s.mode==='heading',editing:!!s.editing});
const gestureTraces=[];
for(const fit of [false,true]){
 const s={fitLocked:fit,following:!fit,cameraUserOverride:false,navigationActive:!fit,navigationRequested:!fit,mode:'heading',editing:false};let hidden=false,now=0,seq=0,stops=0,resumes=0;const tasks=new Map();
 const c=new Interaction.Controller({getState:()=>s,isHidden:()=>hidden,isEditing:()=>s.editing,stop:()=>stops++,resume:()=>resumes++,setTimer:(f,ms)=>{tasks.set(++seq,{f,at:now+ms});return seq;},clearTimer:id=>tasks.delete(id)});c.selectionChanged();
 const actions=[{op:'begin',id:1,x:150,y:400},{op:'end',id:1},{op:'begin',id:1,x:150,y:400},{op:'begin',id:2,x:240,y:400},{op:'transform'},{op:'move',x:185,y:400},{op:'end',id:1,remaining:1},{op:'end',id:2},{op:'advance',delta:1499},{op:'advance',delta:1},{op:'begin',id:4,x:100,y:100},{op:'move',x:104,y:104},{op:'end',id:4},{op:'begin',id:5,x:100,y:100},{op:'move',x:109,y:100},{op:'lifecycle',foreground:false},{op:'end',id:5,cancelled:true},{op:'lifecycle',foreground:true},{op:'wheel'},{op:'selection',manual:true},{op:'advance',delta:2000},{op:'lifecycle',foreground:true}];
 const steps=[];for(const e of actions){
  if(e.op==='begin')c.begin({type:'pointerdown',pointerId:e.id,clientX:e.x,clientY:e.y});
  if(e.op==='move')c.move({clientX:e.x,clientY:e.y});
  if(e.op==='transform')c.handle({type:'zoomstart',originalEvent:{type:'touchmove',touches:[{},{}]}});
  if(e.op==='end')c.end({type:e.cancelled?'pointercancel':'pointerup',pointerId:e.id,touches:Array(e.remaining||0).fill({})});
  if(e.op==='advance'){now+=e.delta;for(const [id,t] of [...tasks])if(t.at<=now){tasks.delete(id);t.f();}}
  if(e.op==='lifecycle'){hidden=!e.foreground;c.lifecycle(e.foreground);}
  if(e.op==='wheel')c.handle({type:'wheel'});
  if(e.op==='selection'){s.fitLocked=false;s.following=false;s.cameraUserOverride=true;s.navigationActive=false;s.navigationRequested=false;c.selectionChanged();}
  steps.push({action:e,nowMS:now,foreground:!hidden,selection:selection(s),expected:{holding:!!s.cameraGestureHold,fitHolding:!!s.fitGestureHold,active:c.active,moved:c.moved,pointerCount:c.pointers.size,resumes,stops,resumeAtMS:tasks.size?[...tasks.values()][0].at:null}});
 }
 gestureTraces.push({initial:selection({fitLocked:fit,following:!fit,cameraUserOverride:false,navigationActive:!fit,navigationRequested:!fit,mode:'heading',editing:false}),steps});
}
const out={schema:1,sourceHashes,fitCases,projectionCases,leadTraces,viewportCases,arrivalCases,headingTraces,bearingTraces,gestureTraces,scope:'NEW_S3_GOLDEN_ORACLE_NO_RUNTIME_JS_NO_NETWORK_NO_OLD_SUITE_RERUN'};
const file=path.join(root,'NativeCoreTests/NativeCoreFixtures/camera-golden.json');fs.writeFileSync(file,JSON.stringify(out)+'\n');
const receipt={status:'S3_GOLDEN_CREATED',at:new Date().toISOString(),sourceHashes,fixtureSHA256:sha(fs.readFileSync(file)),fitCases:fitCases.length,fitNonNil:fitCases.filter(x=>x.expected).length,projectionCases:projectionCases.length,leadSteps:leadTraces.reduce((n,t)=>n+t.steps.length,0),viewportCases:viewportCases.length,arrivalCases:arrivalCases.length,headingSteps:headingTraces.reduce((n,t)=>n+t.steps.length,0),bearingSteps:bearingTraces.reduce((n,t)=>n+t.steps.length,0),gestureSteps:gestureTraces.reduce((n,t)=>n+t.steps.length,0),newIPA:false};
fs.writeFileSync(path.join(root,'docs/native-port/S3_GOLDEN_RESULT.json'),JSON.stringify(receipt,null,2)+'\n');console.log(JSON.stringify(receipt));
