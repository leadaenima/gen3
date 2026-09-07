#!/usr/bin/env python3
"""Bake Gen3 (Ruby) trainer card front/back + badges + star + pics from pokeruby.

Validated against misc/pokeruby-master/.../src/trainer_card.c:
  TrainerCard_LoadCardTileMap / sub_8093F48 maps
  TrainerCard_DrawStars (tile 0x8F, pal 83B5F4C)
  TrainerCard_DisplayBadges (83B5F8C_map + badges.png)
  TrainerCard_LoadTrainerTilemap (64x64 at tile 19,5)
  star pals trainer_card_{0..4}star.pal

Outputs under assets/generated/trainer_card/ — no ROM-cache contract bump.
"""
from __future__ import annotations

import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PR = ROOT / "misc" / "pokeruby-master" / "pokeruby-master" / "graphics"
TC = PR / "trainer_card"
TR = PR / "trainers"
OUT = ROOT / "assets" / "generated" / "trainer_card"


def read_jasc(path: Path) -> list[tuple[int, int, int]]:
    lines = path.read_text(encoding="utf-8", errors="replace").strip().splitlines()
    n = int(lines[2])
    cols = []
    for i in range(3, 3 + n):
        parts = lines[i].split()
        cols.append((int(parts[0]), int(parts[1]), int(parts[2])))
    return cols


def tiles_from_indexed(path: Path) -> list[Image.Image]:
    im = Image.open(path)
    if im.mode != "P":
        im = im.convert("P")
    w, h = im.size
    tiles = []
    for ty in range(h // 8):
        for tx in range(w // 8):
            tiles.append(im.crop((tx * 8, ty * 8, tx * 8 + 8, ty * 8 + 8)))
    return tiles


def flip_tile(tile: Image.Image, hflip: bool, vflip: bool) -> Image.Image:
    if hflip:
        tile = tile.transpose(Image.FLIP_LEFT_RIGHT)
    if vflip:
        tile = tile.transpose(Image.FLIP_TOP_BOTTOM)
    return tile


def colorize_tile(
    tile_p: Image.Image,
    pal: list[tuple[int, int, int]],
    *,
    key_zero: bool = False,
) -> Image.Image:
    out = Image.new("RGBA", (8, 8))
    ip = tile_p.load()
    op = out.load()
    for y in range(8):
        for x in range(8):
            idx = ip[x, y] & 0xFF
            if key_zero and idx == 0:
                op[x, y] = (0, 0, 0, 0)
                continue
            if idx >= len(pal):
                idx = len(pal) - 1
            r, g, b = pal[idx]
            op[x, y] = (r, g, b, 255)
    return out


def bake_map(
    tiles_p: list[Image.Image],
    map_path: Path,
    pal16: list[tuple[int, int, int]],
    *,
    key_zero: bool = False,
) -> Image.Image:
    raw = map_path.read_bytes()
    ents = [struct.unpack_from("<H", raw, i)[0] for i in range(0, len(raw), 2)]
    assert len(ents) == 32 * 20, map_path
    colored = [colorize_tile(t, pal16, key_zero=key_zero) for t in tiles_p]
    out = Image.new("RGBA", (256, 160), (0, 0, 0, 255))
    for row in range(20):
        for col in range(32):
            e = ents[row * 32 + col]
            tid = e & 0x3FF
            hflip = bool(e & 0x400)
            vflip = bool(e & 0x800)
            if tid >= len(colored):
                continue
            tile = flip_tile(colored[tid], hflip, vflip)
            out.paste(tile, (col * 8, row * 8), tile)
    return out.crop((0, 0, 240, 160))


def key_index0(im_p: Image.Image, pal: list[tuple[int, int, int]]) -> Image.Image:
    rgba = Image.new("RGBA", im_p.size)
    ip = im_p.load()
    op = rgba.load()
    w, h = im_p.size
    for y in range(h):
        for x in range(w):
            idx = ip[x, y] & 0xFF
            if idx == 0:
                op[x, y] = (0, 0, 0, 0)
            else:
                if idx >= len(pal):
                    idx = len(pal) - 1
                r, g, b = pal[idx]
                op[x, y] = (r, g, b, 255)
    return rgba


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    tiles = tiles_from_indexed(TC / "trainer_card.png")
    assert len(tiles) == 160

    star_gold = read_jasc(TC / "83B5F4C.pal")
    while len(star_gold) < 16:
        star_gold.append((0, 0, 0))

    # Star glyph: tile 0x8F, palette 4 (gold). Index 0 transparent.
    star_tile = colorize_tile(tiles[0x8F], star_gold, key_zero=True)
    star_tile.save(OUT / "ruby_star.png")

    # Badges: 128x16 sheet, 8 x 16x16. Use embedded PNG palette (matches badges.gbapal).
    badges_p = Image.open(TC / "badges.png")
    if badges_p.mode != "P":
        badges_p = badges_p.convert("P")
    bpal = badges_p.getpalette() or []
    badge_colors = []
    for i in range(16):
        if i * 3 + 2 < len(bpal):
            badge_colors.append((bpal[i * 3], bpal[i * 3 + 1], bpal[i * 3 + 2]))
        else:
            badge_colors.append((0, 0, 0))
    badges_rgba = key_index0(badges_p, badge_colors)
    badges_rgba.save(OUT / "ruby_badges.png")

    for stars in range(5):
        full = read_jasc(TC / f"trainer_card_{stars}star.pal")
        pal0 = list(full[:16])
        while len(pal0) < 16:
            pal0.append((0, 0, 0))
        front = bake_map(tiles, TC / "trainer_card_front.map.bin", pal0)
        back = bake_map(tiles, TC / "trainer_card_back.map.bin", pal0)
        front.save(OUT / f"ruby_front_{stars}.png")
        back.save(OUT / f"ruby_back_{stars}.png")
        print(f"baked front/back stars={stars}")

    # Brendan / May front pics (64x64), index 0 keyed.
    for name in ("brendan", "may"):
        src = TR / f"{name}.png"
        im = Image.open(src)
        if im.mode != "P":
            im = im.convert("P")
        pal = im.getpalette() or []
        colors = []
        for i in range(256):
            if i * 3 + 2 < len(pal):
                colors.append((pal[i * 3], pal[i * 3 + 1], pal[i * 3 + 2]))
            else:
                colors.append((0, 0, 0))
        key_index0(im, colors).save(OUT / f"ruby_{name}.png")
        print(f"baked ruby_{name}.png")

    print("done ->", OUT)


if __name__ == "__main__":
    main()
