#!/usr/bin/env python3
"""Rip TXOB textures from NintendoWare CGFX (ORAS move-effect packs).

Uses the same PICA decode path as bch_tex.decode_texture. Cache-only PNGs —
never write into mods/oras_models/assets or git.
"""
from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from bch_tex import BCH_FMT_NAMES, RippedTexture, decode_texture, export_textures


def _u32(d: bytes, o: int) -> int:
    return struct.unpack_from("<I", d, o)[0]


def _cstr(d: bytes, o: int) -> str:
    if o < 0 or o >= len(d):
        return ""
    end = d.find(b"\x00", o)
    if end < 0:
        end = min(len(d), o + 64)
    try:
        return d[o:end].decode("ascii", "replace")
    except Exception:
        return ""


@dataclass
class CgfxTxob:
    name: str
    width: int
    height: int
    fmt: int
    data: bytes
    offset: int


def find_txobs(data: bytes) -> list[CgfxTxob]:
    """Locate ImageTexture TXOB blocks inside a CGFX blob."""
    out: list[CgfxTxob] = []
    i = 0
    while True:
        j = data.find(b"TXOB", i)
        if j < 0:
            break
        if j < 4:
            i = j + 4
            continue
        base = j - 4  # flags precede magic
        try:
            name_rel = _u32(data, base + 0x0C)
            height = _u32(data, base + 0x18)
            width = _u32(data, base + 0x1C)
            fmt = _u32(data, base + 0x34)
            size = _u32(data, base + 0x44)
            data_rel = _u32(data, base + 0x48)
        except struct.error:
            i = j + 4
            continue
        if not (
            1 <= width <= 2048
            and 1 <= height <= 2048
            and fmt <= 0x0D
            and 16 <= size <= 8_000_000
        ):
            i = j + 4
            continue
        name = ""
        if name_rel:
            name = _cstr(data, base + 0x0C + name_rel)
        data_off = base + 0x48 + data_rel
        if data_off < 0 or data_off + size > len(data):
            i = j + 4
            continue
        blob = data[data_off : data_off + size]
        out.append(
            CgfxTxob(
                name=name or f"tex_{len(out)}",
                width=width,
                height=height,
                fmt=fmt,
                data=blob,
                offset=base,
            )
        )
        i = j + 4
    return out


def rip_cgfx_textures(path: Path | str) -> list[RippedTexture]:
    path = Path(path)
    data = path.read_bytes()
    if data[:4] != b"CGFX":
        return []
    ripped: list[RippedTexture] = []
    for ti, tx in enumerate(find_txobs(data)):
        try:
            img = decode_texture(tx.data, tx.width, tx.height, tx.fmt)
        except Exception:
            continue
        ripped.append(
            RippedTexture(
                name=tx.name or f"{path.stem}_{ti}",
                width=tx.width,
                height=tx.height,
                fmt=tx.fmt,
                fmt_name=BCH_FMT_NAMES.get(tx.fmt, str(tx.fmt)),
                image=img,
                source=str(path),
            )
        )
    return ripped


def export_cgfx_file(path: Path | str, out_dir: Path | str) -> dict:
    path = Path(path)
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    texs = rip_cgfx_textures(path)
    written = export_textures(texs, out_dir, prefix=f"{path.stem}_")
    return {
        "source": str(path),
        "textures": len(texs),
        "written": [str(p) for p in written],
    }
