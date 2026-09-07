#!/usr/bin/env python3
"""Composite a 240×160 PC box preview and assert layout invariants."""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
PC = ROOT / "assets" / "pc"
OUT = ROOT / "tmp" / "pc_verify"


def tile(dst: Image.Image, src: Image.Image, x0, y0, w, h):
    tw, th = src.size
    for y in range(y0, y0 + h, th):
        for x in range(x0, x0 + w, tw):
            dst.paste(src, (x, y))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    hand = Image.open(PC / "hand_cursor.png").convert("RGBA")
    assert hand.getpixel((0, 0))[3] == 0, "hand cursor pink key failed"
    wp = Image.open(PC / "wallpapers" / "forest.png").convert("RGBA")
    assert wp.size == (160, 144), wp.size
    header = Image.open(PC / "header.png").convert("RGBA")
    assert header.size == (80, 160), header.size
    scroll = Image.open(PC / "scrolling_bg.png").convert("RGBA")

    # --- closed party (WITHDRAW / MOVE default) ---
    closed = Image.new("RGBA", (240, 160), (0, 0, 0, 255))
    tile(closed, scroll, 0, 0, 240, 160)
    closed.paste(wp, (80, 16), wp)
    closed.alpha_composite(header, (0, 0))
    draw = ImageDraw.Draw(closed)
    # 6×5 icon centres
    for i in range(30):
        col, row = i % 6, i // 6
        cx, cy = 0x64 + col * 24, 0x2C + row * 24
        # placeholder mon dots
        if i < 8:
            draw.ellipse((cx - 10, cy - 10, cx + 10, cy + 10), fill=(220, 80, 60, 255))
    # PARTY / CLOSE buttons near (0x78,14) / (0xd0,14)
    draw.rectangle((0x78 - 28, 14 - 8, 0x78 + 28, 14 + 10), outline=(20, 20, 30), fill=(248, 248, 248))
    draw.rectangle((0xD0 - 28, 14 - 8, 0xD0 + 28, 14 + 10), outline=(20, 20, 30), fill=(248, 248, 248))
    # hand over slot 0
    cx, cy = 0x64, 0x2C
    hand0 = hand.crop((0, 0, 32, 32))
    closed.alpha_composite(hand0, (cx - 16, cy - 12 - 16))
    # msg window
    draw.rectangle((80, 128, 232, 152), outline=(40, 80, 160), fill=(248, 248, 248))
    closed_path = OUT / "box_closed.png"
    closed.convert("RGB").save(closed_path)

    # --- party open ---
    opened = closed.copy()
    draw = ImageDraw.Draw(opened)
    for x in range(88, 192, 4):
        color = (148, 214, 107) if ((x - 88) // 4) % 2 == 0 else (122, 189, 128)
        draw.rectangle((x, 0, x + 3, 143), fill=color)
    opened_path = OUT / "box_party_open.png"
    opened.convert("RGB").save(opened_path)

    # Invariants against the closed shot
    px = closed.load()
    # Wallpaper green should be visible mid-box (not covered by white party panel)
    r, g, b = px[160, 80][:3]
    assert g > r and g > 80, f"wallpaper not visible at mid-box: {(r,g,b)}"
    # Hand area should not be solid pink
    pr, pg, pb = px[cx, cy - 8][:3]
    assert not (pr > 200 and pb > 200 and pg < 210), f"pink hand backdrop still present: {(pr,pg,pb)}"
    # Header present on left
    hr, hg, hb = px[40, 8][:3]
    assert not (hr == 0 and hg == 0 and hb == 0), "header missing"

    print("ok", closed_path)
    print("ok", opened_path)


if __name__ == "__main__":
    main()
