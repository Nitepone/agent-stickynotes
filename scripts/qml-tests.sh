#!/usr/bin/env bash
# Run the QML view tests headlessly. The views do not depend on the Rust
# controller, so we stage them as a plain QML module for qmltestrunner.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
qml_dir="$root/crates/app/qml"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/StickyNotes"
cp "$qml_dir"/*.qml "$stage/StickyNotes/"
{
    echo "module StickyNotes"
    for f in "$qml_dir"/*.qml; do
        name="$(basename "$f" .qml)"
        [ "$name" = Main ] && continue   # needs the Rust BoardController
        if head -1 "$f" | grep -q "pragma Singleton"; then
            echo "singleton $name 1.0 $name.qml"
        else
            echo "$name 1.0 $name.qml"
        fi
    done
} > "$stage/StickyNotes/qmldir"

runner="${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}"
QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}" QT_QUICK_CONTROLS_STYLE=Fusion \
    "$runner" -import "$stage" -input "$root/crates/app/tests/qml" "$@"
