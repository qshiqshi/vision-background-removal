#!/bin/bash
#
# OBS Background Removal Plugin - Quick Install Script
# Copyright (C) 2026 Andreas Kuschner
#

set -e

PLUGIN_NAME="obs-background-removal-mac"
PLUGIN_DIR="$HOME/Library/Application Support/obs-studio/plugins"

echo "========================================"
echo "OBS Background Removal - Quick Install"
echo "========================================"
echo ""

# Check if OBS is installed
if [ ! -d "/Applications/OBS.app" ]; then
    echo "Warning: OBS Studio not found in /Applications"
    echo "Please install OBS Studio first: https://obsproject.com"
    exit 1
fi

# Check if plugin directory exists
if [ ! -d "$PLUGIN_DIR" ]; then
    echo "Creating plugins directory..."
    mkdir -p "$PLUGIN_DIR"
fi

# Check if script is run from plugin directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -d "$SCRIPT_DIR/release/$PLUGIN_NAME" ]; then
    SOURCE_DIR="$SCRIPT_DIR/release/$PLUGIN_NAME"
elif [ -d "$SCRIPT_DIR/$PLUGIN_NAME" ]; then
    SOURCE_DIR="$SCRIPT_DIR/$PLUGIN_NAME"
else
    echo "Error: Plugin files not found."
    echo "Please run the build script first: ./.github/scripts/build-macos.sh"
    exit 1
fi

# Install plugin
echo "Installing plugin..."
cp -r "$SOURCE_DIR" "$PLUGIN_DIR/"

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Restart OBS Studio"
echo "  2. Add a video capture source"
echo "  3. Right-click source > Filters > + > Background Removal"
echo ""
echo "Enjoy your virtual background!"
