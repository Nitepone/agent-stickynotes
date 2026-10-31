#!/usr/bin/env bash
# Build the release binary on macOS and package it as a .dmg.
#
# Needs: Rust, Xcode command line tools and Qt 6 for macOS with `qmake` and
# `macdeployqt` on PATH (CI installs Qt with install-qt-action). Qt's official
# builds are universal, so the architecture is that of the Rust host (arm64 on
# the macos-14 runner).
#
# The app is ad hoc signed (`-codesign=-`), not signed with a Developer ID and not
# notarized, so Gatekeeper asks users to approve it on first launch.
#
# Output: target/dist/stickynotes-<version>-macos-<arch>.dmg
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version="$("$root/scripts/version.sh")"
arch="$(uname -m)"          # arm64 or x86_64
dist="$root/target/dist"
work="$root/target/macos-package"
app="$work/Agent Sticky Notes.app"
# CFBundleVersion must be dotted numbers; drop any "-<sha>" suffix for the plist.
plist_version="${version%%-*}"

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"   # Qt 6.8 minimum
if [ -z "${QMAKE:-}" ]; then
    QMAKE="$(command -v qmake)"
    export QMAKE
fi
command -v macdeployqt >/dev/null || { echo "package-macos: macdeployqt not on PATH" >&2; exit 1; }

if [ "${SKIP_BUILD:-0}" != 1 ]; then
    cargo build --release --locked -p stickynotes
fi
bin="$root/target/release/stickynotes"
[ -x "$bin" ] || { echo "package-macos: $bin not found" >&2; exit 1; }

rm -rf "$work"
rm -f "$dist"/*.dmg     # packages left in a cached target directory
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$dist"
cp "$bin" "$app/Contents/MacOS/stickynotes"
# Dock and Finder icon (CFBundleIconFile below); regenerate with scripts/make-icons.sh.
cp "$root/scripts/packaging/icon.icns" "$app/Contents/Resources/icon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Agent Sticky Notes</string>
    <key>CFBundleDisplayName</key><string>Agent Sticky Notes</string>
    <key>CFBundleIdentifier</key><string>io.github.agent-stickynotes</string>
    <key>CFBundleExecutable</key><string>stickynotes</string>
    <key>CFBundleIconFile</key><string>icon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${plist_version}</string>
    <key>CFBundleVersion</key><string>${plist_version}</string>
    <key>LSMinimumSystemVersion</key><string>${MACOSX_DEPLOYMENT_TARGET}</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Copies the Qt frameworks, plugins and the QML modules the views import into the
# bundle, re-signs it ad hoc and writes "<bundle name>.dmg" next to it.
macdeployqt "$app" -qmldir="$root/crates/app/qml" -codesign=- -dmg

out="$dist/stickynotes-${version}-macos-${arch}.dmg"
mv "$work/Agent Sticky Notes.dmg" "$out"
echo "Built $out"
