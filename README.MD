# Spotify Autopause

## Overview

Spotify Autopause is a macOS application that automatically pauses Spotify when other applications start playing audio. It then resumes Spotify playback when the other audio stops. This application is for users who love to listen to music continuously, but have that music pause when they are listening to other content.

This project was created as an alternative to the excellent BackgroundMusic project (https://github.com/kyleneideck/BackgroundMusic.git). Instead of interacting with audio drivers at a low level, this project relies on macOS shell commands for increased simplicity, faster response, and greater reliability, resulting in fewer idiosyncratic behaviors.

## Features

- **Automatic Spotify Control**: Pauses Spotify when other audio starts and resumes when it stops.
- **Customizable Ignore List**: Allows users to specify applications that should not trigger Spotify pausing.
- **Recent Activity Logging**: Maintains a log of audio state changes for user review and configuring the ignore list.
- **Menu Bar Integration**: Runs quietly in the menu bar for easy access and minimal intrusion.
- **Terminal Output**: Provides real-time status updates in the terminal (if run directly) for debugging and monitoring.

## Requirements

- macOS 10.12 or later
- Python 3.7 or later
- Spotify desktop application installed

## Installation

1. Clone the repository:
   ```
   git clone https://github.com/psykadel/mac-spotify-autopause.git
   ```

2. Install the required dependencies:
   ```
   pip install -r requirements.txt
   ```

3. Ensure you have the necessary permissions to control Spotify and monitor system audio.

## Installation (Application Option)

1. Download the .dmg file from "Releases."

2. Open the .dmg file, and drag and drop "Spotify Autopause" to your Applications folder.

## Usage

1. Run the application:
   ```
   python spotify_autopause.py
   ```

2. The application will appear as an icon in the menu bar.

3. Click the icon to access the following options:
   - **Recent Activity**: Opens a log file showing recent audio state changes.
   - **Edit Ignored Apps**: Allows you to specify applications that should not trigger Spotify pausing.

4. The application will automatically start monitoring audio and controlling Spotify.

## Running As Application

1. Install pyinstaller.
   ```
   pip install pyinstaller
   ```

2. Run ./utilities/build.sh from the root mac-spotify-autopause folder.  A cleanup.sh is also available to clean the build and dist folders up after a build if you choose.

3. A .app will be created in ./dist, which you can then copy to your Applications folder.

## Configuration

### Ignoring Applications

To prevent specific applications from triggering Spotify to pause:

1. Click the Spotify Autopause icon in the menu bar.
2. Select "Edit Ignored Apps".
3. Enter the names of the applications you want to ignore, separated by commas.
4. Click "Save" to apply the changes.

### Adjusting Timers

You can modify the following constants in the `spotify_autopause.py` file to adjust the application's behavior:

- `DELAY_WHEN_START`: Initial delay when the application starts monitoring (default: 1 second)
- `DELAY_WHEN_PLAYING`: Interval between checks when Spotify is playing (default: 1 second)
- `DELAY_WHEN_NOT_PLAYING`: Interval between checks when Spotify is not playing (default: 3 seconds)

## File Locations

- **Ignore List**: `~/Library/Application Support/Spotify Autopause/ignore_list.json`
- **Activity Log**: `~/Library/Application Support/Spotify Autopause/spotify_autopause.log`

## Troubleshooting

If you encounter any issues:

1. Check the terminal output any error messages.
2. Verify that the application has the necessary permissions to control Spotify and monitor system audio.
3. Check the "Recent Activity" log and consider adding items from "Other Audio" to the "Ignored Apps" list. Apps that you may not want to affect Spotify's play state could be interfering.

## Contributing

Contributions to Spotify Autopause are welcome! Please follow these steps:

1. Fork the repository.
2. Create a new branch for your feature or bug fix.
3. Commit your changes with clear, descriptive commit messages.
4. Push your branch and submit a pull request.

Please ensure your code adheres to the existing style.

## License

This project is licensed under the GNU General Public License v3.0 (GPL-3.0) - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- The Spotify Autopause project uses the `rumps` library for creating the macOS menu bar application.

## Contact

For support, feature requests, or any questions, please open an issue on the GitHub repository.

---

Spotify Autopause - Enhance your audio experience on macOS.