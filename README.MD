# Spotify Autopause

Spotify Autopause is a native macOS menu bar app that pauses Spotify when other apps start playing audio, then resumes Spotify when that audio stops.

## Highlights

- Native `MenuBarExtra(.window)` macOS app built with SwiftUI and AppKit
- Spotify control via AppleScript, with the existing pause/resume intent preserved
- Audio-source detection based on `pmset -g assertions`, resolved into app identities when possible
- Live Recent Activity window with structured history
- Ignored Apps manager with persistent checkboxes, last-seen timestamps, seen counts, and recent-trigger context
- Local-only state stored in `~/Library/Application Support/Spotify Autopause/state.json`

## Requirements

- macOS 14 or later
- Xcode 26 or later for local builds
- Spotify desktop app installed

## Build

```bash
./build.sh
```

The build script creates:

- `build/DerivedData/Build/Products/Release/Spotify Autopause.app`
- `build/Artifacts/SpotifyAutopause.dmg`

## Permissions

Spotify Autopause works entirely on-device, but macOS may prompt for:

- Automation access to control Spotify with Apple Events
- Permission to observe the system audio state indirectly through the macOS command-line tools it uses

If Spotify is running but the app does not pause or resume it, check **System Settings > Privacy & Security > Automation** and confirm Spotify Autopause is allowed to control Spotify.

## How It Works

1. Spotify Autopause polls the current system audio assertions.
2. Any active audio source is resolved to a bundle identifier or executable path when possible.
3. Sources marked as ignored stay visible in the UI but do not trigger a Spotify pause or resume.
4. If actionable audio starts while Spotify is playing, Spotify Autopause pauses it.
5. If that actionable audio ends and Spotify Autopause was the component that paused Spotify, it resumes playback.

## License

This project is licensed under the GNU General Public License v3.0 (GPL-3.0). See [LICENSE](LICENSE).
