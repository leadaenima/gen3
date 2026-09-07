#!/usr/bin/env python3
"""Bake Ruby PSS chrome from pokeruby graphics/pokemon_storage into assets/pc/."""
from __future__ import annotations

import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "misc" / "pokeruby-master" / "pokeruby-master" / "graphics" / "pokemon_storage"
OUT = ROOT / "assets" / "pc"

FRAME_TILES = {
    "forest": 49, "city": 37, "desert": 48, "savanna": 40, "crag": 46,
    "volcano": 49, "snow": 46, "cave": 57, "beach": 48, "seafloor": 45,
    "river": 57, "sky": 45, "polkadot": 34, "pokecenter": None,
    "machine": 46, "plain": 18,
}
NAMES = list(FRAME_TILES.keys())


def tiles_from_png(path: Path, max_tiles=None):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    tiles = []
    for ty in range(h // 8):
        for tx in range(w // 8):
            tiles.append(im.crop((tx * 8, ty * 8, tx * 8 + 8, ty * 8 + 8)))
            if max_tiles is not None and len(tiles) >= max_tiles:
                return tiles
    return tiles


def flip(tile, hflip, vflip):
    if hflip:
        tile = tile.transpose(Image.FLIP_LEFT_RIGHT)
    if vflip:
        tile = tile.transpose(Image.FLIP_TOP_BOTTOM)
    return tile


def key_rgba(im: Image.Image, keys) -> Image.Image:
    im = im.convert("RGBA")
    px = im.load()
    keys = set(keys)
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, _ = px[x, y]
            if (r, g, b) in keys:
                px[x, y] = (0, 0, 0, 0)
    return im


def bake_wallpaper(name: str):
    # forest.4bpp = cat(frame.4bpp, bg.4bpp). Tile index 0 is the first
    # frame tile — do NOT prepend a blank or every cell is off-by-one.
    tiles = []
    frame = SRC / f"{name}_frame.png"
    bg = SRC / f"{name}_bg.png"
    if frame.exists():
        tiles += tiles_from_png(frame, FRAME_TILES[name])
    if bg.exists():
        tiles += tiles_from_png(bg, 38 if name == "pokecenter" else None)
    tm = (SRC / f"{name}.bin").read_bytes()
    out = Image.new("RGBA", (160, 144), (0, 0, 0, 0))
    for i in range(360):
        entry = struct.unpack_from("<H", tm, i * 2)[0]
        tid = entry & 0x3FF
        if tid == 0 or tid >= len(tiles):
            continue
        t = flip(tiles[tid], bool(entry & 0x400), bool(entry & 0x800))
        out.paste(t, ((i % 20) * 8, (i // 20) * 8), t)
    out.save(OUT / "wallpapers" / f"{name}.png")


def bake_header():
    base = 0x280
    ht = tiles_from_png(SRC / "header.png", 47)
    hdr = (SRC / "header.bin").read_bytes()
    full = Image.new("RGBA", (256, 160), (0, 0, 0, 0))
    for i in range(640):
        entry = struct.unpack_from("<H", hdr, i * 2)[0]
        tid = (entry & 0x3FF) - base
        if tid < 0 or tid >= len(ht):
            continue
        t = flip(ht[tid], bool(entry & 0x400), bool(entry & 0x800))
        full.paste(t, ((i % 32) * 8, (i // 32) * 8), t)
    full.crop((0, 0, 80, 160)).save(OUT / "header.png")


def load_jasc(path: Path):
    lines = path.read_text(encoding="ascii", errors="ignore").splitlines()
    n = int(lines[2])
    return [tuple(map(int, lines[3 + i].split()[:3])) for i in range(n)]


def nearest_idx(gray: int, pal):
    best, best_d = 0, 10**9
    for i, c in enumerate(pal):
        lum = (c[0] + c[1] + c[2]) // 3
        d = (lum - gray) * (lum - gray)
        if c == (0, 0, 0) and gray > 8:
            d += 50000
        if d < best_d:
            best_d, best = d, i
    return best


def png_index(gray: int) -> int:
    """pret L-mode graphics store palette index as gray≈index*17."""
    return max(0, min(15, (int(gray) + 8) // 17))


def expand_pal(pal):
    """JASC dumps often leave high slots black; misc1 buttons use indices 8–15."""
    out = list(pal) + [(0, 0, 0)] * (16 - len(pal))
    out = out[:16]
    if all(c == (0, 0, 0) for c in out[8:]):
        for i in range(8):
            out[8 + i] = out[i]
    if all(c == (0, 0, 0) for c in out[12:]):
        for i in range(4):
            src = out[8 + i] if out[8 + i] != (0, 0, 0) else out[4 + i]
            out[12 + i] = src
    return out


def bake_misc1():
    """Party panel / closed bar / CLOSE BOX button from misc1 tilemap.

    Open party: 12×22 tiles from (0,0) → screen (80,0).
    Closed bar: 12×2 from (0,20) = PARTY POKEMON tab (this IS the party button).
    CLOSE BOX: 9×2 normal at (12,0), flash at (12,2) → screen tile (21,0)=(168,0).
    There is no separate PARTY button graphic in the ROM.
    """
    pals = {
        0: expand_pal(load_jasc(SRC / "menu1.pal")),
        1: expand_pal(load_jasc(SRC / "menu1.pal")),
        2: expand_pal(load_jasc(SRC / "menu3.pal")),
        3: expand_pal(load_jasc(SRC / "menu4.pal")),
    }
    raw = Image.open(SRC / "misc1.png")
    bank_tiles = {}
    for bank, pal in pals.items():
        key0 = pal[0]
        rgba = Image.new("RGBA", raw.size)
        px, outpx = raw.load(), rgba.load()
        for y in range(raw.height):
            for x in range(raw.width):
                g = px[x, y]
                if isinstance(g, tuple):
                    g = g[0]
                idx = png_index(g)
                c = pal[idx]
                # Index 0 (and mirrored pink key) = transparent.
                if idx == 0 or c == key0 == (255, 197, 255) or (
                    bank == 3 and c == (255, 197, 255)
                ):
                    outpx[x, y] = (0, 0, 0, 0)
                    continue
                outpx[x, y] = (c[0], c[1], c[2], 255)
        tiles = []
        w, h = rgba.size
        for ty in range(h // 8):
            for tx in range(w // 8):
                tiles.append(rgba.crop((tx * 8, ty * 8, tx * 8 + 8, ty * 8 + 8)))
                if len(tiles) >= 91:
                    break
            if len(tiles) >= 91:
                break
        bank_tiles[bank] = tiles

    base = 0x340
    mb = (SRC / "misc1.bin").read_bytes()

    def blit_region(x0, y0, tw, th):
        img = Image.new("RGBA", (tw * 8, th * 8), (0, 0, 0, 0))
        for row in range(th):
            for col in range(tw):
                i = (y0 + row) * 32 + (x0 + col)
                entry = struct.unpack_from("<H", mb, i * 2)[0]
                tid = (entry & 0x3FF) - base
                bank = (entry >> 12) & 0xF
                tiles = bank_tiles.get(bank) or bank_tiles[0]
                if tid < 0 or tid >= len(tiles):
                    continue
                t = flip(tiles[tid], bool(entry & 0x400), bool(entry & 0x800))
                img.paste(t, (col * 8, row * 8), t)
        return img

    blit_region(0, 0, 12, 22).save(OUT / "party_panel.png")
    bar = blit_region(0, 20, 12, 2)
    # Trailing cols use filler tile 45 — clear so BOX title/arrows stay visible.
    px = bar.load()
    for y in range(bar.height):
        for x in range(72, bar.width):  # last 3 tiles
            px[x, y] = (0, 0, 0, 0)
    bar.save(OUT / "party_close_bar.png")
    blit_region(12, 0, 9, 2).save(OUT / "btn_close.png")
    blit_region(12, 2, 9, 2).save(OUT / "btn_close_flash.png")
    for stale in ("btn_party.png",):
        p = OUT / stale
        if p.exists():
            p.unlink()


def copy_chrome():
    hand = Image.open(SRC / "hand_cursor.png")
    key_rgba(hand, {(255, 197, 255), (255, 0, 255)}).save(OUT / "hand_cursor.png")
    shadow = Image.open(SRC / "hand_cursor_shadow.png")
    key_rgba(shadow, {(255, 197, 255), (255, 0, 255), (0, 0, 0)}).save(
        OUT / "hand_cursor_shadow.png"
    )
    arrow = Image.open(SRC / "arrow.png")
    key_rgba(arrow, {(0, 0, 0)}).save(OUT / "arrow.png")
    for name in (
        "scrolling_bg.png",
        "waveform.png",
        "box_selection_popup_center.png",
        "box_selection_popup_sides.png",
    ):
        Image.open(SRC / name).save(OUT / name)


def main():
    if not SRC.is_dir():
        raise SystemExit(f"missing pokeruby graphics at {SRC}")
    (OUT / "wallpapers").mkdir(parents=True, exist_ok=True)
    for name in NAMES:
        bake_wallpaper(name)
        print("wallpaper", name)
    bake_header()
    print("header")
    bake_misc1()
    print("misc1 party/buttons")
    copy_chrome()
    print("chrome ->", OUT)


if __name__ == "__main__":
    main()
