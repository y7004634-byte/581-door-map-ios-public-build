param([string]$WebCandidate = (Join-Path $PSScriptRoot '..\..\door-map-apple-pin-truth\public'))
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'DoorMap581'
$failures = [System.Collections.Generic.List[string]]::new()
function Check([bool]$ok, [string]$message) {
  if ($ok) { Write-Output "PASS $message" }
  else { Write-Output "FAIL $message"; $failures.Add($message) }
}
function Raw([string]$path) { [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) }
function Has([string]$path, [string]$needle) { return (Raw $path).Contains($needle) }

$plistPath = Join-Path $src 'Info.plist'
try {
  [xml]$null = Raw $plistPath
  Check $true 'Info.plist XML parses'
} catch {
  Check $false ('Info.plist XML parses: ' + $_.Exception.Message)
}
$plistRaw = Raw $plistPath
Check ($plistRaw.Contains('<string>door581-apple-test</string>')) 'isolated Apple test URL scheme registered'
Check (-not ($plistRaw.Contains('<string>waze</string>'))) 'Apple test wrapper does not claim production Waze URL scheme'
Check ($plistRaw.Contains('NSLocationWhenInUseUsageDescription')) 'location permission description present'
Check ($plistRaw.Contains('NSMotionUsageDescription')) 'motion permission description present'
Check ($plistRaw.Contains('UIApplicationSceneManifest')) 'scene lifecycle manifest present'
Check ($plistRaw.Contains('CFBundleInfoDictionaryVersion')) 'standard bundle metadata present'
Check ($plistRaw.Contains('LSRequiresIPhoneOS')) 'iPhone OS requirement declared'
Check ($plistRaw -match '<key>NSAllowsArbitraryLoads</key>\s*<false\s*/>') 'ATS arbitrary loads explicitly disabled'

$vc = Join-Path $src 'DoorMapViewController.swift'
$loc = Join-Path $src 'LocationBridge.swift'
$bridge = Join-Path $src 'NativeBridge.swift'
$apple = Join-Path $src 'AppleSearchBridge.swift'
$router = Join-Path $src 'DeepLinkRouter.swift'
$project = Join-Path $root 'project.yml'

Check (Has $vc 'WKWebViewConfiguration') 'WKWebView container configured'
Check (Has $vc 'loadFileURL') 'bundled file loading path present'
Check (Has $vc 'webViewWebContentProcessDidTerminate') 'WKWebView process termination recovery present'
Check (Has $vc 'navigationAction.shouldPerformDownload') 'HTML download actions become WKDownload'
Check (Has $vc 'WKDownloadDelegate') 'WKDownload delegate preserves Web export flow'
Check (Has $vc 'UIActivityViewController') 'completed Web downloads hand off to iOS share sheet'
Check (Has $vc "door581:nativeLifecycle") 'native lifecycle event bridge present'
Check (Has $vc 'requestDeviceOrientationAndMotionPermissionFor') 'WKWebView motion permission delegate present'
Check (Has $vc 'decisionHandler(.deny)') 'native shell never prompts WebKit motion/orientation permission'
Check (Has $bridge 'WKScriptMessageHandler') 'JavaScript to Swift message bridge present'
Check (Has $bridge 'searchApple') 'native bridge exposes Apple search'
Check (Has $bridge 'startLocation') 'native bridge exposes continuous location stream'
Check (Has $apple 'MKLocalSearch') 'Apple MKLocalSearch bridge present'
Check (Has $loc 'requestWhenInUseAuthorization') 'native location permission flow present'
Check (Has $loc 'manager.startUpdatingHeading()') 'foreground native heading stream present'
Check (Has $loc 'manager.startUpdatingLocation()') 'native continuous GPS stream present'
Check (-not (Has $loc 'CoreMotion')) 'no always-on CoreMotion loop added'
Check (Has $loc 'pendingOneShot') 'first authorization request resumes pending location'
Check (-not (Has $vc 'locationBridge.preparePermission()')) 'native shell does not race Web geolocation on launch'
Check (Has $router 'URLQueryItem(name: "dest"') 'destination deep-link mapping present'
Check (Has $router 'URLQueryItem(name: "gmap"') 'Google share deep-link mapping present'
Check (Has $router 'scheme == "waze"') 'Uber Waze scheme handled directly'
Check (Has $router '$0.name.lowercased() == "ll"') 'Uber Waze ll coordinate parsed directly'
Check (-not (Has $router 'Dictionary(uniqueKeysWithValues:')) 'duplicate deep-link query keys cannot trap dictionary construction'
Check (Has $project 'excludes:') 'Info.plist excluded from source copy phase'
Check (Has $project 'SWIFT_VERSION: "5.0"') 'Swift language mode is Xcode-compatible'
Check (Has $project 'PRODUCT_MODULE_NAME: DoorMap581') 'Swift module name is stable for @testable import'
Check (Has $project 'PRODUCT_BUNDLE_IDENTIFIER: com.door581.appletest') 'isolated Apple test bundle identity preserved'
Check (Has $project 'ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon') 'native AppIcon catalog configured'
Check ((Test-Path (Join-Path $src 'Assets.xcassets\AppIcon.appiconset\Contents.json'))) 'AppIcon asset catalog present'
Check ($plistRaw -match '<key>CFBundleShortVersionString</key>\s*<string>0\.3\.2</string>') 'wrapper marketing version is 0.3.2'
Check ($plistRaw -match '<key>CFBundleVersion</key>\s*<string>10</string>') 'wrapper build is 10'
Check (Has $project 'DoorMap581Tests:') 'unit-test target declared'
Check (Has $bridge 'injectionTime: .atDocumentEnd') 'native-ready handshake runs after document load'

@(Get-ChildItem $src -Filter '*.swift') + @(Get-ChildItem (Join-Path $root 'DoorMap581Tests') -Filter '*.swift') | ForEach-Object {
  $raw = Raw $_.FullName
  $open = ([regex]::Matches($raw, '\{')).Count
  $close = ([regex]::Matches($raw, '\}')).Count
  Check ($open -eq $close) ($_.Name + ' brace count balanced')
  Check ($raw.TrimEnd().EndsWith('}')) ($_.Name + ' ends at a closed declaration')
}

$candidate = $WebCandidate
$doorMap = Join-Path $candidate 'door-map.js'
$index = Join-Path $candidate 'index.html'
$releasePath = Join-Path $candidate 'release.json'
Check (Has $doorMap "q.get('dest')") 'current Web accepts dest query'
Check (Has $doorMap "q.get('gmap')") 'current Web accepts gmap query'
Check (Has $doorMap 'nativeAppleSearch') 'current Web can merge native Apple search'
Check (Has $doorMap 'door581:nativeHeading') 'current Web consumes native heading events'
Check (Has $doorMap 'door581:nativeLocation') 'current Web consumes native location events'
Check (Has $doorMap 'Locate/recenter is GPS-only') 'locate button no longer requests orientation permission'
Check (Has $index 'viewport-fit=cover') 'current Web declares safe-area viewport'
try {
  $release = Raw $releasePath | ConvertFrom-Json
  Check ([bool]$release.version) ('candidate release readable: ' + $release.version)
} catch {
  Check $false ('candidate release readable: ' + $_.Exception.Message)
}

if ($failures.Count -gt 0) {
  Write-Output ('RESULT FAIL count=' + $failures.Count)
  exit 1
}
Write-Output 'RESULT PASS'
exit 0
