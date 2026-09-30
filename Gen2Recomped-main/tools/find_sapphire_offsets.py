"""Relocate US Ruby 1.0 extractor offsets onto US Sapphire 1.0 (AXPE)."""
from __future__ import annotations

import json
import os
import re
import struct
from collections import defaultdict

RUBY = r"C:\Users\Feces\Desktop\Pokemon - Ruby Version (USA).gba"
SAPP = r"C:\Users\Feces\Desktop\PokemonSapphireVersion.gba"
SRC = os.path.join(os.path.dirname(__file__), "..", "src", "import")
OUT = os.path.join(os.path.dirname(__file__), "sapphire_offsets.json")

# Game3 RS core lives in RomExtractorGen3RS.lua; Emerald's Gen3.lua is a
# different cart and must not feed SapphireOff.Core.
FILES = [
    "RomExtractorGen3RS.lua",
    "RomExtractorGen3Cinema.lua",
    "RomExtractorGen3Battle.lua",
    "RomExtractorGen3Ui.lua",
    "RomExtractorGen3Audio.lua",
    "RomExtractorGen3Dex.lua",
    "RomExtractorGen3Party.lua",
    "RomExtractorGen3Pokenav.lua",
    "RomExtractorGen3Card.lua",
    "RomExtractorGen3Anim.lua",
    "RomExtractorGen3Balls.lua",
    "RomExtractorGen3Transition.lua",
    "RomExtractorGen3Pc.lua",
    "RomExtractorGen3Icons.lua",
]

# name = 0xHHHHHH inside tables / locals
PAT = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*0x([0-9A-Fa-f]{5,7})\b")
SKIP_COLLECT = {
    "hi", "lo", "i", "j", "n", "end", "start", "stop", "size", "count",
    "off", "base", "ptr", "len", "num",
}

KNOWN_SAP_SONG = 0x4554E8


def u32(b: bytes, o: int) -> int:
    return struct.unpack_from("<I", b, o)[0]


def u16(b: bytes, o: int) -> int:
    return struct.unpack_from("<H", b, o)[0]


def is_romptr(p: int, n: int) -> bool:
    return 0x08000000 <= p < 0x08000000 + n


def lz_size(b: bytes, o: int):
    if o + 4 > len(b) or b[o] != 0x10:
        return None
    return b[o + 1] | (b[o + 2] << 8) | (b[o + 3] << 16)


def unique_find(hay: bytes, needle: bytes) -> int | None:
    if not needle:
        return None
    at = hay.find(needle)
    if at < 0:
        return None
    if hay.find(needle, at + 1) >= 0:
        return None
    return at


def collect_named(path: str):
    text = open(path, encoding="utf-8", errors="replace").read()
    seen = set()
    rows = []
    for m in PAT.finditer(text):
        name, hx = m.group(1), m.group(2)
        off = int(hx, 16)
        if off < 0x100 or off >= 0x1000000:
            continue
        if name in SKIP_COLLECT:
            continue
        key = (name, off)
        if key in seen:
            continue
        seen.add(key)
        rows.append((name, off))
    return rows


def score_song_table(b: bytes, off: int, count: int = 468) -> int:
    n = len(b)
    good = 0
    for i in range(count):
        e = off + i * 8
        if e + 8 > n:
            return good
        p = u32(b, e)
        ms = u16(b, e + 4)
        if is_romptr(p, n) and ms <= 4:
            good += 1
        else:
            return good
    return good


def find_door_table(b: bytes) -> int | None:
    """US Ruby doors sit at 0x30F9B4; Sapphire is 0x70 bytes earlier."""
    n = len(b)
    count = 34
    windows = ((0x30F000, 0x310000), (0x308000, 0x318000))
    for lo, hi in windows:
        for off in range(lo, min(hi, n - count * 12 - 8), 4):
            ok = True
            for i in range(count):
                o = off + i * 12
                tiles = u32(b, o + 4)
                pal = u32(b, o + 8)
                if not is_romptr(tiles, n) or not is_romptr(pal, n):
                    ok = False
                    break
                if u16(b, o) == 0 and u16(b, o + 2) == 0 and i == 0:
                    ok = False
                    break
            if not ok:
                continue
            term = u32(b, off + count * 12 + 4)
            if term == 0:
                return off
    return None


def find_wild_headers(b: bytes) -> int | None:
    n = len(b)
    best = None
    for off in range(0x39C000, 0x3A0000, 4):
        if b[off:off + 8] != b"\x00" * 8:
            continue
        p1, p2, p3, p4 = u32(b, off + 4), u32(b, off + 8), u32(b, off + 12), u32(b, off + 16)
        if p1 != 0 or p3 != 0:
            continue
        if not is_romptr(p2, n) or not is_romptr(p4, n):
            continue
        rows = 1
        o = off + 20
        while rows < 120:
            if b[o] == 0xFF and b[o + 1] == 0xFF:
                break
            land = u32(b, o + 4)
            water = u32(b, o + 8)
            rock = u32(b, o + 12)
            fish = u32(b, o + 16)
            for p in (land, water, rock, fish):
                if p != 0 and not is_romptr(p, n):
                    rows = 0
                    break
            if rows == 0:
                break
            rows += 1
            o += 20
        if rows >= 90:
            return off
        if best is None or (rows > best[0]):
            best = (rows, off)
    return best[1] if best and best[0] >= 80 else None


def find_song_table(b: bytes) -> int | None:
    n = len(b)
    if score_song_table(b, KNOWN_SAP_SONG) >= 468:
        return KNOWN_SAP_SONG
    lo, hi = 0x430000, 0x480000
    best = None
    for off in range(lo, min(hi, n - 468 * 8), 4):
        if not is_romptr(u32(b, off), n) or u16(b, off + 4) > 4:
            continue
        if score_song_table(b, off, 16) < 16:
            continue
        g = score_song_table(b, off)
        if g >= 468:
            return off
        if best is None or g > best[0]:
            best = (g, off)
    return best[1] if best and best[0] >= 400 else None


def main():
    rb = open(RUBY, "rb").read()
    sb = open(SAPP, "rb").read()
    results = {}
    unmatched = []
    deltas = []

    for fn in FILES:
        path = os.path.abspath(os.path.join(SRC, fn))
        if not os.path.isfile(path):
            continue
        for name, off in collect_named(path):
            rec = {
                "file": fn,
                "name": name,
                "ruby": off,
                "sapphire": None,
                "how": None,
            }
            win = 32
            while win >= 8:
                chunk = rb[off : off + win]
                if len(chunk) < win:
                    break
                hit = unique_find(sb, chunk)
                if hit is not None:
                    rec["sapphire"] = hit
                    rec["how"] = f"unique{win}"
                    deltas.append(hit - off)
                    break
                win //= 2
            if rec["sapphire"] is None:
                for win in (64, 128, 256, 512, 1024, 4096):
                    chunk = rb[off : off + win]
                    if len(chunk) < win:
                        break
                    if chunk.count(0) >= int(win * 0.9):
                        continue
                    hit = unique_find(sb, chunk)
                    if hit is not None:
                        rec["sapphire"] = hit
                        rec["how"] = f"unique{win}"
                        deltas.append(hit - off)
                        break
            if rec["sapphire"] is None:
                size = lz_size(rb, off)
                if size is not None:
                    sig = rb[off : off + 8]
                    hit = unique_find(sb, sig)
                    if hit is not None and lz_size(sb, hit) == size:
                        rec["sapphire"] = hit
                        rec["how"] = "lz-sig"
                        deltas.append(hit - off)
                    else:
                        hits = []
                        start = 0
                        needle = bytes([0x10, size & 0xFF, (size >> 8) & 0xFF, (size >> 16) & 0xFF])
                        while True:
                            at = sb.find(needle, start)
                            if at < 0:
                                break
                            hits.append(at)
                            start = at + 1
                            if len(hits) > 8:
                                break
                        if len(hits) == 1:
                            rec["sapphire"] = hits[0]
                            rec["how"] = "lz-size-unique"
                            deltas.append(hits[0] - off)
            key = f"{fn}:{name}:{off:#x}"
            results[key] = rec
            if rec["sapphire"] is None:
                unmatched.append(rec)

    mode = None
    counts = defaultdict(int)
    if deltas:
        for d in deltas:
            counts[d] += 1
        mode = max(counts.items(), key=lambda kv: kv[1])[0]
        print("delta_mode", hex(mode) if mode >= 0 else mode, "count", counts[mode], "of", len(deltas))

    popular = sorted(counts.items(), key=lambda kv: -kv[1])[:12] if deltas else []
    try_deltas = [(-0x70, 0), (0x58, 0), (-0x1B8, 0)]
    seen_d = {d for d, _ in try_deltas}
    for d, c in popular:
        if d not in seen_d:
            try_deltas.append((d, c))
            seen_d.add(d)
    still = []
    for rec in unmatched:
        off = rec["ruby"]
        found = False
        chunk64 = rb[off : off + 64]
        if (
            len(chunk64) == 64
            and chunk64.count(0) < 56
            and chunk64 == sb[off : off + 64]
        ):
            rec["sapphire"] = off
            rec["how"] = "same64"
            found = True
        if found:
            continue
        for d, _c in try_deltas:
            if d == 0:
                continue
            cand = off + d
            if cand < 0 or cand + 4 > len(sb):
                continue
            rs = lz_size(rb, off)
            if rs is not None:
                ss = lz_size(sb, cand)
                if ss == rs:
                    rec["sapphire"] = cand
                    rec["how"] = f"delta-lz:{d}"
                    found = True
                    break
            else:
                rp, sp = u32(rb, off), u32(sb, cand)
                if is_romptr(rp, len(rb)) and is_romptr(sp, len(sb)) and (sp - rp) == d:
                    rec["sapphire"] = cand
                    rec["how"] = f"delta-ptr:{d}"
                    found = True
                    break
                chunk = rb[off : off + 32]
                if chunk != b"\x00" * 32 and chunk == sb[cand : cand + 32]:
                    rec["sapphire"] = cand
                    rec["how"] = f"delta-bytes:{d}"
                    found = True
                    break
        if not found:
            chunk32 = rb[off : off + 32]
            if (
                len(chunk32) == 32
                and chunk32 != b"\x00" * 32
                and chunk32 == sb[off : off + 32]
            ):
                rec["sapphire"] = off
                rec["how"] = "same"
                found = True
            else:
                rs = lz_size(rb, off)
                ss = lz_size(sb, off)
                if rs is not None and ss == rs:
                    rec["sapphire"] = off
                    rec["how"] = "same-lz"
                    found = True
        if not found:
            still.append(rec)

    song_r = 0x45548C
    print("ruby_song_score", score_song_table(rb, song_r))
    print("finding sapphire song table...")
    song_s = find_song_table(sb)
    print("sapphire_song_table", hex(song_s) if song_s is not None else None)

    door = find_door_table(sb)
    print("sapphire_door_table", hex(door) if door is not None else None)
    wild = find_wild_headers(sb)
    print("sapphire_wild_headers", hex(wild) if wild is not None else None)

    print("finding decorations...")
    decor = None
    for start, end in ((0x3C0000, 0x400000), (0x380000, 0x420000)):
        n = len(sb)
        stride, count = 32, 121
        for off in range(start, min(end, n - stride * count), 4):
            if sb[off] != 0:
                continue
            ok = True
            for i in range(count):
                o = off + i * stride
                if sb[o] != i:
                    ok = False
                    break
                if not is_romptr(u32(sb, o + 0x18), n) or not is_romptr(u32(sb, o + 0x1C), n):
                    ok = False
                    break
            if ok:
                decor = off
                break
        if decor is not None:
            break
    print("sapphire_decorations", hex(decor) if decor is not None else None)

    matched = sum(1 for r in results.values() if r["sapphire"] is not None)
    print("matched", matched, "/", len(results), "unmatched_after_delta", len(still))
    for rec in still[:40]:
        print("  MISS", rec["file"], rec["name"], hex(rec["ruby"]))

    payload = {
        "songTable": song_s,
        "decorations": decor,
        "doorTable": door,
        "wildHeaders": wild,
        "deltaMode": mode,
        "offsets": results,
        "unmatched": still,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=1)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
