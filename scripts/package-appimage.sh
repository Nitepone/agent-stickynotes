#!/usr/bin/env bash
# Build the release binary and package it as an AppImage.
#
# Needs Qt 6 (QMAKE pointing at qmake6) and linuxdeploy + its qt and appimage
# plugins on PATH: the build container (Dockerfile) has all of it. Run it
# through scripts/build-linux-container.sh rather than on the host.
#
# Output: target/dist/stickynotes-<version>-linux-x86_64.AppImage
# (under $CARGO_TARGET_DIR if that is set). SKIP_BUILD=1 reuses an existing binary.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version="$("$root/scripts/version.sh")"
target_dir="${CARGO_TARGET_DIR:-$root/target}"
dist="$target_dir/dist"
appdir="$target_dir/appimage/AppDir"
out="stickynotes-${version}-linux-x86_64.AppImage"

export QMAKE="${QMAKE:-/usr/lib/qt6/bin/qmake6}"

if [ "${SKIP_BUILD:-0}" != 1 ]; then
    cargo build --release --locked -p stickynotes
fi
bin="$target_dir/release/stickynotes"
[ -x "$bin" ] || { echo "package-appimage: $bin not found" >&2; exit 1; }

rm -rf "$appdir"
# A cached target directory may hold packages from earlier runs; only this one is wanted.
rm -f "$dist"/*.AppImage
mkdir -p "$appdir/usr/bin" "$dist"
install -m 0755 "$bin" "$appdir/usr/bin/stickynotes"
strip "$appdir/usr/bin/stickynotes" || true

# The spell checker reads Hunspell dictionaries from a "dictionaries" folder next
# to the executable (see crates/app/src/editor.rs).
mkdir -p "$appdir/usr/bin/dictionaries"
cp /usr/share/hunspell/en_US.aff /usr/share/hunspell/en_US.dic "$appdir/usr/bin/dictionaries/"

# linuxdeploy copies the shared libraries, the Qt platform plugins and the QML
# modules the views import (it scans QML_SOURCES_PATHS) into the AppDir, then
# the appimage plugin squashes it into one file.
export QML_SOURCES_PATHS="$root/crates/app/qml"
export EXTRA_PLATFORM_PLUGINS="libqwayland-generic.so;libqwayland-egl.so"
export EXTRA_QT_PLUGINS="waylandcompositor;wayland-decoration-client;wayland-graphics-integration-client;wayland-shell-integration;tls"
export LINUXDEPLOY_OUTPUT_VERSION="$version"
export OUTPUT="$dist/$out"
export VERSION="$version"

linuxdeploy-x86_64.AppImage \
    --appdir "$appdir" \
    --executable "$appdir/usr/bin/stickynotes" \
    --desktop-file "$root/scripts/packaging/agent-stickynotes.desktop" \
    --icon-file "$root/scripts/packaging/agent-stickynotes.svg" \
    --icon-filename agent-stickynotes \
    --plugin qt \
    --output appimage

# linuxdeploy-plugin-appimage names the file itself; settle on our name.
if [ ! -f "$dist/$out" ]; then
    built="$(find "$root" "$dist" -maxdepth 1 -name '*.AppImage' -newer "$bin" | head -1)"
    [ -n "$built" ] || { echo "package-appimage: no AppImage was produced" >&2; exit 1; }
    mv "$built" "$dist/$out"
fi
echo "Built $dist/$out"
