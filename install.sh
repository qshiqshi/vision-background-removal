#!/usr/bin/env bash
#
# OBS Vision Background Removal Plugin - Installer
# Copyright (C) 2026 Andreas Kuschner
#
# Installs a previously built plugin bundle into the current user's
# OBS plugin directory.
#
# Usage:
#   ./install.sh             # install build/vision-background-removal.plugin
#   ./install.sh --uninstall # remove the installed plugin
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_NAME="vision-background-removal"
OBS_PLUGIN_DIR="$HOME/Library/Application Support/obs-studio/plugins"
INSTALLED_BUNDLE="$OBS_PLUGIN_DIR/$PLUGIN_NAME.plugin"

if [[ "${1:-}" == "--uninstall" ]]; then
    if [[ -d "$INSTALLED_BUNDLE" ]]; then
        rm -rf "$INSTALLED_BUNDLE"
        echo "Removed: $INSTALLED_BUNDLE"
    else
        echo "Plugin is not installed."
    fi
    exit 0
fi

if [[ ! -d "/Applications/OBS.app" ]]; then
    echo "Warning: OBS Studio was not found in /Applications." >&2
fi

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "Error: this plugin requires an Apple Silicon Mac." >&2
    exit 1
fi

SOURCE_BUNDLE=""
for candidate in \
    "$SCRIPT_DIR/build/$PLUGIN_NAME.plugin" \
    "$SCRIPT_DIR/release/$PLUGIN_NAME.plugin" \
    "$SCRIPT_DIR/$PLUGIN_NAME.plugin"; do
    if [[ -d "$candidate" ]]; then
        SOURCE_BUNDLE="$candidate"
        break
    fi
done

if [[ -z "$SOURCE_BUNDLE" ]]; then
    echo "Error: no built plugin found." >&2
    echo "Build it first with: ./.github/scripts/build-macos.sh" >&2
    exit 1
fi

mkdir -p "$OBS_PLUGIN_DIR"
rm -rf "$INSTALLED_BUNDLE"
cp -R "$SOURCE_BUNDLE" "$INSTALLED_BUNDLE"

echo "Installed: $INSTALLED_BUNDLE"
echo ""
echo "Next steps:"
echo "  1. Restart OBS Studio (Cmd+Q, then reopen)"
echo "  2. Right-click a video source -> Filters"
echo "  3. Under Effect Filters click + and choose \"Vision Background Removal\""
