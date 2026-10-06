# 581 Door Map Native iOS — iPhone Acceptance

Target device: iPhone 16 / iOS 27
App phase: Hybrid Native (UIKit + WKWebView), personal install, no App Store.
Record PASS/FAIL plus evidence for every item. Do not promote on partial success.

## Build identity
- Native source manifest SHA256:
- Xcode version:
- Build configuration:
- Bundle identifier:
- Signing team:
- Installed app version/build:
- Loaded Door Map release.json version/build:

## Core acceptance
1. INSTALL — app installs and launches on the physical iPhone 16.
2. OPEN — WKWebView loads current 581 Door Map, not an older bundled copy.
3. GPS — first position fix succeeds; rider marker updates; watchPosition continues.
4. DESTINATION — manual/coordinate destination enters normally.
5. DEEP LINK — door581:// lat/lng and Google Maps share URL both reach the existing Web intake.

6. ROUTE — 581 routing returns a route and the blue navigation line renders.
7. VISUAL REGRESSION — HUD, official house numbers, community/building judgement,
   NLSC close layer and 3D all remain functional inside WKWebView.
8. LIFECYCLE — background the app, return to foreground, and confirm map/GPS/UI recover
   without a duplicate shell, blank page, or corrupted route state.
9. RELAUNCH STATE — close/reopen the app and confirm persistent Web data/settings are intact;
   normal startup must not wipe localStorage/IndexedDB.
10. WEB/PWA SAFETY — open the existing Safari/PWA Door Map separately and confirm it still works.
11. BACKUP EXPORT/IMPORT — export the current personal backup; if Web Share is unavailable, verify the WKDownload fallback opens the iOS share sheet. Then re-import a known-safe backup and confirm the existing Web restore flow still works.

## Focused sensor checks
- Motion/orientation permission is requested only from the trusted Door Map content.
- Compass permission remains gesture-driven after GPS, matching existing Web sequencing.
- Native Core Location bridge does not race navigator.geolocation during launch.
- If WebKit content process terminates, record whether recovery returns to the current live page.

## Evidence
For failures record: exact step, visible symptom, loaded release version, app lifecycle state,
network state, screenshot/video if useful, and whether Safari/PWA shows the same symptom.
Do not fix a native-only failure by changing the Web/PWA source unless evidence proves the Web is the root cause.
