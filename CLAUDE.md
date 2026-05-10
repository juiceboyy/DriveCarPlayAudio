# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Drive CarPlay Audio is a UIKit/CarPlay iOS app (minimum iOS 16.0) that lets users browse and stream audio files from Google Drive via a CarPlay interface. There is no SPM/CocoaPods dependency — all source files are plain Swift using only Apple frameworks.

## Build & run

This repo contains only source files; **there is no `.xcodeproj` in the repo**. The Xcode project must be created manually (see `SETUP.md`). Once created, use Xcode or:

```bash
# Build for simulator (replace scheme/destination as needed)
xcodebuild -scheme DriveCarPlayAudio -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests (none currently exist)
xcodebuild -scheme DriveCarPlayAudio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

To test CarPlay in the simulator: run the app, then **I/O > External Displays > CarPlay** in the Simulator menu bar.

## Required configuration before building

Fill in real credentials in [Sources/Services/GoogleAuthService.swift](Sources/Services/GoogleAuthService.swift) before the app can authenticate:

```swift
enum GoogleOAuthConfig {
    static let bundleID     = "com.yourname.drivecarplayaudio"  // must match Info.plist URL scheme
    static let clientID     = "YOUR_CLIENT_ID.apps.googleusercontent.com"
    static let clientSecret = "YOUR_CLIENT_SECRET"
}
```

The bundle ID must also match the `CFBundleURLSchemes` entry in [Resources/Info.plist](Resources/Info.plist).

## Architecture

The app runs two simultaneous UIKit scenes routed in [Sources/App/AppDelegate.swift](Sources/App/AppDelegate.swift):

- **iPhone scene** → `SceneDelegate` → `MainViewController` (sign-in/sign-out UI only)
- **CarPlay scene** → `CarPlaySceneDelegate` → `CarPlayTemplateManager` (all playback UI)

All three service singletons are shared between scenes:

| Service | Responsibility |
|---|---|
| `GoogleAuthService.shared` | OAuth 2.0 PKCE flow via `ASWebAuthenticationSession`; stores tokens in Keychain with auto-refresh 60 s before expiry |
| `GoogleDriveService.shared` | Drive API v3 file listing and streaming URL construction; `fetchWithRetry` with exponential backoff (1s/2s/4s); retries on 429/5xx, never on 401 |
| `AudioPlayerService.shared` | `AVPlayer` queue management; `MPRemoteCommandCenter` for lock screen / CarPlay controls; streams audio directly from Drive via HTTP Authorization header |

**Auth → Drive → CarPlay data flow:**
1. User taps "Sign in" in `MainViewController` → `GoogleAuthService.authenticate()` → tokens stored in Keychain
2. `CarPlayTemplateManager.connect()` fires on CarPlay connect → calls `GoogleDriveService.listFiles(inFolder: "root")`
3. Drive API returns `[DriveFile]`; `DriveFile.isFolder` and `DriveFile.isAudio` gate which items render as navigation vs. playback items
4. Tapping an audio item calls `AudioPlayerService.play(file:fromQueue:)` → constructs an `AVURLAsset` with a Bearer token header
5. When the token expires mid-session, `DriveError.unauthorized` posts `.driveAuthRequired` → `MainViewController` re-triggers sign-in

**Notification bus:** `.driveAuthRequired` (`Notification.Name` defined in `CarPlayTemplateManager.swift`) is the only cross-layer signal.

## Key constraints

- **CarPlay audio entitlement** (`com.apple.developer.carplay-audio`) in [DriveCarPlayAudio.entitlements](DriveCarPlayAudio.entitlements) requires explicit Apple approval for App Store distribution; simulator testing works without it.
- Audio is streamed via `AVURLAsset` with `AVURLAssetHTTPHeaderFieldsKey` — no local caching. The token is fetched fresh per `loadAndPlay` call.
- `GoogleAuthService` implements `ASWebAuthenticationPresentationContextProviding` by finding the key window at call time; this must be called on the main thread.
- UI strings are in Dutch (the app's working language).
