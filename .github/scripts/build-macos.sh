#!/bin/bash
#
# OBS Background Removal Plugin - macOS Build Script
# Copyright (C) 2026 Andreas Kuschner
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
BUILD_TYPE="${BUILD_TYPE:-Release}"
ARCHITECTURE="${ARCHITECTURE:-arm64}"
OBS_VERSION="${OBS_VERSION:-30.0.0}"

echo "============================================"
echo "OBS Background Removal Plugin - Build Script"
echo "============================================"
echo "Build Type: $BUILD_TYPE"
echo "Architecture: $ARCHITECTURE"
echo "OBS Version: $OBS_VERSION"
echo ""

# Check dependencies
check_dependencies() {
    echo "Checking dependencies..."

    if ! command -v cmake &> /dev/null; then
        echo "Error: CMake not found. Install with: brew install cmake"
        exit 1
    fi

    if ! command -v xcodebuild &> /dev/null; then
        echo "Error: Xcode not found. Install Xcode from the App Store."
        exit 1
    fi

    echo "All dependencies found."
}

# Download OBS headers if needed
setup_obs_headers() {
    local OBS_DEPS_DIR="$PROJECT_ROOT/deps/obs-studio"

    if [ ! -d "$OBS_DEPS_DIR" ]; then
        echo "Downloading OBS Studio headers..."
        mkdir -p "$OBS_DEPS_DIR"

        # Download OBS source for headers
        curl -L "https://github.com/obsproject/obs-studio/archive/refs/tags/${OBS_VERSION}.tar.gz" \
            -o /tmp/obs-studio.tar.gz

        tar -xzf /tmp/obs-studio.tar.gz -C /tmp
        cp -r "/tmp/obs-studio-${OBS_VERSION}/libobs" "$OBS_DEPS_DIR/"

        rm -rf /tmp/obs-studio.tar.gz "/tmp/obs-studio-${OBS_VERSION}"

        echo "OBS headers downloaded to $OBS_DEPS_DIR"
    fi
}

# Build the plugin
build_plugin() {
    echo "Building plugin..."

    local BUILD_DIR="$PROJECT_ROOT/build"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    cmake .. \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_OSX_ARCHITECTURES="$ARCHITECTURE" \
        -DOBS_SOURCE_DIR="$PROJECT_ROOT/deps/obs-studio"

    cmake --build . --config "$BUILD_TYPE" --parallel

    echo "Build complete!"
}

# Create installer package
create_package() {
    echo "Creating installer package..."

    local RELEASE_DIR="$PROJECT_ROOT/release"
    local PLUGIN_NAME="obs-background-removal-mac"

    mkdir -p "$RELEASE_DIR/$PLUGIN_NAME/bin"
    mkdir -p "$RELEASE_DIR/$PLUGIN_NAME/data"

    # Copy plugin binary
    cp "$PROJECT_ROOT/build/$PLUGIN_NAME.so" "$RELEASE_DIR/$PLUGIN_NAME/bin/"

    # Copy data files
    cp -r "$PROJECT_ROOT/data/"* "$RELEASE_DIR/$PLUGIN_NAME/data/"

    # Create zip archive
    cd "$RELEASE_DIR"
    zip -r "$PLUGIN_NAME-$ARCHITECTURE.zip" "$PLUGIN_NAME"

    echo "Package created: $RELEASE_DIR/$PLUGIN_NAME-$ARCHITECTURE.zip"
}

# Main
check_dependencies
setup_obs_headers
build_plugin
create_package

echo ""
echo "============================================"
echo "Build completed successfully!"
echo "============================================"
echo ""
echo "To install the plugin:"
echo "  1. Copy the 'obs-background-removal-mac' folder to:"
echo "     ~/Library/Application Support/obs-studio/plugins/"
echo ""
echo "  2. Restart OBS Studio"
echo ""
echo "  3. Add the filter to your video source:"
echo "     Right-click source > Filters > + > Background Removal"
echo ""
