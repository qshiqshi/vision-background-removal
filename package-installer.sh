#!/usr/bin/env bash
#
# OBS Vision Background Removal Plugin - package builder
# Copyright (C) 2026 Andreas Kuschner
#
# Builds a distributable .zip/.dmg containing the built .plugin bundle and
# double-clickable install/uninstall scripts. Requires the plugin to have been
# built already (or calls the build script automatically).
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_NAME="vision-background-removal"
ARCH="$(uname -m)"

PLUGIN_VERSION="$(sed -n 's/^set(PLUGIN_VERSION "\(.*\)")/\1/p' "$SCRIPT_DIR/CMakeLists.txt" | head -1)"
PLUGIN_VERSION="${PLUGIN_VERSION:-1.0.0}"
PACKAGE_NAME="$PLUGIN_NAME-v$PLUGIN_VERSION-macOS-$ARCH"
BUNDLE="$SCRIPT_DIR/build/$PLUGIN_NAME.plugin"

if [[ ! -d "$BUNDLE" ]]; then
    echo "Plugin has not been built yet. Building..."
    "$SCRIPT_DIR/.github/scripts/build-macos.sh"
fi

[[ -d "$BUNDLE" ]] || {
    echo "Error: build output not found: $BUNDLE" >&2
    exit 1
}

DIST_DIR="$SCRIPT_DIR/dist"
PACKAGE_DIR="$DIST_DIR/$PACKAGE_NAME"
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"

echo "Creating package in $PACKAGE_DIR ..."
cp -R "$BUNDLE" "$PACKAGE_DIR/"
if [[ -f "$SCRIPT_DIR/docs/setup-guide.html" ]]; then
    cp "$SCRIPT_DIR/docs/setup-guide.html" "$PACKAGE_DIR/"
fi

cat > "$PACKAGE_DIR/install.command" <<'INSTALLER_EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_NAME="vision-background-removal"
OBS_PLUGIN_DIR="$HOME/Library/Application Support/obs-studio/plugins"
SOURCE_BUNDLE="$SCRIPT_DIR/$PLUGIN_NAME.plugin"

clear
echo "============================================"
echo "  OBS Vision Background Removal - Installer"
echo "============================================"
echo ""

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "ERROR: this plugin requires an Apple Silicon Mac."
    read -r -p "Press Enter to exit..."
    exit 1
fi

if [[ ! -d "$SOURCE_BUNDLE" ]]; then
    echo "ERROR: $PLUGIN_NAME.plugin is missing from this package."
    read -r -p "Press Enter to exit..."
    exit 1
fi

if [[ -d "/Applications/OBS.app" ]]; then
    echo "Found OBS Studio at /Applications/OBS.app"
else
    echo "WARNING: OBS Studio was not found in /Applications."
fi

mkdir -p "$OBS_PLUGIN_DIR"
rm -rf "$OBS_PLUGIN_DIR/$PLUGIN_NAME.plugin"
cp -R "$SOURCE_BUNDLE" "$OBS_PLUGIN_DIR/"

echo ""
echo "============================================"
echo "  Installation complete"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Restart OBS Studio (Cmd+Q, then reopen)"
echo "  2. Right-click a video source -> Filters"
echo "  3. Under Effect Filters click + -> Vision Background Removal"
echo ""
read -r -p "Press Enter to exit..."
INSTALLER_EOF
chmod +x "$PACKAGE_DIR/install.command"

cat > "$PACKAGE_DIR/uninstall.command" <<'UNINSTALLER_EOF'
#!/usr/bin/env bash
set -euo pipefail

PLUGIN_NAME="vision-background-removal"
PLUGIN_DIR="$HOME/Library/Application Support/obs-studio/plugins/$PLUGIN_NAME.plugin"

clear
echo "============================================"
echo "  OBS Vision Background Removal - Uninstall"
echo "============================================"
echo ""

if [[ -d "$PLUGIN_DIR" ]]; then
    rm -rf "$PLUGIN_DIR"
    echo "Removed: $PLUGIN_DIR"
else
    echo "Plugin is not installed."
fi

echo ""
read -r -p "Press Enter to exit..."
UNINSTALLER_EOF
chmod +x "$PACKAGE_DIR/uninstall.command"

cat > "$PACKAGE_DIR/README.txt" <<README_EOF
============================================
OBS Vision Background Removal
Version $PLUGIN_VERSION - macOS $ARCH
============================================

Real-time background removal for OBS Studio using Apple's Vision Framework.

REQUIREMENTS
------------
- macOS 13.0 (Ventura) or later
- Apple Silicon Mac (M1/M2/M3/M4)
- OBS Studio 33.0 or later

INSTALLATION
------------
Double-click "install.command".

The installer copies "vision-background-removal.plugin" to:
  ~/Library/Application Support/obs-studio/plugins/

Then restart OBS Studio and add the filter:
  Right-click a video source -> Filters -> + -> Vision Background Removal

UNINSTALL
---------
Double-click "uninstall.command".

DOCUMENTATION
-------------
Open setup-guide.html for detailed instructions.

LICENSE
-------
GPL-2.0. See the project repository for details.

Copyright (C) 2026 Andreas Kuschner
README_EOF

echo "Creating ZIP archive..."
rm -f "$DIST_DIR/$PACKAGE_NAME.zip"
( cd "$DIST_DIR" && COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc "$PACKAGE_NAME" "$PACKAGE_NAME.zip" )

if command -v hdiutil >/dev/null 2>&1; then
    echo "Creating DMG..."
    DMG_TEMP="$DIST_DIR/dmg_temp"
    DMG_FINAL="$DIST_DIR/$PACKAGE_NAME.dmg"
    rm -rf "$DMG_TEMP" "$DMG_FINAL"
    mkdir -p "$DMG_TEMP"
    cp -R "$PACKAGE_DIR" "$DMG_TEMP/"
    hdiutil create -volname "OBS Vision Background Removal" \
        -srcfolder "$DMG_TEMP" -ov -format UDZO "$DMG_FINAL" >/dev/null
    rm -rf "$DMG_TEMP"
    echo "DMG: $DMG_FINAL"
fi

echo ""
echo "Package created:"
echo "  $DIST_DIR/$PACKAGE_NAME.zip"
if [[ -f "$DIST_DIR/$PACKAGE_NAME.dmg" ]]; then
    echo "  $DIST_DIR/$PACKAGE_NAME.dmg"
fi
