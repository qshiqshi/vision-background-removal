#!/usr/bin/env bash
#
# OBS Vision Background Removal Plugin - macOS build script
# Copyright (C) 2026 Andreas Kuschner
#
# Usage:
#   ./.github/scripts/build-macos.sh              # build + package
#   ./.github/scripts/build-macos.sh --install    # build + install into OBS
#
# Environment:
#   BUILD_TYPE=Release
#   ARCHITECTURE=arm64
#   OBS_VERSION=33.0.1     (defaults to the version of /Applications/OBS.app)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BUILD_TYPE="${BUILD_TYPE:-Release}"
ARCHITECTURE="${ARCHITECTURE:-arm64}"
PLUGIN_NAME="vision-background-removal"
OBS_APP="/Applications/OBS.app"
OBS_DEPS_DIR="$PROJECT_ROOT/deps/obs-studio"

if [[ -z "${OBS_VERSION:-}" ]]; then
    if [[ -d "$OBS_APP" ]]; then
        OBS_VERSION="$(defaults read "$OBS_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || true)"
    fi
    OBS_VERSION="${OBS_VERSION:-33.0.1}"
fi

PLUGIN_VERSION="$(sed -n 's/^set(PLUGIN_VERSION "\(.*\)")/\1/p' "$PROJECT_ROOT/CMakeLists.txt" | head -1)"
PLUGIN_VERSION="${PLUGIN_VERSION:-1.0.0}"

echo "============================================"
echo "OBS Vision Background Removal - Build"
echo "============================================"
echo "Build type:   $BUILD_TYPE"
echo "Architecture: $ARCHITECTURE"
echo "OBS version:  $OBS_VERSION"
echo "Plugin:       $PLUGIN_VERSION"
echo ""

die() {
    echo "Error: $*" >&2
    exit 1
}

check_dependencies() {
    echo "Checking dependencies..."

    [[ "$(uname -s)" == "Darwin" ]] || die "This plugin only builds on macOS."
    [[ "$(uname -m)" == "arm64" ]] || die "This plugin requires an Apple Silicon Mac."

    command -v cmake >/dev/null 2>&1 || die "CMake not found. Install with: brew install cmake"
    command -v git >/dev/null 2>&1 || die "git not found. Install the Xcode Command Line Tools."
    xcode-select -p >/dev/null 2>&1 || die "Xcode Command Line Tools not found. Run: xcode-select --install"

    [[ -d "$OBS_APP" ]] || die "OBS Studio not found at $OBS_APP. Install OBS 33 or later first."

    echo "  cmake:  $(cmake --version | head -1)"
    echo "  OBS:    $OBS_VERSION at $OBS_APP"
}

ensure_simde() {
    # libobs/util/sse-intrin.h includes <simde/x86/sse2.h>.
    if [[ -f /opt/homebrew/include/simde/simde-common.h ]] ||
       [[ -f /usr/local/include/simde/simde-common.h ]] ||
       [[ -n "${SIMDE_ROOT:-}" && -f "$SIMDE_ROOT/include/simde/simde-common.h" ]]; then
        echo "SIMDe headers found."
        return
    fi

    command -v brew >/dev/null 2>&1 || die "SIMDe not found. Install Homebrew and run: brew install simde"
    echo "Installing SIMDe headers..."
    brew install simde
}

ensure_obs_headers() {
    if [[ -f "$OBS_DEPS_DIR/libobs/obs.h" ]]; then
        echo "OBS headers already present in deps/obs-studio."
        return
    fi

    echo "Fetching OBS $OBS_VERSION headers..."
    rm -rf "$OBS_DEPS_DIR"
    mkdir -p "$(dirname "$OBS_DEPS_DIR")"

    if ! git clone --depth 1 --branch "$OBS_VERSION" --filter=blob:none --sparse \
        https://github.com/obsproject/obs-studio.git "$OBS_DEPS_DIR"; then
        die "Could not fetch OBS $OBS_VERSION headers. Install the matching OBS version or set OBS_VERSION manually."
    fi

    git -C "$OBS_DEPS_DIR" sparse-checkout set libobs
}

build_plugin() {
    echo ""
    echo "Configuring..."
    cmake -S "$PROJECT_ROOT" -B "$PROJECT_ROOT/build" \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_OSX_ARCHITECTURES="$ARCHITECTURE" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0

    echo ""
    echo "Building..."
    cmake --build "$PROJECT_ROOT/build" --config "$BUILD_TYPE" --parallel
}

package_plugin() {
    local release_dir="$PROJECT_ROOT/release"
    local bundle="$PROJECT_ROOT/build/$PLUGIN_NAME.plugin"
    local archive="$PLUGIN_NAME-v${PLUGIN_VERSION}-macOS-${ARCHITECTURE}.zip"

    [[ -d "$bundle" ]] || die "Build output not found: $bundle"

    echo ""
    echo "Packaging..."
    rm -rf "$release_dir/$PLUGIN_NAME.plugin"
    mkdir -p "$release_dir"
    cp -R "$bundle" "$release_dir/"

    rm -f "$release_dir/$archive"
    ( cd "$release_dir" && COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc "$PLUGIN_NAME.plugin" "$archive" )

    echo "Release bundle: $release_dir/$PLUGIN_NAME.plugin"
    echo "Release archive: $release_dir/$archive"
}

install_plugin() {
    local bundle="$PROJECT_ROOT/build/$PLUGIN_NAME.plugin"
    local plugin_dir="$HOME/Library/Application Support/obs-studio/plugins"

    [[ -d "$bundle" ]] || die "Build output not found: $bundle"

    echo ""
    echo "Installing into $plugin_dir ..."
    mkdir -p "$plugin_dir"
    rm -rf "$plugin_dir/$PLUGIN_NAME.plugin"
    cp -R "$bundle" "$plugin_dir/"

    echo "Installed: $plugin_dir/$PLUGIN_NAME.plugin"
}

check_dependencies
ensure_simde
ensure_obs_headers
build_plugin
package_plugin

if [[ "${1:-}" == "--install" || "${INSTALL:-0}" == "1" ]]; then
    install_plugin
fi

echo ""
echo "============================================"
echo "Build completed successfully"
echo "============================================"
echo ""
if [[ "${1:-}" != "--install" && "${INSTALL:-0}" != "1" ]]; then
    echo "Install with:  ./install.sh"
    echo "Or rebuild and install in one step:"
    echo "  INSTALL=1 ./.github/scripts/build-macos.sh"
    echo ""
fi
