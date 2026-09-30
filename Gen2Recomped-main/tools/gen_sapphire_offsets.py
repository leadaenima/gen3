"""Build src/import/RomExtractorGen3Sapphire.lua from relocated offsets."""
from __future__ import annotations

import json
import os
import re
import struct

RUBY = r"C:\Users\Feces\Desktop\Pokemon - Ruby Version (USA).gba"
SAPP = r"C:\Users\Feces\Desktop\PokemonSapphireVersion.gba"
HERE = os.path.dirname(os.path.abspath(__file__))
JSON_PATH = os.path.join(HERE, "sapphire_offsets.json")
SRC = os.path.join(HERE, "..", "src", "import")
OUT = os.path.join(SRC, "RomExtractorGen3Sapphire.lua")

FILE_TO_KEY = {
    "RomExtractorGen3Cinema.lua": "Cinema",
    "RomExtractorGen3Battle.lua": "Battle",
    "RomExtractorGen3Ui.lua": "Ui",
    "RomExtractorGen3Audio.lua": "Audio",
    "RomExtractorGen3Dex.lua": "Dex",
    "RomExtractorGen3Party.lua": "Party",
    "RomExtractorGen3Pokenav.lua": "Pokenav",
    "RomExtractorGen3Card.lua": "Card",
    "RomExtractorGen3Anim.lua": "Anim",
    "RomExtractorGen3Balls.lua": "Balls",
    "RomExtractorGen3Transition.lua": "Transition",
    "RomExtractorGen3Pc.lua": "Pc",
    "RomExtractorGen3Icons.lua": "Icons",
    "RomExtractorGen3RS.lua": "Core",
}

SKIP_NAMES = {
    "ROM_BASE", "BLOB_PATH", "SCREEN_W", "SCREEN_H", "MAP_PITCH", "TILE",
    "TILE_BYTES", "TILE_8BPP",
    "hi", "lo", "off", "start", "stop", "size",
}

RUBY_INTRO1_GFX = 0x407764
RUBY_INTRO1_MAPS = (0x406B74, 0x406F28, 0x40725C, 0x40754C)
RUBY_ROTATING_GATE = {
    0: 0x3D5A0C,
    1: 0x3D2A0C,
    2: 0x3D320C,
    3: 0x3D3A0C,
    4: 0x3D5C0C,
    5: 0x3D420C,
    6: 0x3D4A0C,
    7: 0x3D520C,
}


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def is_romptr(p, n):
    return 0x08000000 <= p < 0x08000000 + n


def lz_size(b, o):
    if o + 4 > len(b) or b[o] != 0x10:
        return None
    return b[o + 1] | (b[o + 2] << 8) | (b[o + 3] << 16)


def lz_end(b, o):
    """Byte offset after the LZ stream (exclusive). Mirrors GbaLz77.streamEnd + 0."""
    if o + 4 > len(b) or b[o] != 0x10:
        return None
    size = lz_size(b, o)
    i = o + 4
    written = 0
    n = len(b)
    if size == 0:
        return i
    while written < size:
        if i >= n:
            return None
        flags = b[i]
        i += 1
        for bit in range(8):
            if written >= size:
                break
            if (flags >> (7 - bit)) & 1:
                if i + 1 >= n:
                    return None
                b1 = b[i]
                i += 2
                written += (b1 >> 4) + 3
                if written > size:
                    written = size
            else:
                if i >= n:
                    return None
                written += 1
                i += 1
    return i


def valid_cry_table(b, off, count=388, voice=12):
    n = len(b)
    if off + count * voice > n:
        return False
    for i in range(count):
        o = off + i * voice
        typ = b[o]
        if typ not in (0x20, 0x30):
            return False
        if b[o + 1] != 60:
            return False
        if not is_romptr(u32(b, o + 4), n):
            return False
    return True


def find_cry_tables(sb, song_table):
    ruby_song, ruby_cry, ruby_cry2 = 0x45548C, 0x452590, 0x4537C0
    d = song_table - ruby_song
    c1 = ruby_cry + d
    c2 = ruby_cry2 + d
    if valid_cry_table(sb, c1) and valid_cry_table(sb, c2):
        return c1, c2
    lo = max(0, song_table - 0x8000)
    hi = song_table
    hits = []
    for off in range(lo, hi, 4):
        if valid_cry_table(sb, off):
            hits.append(off)
            if len(hits) >= 4:
                break
    if len(hits) >= 2:
        return hits[0], hits[1]
    return None, None


def find_door_table(sb):
    n = len(sb)
    count = 34
    for lo, hi in ((0x30F000, 0x310000), (0x308000, 0x318000)):
        for off in range(lo, min(hi, n - count * 12 - 8), 4):
            ok = True
            for i in range(count):
                o = off + i * 12
                tiles = u32(sb, o + 4)
                pal = u32(sb, o + 8)
                if not is_romptr(tiles, n) or not is_romptr(pal, n):
                    ok = False
                    break
                if u16(sb, o) == 0 and u16(sb, o + 2) == 0 and i == 0:
                    ok = False
                    break
            if not ok:
                continue
            term = u32(sb, off + count * 12 + 4)
            if term == 0:
                return off
    return None


def is_size_name(name):
    if name in SKIP_NAMES:
        return True
    if name.endswith(("Bytes", "Count", "Length", "Stride", "Slots")):
        return True
    if name in ("entry", "count", "colours"):
        return True
    return False


def is_rom_off(v):
    return isinstance(v, int) and 0x10000 <= v < 0x1000000


def parse_ruby_us(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"(?:local\s+)?(?:\w+\.)?RUBY_US\s*=\s*\{", text)
    if not m:
        return {}
    i = m.end()
    depth = 1
    start = i
    while i < len(text) and depth:
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
        i += 1
    body = text[start : i - 1]
    out = {}
    depth = 1
    pos = 0
    for m in re.finditer(r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*0x([0-9A-Fa-f]+)|([{}])", body):
        if m.group(3) == "{":
            depth += 1
        elif m.group(3) == "}":
            depth -= 1
        elif m.group(1) and depth == 1:
            out[m.group(1)] = int(m.group(2), 16)
        pos = m.end()
    return out


def lookup_sapphire(by_file_off, fn, name, ruby):
    rec = by_file_off.get((fn, name, ruby))
    if rec and rec.get("sapphire") is not None:
        return int(rec["sapphire"])
    rec = by_file_off.get((fn, name))
    if rec and rec.get("sapphire") is not None and rec.get("ruby") == ruby:
        return int(rec["sapphire"])
    return None


def main():
    rb = open(RUBY, "rb").read()
    sb = open(SAPP, "rb").read()
    data = json.load(open(JSON_PATH, encoding="utf-8"))
    song = data["songTable"]
    decor = data["decorations"]
    delta_mode = data.get("deltaMode") or 0
    cry1, cry2 = find_cry_tables(sb, song)
    door = find_door_table(sb)
    print("song", hex(song), "cry", hex(cry1) if cry1 else None, hex(cry2) if cry2 else None)
    print("door", hex(door) if door else None, "decor", hex(decor) if decor is not None else None)

    extras = {
        ("RomExtractorGen3Audio.lua", "songTable"): song,
        ("RomExtractorGen3Audio.lua", "cryTable"): cry1,
        ("RomExtractorGen3Audio.lua", "cryTable2"): cry2,
        ("RomExtractorGen3RS.lua", "DECORATIONS_OFF"): decor,
        ("RomExtractorGen3RS.lua", "DOOR_TABLE_OFF"): data.get("doorTable") or door,
        ("RomExtractorGen3Battle.lua", "wildHeaders"): data.get("wildHeaders"),
    }

    tables = {}
    by_file_off = {}
    for rec in data["offsets"].values():
        fn, name, sapp = rec["file"], rec["name"], rec["sapphire"]
        by_file_off[(fn, name, rec["ruby"])] = rec
        how = rec.get("how") or ""
        if how.startswith("delta") and how.endswith(":0"):
            sapp = None
        extra = extras.get((fn, name))
        if extra:
            sapp = extra
            rec["sapphire"] = extra
            rec["how"] = rec.get("how") or "scan"
        if sapp is None:
            continue
        rs = lz_size(rb, rec["ruby"])
        if rs is not None:
            ss = lz_size(sb, sapp)
            if ss != rs:
                if ss is None:
                    rec["sapphire"] = None
                    continue
        key = FILE_TO_KEY.get(fn)
        if not key:
            continue
        if is_size_name(name) or not is_rom_off(int(sapp)):
            continue
        tables.setdefault(key, {})[name] = int(sapp)

    # Fill every RUBY_US ROM address, including ones unique-byte search missed.
    still_ruby_us = []
    for fn, key in FILE_TO_KEY.items():
        path = os.path.join(SRC, fn)
        if not os.path.isfile(path):
            continue
        ruby_us = parse_ruby_us(path)
        dest = tables.setdefault(key, {})
        for name, ruby in ruby_us.items():
            if is_size_name(name) or not is_rom_off(ruby):
                continue
            if name in dest:
                continue
            sapp = lookup_sapphire(by_file_off, fn, name, ruby)
            if sapp is None:
                for d in (-0x70, 0x58, -0x1B8):
                    cand = ruby + d
                    if cand < 0 or cand + 4 > len(sb):
                        continue
                    rs = lz_size(rb, ruby)
                    if rs is not None:
                        if lz_size(sb, cand) is not None:
                            sapp = cand
                            break
                    elif is_romptr(u32(rb, ruby), len(rb)) and is_romptr(u32(sb, cand), len(sb)):
                        if u32(sb, cand) - u32(rb, ruby) == d:
                            sapp = cand
                            break
                    elif rb[ruby : ruby + 16] != b"\x00" * 16 and rb[ruby : ruby + 16] == sb[cand : cand + 16]:
                        sapp = cand
                        break
            if sapp is None:
                chunk32 = rb[ruby : ruby + 32]
                if len(chunk32) == 32 and chunk32 != b"\x00" * 32 and chunk32 == sb[ruby : ruby + 32]:
                    sapp = ruby
                else:
                    rs = lz_size(rb, ruby)
                    if rs is not None and lz_size(sb, ruby) == rs:
                        sapp = ruby
            if sapp is None:
                still_ruby_us.append((key, name, ruby))
                continue
            dest[name] = int(sapp)

    cine = tables.get("Cinema", {})
    gfx = cine.get("groudonGfx")
    if gfx is not None and lz_size(sb, gfx):
        pal = gfx - 0x40
        cine["groudonPal"] = pal
        end = lz_end(sb, gfx)
        if end:
            end = (end + 3) & ~3
            cine["groudonMap"] = end
            mend = lz_end(sb, end)
            if mend:
                mend = (mend + 3) & ~3
                cine["lavaMap"] = mend
        tables["Cinema"] = cine
        print("title chain pal", hex(pal), "map", hex(cine.get("groudonMap") or 0),
              "lava", hex(cine.get("lavaMap") or 0))

    battle = tables.get("Battle", {})
    def evo_ok(off):
        if off is None or off + 48 > len(sb):
            return False
        return u16(sb, off + 40) == 4 and u16(sb, off + 42) == 16 and u16(sb, off + 44) == 2
    if not evo_ok(battle.get("evolutions")):
        for cand in (0x203AF8, 0x203B68 - 0x70):
            if evo_ok(cand):
                battle["evolutions"] = cand
                tables["Battle"] = battle
                print("evolutions", hex(cand))
                break
    pc = tables.get("Pc", {})
    if pc.get("handGfx") and "handPal" not in pc:
        pc["handPal"] = pc["handGfx"] - 0x48
        tables["Pc"] = pc
        print("handPal", hex(pc["handPal"]))

    pokenav = tables.setdefault("Pokenav", {})
    for name, ruby in (
        ("menuHelpTable", 0x3E31B0),
        ("conditionHelpTable", 0x3E31CC),
        ("searchHelpTable", 0x3E31D8),
    ):
        if name in pokenav:
            continue
        cand = ruby + 0x58
        if cand + 12 <= len(sb) and all(
            is_romptr(u32(sb, cand + i * 4), len(sb)) for i in range(3)
        ):
            pokenav[name] = cand
            print(name, hex(cand))

    intro1_maps = None
    if cine.get("intro1Gfx") is not None:
        d = cine["intro1Gfx"] - RUBY_INTRO1_GFX
        intro1_maps = [m + d for m in RUBY_INTRO1_MAPS]

    gate_delta = None
    if cine.get("rotatingGateFortree") is not None:
        gate_delta = cine["rotatingGateFortree"] - 0x3D2964
    elif delta_mode:
        gate_delta = int(delta_mode)

    lines = [
        "-- US Sapphire 1.0 (AXPE) extractor offsets. Overlay on each module's",
        "-- RUBY_US table: same keys, relocated addresses. Generated by",
        "-- tools/find_sapphire_offsets.py + tools/gen_sapphire_offsets.py.",
        "local T = {}",
        "",
    ]
    for key in sorted(tables):
        lines.append(f"T.{key} = {{")
        body = tables[key]
        names = sorted(body, key=lambda n: (body[n], n))
        for name in names:
            if is_size_name(name):
                continue
            if key == "Cinema" and name == "intro1Maps":
                continue
            lines.append(f"  {name} = 0x{body[name]:X},")
        if key == "Cinema":
            if intro1_maps:
                maps = ", ".join(f"0x{m:X}" for m in intro1_maps)
                lines.append(f"  intro1Maps = {{ {maps} }},")
            lines.append("  -- Pack 0 clouds + Latias. Unique-byte overlay would match Ruby pack 1")
            lines.append("  -- (mountains / Latios leftover); Cinema.applyIntro2Version forces these.")
            if gate_delta is not None:
                lines.append("  rotatingGate = {")
                for idx in range(8):
                    ruby_off = RUBY_ROTATING_GATE[idx]
                    sap_off = ruby_off + gate_delta
                    tw, th, nbytes = (4, 4, 0x200) if idx in (0, 4) else (8, 8, 0x800)
                    lines.append(
                        f"    [{idx}] = {{ off = 0x{sap_off:X}, bytes = 0x{nbytes:X}, tw = {tw}, th = {th} }},"
                    )
                lines.append("  },")
        lines.append("}")
        lines.append("")
    lines.append("return T")
    lines.append("")
    open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print("wrote", OUT, "modules", sorted(tables), "keys", sum(len(v) for v in tables.values()))
    print("RUBY_US still missing", len(still_ruby_us))
    for rec in still_ruby_us[:50]:
        print("  ", rec[0], rec[1], hex(rec[2]))


if __name__ == "__main__":
    main()
