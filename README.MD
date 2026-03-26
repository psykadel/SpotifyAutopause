# Spotify Autopause

Spotify Autopause is a small menu bar app for Mac that pauses Spotify when another app starts making sound, then resumes Spotify when that sound stops.

It is useful if you listen to Spotify while watching videos, taking calls, or opening apps that suddenly start playing audio.

## What It Does

- Lives in your menu bar
- Watches for other audible apps
- Pauses Spotify automatically when needed
- Resumes Spotify when the interruption is over
- Lets you ignore apps you never want to trigger a pause
- Shows a simple recent activity log so you can see what happened

## What You Need

- A Mac running macOS 14.2 or later
- The Spotify desktop app installed

## Permissions

The app runs locally on your Mac, but macOS may ask for permission to:

- control Spotify
- check whether another app is actually producing audible sound

If Spotify does not pause or resume correctly, open:

- `System Settings > Privacy & Security > Automation`
- `System Settings > Privacy & Security > System Audio Recording`

and make sure Spotify Autopause is allowed.

## How To Use It

1. Open Spotify Autopause.
2. Leave it running in the menu bar.
3. Play music in Spotify.
4. Open another app that plays sound.
5. Spotify Autopause will pause Spotify and bring it back when the sound ends.

If there is an app you do not want to count, open `Ignored Apps` and add it to the ignore list.

## Download A Release

If you do not want to build the app yourself, you can download a prebuilt release from the repository's GitHub Releases section.

## Build From Source

```bash
./build.sh
```

This creates the app and a DMG in the `build` folder.

## Privacy

Spotify Autopause keeps its data on your Mac. It does not need a cloud service to work.

## License

This project is licensed under the GNU General Public License v3.0 (GPL-3.0). See [LICENSE](LICENSE).
