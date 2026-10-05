const {chromium}=require('C:/Users/cxz30/AppData/Local/npm-cache/_npx/420ff84f11983ee5/node_modules/playwright');
const fs=require('node:fs'),path=require('node:path'),{pathToFileURL}=require('node:url'),assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({channel:'msedge',headless:true});
 const report={scope:'Real NLSC WK content in desktop browser; native UI checked separately in Xcode',checks:[],tileResponses:[],errors:[]};
 try {
  const page=await browser.newPage({viewport:{width:390,height:440},deviceScaleFactor:2});
  await page.addInitScript(()=>{window.__messages=[];window.webkit={messageHandlers:{nlscMini:{postMessage:x=>window.__messages.push(x)}}};});
  page.on('pageerror',e=>report.errors.push(String(e)));
  page.on('response',r=>{if(r.url().startsWith('https://wmts.nlsc.gov.tw/'))report.tileResponses.push({status:r.status(),contentType:r.headers()['content-type']});});
  await page.goto(pathToFileURL(path.resolve('DoorMap581/MiniMap/nlsc-map.html')).href);
  await page.waitForFunction(()=>window.__messages.some(x=>x.type==='ready'),{},{timeout:30000});
  await page.evaluate(()=>{NLSCMini.begin({center:[120.6736,24.1477],metersPerPoint:0.55,bearing:27,heading:40,
   rider:[120.6736,24.1477],place:{name:'MUST NOT CROSS'},applePOIs:[{name:'MUST NOT CROSS'}]},'session-1');NLSCMini.allowCorrection(true);});
  const start=await page.evaluate(()=>NLSCMini.diagnostics());
  assert.deepEqual(start.sourceIds,['nlsc']);assert.deepEqual(start.layerIds,['nlsc']);assert(start.editing);
  report.checks.push('Only the NLSC raster and device marker are displayed');
  await page.click('#plus');await page.waitForFunction(z=>NLSCMini.diagnostics().zoom>z,start.zoom);
  await page.evaluate(()=>NLSCMini.theme(false));assert.equal(await page.locator('html').getAttribute('data-theme'),'light');
  await page.evaluate(()=>NLSCMini.theme(true));report.checks.push('Zoom and theme chrome work without recoloring NLSC labels');
  await page.mouse.move(170,180);await page.mouse.down();await page.mouse.move(260,235,{steps:12});await page.mouse.up();
  await page.waitForFunction(c=>Math.abs(NLSCMini.diagnostics().center.lng-c.lng)>1e-5,start.center);
  const draft=await page.evaluate(()=>NLSCMini.diagnostics().center);
  await page.evaluate(()=>NLSCMini.receive({center:[121,25],metersPerPoint:1,bearing:0,heading:0}));
  const retained=await page.evaluate(()=>NLSCMini.diagnostics().center);
  assert(Math.abs(retained.lng-draft.lng)<1e-7);assert(Math.abs(retained.lat-draft.lat)<1e-7);
  assert.equal(await page.evaluate(()=>window.__messages.filter(x=>x.type==='correct').length),0);
  await page.click('#apply');const applied=await page.evaluate(()=>window.__messages.filter(x=>x.type==='correct').at(-1));
  assert.equal(applied.session,'session-1');assert.deepEqual(Object.keys(applied).sort(),['center','session','type']);
  report.checks.push('Drag stays local despite main updates; only explicit confirmation sends a correction and session');
  await page.evaluate(()=>NLSCMini.end());await page.click('#apply');
  assert.equal(await page.evaluate(()=>window.__messages.filter(x=>x.type==='correct').length),1);
  await page.evaluate(()=>NLSCMini.begin({center:[120.6736,24.1477],metersPerPoint:0.55,bearing:27,heading:40},'session-2'));
  const reopened=await page.evaluate(()=>NLSCMini.diagnostics());assert.equal(reopened.session,'session-2');
  assert(Math.abs(reopened.center.lng-start.center.lng)<1e-7);
  report.checks.push('Closing rejects confirmation and reopening discards the previous draft');
  assert(!(await page.locator('body').innerText()).includes('MUST NOT CROSS'));
  report.checks.push('Apple place data is absent from the NLSC DOM');
  await page.waitForTimeout(1200);await page.screenshot({path:'docs/nlsc-minimap-browser.png'});
  report.liveTilesLoaded=report.tileResponses.some(x=>x.status===200&&/image/.test(x.contentType||''));
  report.status=report.errors.length===0&&report.liveTilesLoaded?'PASS':'PARTIAL';report.diagnostics=reopened;
 }catch(e){report.status='FAIL';report.failure=String(e);process.exitCode=1;}
 finally{await browser.close();fs.writeFileSync('docs/minimap-browser-result.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));}
})();
