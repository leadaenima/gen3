"""Diff a cart snapshot against what Game3 claims NEW GAME looks like.

The oracle's job is to say whether the Lua engine's constants and inits
match the cart, not to re-read pokeruby by hand.  This loads a snapshot
(from snapshot.py --json, or by booting the cart) and compares it to:

    - Game3.NEW_GAME_HIDE_FLAGS  (EventScript_ResetAllMapFlags)
    - FLAG_SYS_TV_WATCH          (UpdateTVScreensOnMap on every load)
    - size-record vars           (InitShroomish/BarboachSizeRecord)
    - truck dummy-warp coords    (SetPlayerCoordsFromWarp: width/2, height/2)

    python tools/gba_oracle/compare_engine.py --json %TEMP%/ruby_newgame.json
    python tools/gba_oracle/compare_engine.py <rom> --state states/newgame.state

Exits 1 when a hide-flag or size-record disagrees.  Random lottery / Mauville
gfx vars and trainer id are reported but do not fail the run.
"""

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import names  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
GAME3 = os.path.join(HERE, "..", "..", "src", "core", "Game3.lua")
NEW_GAME_INC = "data/scripts/new_game.inc"

# Vars NewGameInitData writes that are not a fixed constant (lottery RNG,
# Mauville old-man gfx from trainer id).
RANDOM_VARS = {0x4010, 0x404B, 0x404C}

SIZE_RECORD_DEFAULT = 0x8100
FLAG_SYS_TV_WATCH = 0x831
VAR_SHROOMISH = 0x4047
VAR_BARBOACH = 0x404F

# WarpToTruck uses dummy xy; SetPlayerCoordsFromWarp then does width/2.
TRUCK_LAYOUT = (5, 5)


def _game3_source():
    with open(GAME3, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read()


def hide_flags():
    src = _game3_source()
    m = re.search(r"Game3\.NEW_GAME_HIDE_FLAGS\s*=\s*\{([^}]+)\}", src)
    if not m:
        sys.exit("Game3.NEW_GAME_HIDE_FLAGS not found")
    return [int(tok, 0) for tok in re.findall(r"0x[0-9A-Fa-f]+|\d+", m.group(1))]


def reset_all_map_flags():
    """Flag ids named by EventScript_ResetAllMapFlags, if pokeruby is around."""
    path = names._find(NEW_GAME_INC)
    if not path:
        return None
    out = []
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        in_script = False
        for line in fh:
            if "EventScript_ResetAllMapFlags" in line:
                in_script = True
                continue
            if not in_script:
                continue
            if re.match(r"^\S", line) and "setflag" not in line and "call" not in line:
                if out:
                    break
            m = re.search(r"setflag\s+(FLAG_\w+)", line)
            if m:
                fid = names.flag_id(m.group(1))
                if fid is not None:
                    out.append(fid)
    return out


def load_snapshot(args):
    if args.json:
        with open(args.json, "r", encoding="utf-8") as fh:
            return json.load(fh)
    import libretro  # noqa: E402
    import ruby  # noqa: E402
    with libretro.Core() as core:
        core.load(args.rom)
        if args.state:
            with open(args.state, "rb") as fh:
                core.load_state(fh.read())
        return ruby.RubyState(core).snapshot()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rom", nargs="?", help="Ruby cart; skipped when --json is set")
    ap.add_argument("--state", help="savestate to load before reading")
    ap.add_argument("--json", help="cart snapshot from snapshot.py --json")
    args = ap.parse_args()
    if not args.json and not args.rom:
        ap.error("need a ROM or --json")

    snap = load_snapshot(args)
    cart_flags = set(snap.get("flags") or [])
    engine_hide = hide_flags()
    expected = set(engine_hide)
    expected.add(FLAG_SYS_TV_WATCH)

    print("== NEW GAME hide flags")
    print("   engine list  %d" % len(engine_hide))
    print("   cart set     %d" % len(cart_flags))
    rom_script = reset_all_map_flags()
    if rom_script is not None:
        missing = [i for i in rom_script if i not in expected]
        extra = [i for i in engine_hide if i not in set(rom_script)]
        print("   pokeruby     %d setflag lines" % len(rom_script))
        for i in missing:
            print("   SCRIPT-ONLY  %s" % names.flag(i))
        for i in extra:
            print("   ENGINE-ONLY  %s" % names.flag(i))

    hide_set = set(engine_hide)
    cart_only = sorted(cart_flags - expected)
    engine_only = sorted(hide_set - cart_flags)
    print("")
    print("== cart vs engine expected (%d cart-only, %d engine-only)"
          % (len(cart_only), len(engine_only)))
    for i in cart_only:
        print("   CART   %s" % names.flag(i))
    for i in engine_only:
        print("   ENGINE %s" % names.flag(i))
    if FLAG_SYS_TV_WATCH in cart_flags:
        print("   ok     FLAG_SYS_TV_WATCH is set (map load)")
    else:
        print("   MISS   FLAG_SYS_TV_WATCH (0x831)")

    vars_ = {int(k): int(v) for k, v in (snap.get("vars") or {}).items()}
    print("")
    print("== vars")
    for vid, want in ((VAR_SHROOMISH, SIZE_RECORD_DEFAULT),
                      (VAR_BARBOACH, SIZE_RECORD_DEFAULT)):
        got = vars_.get(vid, 0)
        tag = "ok" if got == want else "MISS"
        print("   %s     %s = %d (want %d)"
              % (tag, names.var(vid), got, want))
    extras = sorted(i for i in vars_ if i not in (
        VAR_SHROOMISH, VAR_BARBOACH) and i not in RANDOM_VARS)
    for i in extras:
        print("   extra  %s = %d" % (names.var(i), vars_[i]))
    for i in sorted(RANDOM_VARS):
        if i in vars_:
            print("   rng    %s = %d" % (names.var(i), vars_[i]))

    pos = snap.get("position")
    want_pos = (TRUCK_LAYOUT[0] // 2, TRUCK_LAYOUT[1] // 2)
    print("")
    print("== truck dummy warp")
    print("   position   %s (want %s)" % (tuple(pos) if pos else None, want_pos))
    loc = snap.get("location") or {}
    print("   map        group %s num %s" % (loc.get("mapGroup"), loc.get("mapNum")))
    if snap.get("playerXY") is not None:
        print("   playerXY   %s" % (tuple(snap["playerXY"]),))

    failed = bool(cart_only or engine_only)
    failed = failed or vars_.get(VAR_SHROOMISH, 0) != SIZE_RECORD_DEFAULT
    failed = failed or vars_.get(VAR_BARBOACH, 0) != SIZE_RECORD_DEFAULT
    failed = failed or FLAG_SYS_TV_WATCH not in cart_flags
    failed = failed or (pos is not None and tuple(pos) != want_pos)
    print("")
    print("== %s" % ("MISMATCH" if failed else "match"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
