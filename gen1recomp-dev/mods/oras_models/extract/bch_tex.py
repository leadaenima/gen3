#!/usr/bin/env python3
"""BCH + BCLIM (CLIM) texture ripper for ORAS — pure Python, cache-only PNGs.

Based on gdkchan Ohana3DS-Rebirth (BCH relocation, PICA tex cmds, TextureCodec)
and NW4C BCLIM imag/CLIM footer layout. Never writes into mods/*/assets or git.
"""
from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image

# PICA / BCH texture format (Ohana OTextureFormat)
FMT_RGBA8, FMT_RGB8, FMT_RGBA5551, FMT_RGB565 = 0, 1, 2, 3
FMT_RGBA4, FMT_LA8, FMT_HILO8, FMT_L8 = 4, 5, 6, 7
FMT_A8, FMT_LA4, FMT_L4, FMT_A4 = 8, 9, 10, 11
FMT_ETC1, FMT_ETC1A4 = 12, 13

BCH_FMT_NAMES = {
    0: "rgba8", 1: "rgb8", 2: "rgba5551", 3: "rgb565", 4: "rgba4",
    5: "la8", 6: "hilo8", 7: "l8", 8: "a8", 9: "la4", 10: "l4",
    11: "a4", 12: "etc1", 13: "etc1a4",
}

# BCLIM / NW4C imag format enum (different from BCH!)
BCLIM_TO_BCH = {
    0: FMT_L8, 1: FMT_A8, 2: FMT_LA4, 3: FMT_LA8, 4: FMT_HILO8,
    5: FMT_RGB565, 6: FMT_RGB8, 7: FMT_RGBA5551, 8: FMT_RGBA4, 9: FMT_RGBA8,
    10: FMT_ETC1, 11: FMT_ETC1A4, 12: FMT_L4, 13: FMT_A4,
}

TILE_ORDER = [
    0, 1, 8, 9, 2, 3, 10, 11, 16, 17, 24, 25, 18, 19, 26, 27,
    4, 5, 12, 13, 6, 7, 14, 15, 20, 21, 28, 29, 22, 23, 30, 31,
    32, 33, 40, 41, 34, 35, 42, 43, 48, 49, 56, 57, 50, 51, 58, 59,
    36, 37, 44, 45, 38, 39, 46, 47, 52, 53, 60, 61, 54, 55, 62, 63,
]

ETC1_LUT = [
    [2, 8, -2, -8], [5, 17, -5, -17], [9, 29, -9, -29], [13, 42, -13, -42],
    [18, 60, -18, -60], [24, 80, -24, -80], [33, 106, -33, -106], [47, 183, -47, -183],
]

# PICA register IDs
REG_TEX0_SIZE = 0x82
REG_TEX0_ADDR = 0x85
REG_TEX0_TYPE = 0x8E


def _bpp(fmt: int) -> float:
    return {
        0: 32, 1: 24, 2: 16, 3: 16, 4: 16, 5: 16, 6: 16, 7: 8,
        8: 8, 9: 8, 10: 4, 11: 4, 12: 4, 13: 8,
    }.get(fmt, 32)


def _tex_data_size(w: int, h: int, fmt: int) -> int:
    return int(w * h * _bpp(fmt) / 8)


def _sat(v: int) -> int:
    return 0 if v < 0 else 255 if v > 255 else v


def _etc1_scramble(width: int, height: int) -> list[int]:
    n = (width // 4) * (height // 4)
    out = [0] * n
    base_acc = row_acc = base_n = row_n = 0
    for tile in range(n):
        if tile % (width // 4) == 0 and tile > 0:
            if row_acc < 1:
                row_acc += 1
                row_n += 2
                base_n = row_n
            else:
                row_acc = 0
                base_n -= 2
                row_n = base_n
        out[tile] = base_n
        if base_acc < 1:
            base_acc += 1
            base_n += 1
        else:
            base_acc = 0
            base_n += 3
    return out


def _etc1_pixel(r: int, g: int, b: int, x: int, y: int, block: int, table: int) -> tuple[int, int, int]:
    index = x * 4 + y
    msb = block << 1
    if index < 8:
        pixel = ETC1_LUT[table][((block >> (index + 24)) & 1) + ((msb >> (index + 8)) & 2)]
    else:
        pixel = ETC1_LUT[table][((block >> (index + 8)) & 1) + ((msb >> (index - 8)) & 2)]
    return _sat(r + pixel), _sat(g + pixel), _sat(b + pixel)


def _etc1_decode_block(data: bytes) -> bytes:
    top = struct.unpack_from("<I", data, 0)[0]
    bottom = struct.unpack_from("<I", data, 4)[0]
    flip = (top & 0x1000000) > 0
    diff = (top & 0x2000000) > 0
    if diff:
        r1 = top & 0xF8
        g1 = (top & 0xF800) >> 8
        b1 = (top & 0xF80000) >> 16
        r2 = ((r1 >> 3) + (((top & 7) << 5) >> 5)) & 0xFF
        # signed 3-bit add — match Ohana sbyte trick
        def s3(v: int) -> int:
            v &= 7
            return v - 8 if v >= 4 else v
        r2 = ((r1 >> 3) + s3(top & 7)) & 0xFF
        g2 = ((g1 >> 3) + s3((top & 0x700) >> 8)) & 0xFF
        b2 = ((b1 >> 3) + s3((top & 0x70000) >> 16)) & 0xFF
        # Ohana uses sbyte cast on shifted values — reimplement carefully:
        r1b = r1 >> 3
        g1b = g1 >> 3
        b1b = b1 >> 3
        dr = top & 7
        dg = (top & 0x700) >> 8
        db = (top & 0x70000) >> 16
        # sign-extend 3-bit
        dr = dr - 8 if dr & 4 else dr
        dg = dg - 8 if dg & 4 else dg
        db = db - 8 if db & 4 else db
        r2 = r1b + dr
        g2 = g1b + dg
        b2 = b1b + db
        r1 = r1 | (r1 >> 5)
        g1 = g1 | (g1 >> 5)
        b1 = b1 | (b1 >> 5)
        r2 = ((r2 << 3) | (r2 >> 2)) & 0xFF
        g2 = ((g2 << 3) | (g2 >> 2)) & 0xFF
        b2 = ((b2 << 3) | (b2 >> 2)) & 0xFF
    else:
        r1 = top & 0xF0
        g1 = (top & 0xF000) >> 8
        b1 = (top & 0xF00000) >> 16
        r2 = (top & 0xF) << 4
        g2 = (top & 0xF00) >> 4
        b2 = (top & 0xF0000) >> 12
        r1 |= r1 >> 4
        g1 |= g1 >> 4
        b1 |= b1 >> 4
        r2 |= r2 >> 4
        g2 |= g2 >> 4
        b2 |= b2 >> 4
    table1 = (top >> 29) & 7
    table2 = (top >> 26) & 7
    out = bytearray(64)
    if not flip:
        for y in range(4):
            for x in range(2):
                c1 = _etc1_pixel(r1, g1, b1, x, y, bottom, table1)
                c2 = _etc1_pixel(r2, g2, b2, x + 2, y, bottom, table2)
                o1 = (y * 4 + x) * 4
                out[o1:o1 + 3] = bytes((c1[2], c1[1], c1[0]))  # BGR like Ohana then we swap
                # Ohana stores B,G,R in output then TextureUtils interprets — we'll use RGB
                out[o1] = c1[0]
                out[o1 + 1] = c1[1]
                out[o1 + 2] = c1[2]
                o2 = (y * 4 + x + 2) * 4
                out[o2] = c2[0]
                out[o2 + 1] = c2[1]
                out[o2 + 2] = c2[2]
    else:
        for y in range(2):
            for x in range(4):
                c1 = _etc1_pixel(r1, g1, b1, x, y, bottom, table1)
                c2 = _etc1_pixel(r2, g2, b2, x, y + 2, bottom, table2)
                o1 = (y * 4 + x) * 4
                out[o1] = c1[0]
                out[o1 + 1] = c1[1]
                out[o1 + 2] = c1[2]
                o2 = ((y + 2) * 4 + x) * 4
                out[o2] = c2[0]
                out[o2 + 1] = c2[1]
                out[o2 + 2] = c2[2]
    return bytes(out)


def _etc1_decode(data: bytes, width: int, height: int, alpha: bool) -> bytes:
    output = bytearray(width * height * 4)
    offset = 0
    for y in range(height // 4):
        for x in range(width // 4):
            if alpha:
                alpha_block = data[offset:offset + 8]
                color_block = bytes(reversed(data[offset + 8:offset + 16]))
                offset += 16
            else:
                color_block = bytes(reversed(data[offset:offset + 8]))
                alpha_block = b"\xff" * 8
                offset += 8
            decoded = _etc1_decode_block(color_block)
            toggle = False
            aoff = 0
            for tx in range(4):
                for ty in range(4):
                    o = (x * 4 + tx + ((y * 4 + ty) * width)) * 4
                    bo = (tx + ty * 4) * 4
                    output[o:o + 3] = decoded[bo:bo + 3]
                    if toggle:
                        a = (alpha_block[aoff] & 0xF0) >> 4
                        aoff += 1
                    else:
                        a = alpha_block[aoff] & 0xF
                    toggle = not toggle
                    output[o + 3] = (a << 4) | a
    return bytes(output)


def decode_texture(data: bytes, width: int, height: int, fmt: int) -> Image.Image:
    """Decode PICA tiled texture -> RGBA PIL Image (BCH format ids)."""
    out = bytearray(width * height * 4)
    doff = 0
    toggle = False

    def put(tx: int, ty: int, pixel: int, rgba: tuple[int, int, int, int]) -> None:
        x = TILE_ORDER[pixel] % 8
        y = (TILE_ORDER[pixel] - x) // 8
        o = ((tx * 8) + x + ((ty * 8 + y) * width)) * 4
        out[o:o + 4] = bytes(rgba)

    if fmt in (FMT_ETC1, FMT_ETC1A4):
        decoded = _etc1_decode(data, width, height, fmt == FMT_ETC1A4)
        order = _etc1_scramble(width, height)
        i = 0
        for ty in range(height // 4):
            for tx in range(width // 4):
                sx = order[i] % (width // 4)
                sy = (order[i] - sx) // (width // 4)
                for y in range(4):
                    for x in range(4):
                        src = ((sx * 4) + x + (((sy * 4) + y) * width)) * 4
                        dst = ((tx * 4) + x + (((ty * 4) + y) * width)) * 4
                        out[dst:dst + 4] = decoded[src:src + 4]
                i += 1
        return Image.frombytes("RGBA", (width, height), bytes(out))

    for ty in range(height // 8):
        for tx in range(width // 8):
            for pixel in range(64):
                if fmt == FMT_RGBA8:
                    # PICA RGBA8888 bytes are A,B,G,R (3dbrew / citro3d). Ohana copies
                    # file[1..] into a GDI+ BGRA buffer so R=file[3],G=file[2],B=file[1].
                    # PIL wants RGBA: (R,G,B,A) = (file[3], file[2], file[1], file[0]).
                    # Old ARGB interpret made Magikarp/Kyogre blue and Cyndaquil fire cyan.
                    put(tx, ty, pixel, (data[doff + 3], data[doff + 2], data[doff + 1], data[doff]))
                    doff += 4
                elif fmt == FMT_RGB8:
                    # PICA RGB8 is stored B,G,R in file order (gdkchan Ohana3DS-Rebirth).
                    # Direct R,G,B copy makes Torchic blue; BGR->RGB keeps orange / Groudon red.
                    put(tx, ty, pixel, (data[doff + 2], data[doff + 1], data[doff], 255))
                    doff += 3
                elif fmt == FMT_RGBA5551:
                    pix = data[doff] | (data[doff + 1] << 8)
                    r = ((pix >> 1) & 0x1F) << 3
                    g = ((pix >> 6) & 0x1F) << 3
                    b = ((pix >> 11) & 0x1F) << 3
                    a = (pix & 1) * 255
                    put(tx, ty, pixel, (r | (r >> 5), g | (g >> 5), b | (b >> 5), a))
                    doff += 2
                elif fmt == FMT_RGB565:
                    pix = data[doff] | (data[doff + 1] << 8)
                    r = (pix & 0x1F) << 3
                    g = ((pix >> 5) & 0x3F) << 2
                    b = ((pix >> 11) & 0x1F) << 3
                    put(tx, ty, pixel, (r | (r >> 5), g | (g >> 6), b | (b >> 5), 255))
                    doff += 2
                elif fmt == FMT_RGBA4:
                    pix = data[doff] | (data[doff + 1] << 8)
                    r = (pix >> 4) & 0xF
                    g = (pix >> 8) & 0xF
                    b = (pix >> 12) & 0xF
                    a = pix & 0xF
                    put(tx, ty, pixel, ((r << 4) | r, (g << 4) | g, (b << 4) | b, (a << 4) | a))
                    doff += 2
                elif fmt in (FMT_LA8, FMT_HILO8):
                    put(tx, ty, pixel, (data[doff], data[doff], data[doff], data[doff + 1]))
                    doff += 2
                elif fmt == FMT_L8:
                    c = data[doff]
                    put(tx, ty, pixel, (c, c, c, 255))
                    doff += 1
                elif fmt == FMT_A8:
                    put(tx, ty, pixel, (255, 255, 255, data[doff]))
                    doff += 1
                elif fmt == FMT_LA4:
                    c = data[doff] >> 4
                    a = data[doff] & 0xF
                    put(tx, ty, pixel, (c | (c << 4), c | (c << 4), c | (c << 4), a | (a << 4)))
                    doff += 1
                elif fmt == FMT_L4:
                    if toggle:
                        c = (data[doff] & 0xF0) >> 4
                        doff += 1
                    else:
                        c = data[doff] & 0xF
                    toggle = not toggle
                    c = (c << 4) | c
                    put(tx, ty, pixel, (c, c, c, 255))
                elif fmt == FMT_A4:
                    if toggle:
                        a = (data[doff] & 0xF0) >> 4
                        doff += 1
                    else:
                        a = data[doff] & 0xF
                    toggle = not toggle
                    put(tx, ty, pixel, (255, 255, 255, (a << 4) | a))
                else:
                    raise ValueError(f"unsupported texture format {fmt}")
    return Image.frombytes("RGBA", (width, height), bytes(out))


@dataclass
class RippedTexture:
    name: str
    width: int
    height: int
    fmt: int
    fmt_name: str
    image: Image.Image
    source: str


class PicaTexReader:
    def __init__(self, data: bytes | bytearray, offset: int, word_count: int):
        self.cmds = [0] * 0x10000
        self._read(data, offset, word_count)

    def _read(self, data: bytes | bytearray, offset: int, word_count: int) -> None:
        pos = offset
        end = offset + word_count * 4
        readed = 0

        def u32() -> int:
            nonlocal pos, readed
            v = struct.unpack_from("<I", data, pos)[0]
            pos += 4
            readed += 1
            return v

        while readed < word_count and pos + 8 <= len(data):
            parameter = u32()
            header = u32()
            cid = header & 0xFFFF
            mask = (header >> 16) & 0xF
            extra = (header >> 20) & 0x7FF
            consecutive = (header & 0x80000000) != 0
            self.cmds[cid] = (self.cmds[cid] & (~mask & 0xF)) | (parameter & (0xFFFFFFF0 | mask))
            for _ in range(extra):
                if consecutive:
                    cid += 1
                if readed >= word_count:
                    break
                self.cmds[cid] = (self.cmds[cid] & (~mask & 0xF)) | (u32() & (0xFFFFFFF0 | mask))
            while (pos & 7) != 0 and readed < word_count:
                u32()

    def size(self) -> tuple[int, int]:
        v = self.cmds[REG_TEX0_SIZE]
        return (v >> 16) & 0xFFFF, v & 0xFFFF

    def address(self) -> int:
        return self.cmds[REG_TEX0_ADDR]

    def format(self) -> int:
        return self.cmds[REG_TEX0_TYPE] & 0xFFFF


def _apply_bch_relocations(data: bytearray) -> dict:
    if data[:3] != b"BCH":
        raise ValueError("not BCH")
    bc = data[4]

    def u32(o: int) -> int:
        return struct.unpack_from("<I", data, o)[0]

    def wu32(o: int, v: int) -> None:
        struct.pack_into("<I", data, o, v & 0xFFFFFFFF)

    main = u32(8)
    string = u32(12)
    gpu = u32(16)
    dat = u32(20)
    off = 24
    data_ext = 0
    if bc > 0x20:
        data_ext = u32(off)
        off += 4
    reloc = u32(off)
    off += 4
    main_len = u32(off)
    off += 4
    string_len = u32(off)
    off += 4
    gpu_len = u32(off)
    off += 4
    data_len = u32(off)
    off += 4
    data_ext_len = 0
    if bc > 0x20:
        data_ext_len = u32(off)
        off += 4
    reloc_len = u32(off)

    for o in range(reloc, reloc + reloc_len, 4):
        value = u32(o)
        offset = value & 0x1FFFFFF
        flags = value >> 25
        if flags == 0:
            p = (offset * 4) + main
            wu32(p, u32(p) + main)
        elif flags == 1:
            p = offset + main
            wu32(p, u32(p) + string)
        elif flags == 2:
            p = (offset * 4) + main
            wu32(p, u32(p) + gpu)
        elif flags in (7, 0xC):
            p = (offset * 4) + main
            wu32(p, u32(p) + dat)

        go = (offset * 4) + gpu
        if go + 4 > len(data):
            continue
        if bc < 6:
            m = {0x23: dat, 0x25: dat}
            if flags in m:
                wu32(go, u32(go) + m[flags])
            elif flags == 0x26:
                wu32(go, ((u32(go) + dat) & 0x7FFFFFFF) | 0x80000000)
            elif flags == 0x27:
                wu32(go, (u32(go) + dat) & 0x7FFFFFFF)
        elif bc < 8:
            if flags == 0x24:
                wu32(go, u32(go) + dat)
            elif flags == 0x26:
                wu32(go, u32(go) + dat)
            elif flags == 0x27:
                wu32(go, ((u32(go) + dat) & 0x7FFFFFFF) | 0x80000000)
            elif flags == 0x28:
                wu32(go, (u32(go) + dat) & 0x7FFFFFFF)
        elif bc < 0x21:
            if flags == 0x25:
                wu32(go, u32(go) + dat)
            elif flags == 0x27:
                wu32(go, u32(go) + dat)
            elif flags == 0x28:
                wu32(go, ((u32(go) + dat) & 0x7FFFFFFF) | 0x80000000)
            elif flags == 0x29:
                wu32(go, (u32(go) + dat) & 0x7FFFFFFF)
        else:
            if flags == 0x25:
                wu32(go, u32(go) + dat)
            elif flags == 0x26:
                wu32(go, u32(go) + dat)
            elif flags == 0x27:
                wu32(go, ((u32(go) + dat) & 0x7FFFFFFF) | 0x80000000)
            elif flags == 0x28:
                wu32(go, (u32(go) + dat) & 0x7FFFFFFF)
            elif flags == 0x2B:
                wu32(go, u32(go) + data_ext)
            elif flags == 0x2C:
                wu32(go, ((u32(go) + data_ext) & 0x7FFFFFFF) | 0x80000000)
            elif flags == 0x2D:
                wu32(go, (u32(go) + data_ext) & 0x7FFFFFFF)

    return {
        "bc": bc,
        "main": main,
        "string": string,
        "gpu": gpu,
        "data": dat,
        "data_ext": data_ext,
        "data_len": data_len,
    }


def _read_cstr(data: bytes | bytearray, offset: int) -> str:
    if offset <= 0 or offset >= len(data):
        return ""
    end = data.find(b"\x00", offset)
    if end < 0:
        end = min(offset + 64, len(data))
    return bytes(data[offset:end]).decode("ascii", errors="replace")


def rip_bch_textures(path: Path | str) -> list[RippedTexture]:
    path = Path(path)
    data = bytearray(path.read_bytes())
    if data[:3] != b"BCH":
        # try GF container unwrap at 0x80
        if len(data) > 0x84 and data[0x80:0x83] == b"BCH":
            data = bytearray(data[0x80:])
        else:
            raise ValueError(f"not BCH: {path}")
    meta = _apply_bch_relocations(data)
    main = meta["main"]
    tex_ptr = struct.unpack_from("<I", data, main + 0x24)[0]
    tex_entries = struct.unpack_from("<I", data, main + 0x28)[0]
    out: list[RippedTexture] = []
    if tex_ptr + tex_entries * 4 > len(data) or tex_entries > 10000:
        return out
    for i in range(tex_entries):
        ent = struct.unpack_from("<I", data, tex_ptr + i * 4)[0]
        if ent + 32 > len(data):
            continue
        u0_off, u0_wc = struct.unpack_from("<II", data, ent)
        if u0_off + max(u0_wc, 1) * 4 > len(data) or u0_wc > 0x10000:
            continue
        name_off = struct.unpack_from("<I", data, ent + 28)[0]
        name = _read_cstr(data, name_off) or f"tex_{i}"
        reader = PicaTexReader(data, u0_off, u0_wc)
        w, h = reader.size()
        addr = reader.address()
        fmt = reader.format()
        if w == 0 or h == 0 or w > 4096 or h > 4096:
            continue
        if not (w & (w - 1) == 0) or not (h & (h - 1) == 0):
            # PICA textures are power-of-two
            continue
        need = _tex_data_size(w, h, fmt)
        if addr >= len(data) or need <= 0:
            continue
        blob = bytes(data[addr:addr + need])
        if len(blob) < need:
            continue
        try:
            img = decode_texture(blob, w, h, fmt)
        except Exception:
            continue
        out.append(
            RippedTexture(
                name=name,
                width=w,
                height=h,
                fmt=fmt,
                fmt_name=BCH_FMT_NAMES.get(fmt, str(fmt)),
                image=img,
                source=str(path),
            )
        )
    return out


def parse_bclim(path: Path | str) -> RippedTexture | None:
    path = Path(path)
    data = path.read_bytes()
    imag = data.rfind(b"imag")
    clim = data.rfind(b"CLIM")
    if imag < 0 or clim < 0:
        return None
    # imag: magic(4) size(4)=0x10 width(u16) height(u16) format(u32) imageSize(u32)
    section_size, width, height, fmt_raw, image_size = struct.unpack_from(
        "<IHHII", data, imag + 4
    )
    bch_fmt = BCLIM_TO_BCH.get(fmt_raw)
    if bch_fmt is None:
        return None
    # pixel data is at start; footer is last 0x28 bytes typically
    footer = len(data) - imag if imag > clim else len(data) - clim
    # Prefer declared image_size from start
    blob = data[:image_size]
    if len(blob) < image_size:
        return None
    # Some files pad; ensure dimensions match bpp
    expect = _tex_data_size(width, height, bch_fmt)
    if expect and image_size >= expect:
        blob = data[:expect]
    try:
        img = decode_texture(blob, width, height, bch_fmt)
    except Exception:
        return None
    return RippedTexture(
        name=path.stem,
        width=width,
        height=height,
        fmt=bch_fmt,
        fmt_name=BCH_FMT_NAMES.get(bch_fmt, str(bch_fmt)),
        image=img,
        source=str(path),
    )


def is_bclim(path: Path | str) -> bool:
    path = Path(path)
    try:
        data = path.read_bytes()
    except OSError:
        return False
    return b"CLIM" in data[-64:] and b"imag" in data[-64:]


def export_textures(
    textures: Iterable[RippedTexture],
    out_dir: Path,
    *,
    prefix: str = "",
) -> list[Path]:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for tex in textures:
        safe = "".join(c if c.isalnum() or c in "-_" else "_" for c in tex.name)
        name = f"{prefix}{safe}.png" if prefix else f"{safe}.png"
        dest = out_dir / name
        # avoid collisions
        n = 1
        while dest.exists():
            dest = out_dir / (f"{prefix}{safe}_{n}.png" if prefix else f"{safe}_{n}.png")
            n += 1
        tex.image.save(dest, "PNG")
        written.append(dest)
    return written
