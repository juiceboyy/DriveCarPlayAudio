# Drive CarPlay Audio — Setup Guide

## 1. Google Cloud Console

1. Ga naar console.cloud.google.com → maak een nieuw project.
2. Activeer **Google Drive API**.
3. Maak een OAuth 2.0 credential aan:
   - Type: **iOS**
   - Bundle ID: `com.yourname.drivecarplayaudio` (aanpassen)
   - Kopieer **Client ID** en **Client Secret**.
4. Vul deze in in `Sources/Services/GoogleAuthService.swift`:
   ```swift
   enum GoogleOAuthConfig {
       static let bundleID     = "com.yourname.drivecarplayaudio"
       static let clientID     = "<jouw client ID>.apps.googleusercontent.com"
       static let clientSecret = "<jouw client secret>"
   }
   ```

## 2. Xcode Project aanmaken

1. Open Xcode → **File > New > Project** → iOS App.
2. Kies **Storyboard** interface, **UIKit** lifecycle.
3. Bundle Identifier: `com.yourname.drivecarplayaudio`.
4. Verwijder de automatisch gemaakte `ViewController.swift`, `Main.storyboard` en `AppDelegate.swift`.
5. Voeg alle bestanden uit de `Sources/` en `Resources/` map toe via **File > Add Files to…**.
6. Selecteer het project target → **Info** tab:
   - Stel het **Info.plist** in op `DriveCarPlayAudio/Resources/Info.plist`.
7. Target → **Signing & Capabilities**:
   - Voeg **Background Modes** toe → vink **Audio, AirPlay, and Picture in Picture** aan.
   - Voeg het bestand `DriveCarPlayAudio.entitlements` toe via **Signing & Capabilities > + Capability > Custom Entitlements**.

## 3. CarPlay Simulator testen

1. Start de app op de simulator of een fysiek apparaat.
2. In de menu bar van de Simulator: **I/O > External Displays > CarPlay**.
3. Meld je aan via de iPhone app → het CarPlay scherm toont je Drive mappen.

## 4. App Store / fysiek voertuig

Voor gebruik op een echt voertuig moet je de **CarPlay Audio** entitlement aanvragen bij Apple:
- developer.apple.com/contact/request/carplay/

---

## Architectuur

```
Sources/
├── App/
│   ├── AppDelegate.swift         # Scene routing (iPhone vs CarPlay)
│   ├── SceneDelegate.swift       # iPhone window setup
│   └── CarPlaySceneDelegate.swift# CarPlay scene lifecycle
├── Services/
│   ├── GoogleAuthService.swift   # OAuth 2.0 + Keychain token opslag
│   ├── GoogleDriveService.swift  # Drive API + fetchWithRetry
│   └── AudioPlayerService.swift  # AVPlayer + MPRemoteCommandCenter
├── Models/
│   └── DriveFile.swift           # Data model (folder / audio detectie)
├── CarPlay/
│   └── CarPlayTemplateManager.swift # CPListTemplate navigatie
├── UI/
│   └── MainViewController.swift  # iPhone aanmeld-scherm + toast
└── Utilities/
    └── KeychainHelper.swift       # Veilige token opslag
```

## Audio formaten ondersteund

WAV · MP3 · AIFF · M4A · FLAC (alles wat AVFoundation ondersteunt)
