// Windows-capable checks: execute the actual embedded JS; inspect Swift wiring.
// This script does NOT compile Swift, execute XCTest, or query Apple services.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
process.chdir(path.join(__dirname, '..'));
const read = file => fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
const bridge = read('DoorMap581/NativeBridge.swift');
const apple = read('DoorMap581/AppleSearchBridge.swift');
function embedded(name) {
  const body = bridge.slice(bridge.indexOf(`static var ${name}:`));
  const match = body.match(/let source = """\n([\s\S]*?)\n        """/);
  assert(match, name);
  return match[1].split('\n').map(line => line.replace(/^ {8}/, '')).join('\n');
}
const bootstrap = embedded('bootstrapScript');
const ready = embedded('readyScript');
const point = {lat:24.135, lng:120.688};
function harness({postError = false} = {}) {
  const posts = [], timers = new Map(), events = [];
  let timerID = 0;
  const window = {webkit:{messageHandlers:{doorMapNative:{postMessage(message) {
    if (postError) throw Error('post unavailable');
    posts.push(message);
  }}}}, dispatchEvent:event => events.push(event)};
  const context = vm.createContext({window, Date, Map, Promise, Number, Error,
    CustomEvent:class {constructor(type, init) {this.type=type;this.detail=init.detail;}},
    setTimeout(fn, ms) {timers.set(++timerID, {fn, ms});return timerID;},
    clearTimeout(id) {timers.delete(id);}
  });
  vm.runInContext(bootstrap, context);
  const settle = (message, payload = {}, ok = true) => window.Door581Native._resolve(message.payload.requestID, ok, payload);
  return {api:window.Door581Native, posts, timers, events, context, settle};
}
let passed = 0;
async function test(name, run) {await run();passed++;console.log('PASS', name);}
(async () => {
  await test('actual bootstrap exposes a frozen reverseApple API and survives repeated injection', () => {
    const h = harness();assert.equal(typeof h.api.reverseApple, 'function');assert(Object.isFrozen(h.api));
    vm.runInContext(bootstrap, h.context);assert.equal(h.context.window.Door581Native, h.api);
  });
  await test('bootstrap rejects missing, nonnumeric, nonfinite and out-of-region coordinates without posting', async () => {
    const h = harness();
    for (const p of [null, {}, {lat:'24',lng:120}, {lat:NaN,lng:120}, {lat:24,lng:Infinity},
      {lat:19.99,lng:120}, {lat:27.01,lng:120}, {lat:24,lng:116.99}, {lat:24,lng:123.01}]) {
      await assert.rejects(h.api.reverseApple(p), /Invalid Apple reverse coordinate/);
    }
    assert.equal(h.posts.length, 0);assert.equal(h.timers.size, 0);
  });
  await test('bootstrap copies the point, defaults radius and clamps radius to 20 through 100 metres', async () => {
    const h = harness();
    for (const [radius, want] of [[undefined,50],[-5,20],[20,20],[50,50],[100,100],[9999,100],[NaN,50],[Infinity,50],['90',50]]) {
      const input = {...point};const pending = h.api.reverseApple(input, radius);input.lat = 0;
      const message = h.posts.at(-1);assert.equal(message.type, 'appleReverse');
      assert.equal(message.payload.point.lat, point.lat);assert.equal(message.payload.point.lng, point.lng);
      assert.equal(message.payload.radiusM, want);assert.equal([...h.timers.values()][0].ms, 12000);
      h.settle(message, {address:null,pois:[]});await pending;assert.equal(h.timers.size, 0);
    }
    for (const p of [{lat:20,lng:117},{lat:27,lng:123}]) {const pending=h.api.reverseApple(p);h.settle(h.posts.at(-1));await pending;}
  });
  await test('concurrent calls route out-of-order replies by request ID and ignore duplicates', async () => {
    const h=harness(), first=h.api.reverseApple(point), second=h.api.reverseApple(point);
    assert.notEqual(h.posts[0].payload.requestID,h.posts[1].payload.requestID);
    h.settle(h.posts[1],{house:'134'});h.settle(h.posts[0],{house:'126'});h.settle(h.posts[0],{house:'stale'});
    assert.equal((await second).house,'134');assert.equal((await first).house,'126');assert.equal(h.timers.size,0);
  });
  await test('native rejection and timeout settle once and clean up timers', async () => {
    const h=harness();let pending=h.api.reverseApple(point), check=assert.rejects(pending,/cancelled/);
    h.settle(h.posts.at(-1),{message:'cancelled'},false);await check;assert.equal(h.timers.size,0);
    pending=h.api.reverseApple(point);check=assert.rejects(pending,/Native request timeout/);
    const [id,timer]=[...h.timers][0];h.timers.delete(id);timer.fn();await check;
    h.settle(h.posts.at(-1),{house:'late'});assert.equal(h.timers.size,0);
  });
  await test('synchronous WebKit post failure rejects and releases its timer', async () => {
    const h=harness({postError:true});await assert.rejects(h.api.reverseApple(point),/post unavailable/);assert.equal(h.timers.size,0);
  });
  await test('ordinary search signature, defaults, payload and non-reverse timeout behavior are preserved', async () => {
    const h=harness(), pending=h.api.searchApple('test');const message=h.posts[0];
    assert.equal(message.type,'appleSearch');assert.equal(message.payload.query,'test');
    assert.equal(message.payload.center,null);assert.equal(message.payload.radiusM,3000);assert.equal(h.timers.size,0);
    h.settle(message,{results:[]});assert.deepEqual((await pending).results,[]);
  });
  await test('reverse transports address independently of empty, failed, same-house or conflicting diagnostic POIs', async () => {
    for(const pois of [[],[{displayName:'Wu tea',houseNumber:'134'}],[{displayName:'Bank',houseNumber:'126'}]]) {
      const h=harness(),pending=h.api.reverseApple(point),address={houseNumber:'134',road:'Fixture road'};
      const payload={source:'apple-reverse',point,address,pois,errors:pois.length?{}:{pois:'timeout'}};
      h.settle(h.posts[0],payload);const result=await pending;
      assert.deepEqual(result.address,address);assert.deepEqual(result.pois,pois);assert.equal(result.placeName,undefined);
      assert.equal(result.applePlaceLocked,undefined);assert.equal(h.timers.size,0);
    }
  });
  await test('ready event, bootstrap, UA and plist consistently identify wrapper 0.3.2/build10', () => {
    const h=harness();vm.runInContext(ready,h.context);assert.equal(h.api.shell,'0.3.2');
    assert.equal(h.events[0].detail.shell,'0.3.2');assert.equal(h.posts[0].payload.shell,'0.3.2');
    assert.match(read('DoorMap581/Info.plist'),/CFBundleShortVersionString<\/key>\s*<string>0\.3\.2<\/string>/);
    assert.match(read('DoorMap581/Info.plist'),/CFBundleVersion<\/key>\s*<string>10<\/string>/);
    assert(read('DoorMap581/AppConfig.swift').includes('DoorMap581Native/0.3.2'));
  });
  await test('Swift static contract validates finite point, bounds/clamp, missing delegate and rejection dispatch', () => {
    for (const expected of ['latitude.isFinite, longitude.isFinite','(20...27).contains(latitude)',
      '(117...123).contains(longitude)','min(100, max(20, radiusM))','let latitude = point["lat"] as? Double',
      'let longitude = point["lng"] as? Double','handle(type: type, payload: payload)',
      'payload: ["message": message]','webView?.evaluateJavaScript(script)']) assert(bridge.includes(expected),expected);
    const handler=bridge.slice(bridge.indexOf('case "appleReverse":'),bridge.indexOf('case "openExternal":'));
    for (const expected of ['!requestID.isEmpty','AppleReversePoint(payload: payload)',
      'reject(requestID, "Invalid Apple reverse coordinate")','guard let delegate else',
      'reject(requestID, "Apple reverse unavailable")',
      'delegate.reverseApple(requestID: requestID, latitude: point.latitude, longitude: point.longitude, radiusM: point.radiusM)']) assert(handler.includes(expected),expected);
  });
  await test('Swift static reverse path keeps search independent, guards late callbacks and preserves partial results', () => {
    for (const expected of ['private var activeReverse: ReverseRequest?','cancelReverse()',
      'MKLocalPointsOfInterestRequest(center: location.coordinate, radius: point.radiusM)',
      'preferredLocale: Locale(identifier: "zh_TW")','self.activeReverse === pending',
      'guard activeReverse === pending else { return }','DispatchQueue.main.async',
      'pending.result.errors["address"]','pending.result.errors["pois"]',
      'address.map { $0 as Any } ?? NSNull()','JSONSerialization']) {
      assert((apple+bridge).includes(expected),expected);
    }
    const search=apple.slice(apple.indexOf('    func search('),apple.indexOf('    private func resolve('));
    assert(search.includes('activeSearch?.cancel()'));assert(!search.includes('cancelReverse'));
    const finish=apple.slice(apple.indexOf('private func finishReverse'),apple.indexOf('static func addressPayload'));
    assert(finish.indexOf('activeReverse = nil')<finish.indexOf('pending.cancel()'));
    const cancel=apple.slice(apple.indexOf('private func cancelReverse'),apple.indexOf('/// Destination-only'));
    assert(cancel.indexOf('activeReverse = nil')<cancel.indexOf('previous.cancel()'));
    assert(cancel.includes('resolve(requestID: previous.requestID, ok: false'));
  });
  await test('original web controller remains scene root, and both controllers forward reverse requests', () => {
    const scene=read('DoorMap581/SceneDelegate.swift');assert(scene.includes('DoorMapViewController(initialDeepLink: launchURL)'));
    assert(!scene.includes('RestoredAppleMapViewController'));assert(!scene.includes('NativePortViewController'));
    for(const file of ['DoorMap581/DoorMapViewController.swift','DoorMap581/RestoredAppleMapViewController.swift']) {
      const s=read(file).replace(/\s+/g,'');assert(s.includes('funcreverseApple(requestID:String,latitude:Double,longitude:Double,radiusM:Double)'));
      assert(s.includes('appleSearchBridge.reverse(requestID:requestID,latitude:latitude,longitude:longitude,radiusM:radiusM)'));
    }
    assert(read('DoorMap581/AppConfig.swift').includes('static let contentMode: ContentMode = .remoteLive'));
    assert(read('project.yml').includes('PRODUCT_BUNDLE_IDENTIFIER: com.door581.appletest'));
    assert(read('project.yml').includes('iOS: "16.0"'));
    assert(read('project.yml').includes('- path: DoorMap581Tests'));
  });
  await test('point probe uses current MapKit reverse and address fields with a guarded macOS requirement', () => {
    const probe=read('scripts/apple-point-probe.swift');
    for(const expected of ['MKReverseGeocodingRequest(location: location)','request.preferredLocale = Locale(identifier: "zh_TW")',
      'try await request.mapItems','item.address?.fullAddress','item.location.coordinate',
      'guard #available(macOS 26.0, *)','addressRequest.resultTypes = .address']) assert(probe.includes(expected),expected);
    assert(!probe.includes('CLGeocoder('));assert(!probe.includes('.placemark'));
  });
  await test('probe verdict depends only on precise address search and its reverse, never diagnostic shop availability', () => {
    const probe=read('scripts/apple-point-probe.swift');
    assert.match(probe,/let selectedAddress = addressSearch\.items\.first\(where: isPrecise134\)/);
    assert.match(probe,/reverseAddress = await reverse\(selectedAddress\)/);
    assert.match(probe,/let addressSearchPassed = selectedAddress != nil/);
    assert.match(probe,/let reverseAddressPassed = reverseAddress\.items\.contains\(where: isPrecise134\)/);
    assert.match(probe,/let passed = addressSearchPassed && reverseAddressPassed\n/);
    assert.match(probe,/exit\(report\.passed \? 0 : 1\)/);
    assert(probe.includes('directShopDiagnostic: directShopDiagnostic, nearbyPOIDiagnostic: nearbyPOIDiagnostic'));
    assert(probe.includes('return PointProbeLookup(items: [], error: error.localizedDescription)'));
  });
  await test('probe exact-address regex accepts precise134 spellings and rejects126, base/sub-number and road contamination', () => {
    // Execute the literal regex from Swift with equivalent fixture normalization.
    // This checks the pattern, not Swift/Foundation compilation or Apple results.
    const probe=read('scripts/apple-point-probe.swift');
    const pattern=probe.match(/let exact = #"([^\n]+)"#/);assert(pattern);
    const matches=value=>new RegExp(pattern[1],'u').test(value.normalize('NFKC').replace(/\s+/g,''));
    for(const value of ['台中市中華路一段134號','中華路1段１３４號','中華路 一 段 134 号']) assert(matches(value),value);
    for(const value of ['中華路一段126號','中華路一段1134號','中華路一段134之1號','中華路一段134-1號',
      '中華路一段134號之1','中華路一段134號-1','中華路一段134號/1','中華路二段134號','中山路一段134號','吳家紅茶冰']) assert(!matches(value),value);
    const matcher=probe.slice(probe.indexOf('static func isPrecise134'),probe.indexOf('static func record'));
    assert(!matcher.includes('item.name'));assert(matcher.includes('item.latitude.isFinite'));
    assert(matcher.includes('(20...27).contains(item.latitude)'));assert(matcher.includes('(117...123).contains(item.longitude)'));
  });
  console.log(JSON.stringify({suite:'apple-reverse-bridge',passed,failed:0,
    proof:'Embedded JS runtime and Swift source contracts only; Apple SDK compile/XCTest/network NOT RUN'}));
})().catch(error => {console.error(error);process.exitCode=1;});
