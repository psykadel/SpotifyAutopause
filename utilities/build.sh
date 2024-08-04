#!/bin/bash

APP_NAME="Spotify Autopause"
APP_ICON="spotify-autopause.icns"
SCRIPT_NAME="spotify-autopause.py"
OUTPUT_DIR="./dist"
DMG_DIR="./dmg"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
DMG_PATH="$HOME/Desktop/$DMG_NAME"

# run from the folder with spotify-autopause.py
pyinstaller --onefile --windowed --name "$APP_NAME" --icon=spotify-autopause.icns --add-data "$APP_ICON:." $SCRIPT_NAME --hidden-import=objc

# update the app
cp -Rfv "$OUTPUT_DIR/$APP_NAME.app" /Applications/

# create the dmg file
mkdir "$DMG_DIR"
cp -Rfv "$OUTPUT_DIR/$APP_NAME.app" $DMG_DIR
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG_PATH"