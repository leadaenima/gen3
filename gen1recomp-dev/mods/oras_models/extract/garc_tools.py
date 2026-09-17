#!/usr/bin/env python3
"""GARC (CRAG) unpack + Nintendo LZ11 decompress for ORAS RomFS.

Pure Python, based on pk3DS.Core.CTR.GARC / LZSS (dsdecmp).
Outputs stay under the caller-chosen cache dir — never vendor into git.
"""

from __future__ import annotations

import struct
from pathlib import Path

MAGIC_EXTS = {
    b"BCH\x00": ".bch",
    b"CGFX": ".cgfx",
    b"CRAG": ".garc",
    b"SPBD": ".spbd",
    b"SESD": ".sesd",
    b"GFBM": ".gfbm",
    b"BCLIM": ".bclim",
    b"CLIM": ".bclim",
    b"CFNT": ".cfnt",
    b"FFNT": ".ffnt",
    b"DARC": ".darc",
    b"SARC": ".sarc",
    # ORAS mini-containers (often wrap BCH/textures)
    b"MM": ".mm",   # overworld / map model pack
    b"AD": ".ad",   # map texture pack
    b"BB": ".bb",
    b"BS": ".bs",
    b"PC": ".pc",   # pokemon container (seen in model GARCs)
    b"BM": ".bm",
    b"GR": ".gr",
    b"TM": ".tm",
    b"PT": ".pt",
    b"PF": ".pf",
    b"PB": ".pb",
    b"PK": ".pk",
}


def guess_ext(data: bytes) -> str:
    if not data:
        return ".bin"
    if data[:1] == b"\x11":
        return ".lz11"
    # Prefer longer magics first
    for magic, ext in sorted(MAGIC_EXTS.items(), key=lambda kv: -len(kv[0])):
        if data.startswith(magic):
            return ext
    if data[:3] == b"BCH":
        return ".bch"
    if data[:4] == b"CGFX":
        return ".cgfx"
    return ".bin"


def lz11_decompress(src: bytes) -> bytes:
    """Decompress Nintendo LZ11 (type 0x11). Raises ValueError on failure."""
    if not src or src[0] != 0x11:
        raise ValueError("not LZ11")
    i = 1
    dec_size = src[1] | (src[2] << 8) | (src[3] << 16)
    i = 4
    if dec_size == 0:
        if len(src) < 8:
            raise ValueError("LZ11 truncated size")
        dec_size = struct.unpack_from("<I", src, 4)[0]
        i = 8
    out = bytearray()
    while len(out) < dec_size:
        if i >= len(src):
            raise ValueError("LZ11 truncated flags")
        flags = src[i]
        i += 1
        for bit in range(8):
            if len(out) >= dec_size:
                break
            if flags & (0x80 >> bit):
                if i >= len(src):
                    raise ValueError("LZ11 truncated block")
                b1 = src[i]
                i += 1
                length = b1 >> 4
                if length == 0:
                    if i + 1 >= len(src):
                        raise ValueError("LZ11 truncated len0")
                    b2 = src[i]
                    b3 = src[i + 1]
                    i += 2
                    length = (((b1 & 0x0F) << 4) | (b2 >> 4)) + 0x11
                    disp = (((b2 & 0x0F) << 8) | b3) + 1
                elif length == 1:
                    if i + 2 >= len(src):
                        raise ValueError("LZ11 truncated len1")
                    b2 = src[i]
                    b3 = src[i + 1]
                    b4 = src[i + 2]
                    i += 3
                    length = (((b1 & 0x0F) << 12) | (b2 << 4) | (b3 >> 4)) + 0x111
                    disp = (((b3 & 0x0F) << 8) | b4) + 1
                else:
                    if i >= len(src):
                        raise ValueError("LZ11 truncated len>")
                    b2 = src[i]
                    i += 1
                    length = (b1 >> 4) + 1
                    disp = (((b1 & 0x0F) << 8) | b2) + 1
                if disp > len(out):
                    raise ValueError(f"LZ11 bad disp={disp} out={len(out)}")
                for _ in range(length):
                    out.append(out[-disp])
            else:
                if i >= len(src):
                    raise ValueError("LZ11 truncated literal")
                out.append(src[i])
                i += 1
    return bytes(out[:dec_size])


def maybe_decompress(data: bytes) -> tuple[bytes, bool]:
    if data and data[0] == 0x11 and len(data) >= 4:
        try:
            return lz11_decompress(data), True
        except ValueError:
            return data, False
    return data, False


class GarcFile:
    def __init__(self, path: Path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        self._parse()

    def _u16(self, off: int) -> int:
        return struct.unpack_from("<H", self.data, off)[0]

    def _u32(self, off: int) -> int:
        return struct.unpack_from("<I", self.data, off)[0]

    def _parse(self) -> None:
        d = self.data
        if d[:4] != b"CRAG":
            raise ValueError(f"not GARC/CRAG: {self.path}")
        self.header_size = self._u32(4)
        self.endian = self._u16(8)
        self.version = self._u16(10)
        self.chunk_count = self._u32(12)
        self.data_offset = self._u32(16)
        self.file_size = self._u32(20)
        off = 0x1C
        if self.version == 0x0400:
            self.largest_unpadded = self._u32(0x18)
            off = 0x1C
        elif self.version == 0x0600:
            self.largest_padded = self._u32(0x18)
            self.largest_unpadded = self._u32(0x1C)
            self.pad_to = self._u32(0x20)
            off = 0x24
        else:
            raise ValueError(f"unsupported GARC version 0x{self.version:04X}")

        # FATO
        if d[off : off + 4] != b"OTAF":
            raise ValueError("missing FATO")
        fato_hdr = self._u32(off + 4)
        entry_count = self._u16(off + 8)
        off += fato_hdr

        # FATB
        if d[off : off + 4] != b"BTAF":
            raise ValueError("missing FATB")
        fatb_hdr = self._u32(off + 4)
        file_count = self._u32(off + 8)
        p = off + 12
        entries: list[dict] = []
        for _ei in range(entry_count):
            vector = self._u32(p)
            p += 4
            subs: list[dict] = []
            bit = vector
            n_exist = 0
            for b in range(32):
                exists = (bit & 1) == 1
                bit >>= 1
                if not exists:
                    continue
                start = self._u32(p)
                end = self._u32(p + 4)
                length = self._u32(p + 8)
                p += 12
                subs.append(
                    {"bit": b, "start": start, "end": end, "length": length}
                )
                n_exist += 1
                if bit == 0:
                    break
            entries.append(
                {
                    "vector": vector,
                    "is_folder": n_exist > 1,
                    "subs": subs,
                }
            )
        self.entry_count = entry_count
        self.file_count = file_count
        self.entries = entries

    def iter_files(self):
        for ei, entry in enumerate(self.entries):
            for sub in entry["subs"]:
                start = self.data_offset + sub["start"]
                length = sub["length"]
                blob = self.data[start : start + length]
                yield ei, entry["is_folder"], sub["bit"], blob


def unpack_garc(
    garc_path: Path,
    out_dir: Path,
    *,
    decompress: bool = True,
    digits: int | None = None,
) -> dict:
    """Unpack one GARC into out_dir. Returns stats dict."""
    garc = GarcFile(garc_path)
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    width = digits or max(1, len(str(max(garc.entry_count - 1, 0))))
    stats = {
        "source": str(garc_path),
        "out_dir": str(out_dir),
        "entry_count": garc.entry_count,
        "file_count": garc.file_count,
        "version": f"0x{garc.version:04X}",
        "written": 0,
        "decompressed": 0,
        "by_ext": {},
        "bch": 0,
        "cgfx": 0,
        "png": 0,
        "errors": [],
    }
    for ei, is_folder, bit, blob in garc.iter_files():
        name = f"{ei:0{width}d}"
        parent = out_dir / name if is_folder else out_dir
        parent.mkdir(parents=True, exist_ok=True)
        raw = blob
        did_dec = False
        if decompress:
            raw, did_dec = maybe_decompress(blob)
            if did_dec:
                stats["decompressed"] += 1
        ext = guess_ext(raw)
        fname = f"{bit:02d}{ext}" if is_folder else f"{name}{ext}"
        dest = parent / fname
        try:
            dest.write_bytes(raw)
            stats["written"] += 1
            stats["by_ext"][ext] = stats["by_ext"].get(ext, 0) + 1
            if ext == ".bch":
                stats["bch"] += 1
            elif ext == ".cgfx":
                stats["cgfx"] += 1
            elif ext == ".png":
                stats["png"] += 1
        except OSError as exc:
            stats["errors"].append(f"{dest}: {exc}")
    return stats


def scan_magic_counts(root: Path) -> dict:
    """Walk extracted tree; count BCH/CGFX/PNG/etc by magic or extension."""
    counts = {
        "files": 0,
        "bch": 0,
        "cgfx": 0,
        "png": 0,
        "garc": 0,
        "lz11_left": 0,
        "other": 0,
        "by_ext": {},
    }
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        counts["files"] += 1
        ext = p.suffix.lower() or ".bin"
        counts["by_ext"][ext] = counts["by_ext"].get(ext, 0) + 1
        try:
            head = p.read_bytes()[:8]
        except OSError:
            counts["other"] += 1
            continue
        if head.startswith(b"BCH") or ext == ".bch":
            counts["bch"] += 1
        elif head.startswith(b"CGFX") or ext == ".cgfx":
            counts["cgfx"] += 1
        elif head.startswith(b"\x89PNG") or ext == ".png":
            counts["png"] += 1
        elif head.startswith(b"CRAG"):
            counts["garc"] += 1
        elif head[:1] == b"\x11":
            counts["lz11_left"] += 1
        else:
            counts["other"] += 1
    return counts



def is_gf_container(data: bytes) -> bool:
    if len(data) < 12:
        return False
    mag = data[:2]
    return mag in {b"MM", b"AD", b"BB", b"BS", b"PC", b"BM", b"GR", b"TM", b"PM", b"PT", b"PF", b"PB", b"PK"}


def unwrap_gf_container(data: bytes) -> list[tuple[str, bytes]]:
    """Game Freak 0x80-padded mini container (MM/AD/PC/...): payload at offset from header.

    Header (observed ORAS):
      magic[2], u16 ver, u32 content_off (often 0x80), u32 total_size, pad...
    Returns list of (ext, payload) — usually one BCH or texture blob.
    """
    import struct as _struct

    if not is_gf_container(data):
        return []
    content_off = _struct.unpack_from("<I", data, 4)[0]
    total = _struct.unpack_from("<I", data, 8)[0]
    if content_off < 8 or content_off >= len(data):
        return []
    # Prefer declared total if sane, else rest of file
    end = total if 8 < total <= len(data) else len(data)
    if end <= content_off:
        end = len(data)
    payload = data[content_off:end]
    if not payload:
        return []
    return [(guess_ext(payload), payload)]


def rip_nested_models(root: Path) -> dict:
    """Unwrap GF containers; also carve BCH/CGFX payloads found by magic."""
    stats = {"scanned": 0, "unwrapped": 0, "bch": 0, "cgfx": 0, "written": 0}
    for p in root.rglob("*"):
        if not p.is_file() or p.name.startswith("."):
            continue
        if p.suffix.lower() in {".bch", ".cgfx", ".png"}:
            continue
        try:
            data = p.read_bytes()
        except OSError:
            continue
        stats["scanned"] += 1
        payloads: list[tuple[str, bytes]] = []

        parts = unwrap_gf_container(data)
        for ext, payload in parts:
            if ext in {".bch", ".cgfx"}:
                payloads.append((ext, payload))
            elif len(payload) > 0x84 and payload[0x80:0x83] == b"BCH":
                payloads.append((".bch", payload[0x80:]))
            elif payload[:3] == b"BCH":
                payloads.append((".bch", payload))
            elif payload[:4] == b"CGFX":
                payloads.append((".cgfx", payload))

        if not payloads:
            for magic, ext in ((b"BCH", ".bch"), (b"CGFX", ".cgfx")):
                start = 0
                while True:
                    j = data.find(magic, start)
                    if j < 0:
                        break
                    nxt = len(data)
                    for m in (b"BCH", b"CGFX"):
                        k = data.find(m, j + len(magic))
                        if 0 <= k < nxt:
                            nxt = k
                    chunk = data[j : min(nxt, j + 32 * 1024 * 1024)]
                    if len(chunk) > 64:
                        payloads.append((ext, chunk))
                    start = j + len(magic)

        if not payloads:
            continue

        seen: set[tuple] = set()
        uniq: list[tuple[str, bytes]] = []
        for ext, payload in payloads:
            key = (ext, len(payload), payload[:64])
            if key in seen:
                continue
            seen.add(key)
            uniq.append((ext, payload))

        stats["unwrapped"] += 1
        for i, (ext, payload) in enumerate(uniq):
            out = p.with_name(f"{p.stem}_u{i}{ext}")
            if not (out.exists() and out.stat().st_size == len(payload)):
                out.write_bytes(payload)
                stats["written"] += 1
            if ext == ".bch":
                stats["bch"] += 1
            elif ext == ".cgfx":
                stats["cgfx"] += 1
    return stats
