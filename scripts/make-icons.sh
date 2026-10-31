#!/usr/bin/env bash
# Regenerate scripts/packaging/icon.ico and icon.icns from the SVGs.
# The results are committed; run this only when the artwork changes.
# Needs python3 with venv and the cairo library (cairosvg renders the SVG).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
venv="$(mktemp -d)"
trap 'rm -rf "$venv"' EXIT
python3 -m venv "$venv"
"$venv/bin/pip" install -q cairosvg pillow
"$venv/bin/python" "$root/scripts/make-icons.py"
