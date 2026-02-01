#!/bin/bash
#
# OBS Background Removal Plugin - Package Installer Creator
# Creates a distributable installer package
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_NAME="obs-background-removal-mac"
VERSION="1.0.0"
PACKAGE_NAME="${PLUGIN_NAME}-v${VERSION}-macOS-arm64"

echo "============================================"
echo "Creating Installer Package"
echo "============================================"
echo ""

# Create package directory
PACKAGE_DIR="$SCRIPT_DIR/dist/$PACKAGE_NAME"
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR/plugin/bin"
mkdir -p "$PACKAGE_DIR/plugin/data/locale"
mkdir -p "$PACKAGE_DIR/source"
mkdir -p "$PACKAGE_DIR/docs"

# Copy plugin data files
cp -r "$SCRIPT_DIR/data/locale/"* "$PACKAGE_DIR/plugin/data/locale/"

# Copy source files for building
cp -r "$SCRIPT_DIR/src" "$PACKAGE_DIR/source/"
cp -r "$SCRIPT_DIR/cmake" "$PACKAGE_DIR/source/"
cp "$SCRIPT_DIR/CMakeLists.txt" "$PACKAGE_DIR/source/"
cp -r "$SCRIPT_DIR/.github" "$PACKAGE_DIR/source/"

# Copy documentation
cp "$SCRIPT_DIR/docs/setup-guide.html" "$PACKAGE_DIR/docs/"

# Create installer script for the package
cat > "$PACKAGE_DIR/install.command" << 'INSTALLER_EOF'
#!/bin/bash
#
# OBS Background Removal Plugin - Installer
# Double-click this file to install
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_NAME="obs-background-removal-mac"
OBS_PLUGIN_DIR="$HOME/Library/Application Support/obs-studio/plugins"

clear
echo "============================================"
echo "  OBS Background Removal Plugin Installer"
echo "============================================"
echo ""

# Check macOS version
OS_VERSION=$(sw_vers -productVersion)
echo "Detected macOS: $OS_VERSION"

# Check architecture
ARCH=$(uname -m)
echo "Architecture: $ARCH"

if [ "$ARCH" != "arm64" ]; then
    echo ""
    echo "ERROR: This plugin requires Apple Silicon (M1/M2/M3/M4)."
    echo "Intel Macs are not supported."
    echo ""
    read -p "Press Enter to exit..."
    exit 1
fi

# Check if OBS is installed
if [ ! -d "/Applications/OBS.app" ]; then
    echo ""
    echo "WARNING: OBS Studio not found in /Applications"
    echo "Please install OBS Studio first: https://obsproject.com"
    echo ""
fi

# Check if binary exists or needs to be built
if [ ! -f "$SCRIPT_DIR/plugin/bin/$PLUGIN_NAME.so" ]; then
    echo ""
    echo "Plugin binary not found. Building from source..."
    echo ""

    # Check for Xcode
    if ! xcode-select -p &> /dev/null; then
        echo "ERROR: Xcode Command Line Tools required."
        echo "Install with: xcode-select --install"
        echo ""
        read -p "Press Enter to exit..."
        exit 1
    fi

    # Check for CMake
    if ! command -v cmake &> /dev/null; then
        echo "CMake not found. Attempting to install via Homebrew..."
        if command -v brew &> /dev/null; then
            brew install cmake
        else
            echo "ERROR: Please install CMake: brew install cmake"
            echo ""
            read -p "Press Enter to exit..."
            exit 1
        fi
    fi

    # Build the plugin
    echo "Building plugin..."
    cd "$SCRIPT_DIR/source"

    # Download OBS headers
    OBS_VERSION="30.0.0"
    if [ ! -d "deps/obs-studio" ]; then
        echo "Downloading OBS headers..."
        mkdir -p deps/obs-studio
        curl -L "https://github.com/obsproject/obs-studio/archive/refs/tags/${OBS_VERSION}.tar.gz" -o /tmp/obs.tar.gz
        tar -xzf /tmp/obs.tar.gz -C /tmp
        cp -r "/tmp/obs-studio-${OBS_VERSION}/libobs" deps/obs-studio/
        rm -rf /tmp/obs.tar.gz "/tmp/obs-studio-${OBS_VERSION}"
    fi

    # Build
    mkdir -p build && cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64
    cmake --build . --config Release

    # Copy built binary
    cp "$PLUGIN_NAME.so" "$SCRIPT_DIR/plugin/bin/"

    cd "$SCRIPT_DIR"
    echo ""
    echo "Build completed successfully!"
fi

# Create plugins directory if needed
mkdir -p "$OBS_PLUGIN_DIR"

# Remove old version if exists
if [ -d "$OBS_PLUGIN_DIR/$PLUGIN_NAME" ]; then
    echo "Removing previous installation..."
    rm -rf "$OBS_PLUGIN_DIR/$PLUGIN_NAME"
fi

# Install plugin
echo ""
echo "Installing plugin to: $OBS_PLUGIN_DIR"
cp -r "$SCRIPT_DIR/plugin" "$OBS_PLUGIN_DIR/$PLUGIN_NAME"

echo ""
echo "============================================"
echo "  Installation Complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Restart OBS Studio (if running)"
echo "  2. Add a video capture source"
echo "  3. Right-click source > Filters"
echo "  4. Click + > Background Removal"
echo ""
echo "For help, open: docs/setup-guide.html"
echo ""
read -p "Press Enter to exit..."
INSTALLER_EOF

chmod +x "$PACKAGE_DIR/install.command"

# Create uninstaller
cat > "$PACKAGE_DIR/uninstall.command" << 'UNINSTALL_EOF'
#!/bin/bash
#
# OBS Background Removal Plugin - Uninstaller
#

PLUGIN_NAME="obs-background-removal-mac"
OBS_PLUGIN_DIR="$HOME/Library/Application Support/obs-studio/plugins"

clear
echo "============================================"
echo "  OBS Background Removal Plugin Uninstaller"
echo "============================================"
echo ""

if [ -d "$OBS_PLUGIN_DIR/$PLUGIN_NAME" ]; then
    echo "Removing plugin..."
    rm -rf "$OBS_PLUGIN_DIR/$PLUGIN_NAME"
    echo "Plugin removed successfully!"
else
    echo "Plugin not found. Nothing to remove."
fi

echo ""
read -p "Press Enter to exit..."
UNINSTALL_EOF

chmod +x "$PACKAGE_DIR/uninstall.command"

# Create README
cat > "$PACKAGE_DIR/README.txt" << 'README_EOF'
============================================
OBS Background Removal Plugin for macOS
Version 1.0.0
============================================

Remove video backgrounds in real-time using
Apple's Vision Framework with hardware
acceleration on Apple Silicon.

INSTALLATION
------------
Double-click "install.command" to install.

The installer will:
- Build the plugin if needed
- Install to OBS plugins folder
- Guide you through setup

REQUIREMENTS
------------
- macOS 13.0 (Ventura) or later
- Apple Silicon (M1/M2/M3/M4)
- OBS Studio 29.0 or later

FEATURES
--------
- Real-time background blur
- Solid color replacement (green screen)
- Transparent background
- Temporal smoothing (reduces flicker)
- Adjustable quality settings
- Edge refinement

DOCUMENTATION
-------------
Open docs/setup-guide.html for detailed
instructions and troubleshooting.

UNINSTALL
---------
Double-click "uninstall.command" to remove.

LICENSE
-------
GPL-2.0 - See source/LICENSE for details.

Copyright (C) 2026 Andreas Kuschner
README_EOF

# Create ZIP archive
echo "Creating ZIP archive..."
cd "$SCRIPT_DIR/dist"
zip -r "${PACKAGE_NAME}.zip" "$PACKAGE_NAME"

# Create DMG if hdiutil is available
if command -v hdiutil &> /dev/null; then
    echo "Creating DMG installer..."

    DMG_TEMP="$SCRIPT_DIR/dist/dmg_temp"
    DMG_FINAL="$SCRIPT_DIR/dist/${PACKAGE_NAME}.dmg"

    rm -rf "$DMG_TEMP" "$DMG_FINAL"
    mkdir -p "$DMG_TEMP"

    cp -r "$PACKAGE_DIR" "$DMG_TEMP/"

    # Create DMG
    hdiutil create -volname "OBS Background Removal" \
        -srcfolder "$DMG_TEMP" \
        -ov -format UDZO \
        "$DMG_FINAL"

    rm -rf "$DMG_TEMP"

    echo "DMG created: $DMG_FINAL"
fi

echo ""
echo "============================================"
echo "Package created successfully!"
echo "============================================"
echo ""
echo "Files created in dist/:"
ls -la "$SCRIPT_DIR/dist/"
echo ""
echo "Distribute either:"
echo "  - ${PACKAGE_NAME}.zip"
echo "  - ${PACKAGE_NAME}.dmg (if available)"
echo ""
