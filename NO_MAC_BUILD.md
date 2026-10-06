# No-Mac Build Path

The project does not require the user to own a Mac.

## Compile
GitHub Actions workflow: `.github/workflows/ios-cloud-build.yml`.
Runner: `xcode-27` (GitHub-hosted macOS/Xcode environment on Apple hardware).
The job generates the Xcode project, runs simulator tests, builds for generic iPhoneOS with signing disabled,
and packages `cloud-build/DoorMap581-unsigned.ipa` as a downloadable artifact.

## Sign / install on this Windows PC
Use the already-installed 3uTools -> Toolbox -> IPA Signature.
Add `DoorMap581-unsigned.ipa`, choose Sign with Apple ID, select the connected iPhone 16 UDID, sign, then install.
Free Apple ID signing normally expires after 7 days; re-signing with the same Apple ID can replace the app.

No App Store submission is involved.
No macOS VM on non-Apple PC is required.
