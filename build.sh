#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$ROOT_DIR/SpotifyAutopause.xcodeproj"
SCHEME_NAME="SpotifyAutopause"
APP_NAME="Spotify Autopause.app"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="$ROOT_DIR/build/DerivedData"
ARTIFACTS_DIR="$ROOT_DIR/build/Artifacts"

install_app() {
  local source_app_path="$1"
  local target_app_path="$2"

  if [[ -e "$target_app_path" ]]; then
    rm -rf "$target_app_path"
  fi

  /usr/bin/ditto "$source_app_path" "$target_app_path"
}

install_app_with_sudo() {
  local source_app_path="$1"
  local target_app_path="$2"

  if sudo test -e "$target_app_path"; then
    sudo rm -rf "$target_app_path"
  fi

  sudo /usr/bin/ditto "$source_app_path" "$target_app_path"
}

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"
DMG_STAGING_DIR="$ARTIFACTS_DIR/dmg-root"
DMG_PATH="$ARTIFACTS_DIR/SpotifyAutopause.dmg"
INSTALL_PATH="/Applications/$APP_NAME"

mkdir -p "$ARTIFACTS_DIR"
rm -rf "$DMG_STAGING_DIR"
mkdir -p "$DMG_STAGING_DIR"
cp -R "$APP_PATH" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "Spotify Autopause" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo
echo "Build succeeded:"
echo "$APP_PATH"
echo
echo "DMG created:"
echo "$DMG_PATH"

if [[ -t 0 ]]; then
  echo
  read -r -p "Copy $APP_NAME to /Applications and overwrite any existing copy? [y/N] " should_install

  if [[ "$should_install" =~ ^[Yy]$ ]]; then
    if install_app "$APP_PATH" "$INSTALL_PATH"; then
      echo
      echo "Installed app:"
      echo "$INSTALL_PATH"
    else
      echo
      echo "Copy to /Applications requires administrator privileges. Retrying with sudo..."
      install_app_with_sudo "$APP_PATH" "$INSTALL_PATH"
      echo
      echo "Installed app:"
      echo "$INSTALL_PATH"
    fi
  else
    echo
    echo "Skipped installing to /Applications."
  fi
else
  echo
  echo "Skipping /Applications install prompt because no interactive terminal is attached."
fi
