#!/usr/bin/env bash
# Build the release binary on Windows (MSVC toolchain + Qt 6 for MSVC) and
# bundle it with the Qt runtime into a zip. Run from Git Bash.
#
# Needs: rustc/cargo (x86_64-pc-windows-msvc), Visual Studio Build Tools, and Qt 6
# with `qmake` and `windeployqt` on PATH (CI installs Qt with install-qt-action).
#
# The .exe cannot run alone: Qt is linked dynamically, so windeployqt copies the
# Qt DLLs, plugins, QML modules and MSVC runtime next to it, and the zip holds
# that folder.
#
# Output: target/dist/stickynotes-<version>-windows-x86_64.zip
# Set WINDOWS_CONSOLE=1 to keep the console window (useful to see --help output
# and logs); by default the binary is linked as a GUI application.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version="$("$root/scripts/version.sh")"
dist="$root/target/dist"
name="stickynotes-${version}-windows-x86_64"
stage="$root/target/windows-package/$name"

if ! command -v windeployqt >/dev/null 2>&1; then
    echo "package-windows: windeployqt not on PATH; install Qt 6 (MSVC) and add its bin directory" >&2
    exit 1
fi
if [ -z "${QMAKE:-}" ]; then
    # cxx-qt runs this path with a native Windows process: use C:/... form, not /c/...
    QMAKE="$(cygpath -m "$(command -v qmake)")"
    export QMAKE
fi

if [ "${SKIP_BUILD:-0}" != 1 ]; then
    if [ "${WINDOWS_CONSOLE:-0}" = 1 ]; then
        cargo build --release --locked -p stickynotes --bin stickynotes
    else
        # Only the final executable gets the GUI subsystem flags (build scripts do not).
        cargo rustc --release --locked -p stickynotes --bin stickynotes -- \
            -C link-arg=/SUBSYSTEM:WINDOWS -C link-arg=/ENTRY:mainCRTStartup
    fi
fi
exe="$root/target/release/stickynotes.exe"
[ -f "$exe" ] || { echo "package-windows: $exe not found" >&2; exit 1; }

rm -rf "$stage"
rm -f "$dist"/*.zip     # packages left in a cached target directory
mkdir -p "$stage" "$dist"
cp "$exe" "$stage/stickynotes.exe"

windeployqt --release --compiler-runtime --no-translations \
    --qmldir "$root/crates/app/qml" "$stage/stickynotes.exe"

out="$dist/$name.zip"
rm -f "$out"
if command -v 7z >/dev/null 2>&1; then
    (cd "$stage/.." && 7z a -tzip -mx=6 "$out" "$name" >/dev/null)
elif command -v zip >/dev/null 2>&1; then
    (cd "$stage/.." && zip -qr "$out" "$name")
else
    powershell -NoProfile -Command "Compress-Archive -Path '$(cygpath -w "$stage")' -DestinationPath '$(cygpath -w "$out")'"
fi
echo "Built $out"
