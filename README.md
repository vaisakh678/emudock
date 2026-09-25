# EmuDock

Android emulators, zero setup. A desktop app that installs the Android SDK and
creates, launches and manages emulators (AVDs) without Android Studio.

## Layout

- `macos/` — native SwiftUI macOS app (XcodeGen project)

## macOS development

```sh
cd macos
xcodegen generate
open EmuDock.xcodeproj
```

The app is not sandboxed: it runs the SDK's `sdkmanager`, `avdmanager` and
`emulator` tools, so it ships outside the Mac App Store (Developer ID +
notarization, Homebrew cask).
