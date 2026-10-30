#!/usr/bin/env bash
# Install agent-stickynotes for the current user: the binary (cargo install),
# plus the desktop entry and icon so it shows up in the application menu.
#
# Needs Rust and the Qt 6 development packages (see the README).
# The binary goes to ~/.cargo/bin, the menu entry and icon under ~/.local/share;
# remove it with scripts/install-linux.sh --uninstall.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
cargo_root="${CARGO_INSTALL_ROOT:-${CARGO_HOME:-$HOME/.cargo}}"
desktop="$data/applications/agent-stickynotes.desktop"
icon="$data/icons/hicolor/scalable/apps/agent-stickynotes.svg"

case "${1:-}" in
    "" | --uninstall) ;;
    *) echo "usage: $0 [--uninstall]" >&2; exit 2 ;;
esac

if [ "${1:-}" = "--uninstall" ]; then
    cargo uninstall stickynotes --root "$cargo_root" || true
    rm -f "$desktop" "$icon"
    echo "Removed. Your projects are untouched."
    exit 0
fi

export QMAKE="${QMAKE:-/usr/lib/qt6/bin/qmake6}"
cargo install --path "$root/crates/app" --locked --root "$cargo_root"

mkdir -p "$(dirname "$desktop")" "$(dirname "$icon")"
cp "$root/scripts/packaging/agent-stickynotes.svg" "$icon"
# Menu launchers often lack ~/.cargo/bin on their PATH, so name the binary in full.
sed "s|^Exec=.*|Exec=$cargo_root/bin/stickynotes|" \
    "$root/scripts/packaging/agent-stickynotes.desktop" > "$desktop"
command -v update-desktop-database >/dev/null && update-desktop-database "$data/applications" || true

echo "Installed $cargo_root/bin/stickynotes and the menu entry '$desktop'."
