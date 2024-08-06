import subprocess
import re
import time
from collections import deque
import os
import rumps
from Foundation import NSObject
from AppKit import NSApplication, NSBundle, NSProcessInfo
from tabulate import tabulate
import osascript
import json

# Constants
SPOTIFY_PLAYER_STATE_SCRIPT = 'tell application "Spotify" to player state'
SPOTIFY_PAUSE_SCRIPT = 'tell application "Spotify" to pause'
SPOTIFY_PLAY_SCRIPT = 'tell application "Spotify" to play'
DELAY_WHEN_START = 2
DELAY_WHEN_PLAYING = 2
DELAY_WHEN_NOT_PLAYING = 3
APP_SUPPORT_DIR = os.path.join(os.path.expanduser('~'), 'Library', 'Application Support', "Spotify Autopause")
IGNORE_LIST_FILE = os.path.join(APP_SUPPORT_DIR, 'ignore_list.json')
LOG_FILE = os.path.join(APP_SUPPORT_DIR, 'spotify_autopause.log')

class AppDelegate(NSObject):
    def applicationSupportsSecureRestorableState_(self, app) -> bool:
        return True

class SpotifyAutopause:
    def __init__(self) -> None:
        os.makedirs(APP_SUPPORT_DIR, exist_ok=True)
        self.spotify_was_playing: bool = False
        self.non_spotify_audio_playing: bool = False
        self.user_ignore_apps = self.load_ignore_apps()
        self.always_ignore_apps = ["Spotify"]
        self.all_rows: deque = deque(maxlen=8)
        self.status_table: str = ""
        self.last_spotify_state: str = ""
        self.last_other_audio_state: str = ""
        self.app: rumps.App = rumps.App("Spotify Autopause", icon="spotify-autopause.icns", menu=None)
        self.setup_app()

    # Application Setup
    # -----------------

    def setup_app(self):
        """Set up the application, including hiding the dock icon and initializing the menu."""
        self.hide_dock_icon()
        self.setup_delegate()
        self.setup_timer()
        self.setup_menu()

    def hide_dock_icon(self):
        """Hide the application's dock icon."""
        info = NSBundle.mainBundle().infoDictionary()
        info["LSUIElement"] = "1"
        NSProcessInfo.processInfo().environment()

    def setup_delegate(self):
        """Set up the application delegate."""
        self.nsapp = NSApplication.sharedApplication()
        delegate = AppDelegate.alloc().init()
        self.nsapp.setDelegate_(delegate)

    def setup_timer(self):
        """Set up the timer for checking audio status."""
        self.check_audio_timer: rumps.Timer = rumps.Timer(self.check_audio, DELAY_WHEN_START)
        self.check_audio_timer.start()

    def setup_menu(self):
        """Set up the application menu."""
        self.app.menu = [
            rumps.MenuItem("Recent Activity", callback=self.show_recent_activity),
            rumps.MenuItem("Edit Ignored Apps", callback=self.edit_ignore_apps)
        ]

    # Ignore List Management
    # ----------------------

    def load_ignore_apps(self):
        """Load the list of ignored apps from the JSON file."""
        if os.path.exists(IGNORE_LIST_FILE):
            with open(IGNORE_LIST_FILE, 'r') as f:
                return json.load(f)
        return []

    def save_ignore_apps(self):
        """Save the list of ignored apps to the JSON file."""
        with open(IGNORE_LIST_FILE, 'w') as f:
            json.dump(self.user_ignore_apps, f)

    def edit_ignore_apps(self, _):
        """Display a window for editing the list of ignored apps."""
        current_apps = ", ".join(self.user_ignore_apps)
        response = rumps.Window(
            message="Enter additional apps to ignore (comma-separated):",
            title="Edit Ignored Apps",
            default_text=current_apps,
            ok="Save",
            cancel="Cancel"
        ).run()

        if response.clicked:
            new_apps = [app.strip() for app in response.text.split(',') if app.strip()]
            self.user_ignore_apps = new_apps
            self.save_ignore_apps()

    # Recent Activity Logging
    # -----------------------

    def show_recent_activity(self, _):
        """Write the current status table to a log file and open it."""
        self.write_log_file()
        subprocess.run(['open', LOG_FILE])

    def write_log_file(self):
        """Write the current status table to the log file."""
        with open(LOG_FILE, 'w') as f:
            f.write(self.status_table)

    # Audio Status Checking and Handling
    # ----------------------------------

    def check_audio(self, sender=None) -> None:
        """
        Check the current audio status and handle any changes.
        This method is called periodically by the timer.
        """
        spotify_playing = self.is_spotify_playing()
        other_audio_playing, sources = self.is_audio_playing()

        if other_audio_playing and not self.non_spotify_audio_playing:
            self.handle_audio_start(spotify_playing, sources)
        elif not other_audio_playing and self.non_spotify_audio_playing:
            self.handle_audio_stop(spotify_playing)
        else:
            self.log_audio_status(spotify_playing, other_audio_playing, sources)

        self.update_status_table()
        self.print_status()
        self.write_log_file()

    def handle_audio_start(self, spotify_playing: bool, sources: list) -> None:
        """Handle the start of non-Spotify audio playback."""
        self.non_spotify_audio_playing = True
        if spotify_playing:
            self.spotify_was_playing = True
            self.pause_spotify()
            self.log_audio_status(spotify_playing, True, sources, "Pausing Spotify")
            self.check_audio_timer.interval = DELAY_WHEN_NOT_PLAYING

    def handle_audio_stop(self, spotify_playing: bool) -> None:
        """Handle the stop of non-Spotify audio playback."""
        self.non_spotify_audio_playing = False
        if self.spotify_was_playing:
            self.play_spotify()
            self.log_audio_status(spotify_playing, False, [], "Resuming Spotify")
            self.spotify_was_playing = False
            self.check_audio_timer.interval = DELAY_WHEN_PLAYING

    def update_status_table(self) -> None:
        """Update the status table with the current audio status information."""
        self.status_table = tabulate(self.all_rows, ["Timestamp", "Spotify", "Other Audio"], tablefmt="grid", numalign="center", stralign="center")

    def print_status(self) -> None:
        """Print the current status table to the console."""
        os.system('clear')
        print(self.status_table)

    # Spotify Control
    # ---------------

    def is_spotify_playing(self) -> bool:
        """Check if Spotify is currently playing music."""
        code, result, error = osascript.run(SPOTIFY_PLAYER_STATE_SCRIPT)
        return result.strip() == 'playing'

    def pause_spotify(self) -> None:
        """Pause Spotify playback."""
        osascript.run(SPOTIFY_PAUSE_SCRIPT)

    def play_spotify(self) -> None:
        """Resume Spotify playback."""
        osascript.run(SPOTIFY_PLAY_SCRIPT)

    # Audio Process Detection
    # -----------------------

    def get_audio_pids(self) -> list:
        """
        Get the process IDs of applications currently using audio output.
        This method parses the output of 'pmset -g assertions' to find audio-related processes.
        """
        result = subprocess.run(['pmset', '-g', 'assertions'], capture_output=True, text=True)
        lines = result.stdout.split('\n')  
        pids = []
        for i, line in enumerate(lines):
            if "Resources: audio-out" in line and i > 0:
                pid_line = lines[i - 1]
                match = re.search(r'Created for PID: (\d+)', pid_line)
                if match:
                    pids.append(match.group(1))
        return pids

    def list_audio_processes(self, audio_pids: list) -> list:
        """Get the names of processes associated with the given process IDs."""
        processes = []
        for pid in audio_pids:
            process_info = subprocess.run(['ps', '-p', pid, '-o', 'comm='], stdout=subprocess.PIPE, text=True, check=True).stdout.strip() 
            processes.append(process_info.title())
        return processes

    def is_audio_playing(self) -> tuple:
        """
        Check if any non-ignored applications are playing audio.
        Returns a tuple: (is_playing, list_of_playing_apps)
        """
        audio_pids = self.get_audio_pids()
        all_audio_processes = self.list_audio_processes(audio_pids)
        
        ignored_apps = self.always_ignore_apps + self.user_ignore_apps
        non_ignored_audio = [
            process for process in all_audio_processes 
            if not any(ignored_app.lower() in process.lower() for ignored_app in ignored_apps)
        ]
        
        return bool(non_ignored_audio), non_ignored_audio

    # Logging
    # -------

    def log_audio_status(self, spotify_status: bool, other_audio_playing: bool, sources: list, action: str = None) -> None:
        """
        Log the current audio status if there's been a change or an action.
        This method updates the all_rows deque with new status information.
        """
        timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
        spotify_state = "Playing" if spotify_status else "Paused"
        other_audio_state = ', '.join(source.split('/')[-1] for source in sources) if other_audio_playing else "No Other Audio"
        
        if spotify_state != self.last_spotify_state or other_audio_state != self.last_other_audio_state or action:
            row = [timestamp, spotify_state, other_audio_state]
            self.all_rows.append(row)
            if action:
                self.all_rows.append([timestamp, action, ""])
            
            self.last_spotify_state = spotify_state
            self.last_other_audio_state = other_audio_state

    # Application Control
    # -------------------

    def quit_app(self, sender) -> None:
        """Quit the application."""
        rumps.quit_application()

if __name__ == "__main__":
    SpotifyAutopause().app.run()