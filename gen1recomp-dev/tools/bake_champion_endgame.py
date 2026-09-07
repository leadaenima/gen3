#!/usr/bin/env python3
"""Bake Gen3 champion mugshot BG + credits bike daypart sheets from pokeruby.

Validated against:
  graphics/battle_transitions/elite_four_bg{,_map.bin} + *_bg.pal
  (battle_transition.c Phase2_Mugshot_Func2)
  graphics/intro/intro2_* + 8412818/8412878/8413E38 pals
  (credits.c LoadBikeScene / intro_credits_graphics.c sub_8148CB0)

Outputs under assets/generated/ — no ROM-cache contract bump.
"""
from __future__ import annotations

import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PR = ROOT / "misc" / "pokeruby-master" / "pokeruby-master" / "graphics"
BT = PR / "battle_transitions"
INTRO = PR / "intro"
OUT_BT = ROOT / "assets" / "generated" / "battle" / "transitions"
OUT_CR = ROOT / "assets" / "generated" / "credits"


def read_jasc(path: Path) -> list[tuple[int, int, int]]:
    lines = path.read_text(encoding="utf-8", errors="replace").strip().splitlines()
    n = int(lines[2])
    cols = []
    for i in range(3, 3 + n):
        parts = lines[i].split()
        cols.append((int(parts[0]), int(parts[1]), int(parts[2])))
    return cols


def tiles_from_gray_strip(path: Path) -> list[Image.Image]:
    """elite_four_bg.png: L-mode strip, index = gray // 17."""
    im = Image.open(path).convert("L")
    w, h = im.size
    tiles = []
    for ty in range(h // 8):
        for tx in range(w // 8):
            tiles.append(im.crop((tx * 8, ty * 8, tx * 8 + 8, ty * 8 + 8)))
    return tiles


def tiles_from_indexed(
    path: Path,
    pal: list[tuple[int, int, int]] | None = None,
    *,
    key_zero_alpha: bool = False,
) -> list[Image.Image]:
    im = Image.open(path)
    if im.mode != "P":
        im = im.convert("P")
    # Preserve indices before optional palette swap so we can key transparency.
    idxs = im.copy()
    if pal is not None:
        flat = []
        for rgb in pal[:256]:
            flat.extend(rgb)
        while len(flat) < 768:
            flat.extend((0, 0, 0))
        im.putpalette(flat)
    rgba = im.convert("RGBA")
    if key_zero_alpha:
        ipx = idxs.load()
        opx = rgba.load()
        w, h = rgba.size
        for y in range(h):
            for x in range(w):
                if ipx[x, y] == 0:
                    r, g, b, _a = opx[x, y]
                    opx[x, y] = (r, g, b, 0)
    w, h = rgba.size
    tiles = []
    for ty in range(h // 8):
        for tx in range(w // 8):
            tiles.append(rgba.crop((tx * 8, ty * 8, tx * 8 + 8, ty * 8 + 8)))
    return tiles


def flip_tile(tile: Image.Image, hflip: bool, vflip: bool) -> Image.Image:
    if hflip:
        tile = tile.transpose(Image.FLIP_LEFT_RIGHT)
    if vflip:
        tile = tile.transpose(Image.FLIP_TOP_BOTTOM)
    return tile


def colorize_gray_tile(tile_l: Image.Image, pal: list[tuple[int, int, int]]) -> Image.Image:
    out = Image.new("RGBA", (8, 8))
    px = tile_l.load()
    op = out.load()
    for y in range(8):
        for x in range(8):
            idx = px[x, y] // 17
            if idx < 0:
                idx = 0
            if idx >= len(pal):
                idx = len(pal) - 1
            r, g, b = pal[idx]
            # index 0 is usually transparent-ish for overlays; keep opaque for BG
            op[x, y] = (r, g, b, 255)
    return out


def bake_mugshot_bgs() -> None:
    OUT_BT.mkdir(parents=True, exist_ok=True)
    strip = tiles_from_gray_strip(BT / "elite_four_bg.png")
    tm = (BT / "elite_four_bg_map.bin").read_bytes()
    ents = [struct.unpack_from("<H", tm, i)[0] for i in range(0, len(tm), 2)]
    assert len(ents) == 32 * 20

    names = ["sidney", "phoebe", "glacia", "drake", "steven"]
    player_brendan = read_jasc(BT / "brendan_bg.pal")
    player_may = read_jasc(BT / "may_bg.pal")

    # Also keep raw tile strip + map reference copies for debugging / future.
    Image.open(BT / "elite_four_bg.png").save(OUT_BT / "elite_four_bg.png")
    (OUT_BT / "elite_four_bg_map.bin").write_bytes(tm)

    for name in names:
        opp = read_jasc(BT / f"{name}_bg.pal")
        # Merge player (Brendan) colors into slots 10..15 like LoadPalette 0xFA, 0xC.
        pal = list(opp[:16])
        while len(pal) < 16:
            pal.append((0, 0, 0))
        for i, c in enumerate(player_brendan[:6]):
            pal[10 + i] = c

        colored = [colorize_gray_tile(t, pal) for t in strip]
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
                out.paste(tile, (col * 8, row * 8))
        # Visible screen is 240x160; keep full 256 for wrap, also save cropped.
        out.save(OUT_BT / f"mugshot_bg_{name}.png")
        out.crop((0, 0, 240, 160)).save(OUT_BT / f"mugshot_bg_{name}_240.png")

        # May variant (optional gender tint on BG right-band indices).
        pal_m = list(opp[:16])
        while len(pal_m) < 16:
            pal_m.append((0, 0, 0))
        for i, c in enumerate(player_may[:6]):
            pal_m[10 + i] = c
        colored_m = [colorize_gray_tile(t, pal_m) for t in strip]
        out_m = Image.new("RGBA", (256, 160), (0, 0, 0, 255))
        for row in range(20):
            for col in range(32):
                e = ents[row * 32 + col]
                tid = e & 0x3FF
                if tid >= len(colored_m):
                    continue
                tile = flip_tile(colored_m[tid], bool(e & 0x400), bool(e & 0x800))
                out_m.paste(tile, (col * 8, row * 8))
        out_m.crop((0, 0, 240, 160)).save(OUT_BT / f"mugshot_bg_{name}_may.png")

    # Copy vs / frame / steven mugshot if present in pokeruby tree.
    for fname in ("vs.png", "vs_frame.png"):
        src = BT / fname
        if src.exists():
            Image.open(src).save(OUT_BT / fname)


def render_tilemap(
    tiles: list[Image.Image],
    map_path: Path,
    width_tiles: int,
    height_tiles: int,
    multi_bank_pals: list[list[tuple[int, int, int]]] | None = None,
) -> Image.Image:
    data = map_path.read_bytes()
    ents = [struct.unpack_from("<H", data, i)[0] for i in range(0, len(data), 2)]
    assert len(ents) >= width_tiles * height_tiles
    out = Image.new("RGBA", (width_tiles * 8, height_tiles * 8), (0, 0, 0, 0))

    # If multi-bank pals provided, rebuild colored tiles per bank from first tile set's indices.
    # For indexed-sourced tiles we already baked one palette; for multi-bank we need index maps.
    # Simpler path: tiles already RGBA for bank 0; for other banks recolor via a gray base if given.
    for row in range(height_tiles):
        for col in range(width_tiles):
            e = ents[row * width_tiles + col]
            tid = e & 0x3FF
            bank = (e >> 12) & 0xF
            if tid >= len(tiles):
                continue
            tile = flip_tile(tiles[tid], bool(e & 0x400), bool(e & 0x800))
            # bank 15 for grass maps often means "use sprite pal" — tiles already colored.
            out.paste(tile, (col * 8, row * 8), tile if tile.mode == "RGBA" else None)
    return out


def tiles_from_indexed_multibank(
    path: Path, banks: list[list[tuple[int, int, int]]]
) -> dict[int, list[Image.Image]]:
    """Return {bank: tiles[]} using the same index map under each bank palette."""
    im = Image.open(path)
    if im.mode != "P":
        im = im.convert("P")
    idxs = im.copy()
    result = {}
    for bi, pal in enumerate(banks):
        flat = []
        for rgb in pal[:256]:
            flat.extend(rgb)
        while len(flat) < 768:
            flat.extend((0, 0, 0))
        colored = idxs.copy()
        colored.putpalette(flat)
        rgba = colored.convert("RGBA")
        # Key pure black (index 0 typical) to alpha for overlay layers? Keep opaque for BG.
        w, h = rgba.size
        tiles = []
        for ty in range(h // 8):
            for tx in range(w // 8):
                tiles.append(rgba.crop((tx * 8, ty * 8, tx * 8 + 8, ty * 8 + 8)))
        result[bi] = tiles
    return result


def render_tilemap_multibank(
    bank_tiles: dict[int, list[Image.Image]],
    map_path: Path,
    width_tiles: int,
    height_tiles: int,
) -> Image.Image:
    data = map_path.read_bytes()
    ents = [struct.unpack_from("<H", data, i)[0] for i in range(0, len(data), 2)]
    out = Image.new("RGBA", (width_tiles * 8, height_tiles * 8), (0, 0, 0, 255))
    fallback = bank_tiles.get(0) or next(iter(bank_tiles.values()))
    for row in range(height_tiles):
        for col in range(width_tiles):
            e = ents[row * width_tiles + col]
            tid = e & 0x3FF
            bank = (e >> 12) & 0xF
            tiles = bank_tiles.get(bank, fallback)
            if tid >= len(tiles):
                continue
            tile = flip_tile(tiles[tid], bool(e & 0x400), bool(e & 0x800))
            out.paste(tile, (col * 8, row * 8))
    return out


def chunk_pal(cols: list[tuple[int, int, int]], n: int = 16) -> list[list[tuple[int, int, int]]]:
    banks = []
    for i in range(0, len(cols), n):
        banks.append(cols[i : i + n])
    return banks


def indexed_sheet_to_rgba(path: Path, *, key_zero_alpha: bool = True) -> Image.Image:
    """OBJ sheets: palette index 0 is transparent on GBA."""
    im = Image.open(path)
    if im.mode != "P":
        return im.convert("RGBA")
    idxs = im.copy()
    rgba = im.convert("RGBA")
    if key_zero_alpha:
        ipx = idxs.load()
        opx = rgba.load()
        w, h = rgba.size
        for y in range(h):
            for x in range(w):
                if ipx[x, y] == 0:
                    r, g, b, _a = opx[x, y]
                    opx[x, y] = (r, g, b, 0)
    return rgba


# LoadBikeScene sets gUnknown_02039358 = 34; BG*VOFS uses that window.
CREDITS_VOFS = 34


def crop_vofs(im: Image.Image, vofs: int = CREDITS_VOFS, height: int = 160) -> Image.Image:
    """Match GBA visible window: map y = vofs .. vofs+height."""
    w, h = im.size
    y0 = max(0, min(vofs, max(0, h - 1)))
    y1 = min(h, y0 + height)
    out = Image.new("RGBA", (w, height), (0, 0, 0, 0))
    out.paste(im.crop((0, y0, w, y1)), (0, 0))
    return out


def bake_credits_bike() -> None:
    OUT_CR.mkdir(parents=True, exist_ok=True)

    # --- Ocean morning (sub_8148CB0 case 0): clouds + 8412818 (3 banks) + grass ---
    clouds_morning = chunk_pal(read_jasc(INTRO / "8412818.pal"), 16)
    cloud_tiles_m = tiles_from_indexed_multibank(INTRO / "intro2_bgclouds.png", clouds_morning)
    # Map is 64x32 (4096 bytes)
    ocean_m = render_tilemap_multibank(cloud_tiles_m, INTRO / "intro2_bgclouds_map.bin", 64, 32)
    crop_vofs(ocean_m).save(OUT_CR / "bike_ocean_morning.png")

    # Grass: key tile index 0 transparent (BG1 overlay), apply VOFS window.
    grass_tiles = tiles_from_indexed(INTRO / "intro2_grass.png", key_zero_alpha=True)
    grass = render_tilemap(grass_tiles, INTRO / "intro2_grass_map.bin", 32, 32)
    crop_vofs(grass).save(OUT_CR / "bike_grass_morning.png")

    # --- Ocean sunset (case 1): clouds + 8412878 + grass afternoon ---
    clouds_sunset = chunk_pal(read_jasc(INTRO / "8412878.pal"), 16)
    cloud_tiles_s = tiles_from_indexed_multibank(INTRO / "intro2_bgclouds.png", clouds_sunset)
    ocean_s = render_tilemap_multibank(cloud_tiles_s, INTRO / "intro2_bgclouds_map.bin", 64, 32)
    crop_vofs(ocean_s).save(OUT_CR / "bike_ocean_sunset.png")

    grass_aft = tiles_from_indexed(
        INTRO / "intro2_grass.png",
        read_jasc(INTRO / "intro2_grass_afternoon.pal"),
        key_zero_alpha=True,
    )
    crop_vofs(render_tilemap(grass_aft, INTRO / "intro2_grass_map.bin", 32, 32)).save(
        OUT_CR / "bike_grass_afternoon.png"
    )

    # --- Forest sunset (case 2/3): trees + afternoon pal + grass afternoon ---
    trees_pal = read_jasc(INTRO / "intro2_bgtrees2_afternoon.pal")
    tree_tiles = tiles_from_indexed(INTRO / "intro2_bgtrees.png", trees_pal)
    forest = render_tilemap(tree_tiles, INTRO / "intro2_bgtrees_map.bin", 64, 32)
    crop_vofs(forest).save(OUT_CR / "bike_forest_sunset.png")

    # --- Town night (case 4): bgnight + 8413E38 + grass night ---
    night_banks = chunk_pal(read_jasc(INTRO / "8413E38.pal"), 16)
    # bgnight sheet is small; pad banks if only one
    while len(night_banks) < 2:
        night_banks.append(night_banks[0] if night_banks else [(0, 0, 0)] * 16)
    night_tiles = tiles_from_indexed_multibank(INTRO / "intro2_bgnight.png", night_banks[:2])
    town = render_tilemap_multibank(night_tiles, INTRO / "intro2_bgnight_map.bin", 64, 32)
    crop_vofs(town).save(OUT_CR / "bike_town_night.png")

    grass_night = tiles_from_indexed(
        INTRO / "intro2_grass.png",
        read_jasc(INTRO / "intro2_grass_night.pal"),
        key_zero_alpha=True,
    )
    crop_vofs(render_tilemap(grass_night, INTRO / "intro2_grass_map.bin", 32, 32)).save(
        OUT_CR / "bike_grass_night.png"
    )

    # Cyclist sheets (OBJ) — index 0 transparent so padding is not a black box.
    for src_name, dst_name in (
        ("intro2_bicycle.png", "bike.png"),
        ("intro2_brendan.png", "brendan.png"),
        ("intro2_may.png", "may.png"),
    ):
        indexed_sheet_to_rgba(INTRO / src_name, key_zero_alpha=True).save(OUT_CR / dst_name)

    # Keep the_end if present; otherwise leave existing.
    the_end_src = PR / "credits"
    # pokeruby has ampersand only; port already has the_end.png stub.


def main() -> None:
    bake_mugshot_bgs()
    bake_credits_bike()
    print("baked mugshot BGs ->", OUT_BT)
    print("baked credits bike dayparts ->", OUT_CR)
    for p in sorted(OUT_BT.glob("mugshot_bg_*.png")):
        im = Image.open(p)
        print(f"  {p.name} {im.size}")
    for p in sorted(OUT_CR.glob("bike_*.png")):
        im = Image.open(p)
        print(f"  {p.name} {im.size}")


if __name__ == "__main__":
    main()
