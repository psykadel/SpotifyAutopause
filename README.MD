# Spotify Autopause

Spotify Autopause is a native macOS menu bar app that pauses Spotify when other apps start playing audio, then resumes Spotify when that audio stops.

## Highlights

- Native macOS app built with SwiftUI and AppKit
- Spotify control via AppleScript
- Audio-source detection based on `pmset -g assertions`, followed by per-PID Core Audio audibility checks
- Live Recent Activity window
- Ignored Apps manager with persistent checkboxes, last-seen timestamps, seen counts, and recent-trigger context
- Local-only state stored in `~/Library/Application Support/Spotify Autopause/state.json`

## Requirements

- macOS 14.2 or later
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
- System audio capture permission so the app can verify whether a candidate process is actually audible

If Spotify is running but the app does not pause or resume it, check:

- **System Settings > Privacy & Security > Automation** and confirm Spotify Autopause is allowed to control Spotify
- **System Settings > Privacy & Security > System Audio Recording** and confirm Spotify Autopause is allowed to capture brief audio samples for audibility checks

## How It Works

1. Spotify Autopause polls the current system audio assertions.
2. Candidate PIDs are resolved to app identities when possible.
3. Only those candidate PIDs are attached to lightweight Core Audio process taps.
4. A source counts as active only when recent captured samples are above the silence threshold.
5. Sources marked as ignored stay visible in the UI but do not trigger a Spotify pause or resume.
6. If actionable audible audio starts while Spotify is playing, Spotify Autopause pauses it.
7. If that actionable audible audio ends and Spotify Autopause was the component that paused Spotify, it resumes playback.

## License

This project is licensed under the GNU General Public License v3.0 (GPL-3.0). See [LICENSE](LICENSE).
