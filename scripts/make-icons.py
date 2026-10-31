#!/usr/bin/env python3
"""Write the Windows .ico and macOS .icns from the SVG artwork.

Run through scripts/make-icons.sh (it sets up a venv with cairosvg and Pillow).

Sizes 32 and up are rendered from agent-stickynotes.svg; 16 px uses the simplified
agent-stickynotes-16.svg, which stays legible at that size. Both containers are
written by hand (PNG-compressed entries), so they do not depend on Pillow's writers.
"""
import io
import struct
import sys
from pathlib import Path

import cairosvg
from PIL import Image

pk = Path(__file__).resolve().parent / "packaging"
FULL, SMALL = pk / "agent-stickynotes.svg", pk / "agent-stickynotes-16.svg"


def render(px: int) -> bytes:
    """PNG bytes at px x px. Rendered at 4x and downsampled for clean edges."""
    src = SMALL if px == 16 else FULL
    big = Image.open(io.BytesIO(cairosvg.svg2png(url=str(src), output_width=px * 4, output_height=px * 4)))
    out = io.BytesIO()
    big.convert("RGBA").resize((px, px), Image.LANCZOS).save(out, "PNG", optimize=True)
    return out.getvalue()


def write_ico(path: Path) -> None:
    sizes = [16, 24, 32, 48, 64, 128, 256]
    pngs = [render(s) for s in sizes]
    head = struct.pack("<HHH", 0, 1, len(sizes))
    offset = 6 + 16 * len(sizes)
    entries = b""
    for s, data in zip(sizes, pngs):
        entries += struct.pack("<BBBBHHII", s % 256, s % 256, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
    path.write_bytes(head + entries + b"".join(pngs))


def write_icns(path: Path) -> None:
    # (type, pixel size): the PNG-based icns entries, 16 px to 1024 px with @2x.
    types = [
        (b"icp4", 16), (b"icp5", 32), (b"icp6", 64), (b"ic07", 128), (b"ic08", 256),
        (b"ic09", 512), (b"ic10", 1024), (b"ic11", 32), (b"ic12", 64), (b"ic13", 256),
        (b"ic14", 512),
    ]
    body = b""
    for t, s in types:
        data = render(s)
        body += t + struct.pack(">I", len(data) + 8) + data
    path.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


def write_window_pngs(folder: Path) -> None:
    """The PNGs the app embeds and sets as its window icon (title bar, taskbar, Dock)."""
    folder.mkdir(exist_ok=True)
    for s in (16, 32, 48, 256):
        (folder / f"window-{s}.png").write_bytes(render(s))


if __name__ == "__main__":
    write_ico(pk / "icon.ico")
    write_icns(pk / "icon.icns")
    write_window_pngs(pk.parent.parent / "crates" / "app" / "icons")
