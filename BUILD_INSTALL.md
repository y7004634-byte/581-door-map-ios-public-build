# 581 Door Map Native iOS Hybrid — Build / Install

## Baseline
- Web authority: https://rider-door-map-canary.pages.dev
- Baseline verified at scaffold start: v0.3.78 / truthful-generic-search-pins
- Web source remains read-only for this workstream.
- Native shell source: F:\581\door-map-ios-native
- Phase 1 content mode: remote live WKWebView.
- Existing Safari/PWA deployment is not replaced or modified.

## Architecture
UIKit App -> WKWebView -> current Door Map live site.
The shell adds native lifecycle, Core Location permission/bridge, motion permission handling,
custom URL ingress, persistent WKWebsiteDataStore, and a future bundled-assets loading path.

## Primary no-Mac build path
Owning a Mac is not required. The checked-in GitHub Actions workflow runs on `xcode-27`.

1. Push this repo's `main` branch to a private GitHub repository.
2. Push automatically triggers `.github/workflows/ios-cloud-build.yml`.
3. The job installs XcodeGen, generates the Xcode project, runs simulator tests (or build-for-testing fallback), and builds a generic iPhoneOS app with code signing disabled.
4. The job publishes `DoorMap581-unsigned.ipa` plus build log/result as an Actions artifact.

The checked-in `project.yml` is the Xcode project source of truth.

## Windows sign / install
No App Store submission is required.
Use 3uTools on this Windows PC: Toolbox -> IPA Signature -> add `DoorMap581-unsigned.ipa` -> Sign with Apple ID -> choose the connected iPhone 16 UDID -> Start Signing -> install the signed IPA.

A free Apple ID signature normally needs periodic re-signing; a paid developer certificate lasts longer. Keep the same bundle ID when replacing the existing test install.

## Optional local-Mac path
If a real Mac becomes available later, `scripts/mac-build-verify.sh` remains available for local Xcode compile/test. It is optional, not a project blocker.

## Deep-link ingress
Supported native URL examples:

    door581://open?lat=24.1371000&lng=120.6684910
    door581://open?dest=24.1371000,120.6684910
    door581://open?gmap=<percent-encoded Google Maps share URL>

The router also accepts a direct Google Maps share URL when iOS later delivers one through
NSUserActivity / universal-link style ingress. The Web side was verified to consume dest and gmap.

## Runtime expectations
- WKWebsiteDataStore.default is used so cookies/localStorage/IndexedDB survive normal app relaunches.
- Foreground, inactive, background and return-to-foreground states are bridged to JavaScript.
- Current Web geolocation remains navigator.geolocation; the native Core Location bridge is additive,
  so the wrapper does not rewrite the Safari/PWA GPS logic before real-device evidence requires it.
- Motion/orientation permission prompts only for the trusted Door Map origin (or bundled-file origin); untrusted origins are denied.
- ATS arbitrary loads remain disabled; current active Web endpoints are HTTPS.
- viewport-fit=cover is already present in the current Web build.

## Bundled-assets mode
The code contains a bundledAssets mode and loadFileURL path, but Phase 1 intentionally stays on
remoteLive so an older bundled snapshot cannot overwrite the current live feature set.
Do not switch to bundledAssets until the Web snapshot is copied from the current accepted source
and its asset graph is verified under WKWebView file loading.
